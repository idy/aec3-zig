//! Ported from: docs/aec3-rs-src/audio_processing/aec3/erle_estimator.rs
//! Aggregated ERLE estimator that coordinates fullband, subband,
//! and optionally signal-dependent ERLE estimation.
const std = @import("std");
const common = @import("../common/aec3_common.zig");
const config_mod = @import("../../api/config.zig");
const spectrum_buffer_mod = @import("../buffer/spectrum_ring_buffer.zig");
const fullband_mod = @import("fullband_erle_estimator.zig");
const subband_mod = @import("subband_erle_estimator.zig");
const signal_dep_mod = @import("signal_dependent_erle_estimator.zig");

const FFT_LENGTH_BY_2_PLUS_1 = common.FFT_LENGTH_BY_2_PLUS_1;
const EchoCanceller3Config = config_mod.EchoCanceller3Config;
const SpectrumBuffer = spectrum_buffer_mod.SpectrumRingBuffer;
const FullBandErleEstimator = fullband_mod.FullBandErleEstimator;
const SubbandErleEstimator = subband_mod.SubbandErleEstimator;
const SignalDependentErleEstimator = signal_dep_mod.SignalDependentErleEstimator;

/// Aggregated ERLE estimator.
pub const ErleEstimator = struct {
    const Self = @This();

    startup_phase_length_blocks: usize,
    fullband_erle_estimator: FullBandErleEstimator,
    subband_erle_estimator: SubbandErleEstimator,
    signal_dependent_erle_estimator: ?SignalDependentErleEstimator,
    blocks_since_reset: usize,
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        startup_phase_length_blocks: usize,
        cfg: *const EchoCanceller3Config,
        num_capture_channels: usize,
    ) !Self {
        var fb = try FullBandErleEstimator.init(allocator, &cfg.erle, num_capture_channels);
        errdefer fb.deinit();
        var sb = try SubbandErleEstimator.init(allocator, cfg, num_capture_channels);
        errdefer sb.deinit();
        var sd: ?SignalDependentErleEstimator = null;
        errdefer if (sd) |*s| s.deinit();
        if (cfg.erle.num_sections > 1) {
            sd = try SignalDependentErleEstimator.init(allocator, cfg, num_capture_channels);
        }

        var instance = Self{
            .startup_phase_length_blocks = startup_phase_length_blocks,
            .fullband_erle_estimator = fb,
            .subband_erle_estimator = sb,
            .signal_dependent_erle_estimator = sd,
            .blocks_since_reset = 0,
            .allocator = allocator,
        };
        instance.reset(true);
        return instance;
    }

    pub fn deinit(self: *Self) void {
        self.fullband_erle_estimator.deinit();
        self.subband_erle_estimator.deinit();
        if (self.signal_dependent_erle_estimator) |*sd| sd.deinit();
        self.* = undefined;
    }

    pub fn reset(self: *Self, delay_change: bool) void {
        self.fullband_erle_estimator.reset();
        self.subband_erle_estimator.reset();
        if (self.signal_dependent_erle_estimator) |*sd| sd.reset();
        if (delay_change) self.blocks_since_reset = 0;
    }

    /// Updates ERLE estimates.
    ///
    /// `spectrum_buffer`/`render_position` serve as the render buffer.
    /// `filter_frequency_responses[ch][block]` is the per-block filter response.
    pub fn update(
        self: *Self,
        spectrum_buffer: *const SpectrumBuffer,
        render_position: usize,
        filter_frequency_responses: []const []const [FFT_LENGTH_BY_2_PLUS_1]f32,
        avg_render_spectrum_with_reverb: *const [FFT_LENGTH_BY_2_PLUS_1]f32,
        capture_spectra: []const [FFT_LENGTH_BY_2_PLUS_1]f32,
        subtractor_spectra: []const [FFT_LENGTH_BY_2_PLUS_1]f32,
        converged_filters: []const bool,
    ) void {
        self.blocks_since_reset += 1;
        if (self.blocks_since_reset < self.startup_phase_length_blocks) return;

        self.subband_erle_estimator.update(
            avg_render_spectrum_with_reverb,
            capture_spectra,
            subtractor_spectra,
            converged_filters,
        );

        if (self.signal_dependent_erle_estimator) |*sd| {
            sd.update(
                spectrum_buffer,
                render_position,
                filter_frequency_responses,
                avg_render_spectrum_with_reverb,
                capture_spectra,
                subtractor_spectra,
                self.subband_erle_estimator.erle(),
                converged_filters,
            );
        }

        self.fullband_erle_estimator.update(
            avg_render_spectrum_with_reverb,
            capture_spectra,
            subtractor_spectra,
            converged_filters,
        );
    }

    /// Returns per-channel ERLE spectra (signal-dependent if available, else subband).
    pub fn erle(self: *const Self) []const [FFT_LENGTH_BY_2_PLUS_1]f32 {
        if (self.signal_dependent_erle_estimator) |*sd| {
            return sd.erle();
        }
        return self.subband_erle_estimator.erle();
    }

    /// Returns per-channel ERLE onset spectra.
    pub fn erle_onsets(self: *const Self) []const [FFT_LENGTH_BY_2_PLUS_1]f32 {
        return self.subband_erle_estimator.erle_onsets();
    }

    /// Returns the fullband ERLE in log2 scale (minimum across channels).
    pub fn fullband_erle_log2(self: *const Self) f32 {
        return self.fullband_erle_estimator.fullband_erle_log2();
    }

    /// Returns instantaneous linear quality estimates per capture channel.
    pub fn get_inst_linear_quality_estimates(self: *const Self) []const ?f32 {
        return self.fullband_erle_estimator.get_linear_quality_estimates();
    }
};

