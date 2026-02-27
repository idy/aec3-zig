//! Ported from: docs/aec3-rs-src/audio_processing/aec3/reverb_model_estimator.rs
//! Aggregates per-channel reverb decay and frequency response estimators.
const std = @import("std");
const common = @import("aec3_common.zig");
const config_mod = @import("../../api/config.zig");
const reverb_decay_mod = @import("reverb_decay_estimator.zig");
const reverb_freq_mod = @import("reverb_frequency_response.zig");

const FFT_LENGTH_BY_2_PLUS_1 = common.FFT_LENGTH_BY_2_PLUS_1;
const EchoCanceller3Config = config_mod.EchoCanceller3Config;
const ReverbDecayEstimator = reverb_decay_mod.ReverbDecayEstimator;
const ReverbFrequencyResponse = reverb_freq_mod.ReverbFrequencyResponse;

/// Aggregated reverb model estimator — coordinates per-channel decay
/// and frequency response estimation.
pub const ReverbModelEstimator = struct {
    const Self = @This();

    reverb_decay_estimators: []ReverbDecayEstimator,
    reverb_frequency_responses: []ReverbFrequencyResponse,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, cfg: *const EchoCanceller3Config, num_capture_channels: usize) !Self {
        const decay_est = try allocator.alloc(ReverbDecayEstimator, num_capture_channels);
        errdefer allocator.free(decay_est);

        var decay_initialized: usize = 0;
        errdefer {
            for (decay_est[0..decay_initialized]) |*e| e.deinit();
        }
        for (decay_est) |*e| {
            e.* = try ReverbDecayEstimator.init(allocator, cfg);
            decay_initialized += 1;
        }

        const freq_resp = try allocator.alloc(ReverbFrequencyResponse, num_capture_channels);
        errdefer allocator.free(freq_resp);
        for (freq_resp) |*r| r.* = ReverbFrequencyResponse.init();

        return .{
            .reverb_decay_estimators = decay_est,
            .reverb_frequency_responses = freq_resp,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.reverb_decay_estimators) |*e| e.deinit();
        self.allocator.free(self.reverb_decay_estimators);
        self.allocator.free(self.reverb_frequency_responses);
        self.* = undefined;
    }

    /// Updates both decay and frequency response estimators for all channels.
    pub fn update(
        self: *Self,
        impulse_responses: []const []const f32,
        frequency_responses: []const []const [FFT_LENGTH_BY_2_PLUS_1]f32,
        linear_filter_qualities: []const ?f32,
        filter_delays_blocks: []const i32,
        usable_linear_estimates: []const bool,
        stationary_block: bool,
    ) void {
        const num_capture_channels = self.reverb_decay_estimators.len;
        std.debug.assert(impulse_responses.len == num_capture_channels);
        std.debug.assert(frequency_responses.len == num_capture_channels);
        std.debug.assert(linear_filter_qualities.len == num_capture_channels);
        std.debug.assert(filter_delays_blocks.len == num_capture_channels);
        std.debug.assert(usable_linear_estimates.len == num_capture_channels);

        for (0..num_capture_channels) |ch| {
            self.reverb_frequency_responses[ch].update(
                frequency_responses[ch],
                filter_delays_blocks[ch],
                linear_filter_qualities[ch],
                stationary_block,
            );
            self.reverb_decay_estimators[ch].update(
                impulse_responses[ch],
                linear_filter_qualities[ch],
                filter_delays_blocks[ch],
                usable_linear_estimates[ch],
                stationary_block,
            );
        }
    }

    /// Returns the reverb decay estimate from the first channel.
    pub fn reverb_decay(self: *const Self) f32 {
        return self.reverb_decay_estimators[0].decay();
    }

    /// Returns the reverb frequency response from the first channel.
    pub fn get_reverb_frequency_response(self: *const Self) *const [FFT_LENGTH_BY_2_PLUS_1]f32 {
        return self.reverb_frequency_responses[0].frequency_response();
    }
};

// ---------------------------------------------------------------------------
// Inline tests
// ---------------------------------------------------------------------------

test "reverb_model_estimator init and deinit" {
    const allocator = std.testing.allocator;
    var cfg = EchoCanceller3Config.default();
    cfg.filter.main.length_blocks = 40;
    var est = try ReverbModelEstimator.init(allocator, &cfg, 2);
    defer est.deinit();

    try std.testing.expectEqual(@as(usize, 2), est.reverb_decay_estimators.len);
    try std.testing.expectEqual(@as(usize, 2), est.reverb_frequency_responses.len);
    // Default decay should match config.
    try std.testing.expectApproxEqAbs(@as(f32, 0.83), est.reverb_decay(), 1e-6);
}

test "reverb_model_estimator not_changing_decay" {
    const allocator = std.testing.allocator;
    const DEFAULT_DECAY: f32 = 0.9;
    var cfg = EchoCanceller3Config.default();
    cfg.ep_strength.default_len = DEFAULT_DECAY; // positive → not adaptive
    cfg.filter.main.length_blocks = 40;
    var est = try ReverbModelEstimator.init(allocator, &cfg, 1);
    defer est.deinit();

    const num_blocks = cfg.filter.main.length_blocks;
    const h = try allocator.alloc(f32, num_blocks * common.FFT_LENGTH_BY_2);
    defer allocator.free(h);
    @memset(h, 0.0);

    var freq_resp = try allocator.alloc([FFT_LENGTH_BY_2_PLUS_1]f32, num_blocks);
    defer allocator.free(freq_resp);
    for (freq_resp) |*block| block.* = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;

    const ir = [_][]const f32{h};
    const fr = [_][]const [FFT_LENGTH_BY_2_PLUS_1]f32{freq_resp};
    const qualities = [_]?f32{1.0};
    const delays = [_]i32{2};
    const usable = [_]bool{true};

    for (0..100) |_| {
        est.update(&ir, &fr, &qualities, &delays, &usable, false);
    }
    // Decay should remain at DEFAULT_DECAY (non-adaptive mode).
    try std.testing.expectApproxEqAbs(DEFAULT_DECAY, est.reverb_decay(), 1e-6);
}

test "reverb_model_estimator stationary skip" {
    const allocator = std.testing.allocator;
    var cfg = EchoCanceller3Config.default();
    cfg.filter.main.length_blocks = 40;
    var est = try ReverbModelEstimator.init(allocator, &cfg, 1);
    defer est.deinit();

    const num_blocks = cfg.filter.main.length_blocks;
    const h = try allocator.alloc(f32, num_blocks * common.FFT_LENGTH_BY_2);
    defer allocator.free(h);
    @memset(h, 0.0);
    var freq_resp = try allocator.alloc([FFT_LENGTH_BY_2_PLUS_1]f32, num_blocks);
    defer allocator.free(freq_resp);
    for (freq_resp) |*block| block.* = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;

    const initial_decay = est.reverb_decay();
    const ir = [_][]const f32{h};
    const fr = [_][]const [FFT_LENGTH_BY_2_PLUS_1]f32{freq_resp};
    const qualities = [_]?f32{1.0};
    const delays = [_]i32{2};
    const usable = [_]bool{true};

    est.update(&ir, &fr, &qualities, &delays, &usable, true); // stationary=true
    try std.testing.expectEqual(initial_decay, est.reverb_decay());
}
