//! Ported from: docs/aec3-rs-src/audio_processing/aec3/subband_erle_estimator.rs
//! Per-subband ERLE estimator with onset detection.
const std = @import("std");
const common = @import("../common/aec3_common.zig");
const config_mod = @import("../../api/config.zig");

const FFT_LENGTH_BY_2 = common.FFT_LENGTH_BY_2;
const FFT_LENGTH_BY_2_PLUS_1 = common.FFT_LENGTH_BY_2_PLUS_1;
const EchoCanceller3Config = config_mod.EchoCanceller3Config;

const X2_BAND_ENERGY_THRESHOLD: f32 = 44_015_068.0;
const BLOCKS_TO_HOLD_ERLE: i32 = 100;
const BLOCKS_FOR_ONSET_DETECTION: i32 = BLOCKS_TO_HOLD_ERLE + 150;
const POINTS_TO_ACCUMULATE: usize = 6;

fn set_max_erle_bands(max_erle_l: f32, max_erle_h: f32) [FFT_LENGTH_BY_2_PLUS_1]f32 {
    var max_erle = [_]f32{max_erle_h} ** FFT_LENGTH_BY_2_PLUS_1;
    for (0..FFT_LENGTH_BY_2 / 2) |k| {
        max_erle[k] = max_erle_l;
    }
    return max_erle;
}

/// Internal accumulated spectra used for smoothed ERLE estimation.
const AccumulatedSpectra = struct {
    y2: [][FFT_LENGTH_BY_2_PLUS_1]f32,
    e2: [][FFT_LENGTH_BY_2_PLUS_1]f32,
    low_render_energy: [][FFT_LENGTH_BY_2_PLUS_1]bool,
    num_points: []usize,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator, num_capture_channels: usize) !AccumulatedSpectra {
        const y2 = try allocator.alloc([FFT_LENGTH_BY_2_PLUS_1]f32, num_capture_channels);
        errdefer allocator.free(y2);
        const e2 = try allocator.alloc([FFT_LENGTH_BY_2_PLUS_1]f32, num_capture_channels);
        errdefer allocator.free(e2);
        const low = try allocator.alloc([FFT_LENGTH_BY_2_PLUS_1]bool, num_capture_channels);
        errdefer allocator.free(low);
        const np = try allocator.alloc(usize, num_capture_channels);
        errdefer allocator.free(np);

        for (y2) |*s| s.* = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
        for (e2) |*s| s.* = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
        for (low) |*s| s.* = [_]bool{false} ** FFT_LENGTH_BY_2_PLUS_1;
        @memset(np, 0);

        return .{ .y2 = y2, .e2 = e2, .low_render_energy = low, .num_points = np, .allocator = allocator };
    }

    fn deinit(self: *AccumulatedSpectra) void {
        self.allocator.free(self.y2);
        self.allocator.free(self.e2);
        self.allocator.free(self.low_render_energy);
        self.allocator.free(self.num_points);
    }

    fn reset(self: *AccumulatedSpectra) void {
        for (self.y2) |*s| s.* = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
        for (self.e2) |*s| s.* = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
        for (self.low_render_energy) |*s| s.* = [_]bool{false} ** FFT_LENGTH_BY_2_PLUS_1;
        @memset(self.num_points, 0);
    }
};

