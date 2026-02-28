//! Estimates residual echo power spectrum.
//! Uses an exponential smoothing model to track the residual echo from
//! render power scaled by the echo path gain.
const std = @import("std");
const common = @import("../common/aec3_common.zig");

const FFT_LENGTH_BY_2_PLUS_1 = common.FFT_LENGTH_BY_2_PLUS_1;

/// Residual echo power spectrum estimator.
///
/// For each frequency bin, the raw residual echo estimate is
/// `echo_path_gain * render_power[k]`, which is then exponentially smoothed
/// with the previous estimate using the configured smoothing factor.
pub const ResidualEchoEstimator = struct {
    const Self = @This();

    echo_path_gain: f32,
    smoothing: f32,
    previous_estimate: [FFT_LENGTH_BY_2_PLUS_1]f32,

    /// Create a new residual echo estimator.
    ///
    /// Returns `error.InvalidEchoPathGain` if `echo_path_gain` is negative or > 1.
    /// Returns `error.InvalidSmoothing` if `smoothing` is not in [0, 1].
    pub fn init(echo_path_gain: f32, smoothing: f32) !Self {
        if (echo_path_gain < 0.0 or echo_path_gain > 1.0) return error.InvalidEchoPathGain;
        if (smoothing < 0.0 or smoothing > 1.0) return error.InvalidSmoothing;
        return .{
            .echo_path_gain = echo_path_gain,
            .smoothing = smoothing,
            .previous_estimate = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1,
        };
    }

    /// Estimate the residual echo power spectrum.
    ///
    /// Both `render_power` and `result` must have length `FFT_LENGTH_BY_2_PLUS_1`.
    /// Returns `error.LengthMismatch` otherwise.
    ///
    /// Per bin:
    ///   raw = echo_path_gain * render_power[k]
    ///   smoothed = previous * smoothing + raw * (1 - smoothing)
    pub fn estimate(self: *Self, render_power: []const f32, result: []f32) !void {
        if (render_power.len != FFT_LENGTH_BY_2_PLUS_1 or result.len != FFT_LENGTH_BY_2_PLUS_1) {
            return error.LengthMismatch;
        }

        const alpha = self.smoothing;
        const one_minus_alpha = 1.0 - alpha;

        for (result, render_power, &self.previous_estimate) |*r, power, *prev| {
            const raw = self.echo_path_gain * power;
            const smoothed = prev.* * alpha + raw * one_minus_alpha;
            r.* = smoothed;
            prev.* = smoothed;
        }
    }

    /// Reset the internal smoothing state to zero.
    pub fn reset(self: *Self) void {
        self.previous_estimate = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    }
};

// ---------------------------------------------------------------------------
// Inline tests
// ---------------------------------------------------------------------------

test "residual_echo_estimator stable path" {
    var est = try ResidualEchoEstimator.init(0.5, 0.0);
    var render_power = [_]f32{100.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var result: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;

    // smoothing=0 -> no history, result = gain * power = 0.5 * 100 = 50
    try est.estimate(&render_power, &result);

    for (result) |v| {
        try std.testing.expectApproxEqAbs(@as(f32, 50.0), v, 1e-6);
    }
}

test "residual_echo_estimator varying power" {
    var est = try ResidualEchoEstimator.init(0.5, 0.0);

    var power_low = [_]f32{10.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var power_high = [_]f32{200.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var result: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;

    try est.estimate(&power_low, &result);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), result[0], 1e-6);

    try est.estimate(&power_high, &result);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), result[0], 1e-6);
}

test "residual_echo_estimator zero echo path" {
    var est = try ResidualEchoEstimator.init(0.0, 0.0);
    var render_power = [_]f32{1000.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var result: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;

    try est.estimate(&render_power, &result);

    for (result) |v| {
        try std.testing.expectEqual(@as(f32, 0.0), v);
    }
}

test "residual_echo_estimator smoothing convergence" {
    // With smoothing=0.9, the estimate converges slowly to the steady-state.
    var est = try ResidualEchoEstimator.init(0.5, 0.9);
    var render_power = [_]f32{100.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var result: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;

    // First iteration: smoothed = 0 * 0.9 + 50 * 0.1 = 5.0
    try est.estimate(&render_power, &result);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), result[0], 1e-6);

    // Second iteration: smoothed = 5 * 0.9 + 50 * 0.1 = 4.5 + 5 = 9.5
    try est.estimate(&render_power, &result);
    try std.testing.expectApproxEqAbs(@as(f32, 9.5), result[0], 1e-5);

    // After many iterations, should converge toward 50 (steady state).
    for (0..200) |_| {
        try est.estimate(&render_power, &result);
    }
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), result[0], 0.1);
}

test "residual_echo_estimator smoothing zero passes through" {
    // smoothing=0 means no history at all.
    var est = try ResidualEchoEstimator.init(1.0, 0.0);
    var render_power = [_]f32{42.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var result: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;

    try est.estimate(&render_power, &result);
    for (result) |v| {
        try std.testing.expectApproxEqAbs(@as(f32, 42.0), v, 1e-6);
    }

    // Change power immediately.
    render_power = [_]f32{10.0} ** FFT_LENGTH_BY_2_PLUS_1;
    try est.estimate(&render_power, &result);
    for (result) |v| {
        try std.testing.expectApproxEqAbs(@as(f32, 10.0), v, 1e-6);
    }
}

test "residual_echo_estimator reset clears state" {
    var est = try ResidualEchoEstimator.init(0.5, 0.9);
    var render_power = [_]f32{100.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var result: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;

    // Build up some state.
    for (0..10) |_| {
        try est.estimate(&render_power, &result);
    }
    try std.testing.expect(est.previous_estimate[0] > 0.0);

    est.reset();
    for (est.previous_estimate) |v| {
        try std.testing.expectEqual(@as(f32, 0.0), v);
    }
}

test "residual_echo_estimator invalid echo_path_gain" {
    try std.testing.expectError(error.InvalidEchoPathGain, ResidualEchoEstimator.init(-0.1, 0.5));
    try std.testing.expectError(error.InvalidEchoPathGain, ResidualEchoEstimator.init(1.1, 0.5));
}

test "residual_echo_estimator invalid smoothing" {
    try std.testing.expectError(error.InvalidSmoothing, ResidualEchoEstimator.init(0.5, -0.1));
    try std.testing.expectError(error.InvalidSmoothing, ResidualEchoEstimator.init(0.5, 1.1));
}

test "residual_echo_estimator length mismatch" {
    var est = try ResidualEchoEstimator.init(0.5, 0.5);
    var short_power = [_]f32{1.0} ** 10;
    var short_result = [_]f32{0.0} ** 10;
    try std.testing.expectError(error.LengthMismatch, est.estimate(&short_power, &short_result));
}

test "residual_echo_estimator boundary gain one" {
    // echo_path_gain = 1.0 -> result = render_power exactly.
    var est = try ResidualEchoEstimator.init(1.0, 0.0);
    var render_power = [_]f32{77.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var result: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;

    try est.estimate(&render_power, &result);
    for (result) |v| {
        try std.testing.expectApproxEqAbs(@as(f32, 77.0), v, 1e-6);
    }
}

test "residual_echo_estimator boundary smoothing one" {
    // smoothing=1.0 means the output never moves from the initial estimate (0).
    var est = try ResidualEchoEstimator.init(0.5, 1.0);
    var render_power = [_]f32{100.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var result: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;

    try est.estimate(&render_power, &result);
    // smoothed = 0 * 1.0 + 50 * 0.0 = 0
    for (result) |v| {
        try std.testing.expectEqual(@as(f32, 0.0), v);
    }
}
