const std = @import("std");

pub const Analysis = struct {
    residual_power: f32,
    residual_echo_likelihood: f32,
};

pub const SubtractorOutputAnalyzer = struct {
    noise_floor: f32,
    sensitivity: f32,

    pub fn init(noise_floor: f32, sensitivity: f32) !SubtractorOutputAnalyzer {
        if (noise_floor < 0.0 or sensitivity <= 0.0) return error.InvalidConfiguration;
        return .{ .noise_floor = noise_floor, .sensitivity = sensitivity };
    }

    pub fn analyze(self: *const SubtractorOutputAnalyzer, residual: []const f32) !Analysis {
        if (residual.len == 0) return error.EmptyInput;

        var power: f32 = 0.0;
        for (residual) |sample| power += sample * sample;
        power /= @as(f32, @floatFromInt(residual.len));

        const scaled = power * self.sensitivity;
        const likelihood = scaled / (scaled + self.noise_floor + 1e-9);
        return .{
            .residual_power = power,
            .residual_echo_likelihood = std.math.clamp(likelihood, 0.0, 1.0),
        };
    }
};

test "subtractor_output_analyzer quality metrics" {
    const analyzer = try SubtractorOutputAnalyzer.init(0.1, 1.0);
    const in = [_]f32{ 0.5, 0.5, 0.5, 0.5 };
    const a = try analyzer.analyze(in[0..]);
    try std.testing.expect(a.residual_power > 0.2);
    try std.testing.expect(a.residual_echo_likelihood > 0.5);
}

test "subtractor_output_analyzer silent input" {
    const analyzer = try SubtractorOutputAnalyzer.init(0.1, 1.0);
    const in = [_]f32{ 0.0, 0.0, 0.0, 0.0 };
    const a = try analyzer.analyze(in[0..]);
    try std.testing.expectEqual(@as(f32, 0.0), a.residual_power);
    try std.testing.expect(a.residual_echo_likelihood <= 1e-6);
}

test "subtractor_output_analyzer echo variation tracking" {
    const analyzer = try SubtractorOutputAnalyzer.init(0.01, 1.0);
    const low = [_]f32{ 0.01, 0.01, 0.01, 0.01 };
    const high = [_]f32{ 1.0, 1.0, 1.0, 1.0 };

    const a_low = try analyzer.analyze(low[0..]);
    const a_high = try analyzer.analyze(high[0..]);
    try std.testing.expect(a_high.residual_echo_likelihood > a_low.residual_echo_likelihood);
}

test "subtractor_output_analyzer invalid parameters error" {
    try std.testing.expectError(error.InvalidConfiguration, SubtractorOutputAnalyzer.init(-1.0, 1.0));
    try std.testing.expectError(error.InvalidConfiguration, SubtractorOutputAnalyzer.init(0.0, 0.0));
    const analyzer = try SubtractorOutputAnalyzer.init(0.1, 1.0);
    try std.testing.expectError(error.EmptyInput, analyzer.analyze(&[_]f32{}));
}
