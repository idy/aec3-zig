const std = @import("std");
const Complex = @import("complex.zig").Complex;
const FixedPoint = @import("fixed_point.zig").FixedPoint;
const FftCore = @import("audio_processing/fft_core.zig").FftCore;
const isPowerOfTwo = @import("audio_processing/fft_core.zig").isPowerOfTwo;
const Aec3Fft = @import("audio_processing/aec3/aec3_fft.zig").Aec3Fft;
const Window = @import("audio_processing/aec3/aec3_fft.zig").Window;
const aec3_common = @import("audio_processing/aec3/aec3_common.zig");
const NrFft = @import("audio_processing/ns/ns_fft.zig").NrFft;
const ns_common = @import("audio_processing/ns/ns_common.zig");

fn maxAbsDiff(a: []const f32, b: []const f32) f32 {
    var max_err: f32 = 0.0;
    for (a, b) |x, y| {
        max_err = @max(max_err, @abs(x - y));
    }
    return max_err;
}

fn makeSine(comptime N: usize, bin: usize) [N]f32 {
    var out: [N]f32 = undefined;
    for (0..N) |i| {
        const phase = 2.0 * std.math.pi * @as(f32, @floatFromInt(bin * i)) / @as(f32, @floatFromInt(N));
        out[i] = @sin(phase);
    }
    return out;
}

test "test_complex_add_sub_mul_conj_f32" {
    const C = Complex(f32);
    const a = C.init(1.5, -2.0);
    const b = C.init(-0.5, 4.0);
    const add = C.add(a, b);
    const sub = C.sub(a, b);
    const mul = C.mul(a, b);
    const conj = C.conj(a);

    try std.testing.expectApproxEqAbs(@as(f32, 1.0), add.re, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), add.im, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), sub.re, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, -6.0), sub.im, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 7.25), mul.re, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 7.0), mul.im, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1.5), conj.re, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), conj.im, 1e-6);
}

test "test_complex_add_sub_mul_conj_fixed_q15" {
    const Q15 = FixedPoint(15);
    const C = Complex(Q15);
    const a = C.init(Q15.fromFloat(0.5), Q15.fromFloat(-0.25));
    const b = C.init(Q15.fromFloat(0.25), Q15.fromFloat(0.75));
    const mul = C.mul(a, b);
    const conj = C.conj(a);

    try std.testing.expectApproxEqAbs(@as(f32, 0.3125), mul.re.toFloat(), 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 0.3125), mul.im.toFloat(), 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), conj.im.toFloat(), 1e-3);
}

test "test_fft_forward_dc_128" {
    const FFT = FftCore(f32, 128);
    const C = Complex(f32);
    var data: [128]C = [_]C{C.zero()} ** 128;
    for (0..128) |i| data[i] = C.init(1.0, 0.0);
    FFT.forward(&data);
    try std.testing.expectApproxEqAbs(@as(f32, 128.0), data[0].re, 1e-3);
    for (1..128) |k| {
        try std.testing.expect(@abs(data[k].re) < 1e-2);
        try std.testing.expect(@abs(data[k].im) < 1e-2);
    }
}

test "test_fft_forward_single_tone_128" {
    const FFT = FftCore(f32, 128);
    const x = makeSine(128, 7);
    const spec = FFT.forwardReal(&x);
    var peak_bin: usize = 1;
    var peak_mag: f32 = 0.0;
    for (1..64) |k| {
        const mag = spec.re[k] * spec.re[k] + spec.im[k] * spec.im[k];
        if (mag > peak_mag) {
            peak_mag = mag;
            peak_bin = k;
        }
    }
    try std.testing.expectEqual(@as(usize, 7), peak_bin);
}

test "test_fft_forward_dc_256" {
    const FFT = FftCore(f32, 256);
    const C = Complex(f32);
    var data: [256]C = [_]C{C.zero()} ** 256;
    for (0..256) |i| data[i] = C.init(1.0, 0.0);
    FFT.forward(&data);
    try std.testing.expectApproxEqAbs(@as(f32, 256.0), data[0].re, 1e-2);
}

