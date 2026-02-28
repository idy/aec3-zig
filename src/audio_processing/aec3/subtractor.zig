const std = @import("std");
const aec3_common = @import("aec3_common.zig");

const BLOCK_SIZE = aec3_common.BLOCK_SIZE;
const FFT_LENGTH_BY_2_PLUS_1 = aec3_common.FFT_LENGTH_BY_2_PLUS_1;

/// Time-domain subtractor that removes echo estimate from captured signal.
///
/// Performs element-wise subtraction: residual[i] = capture[i] - echo[i],
/// with output clamping to prevent overflow.
pub const Subtractor = struct {
    num_capture_channels: usize,
    smoothing: f32,
    previous_residual_energy: f32,

    const saturation_limit: f32 = 32767.0;

    pub fn init(num_capture_channels: usize, smoothing: f32) !Subtractor {
        if (num_capture_channels == 0) return error.InvalidChannels;
        if (smoothing < 0.0 or smoothing > 1.0) return error.InvalidSmoothing;
        return .{
            .num_capture_channels = num_capture_channels,
            .smoothing = smoothing,
            .previous_residual_energy = 0.0,
        };
    }

    /// Subtracts echo estimate from captured signal, producing residual.
    /// residual[i] = clamp(capture[i] - echo[i], -32767, 32767)
    pub fn process(
        self: *Subtractor,
        capture: []const f32,
        echo: []const f32,
        residual: []f32,
    ) !void {
        if (capture.len != echo.len or capture.len != residual.len) {
            return error.LengthMismatch;
        }
        if (capture.len == 0) return error.EmptyInput;

        var energy: f32 = 0.0;
        for (capture, echo, residual) |c, e, *r| {
            const diff = c - e;
            r.* = std.math.clamp(diff, -saturation_limit, saturation_limit);
            energy += r.* * r.*;
        }

        self.previous_residual_energy = self.previous_residual_energy * self.smoothing +
            energy * (1.0 - self.smoothing);
    }

    /// Computes energy of a signal block.
    pub fn compute_energy(signal: []const f32) f32 {
        var energy: f32 = 0.0;
        for (signal) |s| energy += s * s;
        return energy;
    }

    /// Returns the smoothed residual energy from the last process call.
    pub fn get_residual_energy(self: *const Subtractor) f32 {
        return self.previous_residual_energy;
    }

    /// Resets internal state.
    pub fn reset(self: *Subtractor) void {
        self.previous_residual_energy = 0.0;
    }
};

test "subtractor perfect subtraction" {
    var sub = try Subtractor.init(1, 0.0);
    var capture: [BLOCK_SIZE]f32 = undefined;
    var echo: [BLOCK_SIZE]f32 = undefined;
    var residual: [BLOCK_SIZE]f32 = undefined;

    for (&capture, &echo, 0..) |*c, *e, i| {
        const v: f32 = @as(f32, @floatFromInt(i)) * 100.0;
        c.* = v;
        e.* = v;
    }

    try sub.process(&capture, &echo, &residual);

    for (residual) |r| {
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), r, 1e-6);
    }
}

test "subtractor partial echo" {
    var sub = try Subtractor.init(1, 0.0);
    var capture: [BLOCK_SIZE]f32 = undefined;
    var echo: [BLOCK_SIZE]f32 = undefined;
    var residual: [BLOCK_SIZE]f32 = undefined;

    for (&capture, &echo, 0..) |*c, *e, i| {
        const v: f32 = 1000.0 + @as(f32, @floatFromInt(i)) * 50.0;
        c.* = v;
        e.* = v * 0.6;
    }

    try sub.process(&capture, &echo, &residual);

    const capture_energy = Subtractor.compute_energy(&capture);
    const residual_energy = Subtractor.compute_energy(&residual);
    try std.testing.expect(residual_energy < capture_energy);

    for (capture, echo, residual) |c, e, r| {
        try std.testing.expectApproxEqAbs(c - e, r, 1e-3);
    }
}

