const std = @import("std");

pub const TestPattern = enum {
    zeros,
    ramp,
    alternating,
    impulse,
};

pub fn generateTestFrame(allocator: std.mem.Allocator, length: usize, pattern: TestPattern) ![]f32 {
    const frame = try allocator.alloc(f32, length);
    for (frame, 0..) |*sample, i| {
        sample.* = switch (pattern) {
            .zeros => 0.0,
            .ramp => @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(@max(length, 1))),
            .alternating => if (i % 2 == 0) 1.0 else -1.0,
            .impulse => if (i == 0) 1.0 else 0.0,
        };
    }
    return frame;
}

pub fn generateSineWave(allocator: std.mem.Allocator, freq: f32, sample_rate: f32, duration_ms: f32) ![]f32 {
    if (!(freq > 0.0) or !(sample_rate > 0.0) or !(duration_ms > 0.0)) return error.InvalidArgument;
    const length = @as(usize, @intFromFloat(sample_rate * (duration_ms / 1000.0)));
    if (length == 0) return error.InvalidArgument;

    const out = try allocator.alloc(f32, length);
    const two_pi = 2.0 * std.math.pi;
    for (out, 0..) |*sample, i| {
        const t = @as(f32, @floatFromInt(i)) / sample_rate;
        sample.* = @sin(two_pi * freq * t);
    }
    return out;
}

pub fn generateNoise(allocator: std.mem.Allocator, seed: u64, power: f32, length: usize) ![]f32 {
    if (length == 0) return error.InvalidArgument;
    if (power < 0.0) return error.InvalidArgument;

    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();
    const out = try allocator.alloc(f32, length);

    if (power == 0.0) {
        @memset(out, 0.0);
        return out;
    }

    var sum_sq: f32 = 0.0;
    for (out) |*sample| {
        sample.* = random.float(f32) * 2.0 - 1.0;
        sum_sq += sample.* * sample.*;
    }

    const mean_sq = sum_sq / @as(f32, @floatFromInt(length));
    const scale = @sqrt(power / @max(mean_sq, 1e-12));
    for (out) |*sample| sample.* *= scale;
    return out;
}

pub fn generateMixedSignal(
    allocator: std.mem.Allocator,
    near_end: []const f32,
    echo: []const f32,
    noise: []const f32,
    mix_ratio: [3]f32,
) ![]f32 {
    if (near_end.len == 0 or near_end.len != echo.len or near_end.len != noise.len) {
        return error.LengthMismatch;
    }

    const out = try allocator.alloc(f32, near_end.len);
    for (out, 0..) |*sample, i| {
        sample.* = near_end[i] * mix_ratio[0] + echo[i] * mix_ratio[1] + noise[i] * mix_ratio[2];
    }
    return out;
}