// ---------------------------------------------------------------------------
// Inline tests
// ---------------------------------------------------------------------------

test "erle_estimator init and deinit" {
    const allocator = std.testing.allocator;
    const cfg = EchoCanceller3Config.default();
    var est = try ErleEstimator.init(allocator, 0, &cfg, 2);
    defer est.deinit();

    // Signal-dependent should be null with default config (num_sections=1).
    try std.testing.expectEqual(@as(?SignalDependentErleEstimator, null), est.signal_dependent_erle_estimator);
    try std.testing.expectEqual(@as(usize, 2), est.erle().len);
}

test "erle_estimator with signal dependent" {
    const allocator = std.testing.allocator;
    var cfg = EchoCanceller3Config.default();
    cfg.erle.num_sections = 3;
    var est = try ErleEstimator.init(allocator, 0, &cfg, 1);
    defer est.deinit();

    // Signal-dependent should be present.
    try std.testing.expect(est.signal_dependent_erle_estimator != null);
}

test "erle_estimator startup phase blocks update" {
    const allocator = std.testing.allocator;
    const cfg = EchoCanceller3Config.default();
    var est = try ErleEstimator.init(allocator, 10, &cfg, 1);
    defer est.deinit();

    var sb = try SpectrumBuffer.init(allocator, 20, 1);
    defer sb.deinit();
    const x2 = [_]f32{1e8} ** FFT_LENGTH_BY_2_PLUS_1;
    const y2 = [_][FFT_LENGTH_BY_2_PLUS_1]f32{[_]f32{1e9} ** FFT_LENGTH_BY_2_PLUS_1};
    const e2 = [_][FFT_LENGTH_BY_2_PLUS_1]f32{[_]f32{1e8} ** FFT_LENGTH_BY_2_PLUS_1};
    const conv = [_]bool{true};
    const h2 = [_][]const [FFT_LENGTH_BY_2_PLUS_1]f32{&[_][FFT_LENGTH_BY_2_PLUS_1]f32{}};

    // During startup phase, no actual update happens.
    for (0..9) |_| {
        est.update(&sb, 0, &h2, &x2, &y2, &e2, &conv);
    }
    // ERLE should still be at min.
    for (est.erle()[0]) |v| {
        try std.testing.expectEqual(cfg.erle.min, v);
    }
}

test "erle_estimator reset" {
    const allocator = std.testing.allocator;
    const cfg = EchoCanceller3Config.default();
    var est = try ErleEstimator.init(allocator, 0, &cfg, 1);
    defer est.deinit();

    est.blocks_since_reset = 42;
    est.reset(true);
    try std.testing.expectEqual(@as(usize, 0), est.blocks_since_reset);

    est.blocks_since_reset = 42;
    est.reset(false); // delay_change=false: don't reset blocks_since_reset
    try std.testing.expectEqual(@as(usize, 42), est.blocks_since_reset);
}
