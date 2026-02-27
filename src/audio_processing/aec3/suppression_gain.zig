//! Wiener-filter-style suppression gain computation.
//! Computes per-bin suppression gains from ERLE, nearend power, echo power,
//! and reverb power, with temporal smoothing.
const std = @import("std");
const common = @import("aec3_common.zig");

const FFT_LENGTH_BY_2_PLUS_1 = common.FFT_LENGTH_BY_2_PLUS_1;

/// High-nearend-power threshold. When nearend power exceeds this value the
/// gain is boosted toward 1.0 to protect the near-end signal.
const HIGH_NEAREND_THRESHOLD: f32 = 1.0e6;

/// The gain applied when the nearend signal is dominant.
const HIGH_NEAREND_GAIN: f32 = 0.9;

/// Wiener-filter-style suppression gain computer.
///
/// For each frequency bin the base Wiener gain is `erle / (erle + 1)`.
/// When nearend power is high relative to echo, the gain is boosted toward
/// 1.0 to avoid suppressing the near-end speech. Gains are temporally
/// smoothed via an IIR and clamped to `[min_gain, 1.0]`.
pub const SuppressionGain = struct {
    const Self = @This();

    last_gain: [FFT_LENGTH_BY_2_PLUS_1]f32,
    smoothing: f32,
    min_gain: f32,

    /// Create a new suppression gain computer.
    ///
    /// Returns `error.InvalidSmoothing` if `smoothing` is not in [0, 1].
    /// Returns `error.InvalidMinGain` if `min_gain` is not in [0, 1].
    pub fn init(smoothing: f32, min_gain: f32) !Self {
        if (smoothing < 0.0 or smoothing > 1.0) return error.InvalidSmoothing;
        if (min_gain < 0.0 or min_gain > 1.0) return error.InvalidMinGain;
        return .{
            .last_gain = [_]f32{1.0} ** FFT_LENGTH_BY_2_PLUS_1,
            .smoothing = smoothing,
            .min_gain = min_gain,
        };
    }

    /// Compute per-bin suppression gains.
    ///
    /// All power slices and `gains` must have length `FFT_LENGTH_BY_2_PLUS_1`.
    /// Returns `error.InvalidErle` if `erle` is negative.
    /// Returns `error.LengthMismatch` if any slice has the wrong length.
    ///
    /// The algorithm:
    ///   1. wiener = erle / (erle + 1)
    ///   2. For each bin, compute a frequency-dependent factor from
    ///      echo + reverb power (frequency shaping).
    ///   3. If nearend power is high (> HIGH_NEAREND_THRESHOLD), boost gain.
    ///   4. Smooth with the previous frame gain.
    ///   5. Clamp to [min_gain, 1.0].
    pub fn compute(
        self: *Self,
        erle: f32,
        nearend_power: []const f32,
        echo_power: []const f32,
        reverb_power: []const f32,
        gains: []f32,
    ) !void {
        if (erle < 0.0) return error.InvalidErle;
        if (nearend_power.len != FFT_LENGTH_BY_2_PLUS_1 or
            echo_power.len != FFT_LENGTH_BY_2_PLUS_1 or
            reverb_power.len != FFT_LENGTH_BY_2_PLUS_1 or
            gains.len != FFT_LENGTH_BY_2_PLUS_1)
        {
            return error.LengthMismatch;
        }

        const wiener_base = erle / (erle + 1.0);

        for (gains, nearend_power, echo_power, reverb_power, 0..) |*g, ne, echo, reverb, i| {
            // Frequency-dependent shaping: higher bins attenuated by echo+reverb
            const total_echo = echo + reverb;
            const freq_factor = blk: {
                if (total_echo > 0.0 and ne > 0.0) {
                    // Signal-to-interference ratio drives frequency shaping.
                    const sir = ne / (ne + total_echo);
                    break :blk sir;
                }
                // When echo is zero or nearend is zero, use base wiener gain.
                break :blk 1.0;
            };

            var gain: f32 = undefined;

            // High nearend protection: when nearend power is very strong,
            // output a fixed high gain to preserve the near-end signal.
            if (ne > HIGH_NEAREND_THRESHOLD) {
                gain = HIGH_NEAREND_GAIN;
            } else {
                gain = wiener_base * freq_factor;
            }

            // Temporal smoothing with the previous frame.
            gain = self.last_gain[i] * self.smoothing + gain * (1.0 - self.smoothing);

            // Clamp to valid range.
            gain = std.math.clamp(gain, self.min_gain, 1.0);

            g.* = gain;
            self.last_gain[i] = gain;
        }
    }
};

