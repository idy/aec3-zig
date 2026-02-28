const std = @import("std");
const aec3_common = @import("../common/aec3_common.zig");

const FFT_LENGTH_BY_2_PLUS_1 = aec3_common.FFT_LENGTH_BY_2_PLUS_1;

/// Computes averaged render power spectrum with exponential reverb smoothing.
///
/// Each frequency bin is smoothed via a first-order IIR:
///   result[k] = previous[k] * smoothing + render_power[k] * (1 - smoothing)
/// which models the exponential decay of reverberant energy.
pub const AvgRenderReverb = struct {
    smoothing: f32,
    previous: [FFT_LENGTH_BY_2_PLUS_1]f32,

    pub fn init(smoothing: f32) !AvgRenderReverb {
        if (smoothing < 0.0 or smoothing > 1.0) return error.InvalidSmoothing;
        return .{
            .smoothing = smoothing,
            .previous = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1,
        };
    }

    /// Applies the reverb-smoothing IIR to `render_power` and writes the
    /// smoothed spectrum into `result`.  Both slices must have length
    /// `FFT_LENGTH_BY_2_PLUS_1`.
    pub fn update(self: *AvgRenderReverb, render_power: []const f32, result: []f32) !void {
        if (render_power.len != FFT_LENGTH_BY_2_PLUS_1 or result.len != FFT_LENGTH_BY_2_PLUS_1)
            return error.LengthMismatch;

        const one_minus_s = 1.0 - self.smoothing;
        for (0..FFT_LENGTH_BY_2_PLUS_1) |k| {
            const smoothed = self.previous[k] * self.smoothing + render_power[k] * one_minus_s;
            result[k] = smoothed;
            self.previous[k] = smoothed;
        }
    }

    /// Zeros the internal state so the next `update` starts fresh.
    pub fn reset(self: *AvgRenderReverb) void {
        self.previous = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "avg_render_reverb constant power converges" {
    var reverb = try AvgRenderReverb.init(0.8);
    const power = [_]f32{1.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var result: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;

    // After many iterations a constant input converges to the input value.
    for (0..200) |_| {
        try reverb.update(&power, &result);
    }
    for (result) |v| {
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), v, 1e-3);
    }
}

test "avg_render_reverb varying power" {
    var reverb = try AvgRenderReverb.init(0.5);
    var low = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var high = [_]f32{2.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var result: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;

    // Feed low then high – the result should sit between the two.
    try reverb.update(&low, &result);
    try reverb.update(&high, &result);
    for (result) |v| {
        try std.testing.expect(v > 0.0 and v < 2.0);
    }
}

test "avg_render_reverb zero input stays zero" {
    var reverb = try AvgRenderReverb.init(0.9);
    const zeros = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var result: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;

    try reverb.update(&zeros, &result);
    for (result) |v| {
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), v, 1e-9);
    }
}

test "avg_render_reverb reset clears state" {
    var reverb = try AvgRenderReverb.init(0.8);
    const power = [_]f32{5.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var result: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;

    try reverb.update(&power, &result);
    reverb.reset();
    for (reverb.previous) |v| {
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), v, 1e-9);
    }
}

test "avg_render_reverb length mismatch error" {
    var reverb = try AvgRenderReverb.init(0.5);
    var short_buf: [10]f32 = [_]f32{0.0} ** 10;
    var full_buf: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;
    try std.testing.expectError(error.LengthMismatch, reverb.update(&short_buf, &full_buf));
    try std.testing.expectError(error.LengthMismatch, reverb.update(&full_buf, &short_buf));
}

test "avg_render_reverb invalid smoothing" {
    try std.testing.expectError(error.InvalidSmoothing, AvgRenderReverb.init(-0.1));
    try std.testing.expectError(error.InvalidSmoothing, AvgRenderReverb.init(1.1));
}

test "avg_render_reverb boundary smoothing zero passes through" {
    // smoothing == 0 means no memory – output equals input.
    var reverb = try AvgRenderReverb.init(0.0);
    var power: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;
    for (0..FFT_LENGTH_BY_2_PLUS_1) |i| {
        power[i] = @floatFromInt(i);
    }
    var result: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;
    try reverb.update(&power, &result);
    for (0..FFT_LENGTH_BY_2_PLUS_1) |i| {
        try std.testing.expectApproxEqAbs(power[i], result[i], 1e-9);
    }
}