test "subtractor no echo" {
    var sub = try Subtractor.init(1, 0.0);
    var capture: [BLOCK_SIZE]f32 = undefined;
    var echo = [_]f32{0.0} ** BLOCK_SIZE;
    var residual: [BLOCK_SIZE]f32 = undefined;

    for (&capture, 0..) |*c, i| {
        c.* = 500.0 + @as(f32, @floatFromInt(i)) * 10.0;
    }

    try sub.process(&capture, &echo, &residual);

    for (capture, residual) |c, r| {
        try std.testing.expectApproxEqAbs(c, r, 1e-6);
    }
}

test "subtractor saturation clamping" {
    var sub = try Subtractor.init(1, 0.0);
    const capture = [_]f32{ 40000.0, -40000.0, 0.0, 20000.0 };
    const echo = [_]f32{ -10000.0, 10000.0, 0.0, -20000.0 };
    var residual: [4]f32 = undefined;

    try sub.process(&capture, &echo, &residual);

    // 40000 - (-10000) = 50000 → clamped to 32767
    try std.testing.expectApproxEqAbs(@as(f32, 32767.0), residual[0], 1e-3);
    // -40000 - 10000 = -50000 → clamped to -32767
    try std.testing.expectApproxEqAbs(@as(f32, -32767.0), residual[1], 1e-3);
    // 0 - 0 = 0
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), residual[2], 1e-6);
    // 20000 - (-20000) = 40000 → clamped to 32767
    try std.testing.expectApproxEqAbs(@as(f32, 32767.0), residual[3], 1e-3);
}

test "subtractor length mismatch error" {
    var sub = try Subtractor.init(1, 0.0);
    const capture = [_]f32{ 1.0, 2.0 };
    const echo = [_]f32{1.0};
    var residual: [2]f32 = undefined;
    try std.testing.expectError(error.LengthMismatch, sub.process(&capture, &echo, &residual));
}

test "subtractor empty input error" {
    var sub = try Subtractor.init(1, 0.0);
    const empty: []const f32 = &[_]f32{};
    var residual: [0]f32 = .{};
    try std.testing.expectError(error.EmptyInput, sub.process(empty, empty, &residual));
}

test "subtractor invalid channels" {
    try std.testing.expectError(error.InvalidChannels, Subtractor.init(0, 0.5));
}

test "subtractor invalid smoothing" {
    try std.testing.expectError(error.InvalidSmoothing, Subtractor.init(1, -0.1));
    try std.testing.expectError(error.InvalidSmoothing, Subtractor.init(1, 1.1));
}

test "subtractor energy tracking" {
    var sub = try Subtractor.init(1, 0.5);
    const capture = [_]f32{ 100.0, 200.0, 300.0, 400.0 };
    const echo = [_]f32{ 0.0, 0.0, 0.0, 0.0 };
    var residual: [4]f32 = undefined;

    try sub.process(&capture, &echo, &residual);
    const energy1 = sub.get_residual_energy();
    try std.testing.expect(energy1 > 0.0);

    // Second call with zero signal should decrease energy via smoothing
    const zero = [_]f32{ 0.0, 0.0, 0.0, 0.0 };
    try sub.process(&zero, &zero, &residual);
    const energy2 = sub.get_residual_energy();
    try std.testing.expect(energy2 < energy1);
}

test "subtractor reset" {
    var sub = try Subtractor.init(1, 0.0);
    const capture = [_]f32{100.0} ** 4;
    const echo = [_]f32{0.0} ** 4;
    var residual: [4]f32 = undefined;

    try sub.process(&capture, &echo, &residual);
    try std.testing.expect(sub.get_residual_energy() > 0.0);

    sub.reset();
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), sub.get_residual_energy(), 1e-6);
}

test "subtractor compute energy" {
    const signal = [_]f32{ 3.0, 4.0 };
    try std.testing.expectApproxEqAbs(@as(f32, 25.0), Subtractor.compute_energy(&signal), 1e-6);
}