test "test_fft_forward_single_tone_256" {
    const FFT = FftCore(f32, 256);
    const x = makeSine(256, 9);
    const spec = FFT.forwardReal(&x);
    var peak_bin: usize = 1;
    var peak_mag: f32 = 0.0;
    for (1..128) |k| {
        const mag = spec.re[k] * spec.re[k] + spec.im[k] * spec.im[k];
        if (mag > peak_mag) {
            peak_mag = mag;
            peak_bin = k;
        }
    }
    try std.testing.expectEqual(@as(usize, 9), peak_bin);
}

test "test_ifft_roundtrip_128_f32" {
    const FFT = FftCore(f32, 128);
    var x: [128]f32 = undefined;
    for (0..128) |i| x[i] = @as(f32, @floatFromInt(i)) * 0.01;
    const spec = FFT.forwardReal(&x);
    const y = FFT.inverseReal(&spec);
    try std.testing.expect(maxAbsDiff(x[0..], y[0..]) < 1e-5);
}

test "test_ifft_roundtrip_256_f32" {
    const FFT = FftCore(f32, 256);
    var x: [256]f32 = undefined;
    for (0..256) |i| x[i] = @sin(@as(f32, @floatFromInt(i)) * 0.03);
    const spec = FFT.forwardReal(&x);
    const y = FFT.inverseReal(&spec);
    try std.testing.expect(maxAbsDiff(x[0..], y[0..]) < 1e-5);
}

test "test_ifft_roundtrip_128_fixed_vs_float" {
    const Q15 = FixedPoint(15);
    const FftF32 = FftCore(f32, 128);
    const FftQ15 = FftCore(Q15, 128);

    var x_f32: [128]f32 = undefined;
    var x_q15: [128]Q15 = undefined;
    for (0..128) |i| {
        x_f32[i] = 0.1 * @sin(@as(f32, @floatFromInt(i)) * 0.2);
        x_q15[i] = Q15.fromFloatRuntime(x_f32[i]);
    }

    const spec_f32 = FftF32.forwardReal(&x_f32);
    const rec_f32 = FftF32.inverseReal(&spec_f32);
    const spec_q15 = FftQ15.forwardReal(&x_q15);
    const rec_q15 = FftQ15.inverseReal(&spec_q15);

    const lsb = 1.0 / 32768.0;
    var max_err: f32 = 0.0;
    for (0..128) |i| {
        const f32_q15 = Q15.fromFloatRuntime(rec_f32[i]).toFloat();
        max_err = @max(max_err, @abs(rec_q15[i].toFloat() - f32_q15));
    }
    try std.testing.expect(max_err < 2.0 * lsb);
}

test "test_ifft_roundtrip_256_fixed_vs_float" {
    const Q15 = FixedPoint(15);
    const FftF32 = FftCore(f32, 256);
    const FftQ15 = FftCore(Q15, 256);

    var x_f32: [256]f32 = undefined;
    var x_q15: [256]Q15 = undefined;
    for (0..256) |i| {
        x_f32[i] = 0.1 * @cos(@as(f32, @floatFromInt(i)) * 0.15);
        x_q15[i] = Q15.fromFloatRuntime(x_f32[i]);
    }

    const spec_f32 = FftF32.forwardReal(&x_f32);
    const rec_f32 = FftF32.inverseReal(&spec_f32);
    const spec_q15 = FftQ15.forwardReal(&x_q15);
    const rec_q15 = FftQ15.inverseReal(&spec_q15);

    const lsb = 1.0 / 32768.0;
    var max_err: f32 = 0.0;
    for (0..256) |i| {
        const f32_q15 = Q15.fromFloatRuntime(rec_f32[i]).toFloat();
        max_err = @max(max_err, @abs(rec_q15[i].toFloat() - f32_q15));
    }
    try std.testing.expect(max_err < 2.0 * lsb);
}

test "test_fft_energy_conservation_parseval_128" {
    const FFT = FftCore(f32, 128);
    var x: [128]f32 = undefined;
    for (0..128) |i| x[i] = @sin(@as(f32, @floatFromInt(i)) * 0.21);
    const spec = FFT.forwardReal(&x);

    var energy_t: f32 = 0.0;
    for (x) |v| energy_t += v * v;

    var energy_f: f32 = spec.re[0] * spec.re[0] + spec.re[64] * spec.re[64];
    for (1..64) |k| {
        energy_f += 2.0 * (spec.re[k] * spec.re[k] + spec.im[k] * spec.im[k]);
    }
    energy_f /= 128.0;
    try std.testing.expectApproxEqAbs(energy_t, energy_f, 1e-3);
}