/// Per-subband ERLE estimator with onset detection and hold logic.
pub const SubbandErleEstimator = struct {
    const Self = @This();

    use_onset_detection: bool,
    min_erle: f32,
    max_erle: [FFT_LENGTH_BY_2_PLUS_1]f32,
    accum_spectra: AccumulatedSpectra,
    erle_data: [][FFT_LENGTH_BY_2_PLUS_1]f32,
    erle_onsets_data: [][FFT_LENGTH_BY_2_PLUS_1]f32,
    coming_onset: [][FFT_LENGTH_BY_2_PLUS_1]bool,
    hold_counters: [][FFT_LENGTH_BY_2_PLUS_1]i32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, cfg: *const EchoCanceller3Config, num_capture_channels: usize) !Self {
        var accum = try AccumulatedSpectra.init(allocator, num_capture_channels);
        errdefer accum.deinit();
        const erle_d = try allocator.alloc([FFT_LENGTH_BY_2_PLUS_1]f32, num_capture_channels);
        errdefer allocator.free(erle_d);
        const erle_o = try allocator.alloc([FFT_LENGTH_BY_2_PLUS_1]f32, num_capture_channels);
        errdefer allocator.free(erle_o);
        const onset = try allocator.alloc([FFT_LENGTH_BY_2_PLUS_1]bool, num_capture_channels);
        errdefer allocator.free(onset);
        const hold = try allocator.alloc([FFT_LENGTH_BY_2_PLUS_1]i32, num_capture_channels);
        errdefer allocator.free(hold);

        for (erle_d) |*s| s.* = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
        for (erle_o) |*s| s.* = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
        for (onset) |*s| s.* = [_]bool{true} ** FFT_LENGTH_BY_2_PLUS_1;
        for (hold) |*s| s.* = [_]i32{0} ** FFT_LENGTH_BY_2_PLUS_1;

        var estimator = Self{
            .use_onset_detection = cfg.erle.onset_detection,
            .min_erle = cfg.erle.min,
            .max_erle = set_max_erle_bands(cfg.erle.max_l, cfg.erle.max_h),
            .accum_spectra = accum,
            .erle_data = erle_d,
            .erle_onsets_data = erle_o,
            .coming_onset = onset,
            .hold_counters = hold,
            .allocator = allocator,
        };
        estimator.reset();
        return estimator;
    }

    pub fn deinit(self: *Self) void {
        self.accum_spectra.deinit();
        self.allocator.free(self.erle_data);
        self.allocator.free(self.erle_onsets_data);
        self.allocator.free(self.coming_onset);
        self.allocator.free(self.hold_counters);
        self.* = undefined;
    }

    pub fn reset(self: *Self) void {
        for (self.erle_data) |*s| @memset(s, self.min_erle);
        for (self.erle_onsets_data) |*s| @memset(s, self.min_erle);
        for (self.coming_onset) |*s| @memset(s, true);
        for (self.hold_counters) |*s| @memset(s, 0);
        self.accum_spectra.reset();
    }

    pub fn update(
        self: *Self,
        x2: *const [FFT_LENGTH_BY_2_PLUS_1]f32,
        y2: []const [FFT_LENGTH_BY_2_PLUS_1]f32,
        e2: []const [FFT_LENGTH_BY_2_PLUS_1]f32,
        converged_filters: []const bool,
    ) void {
        std.debug.assert(y2.len == e2.len);
        std.debug.assert(y2.len == converged_filters.len);
        self.update_accumulated_spectra(x2, y2, e2, converged_filters);
        self.update_bands(converged_filters);
        if (self.use_onset_detection) {
            self.decrease_erle_per_band_for_low_render_signals();
        }
        for (self.erle_data) |*erle_ch| {
            erle_ch[0] = erle_ch[1];
            erle_ch[FFT_LENGTH_BY_2] = erle_ch[FFT_LENGTH_BY_2 - 1];
        }
    }

    pub fn erle(self: *const Self) []const [FFT_LENGTH_BY_2_PLUS_1]f32 {
        return self.erle_data;
    }

    pub fn erle_onsets(self: *const Self) []const [FFT_LENGTH_BY_2_PLUS_1]f32 {
        return self.erle_onsets_data;
    }

    // ── Private ──

    fn update_accumulated_spectra(
        self: *Self,
        x2: *const [FFT_LENGTH_BY_2_PLUS_1]f32,
        y2: []const [FFT_LENGTH_BY_2_PLUS_1]f32,
        e2: []const [FFT_LENGTH_BY_2_PLUS_1]f32,
        converged_filters: []const bool,
    ) void {
        const st = &self.accum_spectra;
        for (0..y2.len) |ch| {
            if (!converged_filters[ch]) continue;
            if (st.num_points[ch] == POINTS_TO_ACCUMULATE) {
                st.num_points[ch] = 0;
                st.y2[ch] = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
                st.e2[ch] = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
                st.low_render_energy[ch] = [_]bool{false} ** FFT_LENGTH_BY_2_PLUS_1;
            }
            for (&st.y2[ch], y2[ch]) |*dst, src| dst.* += src;
            for (&st.e2[ch], e2[ch]) |*dst, src| dst.* += src;
            for (&st.low_render_energy[ch], x2) |*flag, xv| {
                flag.* = flag.* or (xv < X2_BAND_ENERGY_THRESHOLD);
            }
            st.num_points[ch] += 1;
        }
    }

    fn update_bands(self: *Self, converged_filters: []const bool) void {
        for (0..self.erle_data.len) |ch| {
            if (!converged_filters[ch]) continue;
            if (self.accum_spectra.num_points[ch] != POINTS_TO_ACCUMULATE) continue;

            var new_erle = [_]f32{0.0} ** FFT_LENGTH_BY_2;
            var updated = [_]bool{false} ** FFT_LENGTH_BY_2;
            for (1..FFT_LENGTH_BY_2) |k| {
                if (self.accum_spectra.e2[ch][k] > 0.0) {
                    new_erle[k] = self.accum_spectra.y2[ch][k] / self.accum_spectra.e2[ch][k];
                    updated[k] = true;
                }
            }

            if (self.use_onset_detection) {
                for (1..FFT_LENGTH_BY_2) |k| {
                    if (updated[k] and !self.accum_spectra.low_render_energy[ch][k]) {
                        if (self.coming_onset[ch][k]) {
                            self.coming_onset[ch][k] = false;
                            // use_min_erle_during_onsets is always true, so skip erle_onsets update here.
                        }
                        self.hold_counters[ch][k] = BLOCKS_FOR_ONSET_DETECTION;
                    }
                }
            }

            for (1..FFT_LENGTH_BY_2) |k| {
                if (updated[k]) {
                    var alpha: f32 = 0.05;
                    if (new_erle[k] < self.erle_data[ch][k]) {
                        alpha = if (self.accum_spectra.low_render_energy[ch][k]) 0.0 else 0.1;
                    }
                    self.erle_data[ch][k] = std.math.clamp(
                        self.erle_data[ch][k] + alpha * (new_erle[k] - self.erle_data[ch][k]),
                        self.min_erle,
                        self.max_erle[k],
                    );
                }
            }
        }
    }

    fn decrease_erle_per_band_for_low_render_signals(self: *Self) void {
        for (0..self.erle_data.len) |ch| {
            for (1..FFT_LENGTH_BY_2) |k| {
                self.hold_counters[ch][k] -= 1;
                if (self.hold_counters[ch][k] <= (BLOCKS_FOR_ONSET_DETECTION - BLOCKS_TO_HOLD_ERLE)) {
                    if (self.erle_data[ch][k] > self.erle_onsets_data[ch][k]) {
                        self.erle_data[ch][k] = @max(
                            @max(self.erle_onsets_data[ch][k], 0.97 * self.erle_data[ch][k]),
                            self.min_erle,
                        );
                    }
                    if (self.hold_counters[ch][k] <= 0) {
                        self.coming_onset[ch][k] = true;
                        self.hold_counters[ch][k] = 0;
                    }
                }
            }
        }
    }
};

