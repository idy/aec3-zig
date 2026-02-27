const std = @import("std");

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