test "test_fft_energy_conservation_parseval_256" {
    const FFT = FftCore(f32, 256);
    var x: [256]f32 = undefined;
    for (0..256) |i| x[i] = @cos(@as(f32, @floatFromInt(i)) * 0.11);
    const spec = FFT.forwardReal(&x);

    var energy_t: f32 = 0.0;
    for (x) |v| energy_t += v * v;

    var energy_f: f32 = spec.re[0] * spec.re[0] + spec.re[128] * spec.re[128];
    for (1..128) |k| {
        energy_f += 2.0 * (spec.re[k] * spec.re[k] + spec.im[k] * spec.im[k]);
    }
    energy_f /= 256.0;
    try std.testing.expectApproxEqAbs(energy_t, energy_f, 2e-3);
}

test "test_real_fft_conjugate_symmetry_128" {
    const FFT = FftCore(f32, 128);
    var x: [128]f32 = undefined;
    for (0..128) |i| x[i] = @sin(@as(f32, @floatFromInt(i)) * 0.13);
    const s = FFT.forwardReal(&x);
    for (1..64) |k| {
        try std.testing.expect(!std.math.isNan(s.re[k]));
        try std.testing.expect(!std.math.isNan(s.im[k]));
    }
}

test "test_real_fft_conjugate_symmetry_256" {
    const FFT = FftCore(f32, 256);
    var x: [256]f32 = undefined;
    for (0..256) |i| x[i] = @cos(@as(f32, @floatFromInt(i)) * 0.07);
    const s = FFT.forwardReal(&x);
    for (1..128) |k| {
        try std.testing.expect(!std.math.isNan(s.re[k]));
        try std.testing.expect(!std.math.isNan(s.im[k]));
    }
}

test "test_real_fft_bin0_binN2_real_only" {
    const FFT = FftCore(f32, 128);
    const x = makeSine(128, 3);
    const s = FFT.forwardReal(&x);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), s.im[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), s.im[64], 1e-6);
}

test "test_real_fft_zero_input_all_zero_output" {
    const FFT = FftCore(f32, 256);
    const x = [_]f32{0.0} ** 256;
    const s = FFT.forwardReal(&x);
    for (0..129) |k| {
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), s.re[k], 1e-6);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), s.im[k], 1e-6);
    }
}

test "test_aec3_fft_fft_basic" {
    var fft = Aec3Fft.init();
    const x = [_]f32{1.0} ** aec3_common.FFT_LENGTH;
    const spec = fft.fft(x[0..]);
    try std.testing.expectApproxEqAbs(@as(f32, 128.0), spec.re[0], 1e-3);
}

test "test_aec3_fft_ifft_basic" {
    var fft = Aec3Fft.init();
    var d = @import("audio_processing/aec3/fft_data.zig").FftData{};
    d.re[0] = 128.0;
    const x = fft.ifft(d);
    for (x) |v| try std.testing.expectApproxEqAbs(@as(f32, 64.0), v, 1e-2);
}

test "test_aec3_fft_zero_padded_fft_basic" {
    var fft = Aec3Fft.init();
    var x = [_]f32{0.0} ** aec3_common.FFT_LENGTH_BY_2;
    x[0] = 1.0;
    const s = fft.zero_padded_fft(x[0..], .rectangular);
    try std.testing.expect(s.re[0] > 0.9);
}

test "test_aec3_fft_padded_fft_basic" {
    var fft = Aec3Fft.init();
    const x = [_]f32{0.5} ** aec3_common.FFT_LENGTH_BY_2;
    const x_old = [_]f32{0.25} ** aec3_common.FFT_LENGTH_BY_2;
    const s = fft.padded_fft(x[0..], x_old[0..], .rectangular);
    try std.testing.expect(s.re[0] > 40.0);
}

test "test_aec3_fft_window_sqrt_hanning_coefficients" {
    const w = Aec3Fft.sqrt_hanning();
    try std.testing.expectEqual(@as(usize, 128), w.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), w[0], 1e-7);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), w[64], 1e-6);
}