// ---------------------------------------------------------------------------
// Inline tests
// ---------------------------------------------------------------------------

test "subband_erle_estimator init and deinit" {
    const allocator = std.testing.allocator;
    const cfg = EchoCanceller3Config.default();
    var est = try SubbandErleEstimator.init(allocator, &cfg, 2);
    defer est.deinit();

    // All ERLE values should be at min after init.
    for (est.erle()) |ch_erle| {
        for (ch_erle) |v| {
            try std.testing.expectEqual(cfg.erle.min, v);
        }
    }
}

test "subband_erle_estimator increases for strong echo" {
    const allocator = std.testing.allocator;
    var cfg = EchoCanceller3Config.default();
    cfg.erle.max_l = 20.0;
    cfg.erle.max_h = 20.0;
    cfg.erle.onset_detection = false;
    var est = try SubbandErleEstimator.init(allocator, &cfg, 1);
    defer est.deinit();

    const x2 = [_]f32{100_000_000.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var y2 = [_][FFT_LENGTH_BY_2_PLUS_1]f32{[_]f32{1_000_000_000.0} ** FFT_LENGTH_BY_2_PLUS_1};
    var e2 = [_][FFT_LENGTH_BY_2_PLUS_1]f32{[_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1};
    for (&e2[0]) |*v| v.* = y2[0][0] / 10.0;
    const converged = [_]bool{true};

    for (0..POINTS_TO_ACCUMULATE * 60) |_| {
        est.update(&x2, &y2, &e2, &converged);
    }

    // ERLE bins 1..FFT_LENGTH_BY_2 should be close to 10 (y2/e2 = 10).
    for (1..FFT_LENGTH_BY_2) |k| {
        try std.testing.expect(@abs(est.erle()[0][k] - 10.0) < 1.0);
    }
}

test "subband_erle_estimator unconverged stays at min" {
    const allocator = std.testing.allocator;
    const cfg = EchoCanceller3Config.default();
    var est = try SubbandErleEstimator.init(allocator, &cfg, 1);
    defer est.deinit();

    const x2 = [_]f32{1e9} ** FFT_LENGTH_BY_2_PLUS_1;
    const y2 = [_][FFT_LENGTH_BY_2_PLUS_1]f32{[_]f32{1e9} ** FFT_LENGTH_BY_2_PLUS_1};
    const e2 = [_][FFT_LENGTH_BY_2_PLUS_1]f32{[_]f32{1e8} ** FFT_LENGTH_BY_2_PLUS_1};
    const converged = [_]bool{false};

    for (0..100) |_| {
        est.update(&x2, &y2, &e2, &converged);
    }
    for (est.erle()[0]) |v| {
        try std.testing.expectEqual(cfg.erle.min, v);
    }
}

test "subband_erle_estimator reset" {
    const allocator = std.testing.allocator;
    const cfg = EchoCanceller3Config.default();
    var est = try SubbandErleEstimator.init(allocator, &cfg, 1);
    defer est.deinit();

    // Modify state.
    est.erle_data[0][5] = 99.0;
    est.reset();
    try std.testing.expectEqual(cfg.erle.min, est.erle_data[0][5]);
}
