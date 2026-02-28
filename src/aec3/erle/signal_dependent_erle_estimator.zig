//! Ported from: docs/aec3-rs-src/audio_processing/aec3/signal_dependent_erle_estimator.rs
//! Per-section, signal-dependent ERLE estimator with correction factors.
const std = @import("std");
const common = @import("../common/aec3_common.zig");
const config_mod = @import("../../api/config.zig");
const spectrum_buffer_mod = @import("../buffer/spectrum_ring_buffer.zig");

const FFT_LENGTH_BY_2 = common.FFT_LENGTH_BY_2;
const FFT_LENGTH_BY_2_PLUS_1 = common.FFT_LENGTH_BY_2_PLUS_1;
const BLOCK_SIZE = common.BLOCK_SIZE;
const EchoCanceller3Config = config_mod.EchoCanceller3Config;
const SpectrumBuffer = spectrum_buffer_mod.SpectrumRingBuffer;

const SUBBANDS: usize = 6;
const BAND_BOUNDARIES: [SUBBANDS + 1]usize = .{ 1, 8, 16, 24, 32, 48, FFT_LENGTH_BY_2_PLUS_1 };
const X2_BAND_ENERGY_THRESHOLD: f32 = 44_015_068.0;
const SMOOTH_DECREASE: f32 = 0.1;
const SMOOTH_INCREASE: f32 = SMOOTH_DECREASE / 2.0;
const MIN_UPDATES_FOR_CORRECTION: usize = 50;

fn form_subband_map() [FFT_LENGTH_BY_2_PLUS_1]usize {
    var map = [_]usize{0} ** FFT_LENGTH_BY_2_PLUS_1;
    var subband: usize = 1;
    for (&map, 0..) |*value, k| {
        while (subband < BAND_BOUNDARIES.len and k >= BAND_BOUNDARIES[subband]) {
            subband += 1;
        }
        value.* = @min(subband - 1, SUBBANDS - 1);
    }
    return map;
}

fn define_filter_section_sizes(
    allocator: std.mem.Allocator,
    delay_headroom_blocks: usize,
    num_blocks: usize,
    num_sections: usize,
) ![]usize {
    const section_sizes = try allocator.alloc(usize, num_sections);
    @memset(section_sizes, 0);
    if (num_sections == 0) return section_sizes;

    const filter_length_blocks = if (num_blocks > delay_headroom_blocks) num_blocks - delay_headroom_blocks else 0;
    var remaining_blocks = filter_length_blocks;
    var remaining_sections = num_sections;
    var estimator_size: usize = 2;
    var idx: usize = 0;
    while (remaining_sections > 1 and remaining_blocks > estimator_size * remaining_sections) {
        section_sizes[idx] = estimator_size;
        remaining_blocks -= estimator_size;
        remaining_sections -= 1;
        estimator_size *= 2;
        idx += 1;
        if (idx == num_sections) break;
    }

    if (remaining_sections == 0) return section_sizes;

    const last_group_size = if (remaining_sections > 0) remaining_blocks / remaining_sections else 0;
    while (idx < num_sections) : (idx += 1) {
        section_sizes[idx] = last_group_size;
    }

    if (remaining_sections > 0) {
        const used_blocks = last_group_size * remaining_sections;
        if (num_sections > 0) {
            section_sizes[num_sections - 1] += if (remaining_blocks > used_blocks) remaining_blocks - used_blocks else 0;
        }
    }

    return section_sizes;
}

fn set_sections_boundaries(
    allocator: std.mem.Allocator,
    delay_headroom_blocks: usize,
    num_blocks: usize,
    num_sections: usize,
) ![]usize {
    const boundaries = try allocator.alloc(usize, num_sections + 1);
    @memset(boundaries, 0);
    if (num_sections == 0) return boundaries;
    if (num_sections == 1) {
        boundaries[0] = 0;
        boundaries[1] = num_blocks;
        return boundaries;
    }

    const section_sizes = try define_filter_section_sizes(allocator, delay_headroom_blocks, num_blocks, num_sections);
    defer allocator.free(section_sizes);
    boundaries[0] = delay_headroom_blocks;
    var idx: usize = 0;
    var current_size: usize = 0;
    var k = delay_headroom_blocks;
    while (k < num_blocks) : (k += 1) {
        current_size += 1;
        if (current_size >= section_sizes[idx]) {
            idx += 1;
            if (idx >= section_sizes.len) break;
            boundaries[idx] = k + 1;
            current_size = 0;
        }
    }
    boundaries[section_sizes.len] = num_blocks;
    return boundaries;
}

