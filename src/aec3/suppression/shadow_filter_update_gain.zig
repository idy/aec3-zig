//! NLMS-style gain computer for the shadow adaptive filter.
//! Computes per-bin update gains from render power, gated by a noise floor.
const std = @import("std");
const common = @import("../common/aec3_common.zig");

const FFT_LENGTH_BY_2_PLUS_1 = common.FFT_LENGTH_BY_2_PLUS_1;

/// NLMS-style gain computer for the shadow adaptive filter.
///
/// For each frequency bin, the gain is `rate / render_power[k]` when the
/// render power exceeds the noise gate, clamped to [0, 1]; otherwise the
/// gain is zero.
pub const ShadowFilterUpdateGain = struct {
    const Self = @This();

    rate: f32,
    noise_gate: f32,
    previous_gain: f32,

    /// Create a new shadow filter update gain with the given NLMS rate and
    /// noise gate threshold.
    ///
    /// Returns `error.InvalidRate` if `rate` is not in [0, 1].
    /// Returns `error.InvalidNoiseGate` if `noise_gate` is negative.
    pub fn init(rate: f32, noise_gate: f32) !Self {
        if (rate < 0.0 or rate > 1.0) return error.InvalidRate;
        if (noise_gate < 0.0) return error.InvalidNoiseGate;
        return .{
            .rate = rate,
            .noise_gate = noise_gate,
            .previous_gain = 0.0,
        };
    }

    /// Compute per-bin NLMS gains from render power.
    ///
    /// Both `render_power` and `gains` must have length `FFT_LENGTH_BY_2_PLUS_1`.
    /// Returns `error.LengthMismatch` otherwise.
    pub fn compute(self: *Self, render_power: []const f32, gains: []f32) !void {
        if (render_power.len != FFT_LENGTH_BY_2_PLUS_1 or gains.len != FFT_LENGTH_BY_2_PLUS_1) {
            return error.LengthMismatch;
        }

        for (render_power, gains) |power, *g| {
            if (power > self.noise_gate) {
                g.* = std.math.clamp(self.rate / power, 0.0, 1.0);
            } else {
                g.* = 0.0;
            }
        }

        // Track the DC bin gain as previous_gain for potential external use.
        self.previous_gain = gains[0];
    }

    /// Reset internal state.
    pub fn reset(self: *Self) void {
        self.previous_gain = 0.0;
    }
};

// ---------------------------------------------------------------------------
// Inline tests
// ---------------------------------------------------------------------------

test "shadow_filter_update_gain normal computation" {
    var sfug = try ShadowFilterUpdateGain.init(0.5, 0.01);
    var render_power = [_]f32{2.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var gains: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;

    try sfug.compute(&render_power, &gains);

    // Expected: 0.5 / 2.0 = 0.25
    for (gains) |g| {
        try std.testing.expectApproxEqAbs(@as(f32, 0.25), g, 1e-6);
    }
}

test "shadow_filter_update_gain low power produces zero" {
    var sfug = try ShadowFilterUpdateGain.init(0.5, 1.0);
    var render_power = [_]f32{0.5} ** FFT_LENGTH_BY_2_PLUS_1;
    var gains: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;

    try sfug.compute(&render_power, &gains);

    // All power values are below the noise gate of 1.0.
    for (gains) |g| {
        try std.testing.expectEqual(@as(f32, 0.0), g);
    }
}

test "shadow_filter_update_gain clamping to one" {
    // rate / power = 0.8 / 0.5 = 1.6, should clamp to 1.0
    var sfug = try ShadowFilterUpdateGain.init(0.8, 0.0);
    var render_power = [_]f32{0.5} ** FFT_LENGTH_BY_2_PLUS_1;
    var gains: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;

    try sfug.compute(&render_power, &gains);

    for (gains) |g| {
        try std.testing.expectEqual(@as(f32, 1.0), g);
    }
}

test "shadow_filter_update_gain zero render power" {
    var sfug = try ShadowFilterUpdateGain.init(0.5, 0.0);
    var render_power = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var gains: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;

    try sfug.compute(&render_power, &gains);

    // Zero is not > 0.0 (noise_gate), so gain = 0.
    for (gains) |g| {
        try std.testing.expectEqual(@as(f32, 0.0), g);
    }
}

test "shadow_filter_update_gain mixed power levels" {
    var sfug = try ShadowFilterUpdateGain.init(0.5, 0.1);
    var render_power = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    render_power[0] = 2.0; // above gate -> 0.5/2 = 0.25
    render_power[1] = 0.05; // below gate -> 0.0

    var gains: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;
    try sfug.compute(&render_power, &gains);

    try std.testing.expectApproxEqAbs(@as(f32, 0.25), gains[0], 1e-6);
    try std.testing.expectEqual(@as(f32, 0.0), gains[1]);
}

test "shadow_filter_update_gain reset clears previous_gain" {
    var sfug = try ShadowFilterUpdateGain.init(0.5, 0.0);
    var render_power = [_]f32{1.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var gains: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;
    try sfug.compute(&render_power, &gains);
    try std.testing.expect(sfug.previous_gain > 0.0);

    sfug.reset();
    try std.testing.expectEqual(@as(f32, 0.0), sfug.previous_gain);
}

test "shadow_filter_update_gain invalid rate" {
    try std.testing.expectError(error.InvalidRate, ShadowFilterUpdateGain.init(-0.1, 0.0));
    try std.testing.expectError(error.InvalidRate, ShadowFilterUpdateGain.init(1.1, 0.0));
}

test "shadow_filter_update_gain invalid noise_gate" {
    try std.testing.expectError(error.InvalidNoiseGate, ShadowFilterUpdateGain.init(0.5, -1.0));
}

test "shadow_filter_update_gain length mismatch" {
    var sfug = try ShadowFilterUpdateGain.init(0.5, 0.0);
    var short_power = [_]f32{1.0} ** 10;
    var short_gains = [_]f32{0.0} ** 10;
    try std.testing.expectError(error.LengthMismatch, sfug.compute(&short_power, &short_gains));
}

test "shadow_filter_update_gain boundary rate zero" {
    var sfug = try ShadowFilterUpdateGain.init(0.0, 0.0);
    var render_power = [_]f32{1.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var gains: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;
    try sfug.compute(&render_power, &gains);

    // rate=0 -> gain = 0/power = 0
    for (gains) |g| {
        try std.testing.expectEqual(@as(f32, 0.0), g);
    }
}

test "shadow_filter_update_gain boundary rate one" {
    var sfug = try ShadowFilterUpdateGain.init(1.0, 0.0);
    var render_power = [_]f32{1.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var gains: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;
    try sfug.compute(&render_power, &gains);

    // rate=1, power=1 -> gain = 1.0
    for (gains) |g| {
        try std.testing.expectEqual(@as(f32, 1.0), g);
    }
}
