const std = @import("std");
const test_utils = @import("test_utils.zig");

pub const ComfortNoiseGenerator = struct {
    prng: std.Random.DefaultPrng,

    pub fn init(seed: u64) ComfortNoiseGenerator {
        return .{ .prng = std.Random.DefaultPrng.init(seed) };
    }

    pub fn generate(self: *ComfortNoiseGenerator, out: []f32, power: f32) !void {
        if (power < 0.0) return error.InvalidPower;
        if (out.len == 0) return;

        if (power == 0.0) {
            @memset(out, 0.0);
            return;
        }

        const random = self.prng.random();
        var sum_sq: f32 = 0.0;
        for (out) |*sample| {
            sample.* = random.float(f32) * 2.0 - 1.0;
            sum_sq += sample.* * sample.*;
        }

        const mean_sq = sum_sq / @as(f32, @floatFromInt(out.len));
        const scale = @sqrt(power / @max(mean_sq, 1e-12));
        for (out) |*sample| sample.* = std.math.clamp(sample.* * scale, -1.0, 1.0);
    }
};

test "comfort_noise_generator noise generation" {
    var gen = ComfortNoiseGenerator.init(7);
    var out = [_]f32{0.0} ** 64;
    try gen.generate(out[0..], 0.1);

    var sum_abs: f32 = 0.0;
    for (out) |v| sum_abs += @abs(v);
    try std.testing.expect(sum_abs > 0.0);
}

test "comfort_noise_generator seed repeatability" {
    var g1 = ComfortNoiseGenerator.init(42);
    var g2 = ComfortNoiseGenerator.init(42);
    var a = [_]f32{0.0} ** 32;
    var b = [_]f32{0.0} ** 32;
    try g1.generate(a[0..], 0.2);
    try g2.generate(b[0..], 0.2);
    try std.testing.expectEqualSlices(f32, a[0..], b[0..]);
}

test "comfort_noise_generator zero power boundary" {
    var gen = ComfortNoiseGenerator.init(1);
    var out = [_]f32{1.0} ** 16;
    try gen.generate(out[0..], 0.0);
    for (out) |v| try std.testing.expectEqual(@as(f32, 0.0), v);
}

test "comfort_noise_generator max power saturation" {
    var gen = ComfortNoiseGenerator.init(2);
    var out = [_]f32{0.0} ** 64;
    try gen.generate(out[0..], 100.0);
    for (out) |v| try std.testing.expect(v <= 1.0 and v >= -1.0);
}

test "comfort_noise_generator power matching" {
    var gen = ComfortNoiseGenerator.init(9);
    var out = [_]f32{0.0} ** 256;
    const target_power: f32 = 0.05;
    try gen.generate(out[0..], target_power);

    var power: f32 = 0.0;
    for (out) |v| power += v * v;
    power /= @as(f32, @floatFromInt(out.len));
    try std.testing.expectApproxEqAbs(target_power, power, 0.02);
}

test "comfort_noise_generator invalid power" {
    var gen = ComfortNoiseGenerator.init(9);
    var out = [_]f32{0.0} ** 8;
    try std.testing.expectError(error.InvalidPower, gen.generate(out[0..], -0.01));
}

test "comfort_noise_generator test_utils noise integration" {
    const allocator = std.testing.allocator;
    const reference = try test_utils.generateNoise(allocator, 123, 0.02, 32);
    defer allocator.free(reference);

    var gen = ComfortNoiseGenerator.init(123);
    var out = [_]f32{0.0} ** 32;
    try gen.generate(out[0..], 0.02);

    // 两者都应为非零噪声序列，验证 test_utils 已接入测试流程。
    var ref_energy: f32 = 0.0;
    var out_energy: f32 = 0.0;
    for (reference, out) |r, o| {
        ref_energy += r * r;
        out_energy += o * o;
    }
    try std.testing.expect(ref_energy > 0.0);
    try std.testing.expect(out_energy > 0.0);
}