fn set_max_erle_subbands(max_erle_l: f32, max_erle_h: f32, limit_subband_l: usize) [SUBBANDS]f32 {
    var max_erle = [_]f32{max_erle_h} ** SUBBANDS;
    for (0..@min(limit_subband_l, SUBBANDS)) |i| {
        max_erle[i] = max_erle_l;
    }
    return max_erle;
}

/// Per-section, signal-dependent ERLE estimator with correction factors.
pub const SignalDependentErleEstimator = struct {
    const Self = @This();

    min_erle: f32,
    num_sections: usize,
    band_to_subband: [FFT_LENGTH_BY_2_PLUS_1]usize,
    max_erle: [SUBBANDS]f32,
    section_boundaries_blocks: []usize,
    erle_data: [][FFT_LENGTH_BY_2_PLUS_1]f32,
    // s2_section_accum[ch][section] — flattened as s2_section_accum_flat[ch * num_sections + section]
    s2_section_accum_flat: [][FFT_LENGTH_BY_2_PLUS_1]f32,
    // erle_estimators[ch][section] — flattened
    erle_estimators_flat: [][SUBBANDS]f32,
    erle_ref: [][SUBBANDS]f32,
    // correction_factors[ch][section] — flattened
    correction_factors_flat: [][SUBBANDS]f32,
    num_updates: [][SUBBANDS]usize,
    n_active_sections: [][FFT_LENGTH_BY_2_PLUS_1]usize,
    num_capture_channels: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, cfg: *const EchoCanceller3Config, num_capture_channels: usize) !Self {
        std.debug.assert(cfg.erle.num_sections >= 1);
        const btm = form_subband_map();
        const limit_subband_l = btm[FFT_LENGTH_BY_2 / 2];
        const num_sections = cfg.erle.num_sections;
        const headroom_blocks = cfg.delay.delay_headroom_samples / BLOCK_SIZE;
        const boundaries = try set_sections_boundaries(
            allocator,
            headroom_blocks,
            cfg.filter.main.length_blocks,
            num_sections,
        );
        errdefer allocator.free(boundaries);

        const erle_d = try allocator.alloc([FFT_LENGTH_BY_2_PLUS_1]f32, num_capture_channels);
        errdefer allocator.free(erle_d);
        const s2_flat = try allocator.alloc([FFT_LENGTH_BY_2_PLUS_1]f32, num_capture_channels * num_sections);
        errdefer allocator.free(s2_flat);
        const ee_flat = try allocator.alloc([SUBBANDS]f32, num_capture_channels * num_sections);
        errdefer allocator.free(ee_flat);
        const er = try allocator.alloc([SUBBANDS]f32, num_capture_channels);
        errdefer allocator.free(er);
        const cf_flat = try allocator.alloc([SUBBANDS]f32, num_capture_channels * num_sections);
        errdefer allocator.free(cf_flat);
        const nu = try allocator.alloc([SUBBANDS]usize, num_capture_channels);
        errdefer allocator.free(nu);
        const nas = try allocator.alloc([FFT_LENGTH_BY_2_PLUS_1]usize, num_capture_channels);
        errdefer allocator.free(nas);

        // Zero-initialize everything; reset() will set proper values.
        for (erle_d) |*s| s.* = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
        for (s2_flat) |*s| s.* = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
        for (ee_flat) |*s| s.* = [_]f32{0.0} ** SUBBANDS;
        for (er) |*s| s.* = [_]f32{0.0} ** SUBBANDS;
        for (cf_flat) |*s| s.* = [_]f32{1.0} ** SUBBANDS;
        for (nu) |*s| s.* = [_]usize{0} ** SUBBANDS;
        for (nas) |*s| s.* = [_]usize{0} ** FFT_LENGTH_BY_2_PLUS_1;

        var est = Self{
            .min_erle = cfg.erle.min,
            .num_sections = num_sections,
            .band_to_subband = btm,
            .max_erle = set_max_erle_subbands(cfg.erle.max_l, cfg.erle.max_h, limit_subband_l),
            .section_boundaries_blocks = boundaries,
            .erle_data = erle_d,
            .s2_section_accum_flat = s2_flat,
            .erle_estimators_flat = ee_flat,
            .erle_ref = er,
            .correction_factors_flat = cf_flat,
            .num_updates = nu,
            .n_active_sections = nas,
            .num_capture_channels = num_capture_channels,
            .allocator = allocator,
        };
        est.reset();
        return est;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.section_boundaries_blocks);
        self.allocator.free(self.erle_data);
        self.allocator.free(self.s2_section_accum_flat);
        self.allocator.free(self.erle_estimators_flat);
        self.allocator.free(self.erle_ref);
        self.allocator.free(self.correction_factors_flat);
        self.allocator.free(self.num_updates);
        self.allocator.free(self.n_active_sections);
        self.* = undefined;
    }

    pub fn reset(self: *Self) void {
        for (0..self.num_capture_channels) |ch| {
            @memset(&self.erle_data[ch], self.min_erle);
            for (0..self.num_sections) |s| {
                @memset(&self.erle_estimators_flat[ch * self.num_sections + s], self.min_erle);
                self.correction_factors_flat[ch * self.num_sections + s] = [_]f32{1.0} ** SUBBANDS;
            }
            @memset(&self.erle_ref[ch], self.min_erle);
            self.num_updates[ch] = [_]usize{0} ** SUBBANDS;
            self.n_active_sections[ch] = [_]usize{0} ** FFT_LENGTH_BY_2_PLUS_1;
        }
    }

    pub fn erle(self: *const Self) []const [FFT_LENGTH_BY_2_PLUS_1]f32 {
        return self.erle_data;
    }

    /// Updates the signal-dependent ERLE estimate.
    ///
    /// `spectrum_buffer` and `render_position` serve as the render buffer.
    /// `filter_frequency_responses[ch][block]` is the per-block filter freq response.
    pub fn update(
        self: *Self,
        spectrum_buffer: *const SpectrumBuffer,
        render_position: usize,
        filter_frequency_responses: []const []const [FFT_LENGTH_BY_2_PLUS_1]f32,
        x2: *const [FFT_LENGTH_BY_2_PLUS_1]f32,
        y2: []const [FFT_LENGTH_BY_2_PLUS_1]f32,
        e2: []const [FFT_LENGTH_BY_2_PLUS_1]f32,
        average_erle: []const [FFT_LENGTH_BY_2_PLUS_1]f32,
        converged_filters: []const bool,
    ) void {
        if (self.num_sections <= 1) return;
        std.debug.assert(filter_frequency_responses.len == y2.len);
        std.debug.assert(average_erle.len == y2.len);
        std.debug.assert(converged_filters.len == y2.len);

        self.compute_number_of_active_filter_sections(spectrum_buffer, render_position, filter_frequency_responses);
        self.update_correction_factors(x2, y2, e2, converged_filters);

        for (0..self.num_capture_channels) |ch| {
            for (0..FFT_LENGTH_BY_2) |k| {
                const section_idx = @min(self.n_active_sections[ch][k], self.num_sections - 1);
                const subband = self.band_to_subband[k];
                const correction = self.correction_factors_flat[ch * self.num_sections + section_idx][subband];
                self.erle_data[ch][k] = std.math.clamp(
                    average_erle[ch][k] * correction,
                    self.min_erle,
                    self.max_erle[subband],
                );
            }
            self.erle_data[ch][FFT_LENGTH_BY_2] = self.erle_data[ch][FFT_LENGTH_BY_2 - 1];
        }
    }

    // ── Private ──

    fn compute_number_of_active_filter_sections(
        self: *Self,
        spectrum_buffer: *const SpectrumBuffer,
        render_position: usize,
        filter_frequency_responses: []const []const [FFT_LENGTH_BY_2_PLUS_1]f32,
    ) void {
        self.compute_echo_estimate_per_filter_section(spectrum_buffer, render_position, filter_frequency_responses);
        self.compute_active_filter_sections();
    }

    fn compute_echo_estimate_per_filter_section(
        self: *Self,
        spectrum_buffer: *const SpectrumBuffer,
        render_position: usize,
        filter_frequency_responses: []const []const [FFT_LENGTH_BY_2_PLUS_1]f32,
    ) void {
        const num_render_channels = spectrum_buffer.buffer[0].len;
        const inv_num_render_channels: f32 = if (num_render_channels > 0)
            1.0 / @as(f32, @floatFromInt(num_render_channels))
        else
            0.0;

        for (0..self.num_capture_channels) |capture_ch| {
            const offset0: isize = @intCast(self.section_boundaries_blocks[0]);
            var idx_render = spectrum_buffer.offset_index(render_position, offset0);

            for (0..self.num_sections) |section| {
                var x2_section = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
                var h2_section = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
                const start_block = self.section_boundaries_blocks[section];
                const block_limit = @min(
                    self.section_boundaries_blocks[section + 1],
                    filter_frequency_responses[capture_ch].len,
                );

                var block = start_block;
                while (block < block_limit) : (block += 1) {
                    for (0..num_render_channels) |channel| {
                        for (&x2_section, spectrum_buffer.buffer[idx_render][channel]) |*dst, val| {
                            dst.* += val * inv_num_render_channels;
                        }
                    }
                    for (&h2_section, filter_frequency_responses[capture_ch][block]) |*dst, val| {
                        dst.* += val;
                    }
                    idx_render = spectrum_buffer.inc_index(idx_render);
                }

                const flat_idx = capture_ch * self.num_sections + section;
                for (&self.s2_section_accum_flat[flat_idx], x2_section, h2_section) |*dst, x, h| {
                    dst.* = x * h;
                }
            }

            // Cumulative sum.
            for (1..self.num_sections) |section| {
                const curr = capture_ch * self.num_sections + section;
                const prev = curr - 1;
                for (0..FFT_LENGTH_BY_2_PLUS_1) |k| {
                    self.s2_section_accum_flat[curr][k] += self.s2_section_accum_flat[prev][k];
                }
            }
        }
    }

    fn compute_active_filter_sections(self: *Self) void {
        for (0..self.num_capture_channels) |ch| {
            self.n_active_sections[ch] = [_]usize{0} ** FFT_LENGTH_BY_2_PLUS_1;
            const last_section_flat = ch * self.num_sections + self.num_sections - 1;
            for (0..FFT_LENGTH_BY_2_PLUS_1) |k| {
                var section = self.num_sections;
                const target = 0.9 * self.s2_section_accum_flat[last_section_flat][k];
                while (section > 0 and
                    self.s2_section_accum_flat[ch * self.num_sections + section - 1][k] >= target)
                {
                    section -= 1;
                    self.n_active_sections[ch][k] = section;
                }
            }
        }
    }

    fn update_correction_factors(
        self: *Self,
        x2: *const [FFT_LENGTH_BY_2_PLUS_1]f32,
        y2: []const [FFT_LENGTH_BY_2_PLUS_1]f32,
        e2: []const [FFT_LENGTH_BY_2_PLUS_1]f32,
        converged_filters: []const bool,
    ) void {
        for (0..converged_filters.len) |ch| {
            if (!converged_filters[ch]) continue;

            const x2_subbands = self.aggregate_subband_powers(x2);
            const e2_subbands = self.aggregate_subband_powers(&e2[ch]);
            const y2_subbands = self.aggregate_subband_powers(&y2[ch]);
            const idx_subbands = self.active_sections_per_subband(ch);

            var new_erle = [_]f32{0.0} ** SUBBANDS;
            var is_updated = [_]bool{false} ** SUBBANDS;

            for (0..SUBBANDS) |subband| {
                if (x2_subbands[subband] > X2_BAND_ENERGY_THRESHOLD and e2_subbands[subband] > 0.0) {
                    new_erle[subband] = y2_subbands[subband] / e2_subbands[subband];
                    is_updated[subband] = true;
                    self.num_updates[ch][subband] += 1;
                }
            }

            for (0..SUBBANDS) |subband| {
                const idx = @min(idx_subbands[subband], self.num_sections - 1);
                const flat_idx = ch * self.num_sections + idx;
                const alpha_val = if (new_erle[subband] > self.erle_estimators_flat[flat_idx][subband])
                    SMOOTH_INCREASE
                else
                    SMOOTH_DECREASE;
                const alpha = if (is_updated[subband]) alpha_val else 0.0;
                self.erle_estimators_flat[flat_idx][subband] = std.math.clamp(
                    self.erle_estimators_flat[flat_idx][subband] +
                        alpha * (new_erle[subband] - self.erle_estimators_flat[flat_idx][subband]),
                    self.min_erle,
                    self.max_erle[subband],
                );
            }

            for (0..SUBBANDS) |subband| {
                const alpha_val = if (new_erle[subband] > self.erle_ref[ch][subband])
                    SMOOTH_INCREASE
                else
                    SMOOTH_DECREASE;
                const alpha = if (is_updated[subband]) alpha_val else 0.0;
                self.erle_ref[ch][subband] = std.math.clamp(
                    self.erle_ref[ch][subband] + alpha * (new_erle[subband] - self.erle_ref[ch][subband]),
                    self.min_erle,
                    self.max_erle[subband],
                );
            }

            for (0..SUBBANDS) |subband| {
                if (is_updated[subband] and self.num_updates[ch][subband] > MIN_UPDATES_FOR_CORRECTION) {
                    const idx = @min(idx_subbands[subband], self.num_sections - 1);
                    const flat_idx = ch * self.num_sections + idx;
                    if (self.erle_ref[ch][subband] > 0.0) {
                        const new_factor =
                            self.erle_estimators_flat[flat_idx][subband] / self.erle_ref[ch][subband];
                        self.correction_factors_flat[flat_idx][subband] +=
                            0.1 * (new_factor - self.correction_factors_flat[flat_idx][subband]);
                    }
                }
            }
        }
    }

    fn aggregate_subband_powers(self: *const Self, spectrum: *const [FFT_LENGTH_BY_2_PLUS_1]f32) [SUBBANDS]f32 {
        _ = self;
        var result = [_]f32{0.0} ** SUBBANDS;
        for (0..SUBBANDS) |subband| {
            const start = BAND_BOUNDARIES[subband];
            const end = @min(BAND_BOUNDARIES[subband + 1], spectrum.len);
            for (start..end) |k| {
                result[subband] += spectrum[k];
            }
        }
        return result;
    }

    fn active_sections_per_subband(self: *const Self, ch: usize) [SUBBANDS]usize {
        var idx_subbands = [_]usize{0} ** SUBBANDS;
        for (0..SUBBANDS) |subband| {
            const start = BAND_BOUNDARIES[subband];
            const end = @min(BAND_BOUNDARIES[subband + 1], self.n_active_sections[ch].len);
            var min_section = self.num_sections - 1;
            for (self.n_active_sections[ch][start..end]) |section| {
                min_section = @min(min_section, section);
            }
            idx_subbands[subband] = min_section;
        }
        return idx_subbands;
    }
};

