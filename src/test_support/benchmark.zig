//! Benchmark 测试

const std = @import("std");
const aec3 = @import("aec3");

const SampleOps = aec3.SampleOps;
const FixedPoint = aec3.FixedPoint;
const Complex = aec3.Complex;

fn benchmarkFixedPointMul() !void {
    const Q15 = FixedPoint(15);
    const ops = SampleOps(Q15);

    const iterations: usize = 100_000;
    var a = Q15.fromFloat(0.5);
    var b = Q15.fromFloat(0.3);

    var timer = try std.time.Timer.start();
    const start = timer.lap();

    var result = Q15.zero();
    for (0..iterations) |_| {
        result = ops.mul(a, b);
        // 防止优化掉
        a = result;
        b = ops.fromFloat(0.3);
    }

    const end = timer.read();
    const elapsed_ns = end - start;
    const elapsed_us = elapsed_ns / 1000;
    const ns_per_op = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(iterations));

    std.debug.print("\n=== FixedPoint(Q15) Multiplication Benchmark ===\n", .{});
    std.debug.print("Iterations: {d}\n", .{iterations});
    std.debug.print("Total time: {d} us\n", .{elapsed_us});
    std.debug.print("Time per op: {d:.2} ns\n", .{ns_per_op});
    std.debug.print("Final result: {d:.6}\n", .{result.toFloat()});
}

fn benchmarkF32Mul() !void {
    const ops = SampleOps(f32);

    const iterations: usize = 100_000;
    var a: f32 = 0.5;
    var b: f32 = 0.3;

    var timer = try std.time.Timer.start();
    const start = timer.lap();

    var result: f32 = 0.0;
    for (0..iterations) |_| {
        result = ops.mul(a, b);
        a = result;
        b = 0.3;
    }

    const end = timer.read();
    const elapsed_ns = end - start;
    const elapsed_us = elapsed_ns / 1000;
    const ns_per_op = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(iterations));

    std.debug.print("\n=== f32 Multiplication Benchmark ===\n", .{});
    std.debug.print("Iterations: {d}\n", .{iterations});
    std.debug.print("Total time: {d} us\n", .{elapsed_us});
    std.debug.print("Time per op: {d:.2} ns\n", .{ns_per_op});
    std.debug.print("Final result: {d:.6}\n", .{result});
}

fn benchmarkComplexMulFixed() !void {
    const Q15 = FixedPoint(15);
    const C = Complex(Q15);

    const iterations: usize = 100_000;
    var a = C.init(Q15.fromFloat(0.5), Q15.fromFloat(0.3));
    const b = C.init(Q15.fromFloat(0.2), Q15.fromFloat(0.4));

    var timer = try std.time.Timer.start();
    const start = timer.lap();

    var result = C.zero();
    for (0..iterations) |_| {
        result = C.mul(a, b);
        a = result;
    }

    const end = timer.read();
    const elapsed_ns = end - start;
    const elapsed_us = elapsed_ns / 1000;
    const ns_per_op = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(iterations));

    std.debug.print("\n=== Complex(FixedPoint) Multiplication Benchmark ===\n", .{});
    std.debug.print("Iterations: {d}\n", .{iterations});
    std.debug.print("Total time: {d} us\n", .{elapsed_us});
    std.debug.print("Time per op: {d:.2} ns\n", .{ns_per_op});
    std.debug.print("Final result: ({d:.6}, {d:.6})\n", .{ result.re.toFloat(), result.im.toFloat() });
}

fn benchmarkComplexMulF32() !void {
    const C = Complex(f32);

    const iterations: usize = 100_000;
    var a = C.init(0.5, 0.3);
    const b = C.init(0.2, 0.4);

    var timer = try std.time.Timer.start();
    const start = timer.lap();

    var result = C.zero();
    for (0..iterations) |_| {
        result = C.mul(a, b);
        a = result;
    }

    const end = timer.read();
    const elapsed_ns = end - start;
    const elapsed_us = elapsed_ns / 1000;
    const ns_per_op = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(iterations));

    std.debug.print("\n=== Complex(f32) Multiplication Benchmark ===\n", .{});
    std.debug.print("Iterations: {d}\n", .{iterations});
    std.debug.print("Total time: {d} us\n", .{elapsed_us});
    std.debug.print("Time per op: {d:.2} ns\n", .{ns_per_op});
    std.debug.print("Final result: ({d:.6}, {d:.6})\n", .{ result.re, result.im });
}

pub fn main() !void {
    std.debug.print("\n========================================\n", .{});
    std.debug.print("AEC3 Numeric Types Benchmark\n", .{});
    std.debug.print("========================================\n", .{});

    try benchmarkFixedPointMul();
    try benchmarkF32Mul();
    try benchmarkComplexMulFixed();
    try benchmarkComplexMulF32();

    std.debug.print("\n========================================\n", .{});
    std.debug.print("Benchmark Complete\n", .{});
    std.debug.print("========================================\n", .{});
}
