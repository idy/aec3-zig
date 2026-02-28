//! Applies frequency-domain suppression gains to a signal.
//! Element-wise multiplication with saturation clamping.
const std = @import("std");
const common = @import("aec3_common.zig");

const FFT_LENGTH_BY_2_PLUS_1 = common.FFT_LENGTH_BY_2_PLUS_1;

/// Applies frequency-domain suppression gains to a signal.
///
/// Each frequency bin of the signal is multiplied by the corresponding gain
/// and the result is clamped to the 16-bit PCM range [-32768, 32767].
pub const SuppressionFilter = struct {
    const Self = @This();

    sample_rate_hz: i32,
    num_capture_channels: usize,

    /// Create a new suppression filter.
    ///
    /// Returns `error.InvalidSampleRate` if the sample rate is not a valid
    /// full-band rate (16000, 32000, or 48000 Hz).
    /// Returns `error.InvalidChannelCount` if `num_capture_channels` is zero.
    pub fn init(sample_rate_hz: i32, num_capture_channels: usize) !Self {
        if (!common.valid_full_band_rate(sample_rate_hz)) return error.InvalidSampleRate;
        if (num_capture_channels == 0) return error.InvalidChannelCount;
        return .{
            .sample_rate_hz = sample_rate_hz,
            .num_capture_channels = num_capture_channels,
        };
    }

    /// Apply suppression gains to `signal` in place.
    ///
    /// Both `signal` and `gains` must have length `FFT_LENGTH_BY_2_PLUS_1`.
    /// Each element is multiplied and clamped to [-32768, 32767].
    /// Returns `error.LengthMismatch` if slice lengths differ or are not
    /// `FFT_LENGTH_BY_2_PLUS_1`.
    pub fn apply(_: *const Self, signal: []f32, gains: []const f32) !void {
        if (signal.len != FFT_LENGTH_BY_2_PLUS_1 or gains.len != FFT_LENGTH_BY_2_PLUS_1) {
            return error.LengthMismatch;
        }

        for (signal, gains) |*s, g| {
            s.* = std.math.clamp(s.* * g, -32768.0, 32767.0);
        }
    }
};

// ---------------------------------------------------------------------------
// Inline tests
// ---------------------------------------------------------------------------

test "suppression_filter unity gain preservation" {
    const sf = try SuppressionFilter.init(16000, 1);
    var signal = [_]f32{100.0} ** FFT_LENGTH_BY_2_PLUS_1;
    const gains = [_]f32{1.0} ** FFT_LENGTH_BY_2_PLUS_1;

    try sf.apply(&signal, &gains);

    for (signal) |v| {
        try std.testing.expectApproxEqAbs(@as(f32, 100.0), v, 1e-6);
    }
}

test "suppression_filter zero gain suppression" {
    const sf = try SuppressionFilter.init(16000, 1);
    var signal = [_]f32{500.0} ** FFT_LENGTH_BY_2_PLUS_1;
    const gains = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;

    try sf.apply(&signal, &gains);

    for (signal) |v| {
        try std.testing.expectEqual(@as(f32, 0.0), v);
    }
}

test "suppression_filter frequency selective" {
    const sf = try SuppressionFilter.init(48000, 2);
    var signal = [_]f32{200.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var gains = [_]f32{1.0} ** FFT_LENGTH_BY_2_PLUS_1;
    gains[0] = 0.5;
    gains[1] = 0.0;

    try sf.apply(&signal, &gains);

    try std.testing.expectApproxEqAbs(@as(f32, 100.0), signal[0], 1e-6);
    try std.testing.expectEqual(@as(f32, 0.0), signal[1]);
    try std.testing.expectApproxEqAbs(@as(f32, 200.0), signal[2], 1e-6);
}

test "suppression_filter saturation clamping positive" {
    const sf = try SuppressionFilter.init(16000, 1);
    var signal = [_]f32{30000.0} ** FFT_LENGTH_BY_2_PLUS_1;
    const gains = [_]f32{1.5} ** FFT_LENGTH_BY_2_PLUS_1;

    try sf.apply(&signal, &gains);

    // 30000 * 1.5 = 45000, clamped to 32767
    for (signal) |v| {
        try std.testing.expectEqual(@as(f32, 32767.0), v);
    }
}

test "suppression_filter saturation clamping negative" {
    const sf = try SuppressionFilter.init(16000, 1);
    var signal = [_]f32{-30000.0} ** FFT_LENGTH_BY_2_PLUS_1;
    const gains = [_]f32{1.5} ** FFT_LENGTH_BY_2_PLUS_1;

    try sf.apply(&signal, &gains);

    // -30000 * 1.5 = -45000, clamped to -32768
    for (signal) |v| {
        try std.testing.expectEqual(@as(f32, -32768.0), v);
    }
}

test "suppression_filter half gain" {
    const sf = try SuppressionFilter.init(32000, 1);
    var signal = [_]f32{1000.0} ** FFT_LENGTH_BY_2_PLUS_1;
    const gains = [_]f32{0.5} ** FFT_LENGTH_BY_2_PLUS_1;

    try sf.apply(&signal, &gains);

    for (signal) |v| {
        try std.testing.expectApproxEqAbs(@as(f32, 500.0), v, 1e-6);
    }
}

test "suppression_filter invalid sample rate" {
    try std.testing.expectError(error.InvalidSampleRate, SuppressionFilter.init(8000, 1));
    try std.testing.expectError(error.InvalidSampleRate, SuppressionFilter.init(0, 1));
}

test "suppression_filter invalid channel count" {
    try std.testing.expectError(error.InvalidChannelCount, SuppressionFilter.init(16000, 0));
}

test "suppression_filter length mismatch" {
    const sf = try SuppressionFilter.init(16000, 1);
    var short_signal = [_]f32{1.0} ** 10;
    var short_gains = [_]f32{1.0} ** 10;
    try std.testing.expectError(error.LengthMismatch, sf.apply(&short_signal, &short_gains));
}

test "suppression_filter negative signal with unity gain" {
    const sf = try SuppressionFilter.init(16000, 1);
    var signal = [_]f32{-200.0} ** FFT_LENGTH_BY_2_PLUS_1;
    const gains = [_]f32{1.0} ** FFT_LENGTH_BY_2_PLUS_1;

    try sf.apply(&signal, &gains);

    for (signal) |v| {
        try std.testing.expectApproxEqAbs(@as(f32, -200.0), v, 1e-6);
    }
}