// ---------------------------------------------------------------------------
// Inline tests
// ---------------------------------------------------------------------------

test "suppression_gain high erle uniform" {
    // erle=10 -> wiener = 10/11 ~= 0.909091
    var sg = try SuppressionGain.init(0.0, 0.0);
    const nearend = [_]f32{1.0} ** FFT_LENGTH_BY_2_PLUS_1;
    const echo = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    const reverb = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var gains: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;

    try sg.compute(10.0, &nearend, &echo, &reverb, &gains);

    const expected: f32 = 10.0 / 11.0;
    for (gains) |g| {
        try std.testing.expectApproxEqAbs(expected, g, 1e-5);
    }
}

test "suppression_gain low erle uniform" {
    // erle=2 -> wiener = 2/3 ~= 0.666667
    var sg = try SuppressionGain.init(0.0, 0.0);
    const nearend = [_]f32{1.0} ** FFT_LENGTH_BY_2_PLUS_1;
    const echo = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    const reverb = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var gains: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;

    try sg.compute(2.0, &nearend, &echo, &reverb, &gains);

    const expected: f32 = 2.0 / 3.0;
    for (gains) |g| {
        try std.testing.expectApproxEqAbs(expected, g, 1e-5);
    }
}

test "suppression_gain very high erle" {
    // erle=30 -> wiener = 30/31 ~= 0.967742
    var sg = try SuppressionGain.init(0.0, 0.0);
    const nearend = [_]f32{1.0} ** FFT_LENGTH_BY_2_PLUS_1;
    const echo = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    const reverb = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var gains: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;

    try sg.compute(30.0, &nearend, &echo, &reverb, &gains);

    const expected: f32 = 30.0 / 31.0;
    for (gains) |g| {
        try std.testing.expectApproxEqAbs(expected, g, 1e-5);
    }
}

test "suppression_gain high nearend protection" {
    // When nearend > 1e6, gain should be 0.9 regardless of ERLE.
    var sg = try SuppressionGain.init(0.0, 0.0);
    const nearend = [_]f32{2.0e6} ** FFT_LENGTH_BY_2_PLUS_1;
    const echo = [_]f32{100.0} ** FFT_LENGTH_BY_2_PLUS_1;
    const reverb = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var gains: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;

    try sg.compute(5.0, &nearend, &echo, &reverb, &gains);

    for (gains) |g| {
        try std.testing.expectApproxEqAbs(@as(f32, 0.9), g, 1e-5);
    }
}

test "suppression_gain zero nearend with echo" {
    // nearend=0, echo>0 -> freq_factor=1.0, gain = wiener_base * 1.0
    var sg = try SuppressionGain.init(0.0, 0.0);
    const nearend = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    const echo = [_]f32{100.0} ** FFT_LENGTH_BY_2_PLUS_1;
    const reverb = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var gains: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;

    try sg.compute(10.0, &nearend, &echo, &reverb, &gains);

    const expected: f32 = 10.0 / 11.0;
    for (gains) |g| {
        try std.testing.expectApproxEqAbs(expected, g, 1e-5);
    }
}