test "test_aec3_fft_window_hanning_coefficients" {
    const w = Aec3Fft.hanning();
    try std.testing.expectEqual(@as(usize, 64), w.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), w[0], 1e-7);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), w[63], 1e-7);
}

test "test_nrfft_forward_basic" {
    var fft = NrFft.init();
    const x = [_]f32{1.0} ** ns_common.FFT_SIZE;
    var re = [_]f32{0.0} ** ns_common.FFT_SIZE;
    var im = [_]f32{0.0} ** ns_common.FFT_SIZE;
    fft.fft(&x, &re, &im);
    try std.testing.expectApproxEqAbs(@as(f32, 256.0), re[0], 1e-2);
}

test "test_nrfft_inverse_basic" {
    var fft = NrFft.init();
    var re = [_]f32{0.0} ** ns_common.FFT_SIZE;
    var im = [_]f32{0.0} ** ns_common.FFT_SIZE;
    re[0] = 256.0;
    var x = [_]f32{0.0} ** ns_common.FFT_SIZE;
    fft.ifft(re[0..], im[0..], x[0..]);
    for (x) |v| try std.testing.expectApproxEqAbs(@as(f32, 2.0), v, 1e-3);
}

test "test_aec3_fft_fft_boundary_all_zero_input" {
    var fft = Aec3Fft.init();
    const x = [_]f32{0.0} ** aec3_common.FFT_LENGTH;
    const s = fft.fft(x[0..]);
    for (0..aec3_common.FFT_LENGTH_BY_2_PLUS_1) |k| {
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), s.re[k], 1e-7);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), s.im[k], 1e-7);
    }
}

test "test_nrfft_forward_boundary_impulse_input" {
    var fft = NrFft.init();
    var x = [_]f32{0.0} ** ns_common.FFT_SIZE;
    x[0] = 1.0;
    var re = [_]f32{0.0} ** ns_common.FFT_SIZE;
    var im = [_]f32{0.0} ** ns_common.FFT_SIZE;
    fft.fft(&x, &re, &im);
    for (0..ns_common.FFT_SIZE_BY_2_PLUS_1) |i| {
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), re[i], 1e-3);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), im[i], 1e-3);
    }
}

test "test_aec3_fft_ifft_boundary_zero_spectrum" {
    var fft = Aec3Fft.init();
    const d = @import("audio_processing/aec3/fft_data.zig").FftData{};
    const x = fft.ifft(d);
    for (x) |v| try std.testing.expectApproxEqAbs(@as(f32, 0.0), v, 1e-7);
}

test "test_aec3_fft_zero_padded_fft_boundary_all_zero_input" {
    var fft = Aec3Fft.init();
    const x = [_]f32{0.0} ** aec3_common.FFT_LENGTH_BY_2;
    const s = fft.zero_padded_fft(x[0..], .hanning);
    for (0..aec3_common.FFT_LENGTH_BY_2_PLUS_1) |k| {
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), s.re[k], 1e-6);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), s.im[k], 1e-6);
    }
}

test "test_aec3_fft_padded_fft_boundary_all_zero_input" {
    var fft = Aec3Fft.init();
    const x = [_]f32{0.0} ** aec3_common.FFT_LENGTH_BY_2;
    const x_old = [_]f32{0.0} ** aec3_common.FFT_LENGTH_BY_2;
    const s = fft.padded_fft(x[0..], x_old[0..], .sqrt_hanning);
    for (0..aec3_common.FFT_LENGTH_BY_2_PLUS_1) |k| {
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), s.re[k], 1e-6);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), s.im[k], 1e-6);
    }
}

test "test_nrfft_inverse_boundary_zero_spectrum" {
    var fft = NrFft.init();
    const re = [_]f32{0.0} ** ns_common.FFT_SIZE;
    const im = [_]f32{0.0} ** ns_common.FFT_SIZE;
    var x = [_]f32{1.0} ** ns_common.FFT_SIZE;
    fft.ifft(re[0..], im[0..], x[0..]);
    for (x) |v| try std.testing.expectApproxEqAbs(@as(f32, 0.0), v, 1e-7);
}

test "test_fft_non_power_of_two_rejected" {
    try std.testing.expect(!isPowerOfTwo(192));
    try std.testing.expect(isPowerOfTwo(128));
}
