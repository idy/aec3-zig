const std = @import("std");
const test_utils = @import("test_utils.zig");

pub const EchoAudibility = struct {
    smoothing: f32,
    last: f32 = 0.0,

    pub fn init(smoothing: f32) !EchoAudibility {
        if (smoothing < 0.0 or smoothing > 1.0) return error.InvalidSmoothing;
        return .{ .smoothing = smoothing };
    }

    pub fn update(self: *EchoAudibility, echo_power: f32, noise_power: f32) !f32 {
        if (echo_power < 0.0 or noise_power < 0.0) return error.InvalidPower;

        const inst = echo_power / @max(echo_power + noise_power, 1e-9);
        self.last = self.last * self.smoothing + inst * (1.0 - self.smoothing);
        self.last = std.math.clamp(self.last, 0.0, 1.0);
        return self.last;
    }
};

test "echo_audibility audibility estimation" {
    var audibility = try EchoAudibility.init(0.0);
    const value = try audibility.update(4.0, 1.0);
    try std.testing.expect(value > 0.7 and value < 0.9);
}

test "echo_audibility low echo boundary" {
    var audibility = try EchoAudibility.init(0.0);
    const value = try audibility.update(0.001, 1.0);
    try std.testing.expect(value < 0.01);
}

test "echo_audibility high echo saturation" {
    var audibility = try EchoAudibility.init(0.0);
    const value = try audibility.update(1000.0, 0.001);
    try std.testing.expect(value > 0.99);
}

test "echo_audibility time-varying tracking" {
    var audibility = try EchoAudibility.init(0.8);
    const v1 = try audibility.update(1.0, 1.0);
    const v2 = try audibility.update(10.0, 1.0);
    try std.testing.expect(v2 > v1);
}

test "echo_audibility invalid smoothing" {
    try std.testing.expectError(error.InvalidSmoothing, EchoAudibility.init(-0.1));
    try std.testing.expectError(error.InvalidSmoothing, EchoAudibility.init(1.1));
}

test "echo_audibility invalid power" {
    var audibility = try EchoAudibility.init(0.5);
    try std.testing.expectError(error.InvalidPower, audibility.update(-1.0, 1.0));
    try std.testing.expectError(error.InvalidPower, audibility.update(1.0, -1.0));
}

test "echo_audibility test_utils sine and mixed integration" {
    const allocator = std.testing.allocator;
    const near = try test_utils.generateSineWave(allocator, 440.0, 16_000.0, 2.0);
    defer allocator.free(near);
    const echo = try test_utils.generateNoise(allocator, 77, 0.001, near.len);
    defer allocator.free(echo);
    const noise = try test_utils.generateTestFrame(allocator, near.len, .zeros);
    defer allocator.free(noise);

    const mixed = try test_utils.generateMixedSignal(allocator, near, echo, noise, .{ 1.0, 0.5, 0.1 });
    defer allocator.free(mixed);

    var audibility = try EchoAudibility.init(0.0);
    const v = try audibility.update(@abs(mixed[0]), 1e-3);
    try std.testing.expect(v >= 0.0 and v <= 1.0);
}
