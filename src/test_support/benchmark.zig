//! FFT benchmark

const std = @import("std");
const aec3 = @import("aec3");

fn fillSignalF32(comptime N: usize) [N]f32 {
    var x: [N]f32 = undefined;
    for (0..N) |i| {
        x[i] = 0.5 * @sin(@as(f32, @floatFromInt(i)) * 0.17) + 0.25 * @cos(@as(f32, @floatFromInt(i)) * 0.31);
    }
    return x;
}

fn bench_fft_128_f32() !void {
    const FFT = aec3.FftCore(f32, 128);
    var signal = fillSignalF32(128);
    const iters: usize = 50_000;

    var timer = try std.time.Timer.start();
    _ = timer.lap();
    var acc: f32 = 0.0;
    for (0..iters) |_| {
        const s = FFT.forwardReal(&signal);
        acc += s.re[1];
        signal[0] += 1e-9;
    }
    const elapsed_ns = timer.read();
    const ns_per_op = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(iters));
    const throughput = (@as(f64, @floatFromInt(iters * 128)) * 1e9) / @as(f64, @floatFromInt(elapsed_ns));

    std.debug.print("bench_fft_128_f32: ns/op={d:.2}, throughput={d:.2} samples/s, guard={d:.3}\n", .{ ns_per_op, throughput, acc });
}

fn bench_fft_256_f32() !void {
    const FFT = aec3.FftCore(f32, 256);
    var signal = fillSignalF32(256);
    const iters: usize = 30_000;

    var timer = try std.time.Timer.start();
    _ = timer.lap();
    var acc: f32 = 0.0;
    for (0..iters) |_| {
        const s = FFT.forwardReal(&signal);
        acc += s.re[1];
        signal[0] += 1e-9;
    }
    const elapsed_ns = timer.read();
    const ns_per_op = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(iters));
    const throughput = (@as(f64, @floatFromInt(iters * 256)) * 1e9) / @as(f64, @floatFromInt(elapsed_ns));

    std.debug.print("bench_fft_256_f32: ns/op={d:.2}, throughput={d:.2} samples/s, guard={d:.3}\n", .{ ns_per_op, throughput, acc });
}

fn bench_fft_128_fixed_q15() !void {
    const Q15 = aec3.FixedPoint(15);
    const FFT = aec3.FftCore(Q15, 128);
    const src = fillSignalF32(128);
    var signal: [128]Q15 = undefined;
    for (0..128) |i| signal[i] = Q15.fromFloatRuntime(src[i]);
    const iters: usize = 50_000;

    var timer = try std.time.Timer.start();
    _ = timer.lap();
    var acc: f32 = 0.0;
    for (0..iters) |_| {
        const s = FFT.forwardReal(&signal);
        acc += s.re[1].toFloat();
    }
    const elapsed_ns = timer.read();
    const ns_per_op = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(iters));
    const throughput = (@as(f64, @floatFromInt(iters * 128)) * 1e9) / @as(f64, @floatFromInt(elapsed_ns));

    std.debug.print("bench_fft_128_fixed_q15: ns/op={d:.2}, throughput={d:.2} samples/s, guard={d:.3}\n", .{ ns_per_op, throughput, acc });
}

fn bench_fft_256_fixed_q15() !void {
    const Q15 = aec3.FixedPoint(15);
    const FFT = aec3.FftCore(Q15, 256);
    const src = fillSignalF32(256);
    var signal: [256]Q15 = undefined;
    for (0..256) |i| signal[i] = Q15.fromFloatRuntime(src[i]);
    const iters: usize = 30_000;

    var timer = try std.time.Timer.start();
    _ = timer.lap();
    var acc: f32 = 0.0;
    for (0..iters) |_| {
        const s = FFT.forwardReal(&signal);
        acc += s.re[1].toFloat();
    }
    const elapsed_ns = timer.read();
    const ns_per_op = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(iters));
    const throughput = (@as(f64, @floatFromInt(iters * 256)) * 1e9) / @as(f64, @floatFromInt(elapsed_ns));

    std.debug.print("bench_fft_256_fixed_q15: ns/op={d:.2}, throughput={d:.2} samples/s, guard={d:.3}\n", .{ ns_per_op, throughput, acc });
}

pub fn main() !void {
    try bench_fft_128_f32();
    try bench_fft_128_fixed_q15();
    try bench_fft_256_f32();
    try bench_fft_256_fixed_q15();
}