// ---------------------------------------------------------------------------
// Inline tests
// ---------------------------------------------------------------------------

test "signal_dependent_erle_estimator init and deinit" {
    const allocator = std.testing.allocator;
    var cfg = EchoCanceller3Config.default();
    cfg.erle.num_sections = 2;
    var est = try SignalDependentErleEstimator.init(allocator, &cfg, 1);
    defer est.deinit();

    // After init, ERLE should be at min.
    for (est.erle()[0]) |v| {
        try std.testing.expectEqual(cfg.erle.min, v);
    }
}

test "signal_dependent_erle_estimator single section noop" {
    const allocator = std.testing.allocator;
    var cfg = EchoCanceller3Config.default();
    cfg.erle.num_sections = 1;
    var est = try SignalDependentErleEstimator.init(allocator, &cfg, 1);
    defer est.deinit();

    // With 1 section, update is a no-op.
    var sb = try SpectrumBuffer.init(allocator, 20, 1);
    defer sb.deinit();
    const x2 = [_]f32{1e8} ** FFT_LENGTH_BY_2_PLUS_1;
    const y2 = [_][FFT_LENGTH_BY_2_PLUS_1]f32{[_]f32{1e9} ** FFT_LENGTH_BY_2_PLUS_1};
    const e2 = [_][FFT_LENGTH_BY_2_PLUS_1]f32{[_]f32{1e8} ** FFT_LENGTH_BY_2_PLUS_1};
    const avg = [_][FFT_LENGTH_BY_2_PLUS_1]f32{[_]f32{4.0} ** FFT_LENGTH_BY_2_PLUS_1};
    const conv = [_]bool{true};
    const h2 = [_][]const [FFT_LENGTH_BY_2_PLUS_1]f32{&[_][FFT_LENGTH_BY_2_PLUS_1]f32{}};

    est.update(&sb, 0, &h2, &x2, &y2, &e2, &avg, &conv);
    // ERLE should still be at min (no-op).
    for (est.erle()[0]) |v| {
        try std.testing.expectEqual(cfg.erle.min, v);
    }
}

test "signal_dependent_erle_estimator reset" {
    const allocator = std.testing.allocator;
    var cfg = EchoCanceller3Config.default();
    cfg.erle.num_sections = 2;
    var est = try SignalDependentErleEstimator.init(allocator, &cfg, 1);
    defer est.deinit();

    est.erle_data[0][5] = 99.0;
    est.reset();
    try std.testing.expectEqual(cfg.erle.min, est.erle_data[0][5]);
}

test "form_subband_map boundaries" {
    const map = form_subband_map();
    // bin 0 → subband 0
    try std.testing.expectEqual(@as(usize, 0), map[0]);
    // bin 1 → subband 0 (BAND_BOUNDARIES[0] = 1)
    try std.testing.expectEqual(@as(usize, 0), map[1]);
    // bin 8 → subband 1
    try std.testing.expectEqual(@as(usize, 1), map[8]);
    // last bin → subband 5
    try std.testing.expectEqual(@as(usize, 5), map[FFT_LENGTH_BY_2_PLUS_1 - 1]);
}
