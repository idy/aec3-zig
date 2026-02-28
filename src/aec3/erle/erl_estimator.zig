//! Ported from: docs/aec3-rs-src/audio_processing/aec3/erl_estimator.rs
//! Estimates Echo Return Loss (ERL) per frequency band and in the time domain.
const std = @import("std");
const common = @import("../common/aec3_common.zig");

const FFT_LENGTH_BY_2 = common.FFT_LENGTH_BY_2;
const FFT_LENGTH_BY_2_PLUS_1 = common.FFT_LENGTH_BY_2_PLUS_1;
const FFT_LENGTH_BY_2_MINUS_1 = common.FFT_LENGTH_BY_2_MINUS_1;

const MIN_ERL: f32 = 0.01;
const MAX_ERL: f32 = 1000.0;
const HOLD_BLOCKS: i32 = 1000;
const X2_BAND_ENERGY_THRESHOLD: f32 = 44_015_068.0;

pub const ErlEstimator = struct {
    const Self = @This();

    startup_phase_length_blocks: usize,
    erl_spectrum: [FFT_LENGTH_BY_2_PLUS_1]f32,
    hold_counters: [FFT_LENGTH_BY_2_MINUS_1]i32,
    erl_td: f32,
    hold_counter_time_domain: i32,
    blocks_since_reset: usize,

    pub fn init(startup_phase_length_blocks: usize) Self {
        return .{
            .startup_phase_length_blocks = startup_phase_length_blocks,
            .erl_spectrum = [_]f32{MAX_ERL} ** FFT_LENGTH_BY_2_PLUS_1,
            .hold_counters = [_]i32{0} ** FFT_LENGTH_BY_2_MINUS_1,
            .erl_td = MAX_ERL,
            .hold_counter_time_domain = 0,
            .blocks_since_reset = 0,
        };
    }

    pub fn reset(self: *Self) void {
        self.blocks_since_reset = 0;
    }

    /// Updates ERL estimates given multi-channel render/capture power spectra.
    pub fn update(
        self: *Self,
        converged_filters: []const bool,
        render_spectra: []const [FFT_LENGTH_BY_2_PLUS_1]f32,
        capture_spectra: []const [FFT_LENGTH_BY_2_PLUS_1]f32,
    ) void {
        std.debug.assert(capture_spectra.len == converged_filters.len);
        std.debug.assert(render_spectra.len > 0);

        // Find first converged filter.
        var first_converged: ?usize = null;
        for (converged_filters, 0..) |conv, idx| {
            if (conv) {
                first_converged = idx;
                break;
            }
        }
        const fc = first_converged orelse {
            self.blocks_since_reset = self.blocks_since_reset +| 1;
            return;
        };

        self.blocks_since_reset = self.blocks_since_reset +| 1;
        if (self.blocks_since_reset < self.startup_phase_length_blocks) return;

        // Aggregate capture spectra: max across converged filters.
        var max_capture = capture_spectra[fc];
        for (capture_spectra, converged_filters, 0..) |spectrum, converged, ch| {
            if (ch == fc or !converged) continue;
            for (&max_capture, spectrum) |*dst, src| {
                if (src > dst.*) dst.* = src;
            }
        }

        // Aggregate render spectra: max across all channels.
        var max_render = render_spectra[0];
        for (render_spectra[1..]) |spectrum| {
            for (&max_render, spectrum) |*dst, src| {
                if (src > dst.*) dst.* = src;
            }
        }

        // Update per-band ERL estimates.
        for (1..FFT_LENGTH_BY_2) |k| {
            if (max_render[k] > X2_BAND_ENERGY_THRESHOLD) {
                const new_erl = max_capture[k] / max_render[k];
                if (new_erl < self.erl_spectrum[k]) {
                    self.hold_counters[k - 1] = HOLD_BLOCKS;
                    self.erl_spectrum[k] += 0.1 * (new_erl - self.erl_spectrum[k]);
                    if (self.erl_spectrum[k] < MIN_ERL) {
                        self.erl_spectrum[k] = MIN_ERL;
                    }
                }
            }
        }

        // Decrement hold counters and decay ERL.
        for (&self.hold_counters) |*counter| {
            counter.* -= 1;
        }
        for (self.hold_counters, 0..) |counter, bin| {
            if (counter <= 0) {
                const idx = bin + 1;
                self.erl_spectrum[idx] = @min(2.0 * self.erl_spectrum[idx], MAX_ERL);
            }
        }

        // Boundary bins copy from neighbours.
        self.erl_spectrum[0] = self.erl_spectrum[1];
        self.erl_spectrum[FFT_LENGTH_BY_2] = self.erl_spectrum[FFT_LENGTH_BY_2 - 1];

        // Update time-domain ERL.
        var x2_sum: f32 = 0.0;
        for (max_render) |v| x2_sum += v;
        if (x2_sum > X2_BAND_ENERGY_THRESHOLD * @as(f32, FFT_LENGTH_BY_2_PLUS_1)) {
            var y2_sum: f32 = 0.0;
            for (max_capture) |v| y2_sum += v;
            const new_erl = y2_sum / x2_sum;
            if (new_erl < self.erl_td) {
                self.hold_counter_time_domain = HOLD_BLOCKS;
                self.erl_td += 0.1 * (new_erl - self.erl_td);
                if (self.erl_td < MIN_ERL) {
                    self.erl_td = MIN_ERL;
                }
            }
        }

        self.hold_counter_time_domain -= 1;
        if (self.hold_counter_time_domain <= 0) {
            self.erl_td = @min(2.0 * self.erl_td, MAX_ERL);
        }
    }

    pub fn erl(self: *const Self) *const [FFT_LENGTH_BY_2_PLUS_1]f32 {
        return &self.erl_spectrum;
    }

    pub fn erl_time_domain(self: *const Self) f32 {
        return self.erl_td;
    }
};