test "suppression_gain smoothing behavior" {
    // With smoothing=0.5, gain is averaged with last_gain (initially 1.0).
    var sg = try SuppressionGain.init(0.5, 0.0);
    const nearend = [_]f32{1.0} ** FFT_LENGTH_BY_2_PLUS_1;
    const echo = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    const reverb = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var gains: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;

    // erle=2 -> raw wiener = 2/3
    // smoothed = 1.0 * 0.5 + (2/3) * 0.5 = 0.5 + 0.333 = 0.833
    try sg.compute(2.0, &nearend, &echo, &reverb, &gains);

    const expected: f32 = 1.0 * 0.5 + (2.0 / 3.0) * 0.5;
    try std.testing.expectApproxEqAbs(expected, gains[0], 1e-5);

    // Second call: smoothed = 0.833 * 0.5 + (2/3) * 0.5
    try sg.compute(2.0, &nearend, &echo, &reverb, &gains);
    const expected2: f32 = expected * 0.5 + (2.0 / 3.0) * 0.5;
    try std.testing.expectApproxEqAbs(expected2, gains[0], 1e-5);
}

test "suppression_gain min_gain floor" {
    // erle=0 -> wiener = 0, but min_gain=0.2 should clamp.
    var sg = try SuppressionGain.init(0.0, 0.2);
    const nearend = [_]f32{1.0} ** FFT_LENGTH_BY_2_PLUS_1;
    const echo = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    const reverb = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var gains: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;

    try sg.compute(0.0, &nearend, &echo, &reverb, &gains);

    for (gains) |g| {
        try std.testing.expectApproxEqAbs(@as(f32, 0.2), g, 1e-5);
    }
}

test "suppression_gain frequency shaping with echo" {
    // When nearend and echo are both present, freq_factor = ne / (ne + echo)
    var sg = try SuppressionGain.init(0.0, 0.0);
    // nearend=1.0, echo=1.0 -> sir = 0.5; gain = wiener * 0.5
    const nearend = [_]f32{1.0} ** FFT_LENGTH_BY_2_PLUS_1;
    const echo = [_]f32{1.0} ** FFT_LENGTH_BY_2_PLUS_1;
    const reverb = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var gains: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;

    try sg.compute(10.0, &nearend, &echo, &reverb, &gains);

    const wiener: f32 = 10.0 / 11.0;
    const expected: f32 = wiener * 0.5;
    for (gains) |g| {
        try std.testing.expectApproxEqAbs(expected, g, 1e-5);
    }
}

test "suppression_gain invalid erle" {
    var sg = try SuppressionGain.init(0.0, 0.0);
    const power = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var gains: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;
    try std.testing.expectError(error.InvalidErle, sg.compute(-1.0, &power, &power, &power, &gains));
}

test "suppression_gain invalid smoothing" {
    try std.testing.expectError(error.InvalidSmoothing, SuppressionGain.init(-0.1, 0.0));
    try std.testing.expectError(error.InvalidSmoothing, SuppressionGain.init(1.1, 0.0));
}

test "suppression_gain invalid min_gain" {
    try std.testing.expectError(error.InvalidMinGain, SuppressionGain.init(0.0, -0.1));
    try std.testing.expectError(error.InvalidMinGain, SuppressionGain.init(0.0, 1.1));
}

test "suppression_gain length mismatch" {
    var sg = try SuppressionGain.init(0.0, 0.0);
    var short = [_]f32{0.0} ** 10;
    const full = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var gains: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;
    try std.testing.expectError(error.LengthMismatch, sg.compute(1.0, &short, &full, &full, &gains));
}

test "suppression_gain gains stay in valid range" {
    var sg = try SuppressionGain.init(0.5, 0.1);
    const nearend = [_]f32{500.0} ** FFT_LENGTH_BY_2_PLUS_1;
    const echo = [_]f32{100.0} ** FFT_LENGTH_BY_2_PLUS_1;
    const reverb = [_]f32{50.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var gains: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;

    // Run multiple iterations.
    for (0..10) |_| {
        try sg.compute(5.0, &nearend, &echo, &reverb, &gains);
    }

    for (gains) |g| {
        try std.testing.expect(g >= 0.1 and g <= 1.0);
    }
}
