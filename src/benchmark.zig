//! FFT + Foundation benchmark

const std = @import("std");

const aec3 = @import("aec3");
const aec3_common = aec3.Aec3Common;
const fft_data = aec3.FftData.FftData;
const audio_util = aec3.AudioUtil;

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

fn bench_fast_approx_log2f() !void {
    const iterations: usize = 10_000;
    var acc: f32 = 0.0;
    var timer = try std.time.Timer.start();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const x = 0.01 + @as(f32, @floatFromInt(i % 1000)) * 0.1;
        acc += aec3_common.fast_approx_log2f(x);
    }

    const ns = timer.read();
    const ns_per_op = @as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(iterations));
    std.debug.print("bench_fast_approx_log2f: total={d}ns ns/op={d:.2} acc={d:.3}\n", .{ ns, ns_per_op, acc });
}

fn bench_fft_data_spectrum() !void {
    const iterations: usize = 10_000;
    var d = fft_data.new();
    var k: usize = 0;
    while (k < aec3_common.FFT_LENGTH_BY_2_PLUS_1) : (k += 1) {
        d.re[k] = @as(f32, @floatFromInt(k)) * 0.1;
        d.im[k] = @as(f32, @floatFromInt(k)) * 0.05;
    }
    var out: [aec3_common.FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;

    var timer = try std.time.Timer.start();
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        d.spectrum(.none, &out);
    }

    const ns = timer.read();
    const ns_per_op = @as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(iterations));
    std.debug.print("bench_fft_data_spectrum: total={d}ns ns/op={d:.2} out0={d:.3}\n", .{ ns, ns_per_op, out[0] });
}

fn bench_audio_util_conversions() !void {
    const iterations: usize = 10_000;
    var src: [480]i16 = undefined;
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        src[i] = @intCast((@as(i32, @intCast(i % 32768)) - 16384));
    }

    var fbuf: [480]f32 = undefined;
    var dst: [480]i16 = undefined;
    var timer = try std.time.Timer.start();

    i = 0;
    while (i < iterations) : (i += 1) {
        audio_util.s16_slice_to_float_s16(&src, &fbuf);
        audio_util.float_s16_slice_to_s16(&fbuf, &dst);
    }

    const ns = timer.read();
    const ns_per_op = @as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(iterations));
    std.debug.print("bench_audio_util_conversions: total={d}ns ns/op={d:.2} dst0={d}\n", .{ ns, ns_per_op, dst[0] });
}

pub fn main() !void {
    try bench_fft_128_f32();
    try bench_fft_128_fixed_q15();
    try bench_fft_256_f32();
    try bench_fft_256_fixed_q15();
    try bench_fast_approx_log2f();
    try bench_fft_data_spectrum();
    try bench_audio_util_conversions();
}