// ---------------------------------------------------------------------------
// Inline tests
// ---------------------------------------------------------------------------

fn verify_erl(erl: *const [FFT_LENGTH_BY_2_PLUS_1]f32, erl_time_domain: f32, reference: f32) !void {
    for (erl) |value| {
        try std.testing.expect(@abs(value - reference) < 1e-3);
    }
    try std.testing.expect(@abs(erl_time_domain - reference) < 1e-3);
}

test "erl_estimator estimates_track_reference_behavior" {
    const render_channel_options = [_]usize{ 1, 2, 8 };
    const capture_channel_options = [_]usize{ 1, 2, 8 };

    for (render_channel_options) |num_render_channels| {
        for (capture_channel_options) |num_capture_channels| {
            const allocator = std.testing.allocator;

            // Allocate multi-channel spectra.
            const x2 = try allocator.alloc([FFT_LENGTH_BY_2_PLUS_1]f32, num_render_channels);
            defer allocator.free(x2);
            const y2 = try allocator.alloc([FFT_LENGTH_BY_2_PLUS_1]f32, num_capture_channels);
            defer allocator.free(y2);
            const converged = try allocator.alloc(bool, num_capture_channels);
            defer allocator.free(converged);

            const converged_idx = num_capture_channels - 1;
            for (converged) |*c| c.* = false;
            converged[converged_idx] = true;

            var estimator = ErlEstimator.init(0);

            // Set render spectra: high energy.
            for (x2) |*spectrum| {
                for (spectrum) |*v| v.* = 500.0 * 1_000_000.0;
            }
            // Capture = 10x render.
            for (&y2[converged_idx]) |*v| v.* = 10.0 * x2[0][0];

            for (0..200) |_| {
                estimator.update(converged, x2, y2);
            }
            try verify_erl(estimator.erl(), estimator.erl_time_domain(), 10.0);

            // Set capture = 10000x render -> ERL should hold at 10 for ~1000 blocks.
            for (&y2[converged_idx]) |*v| v.* = 10_000.0 * x2[0][0];
            for (0..998) |_| {
                estimator.update(converged, x2, y2);
            }
            try verify_erl(estimator.erl(), estimator.erl_time_domain(), 10.0);

            // After hold expires, ERL doubles to 20.
            estimator.update(converged, x2, y2);
            try verify_erl(estimator.erl(), estimator.erl_time_domain(), 20.0);

            // After 1000 more blocks of doubling, ERL reaches MAX_ERL.
            for (0..1000) |_| {
                estimator.update(converged, x2, y2);
            }
            try verify_erl(estimator.erl(), estimator.erl_time_domain(), MAX_ERL);

            // Reduce render energy below threshold -> no new updates.
            for (x2) |*spectrum| {
                for (spectrum) |*v| v.* = 1_000_000.0;
            }
            for (&y2[converged_idx]) |*v| v.* = 10.0 * x2[0][0];
            for (0..200) |_| {
                estimator.update(converged, x2, y2);
            }
            try verify_erl(estimator.erl(), estimator.erl_time_domain(), MAX_ERL);
        }
    }
}

test "erl_estimator no converged filters" {
    var estimator = ErlEstimator.init(0);
    const converged = [_]bool{false};
    const x2 = [_][FFT_LENGTH_BY_2_PLUS_1]f32{[_]f32{1e9} ** FFT_LENGTH_BY_2_PLUS_1};
    const y2 = [_][FFT_LENGTH_BY_2_PLUS_1]f32{[_]f32{1e9} ** FFT_LENGTH_BY_2_PLUS_1};
    estimator.update(&converged, &x2, &y2);
    // ERL should remain at MAX_ERL.
    try verify_erl(estimator.erl(), estimator.erl_time_domain(), MAX_ERL);
}

test "erl_estimator startup phase delays updates" {
    var estimator = ErlEstimator.init(10);
    const converged = [_]bool{true};
    const x2 = [_][FFT_LENGTH_BY_2_PLUS_1]f32{[_]f32{500.0 * 1e6} ** FFT_LENGTH_BY_2_PLUS_1};
    var y2 = [_][FFT_LENGTH_BY_2_PLUS_1]f32{[_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1};
    for (&y2[0]) |*v| v.* = 10.0 * x2[0][0];

    // During startup phase, ERL stays at MAX_ERL.
    for (0..9) |_| {
        estimator.update(&converged, &x2, &y2);
    }
    try verify_erl(estimator.erl(), estimator.erl_time_domain(), MAX_ERL);
}
