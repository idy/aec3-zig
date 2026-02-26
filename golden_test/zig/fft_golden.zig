const std = @import("std");
const aec3 = @import("aec3");
const common = @import("common.zig");

const golden_text = @embedFile("../vectors/rust_fft_golden_vectors.txt");

const NS_FFT_SIZE: usize = 256;
const NS_FFT_SIZE_BY_2_PLUS_1: usize = 129;

test "golden_rust_aec3_zero_padded_forward_vector" {
    var fft = aec3.Aec3Fft.initOracle();
    var input = [_]f32{0.0} ** aec3.Aec3Common.FFT_LENGTH_BY_2;
    for (0..aec3.Aec3Common.FFT_LENGTH_BY_2) |i| {
        const x = @as(f32, @floatFromInt(i));
        input[i] = 0.35 * @sin(x * 0.13) + 0.2 * @cos(x * 0.07) + (@as(f32, @floatFromInt(@as(i32, @intCast(i)) - 32)) / 512.0);
    }

    const spec = try fft.zero_padded_fft(input[0..], .rectangular);
    const re_golden = common.parseNamedF32(golden_text, "AEC3_ZERO_PADDED_RE65", aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1);
    const im_golden = common.parseNamedF32(golden_text, "AEC3_ZERO_PADDED_IM65", aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1);

    var max_re_err: f32 = 0.0;
    var max_im_err: f32 = 0.0;
    for (0..aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1) |k| {
        max_re_err = @max(max_re_err, @abs(spec.re[k] - re_golden[k]));
        max_im_err = @max(max_im_err, @abs(spec.im[k] - im_golden[k]));
    }
    try std.testing.expect(max_re_err < 1e-3);
    try std.testing.expect(max_im_err < 1e-3);
}

test "golden_rust_aec3_zero_padded_ifft_vector" {
    var fft = aec3.Aec3Fft.initOracle();

    var spec = aec3.Aec3FftData{};
    const re_golden = common.parseNamedF32(golden_text, "AEC3_ZERO_PADDED_RE65", aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1);
    const im_golden = common.parseNamedF32(golden_text, "AEC3_ZERO_PADDED_IM65", aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1);
    for (0..aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1) |k| {
        spec.re[k] = re_golden[k];
        spec.im[k] = if (k == 0 or k == aec3.Aec3Common.FFT_LENGTH_BY_2) 0.0 else im_golden[k];
    }

    const out = fft.ifft(spec);
    const out_golden = common.parseNamedF32(golden_text, "AEC3_ZERO_PADDED_IFFT128", aec3.Aec3Common.FFT_LENGTH);

    var max_err: f32 = 0.0;
    for (0..aec3.Aec3Common.FFT_LENGTH) |i| {
        max_err = @max(max_err, @abs(out[i] - out_golden[i]));
    }
    try std.testing.expect(max_err < 1e-3);
}

test "golden_rust_ns_forward_inverse_vectors" {
    var fft = aec3.NrFft.initOracle();
    var input = [_]f32{0.0} ** NS_FFT_SIZE;
    for (0..NS_FFT_SIZE) |i| {
        const x = @as(f32, @floatFromInt(i));
        input[i] = 0.4 * @sin(x * 0.11) - 0.15 * @cos(x * 0.05) + (@as(f32, @floatFromInt(@as(i32, @intCast(i)) - 128)) / 1024.0);
    }

    var re = [_]f32{0.0} ** NS_FFT_SIZE;
    var im = [_]f32{0.0} ** NS_FFT_SIZE;
    fft.fft(&input, &re, &im);

    const re_golden = common.parseNamedF32(golden_text, "NS_RE129", NS_FFT_SIZE_BY_2_PLUS_1);
    const im_golden = common.parseNamedF32(golden_text, "NS_IM129", NS_FFT_SIZE_BY_2_PLUS_1);

    var max_re_err: f32 = 0.0;
    var max_im_err: f32 = 0.0;
    for (0..NS_FFT_SIZE_BY_2_PLUS_1) |k| {
        max_re_err = @max(max_re_err, @abs(re[k] - re_golden[k]));
        max_im_err = @max(max_im_err, @abs(im[k] - im_golden[k]));
    }
    try std.testing.expect(max_re_err < 1e-3);
    try std.testing.expect(max_im_err < 1e-3);

    var out = [_]f32{0.0} ** NS_FFT_SIZE;
    try fft.ifft(re[0..], im[0..], out[0..]);
    const out_golden = common.parseNamedF32(golden_text, "NS_IFFT256", NS_FFT_SIZE);

    var max_ifft_err: f32 = 0.0;
    for (0..NS_FFT_SIZE) |i| {
        max_ifft_err = @max(max_ifft_err, @abs(out[i] - out_golden[i]));
    }
    try std.testing.expect(max_ifft_err < 1e-3);
}
