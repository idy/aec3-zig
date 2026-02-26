const std = @import("std");
const aec3 = @import("aec3");
const test_utils = @import("test_utils.zig");

const golden_text = @embedFile("../vectors/rust_fft_golden_vectors.txt");

const NS_FFT_SIZE: usize = 256;
const NS_FFT_SIZE_BY_2_PLUS_1: usize = 129;

// 阈值来源（可追溯）：
// - 采样命令：zig build golden-test -- --test-filter "golden.*(ns|fft|fixed|float)"
// - 采样时间：2026-02-27
// - 采样范围：本文件中的 FFT 场景（AEC3 zero_padded_fft/ifft + NS fft/ifft）
// - 实测包络（max of max/mean/p95 across cases）：
//   oracle-vs-rust = 1.0826439e-4 / 1.4888840e-5 / 5.4122880e-5
//   fixed-vs-rust  = 2.2544860e-3 / 1.0581547e-3 / 1.9550320e-3
//   fixed-vs-float = 6.0920715e-3 / 1.2093098e-3 / 2.9373170e-3
// - 取值策略：在实测包络基础上增加约 1.3x~2.4x 安全裕量，保证回归敏感度。
const FFT_RUST_ORACLE_THRESHOLDS = test_utils.ErrorThresholds{
    .max_abs = 0.00025,
    .mean_abs = 0.00004,
    .p95_abs = 0.00012,
};
const FFT_RUST_FIXED_THRESHOLDS = test_utils.ErrorThresholds{
    .max_abs = 0.0035,
    .mean_abs = 0.0016,
    .p95_abs = 0.0025,
};
const FFT_FIXED_VS_FLOAT_THRESHOLDS = test_utils.ErrorThresholds{
    .max_abs = 0.008,
    .mean_abs = 0.0018,
    .p95_abs = 0.004,
};

fn buildAec3Input() [aec3.Aec3Common.FFT_LENGTH_BY_2]f32 {
    var input = [_]f32{0.0} ** aec3.Aec3Common.FFT_LENGTH_BY_2;
    for (0..aec3.Aec3Common.FFT_LENGTH_BY_2) |i| {
        const x = @as(f32, @floatFromInt(i));
        input[i] = 0.35 * @sin(x * 0.13) + 0.2 * @cos(x * 0.07) + (@as(f32, @floatFromInt(@as(i32, @intCast(i)) - 32)) / 512.0);
    }
    return input;
}

fn buildNsInput() [NS_FFT_SIZE]f32 {
    var input = [_]f32{0.0} ** NS_FFT_SIZE;
    for (0..NS_FFT_SIZE) |i| {
        const x = @as(f32, @floatFromInt(i));
        input[i] = 0.4 * @sin(x * 0.11) - 0.15 * @cos(x * 0.05) + (@as(f32, @floatFromInt(@as(i32, @intCast(i)) - 128)) / 1024.0);
    }
    return input;
}

test "golden_rust_aec3_zero_padded_forward_vector" {
    var fft = aec3.Aec3Fft.initOracle();
    const input = buildAec3Input();

    const spec = try fft.zero_padded_fft(input[0..], .rectangular);
    const re_golden = test_utils.parseNamedF32(golden_text, "AEC3_ZERO_PADDED_RE65", aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1);
    const im_golden = test_utils.parseNamedF32(golden_text, "AEC3_ZERO_PADDED_IM65", aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1);

    try test_utils.expectErrorStatsWithin(
        std.testing.allocator,
        &re_golden,
        spec.re[0..aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1],
        FFT_RUST_ORACLE_THRESHOLDS,
        "aec3 zero_padded_fft re oracle-vs-rust",
    );
    try test_utils.expectErrorStatsWithin(
        std.testing.allocator,
        &im_golden,
        spec.im[0..aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1],
        FFT_RUST_ORACLE_THRESHOLDS,
        "aec3 zero_padded_fft im oracle-vs-rust",
    );
}

test "golden_rust_aec3_zero_padded_ifft_vector" {
    var fft = aec3.Aec3Fft.initOracle();

    var spec = aec3.Aec3FftData{};
    const re_golden = test_utils.parseNamedF32(golden_text, "AEC3_ZERO_PADDED_RE65", aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1);
    const im_golden = test_utils.parseNamedF32(golden_text, "AEC3_ZERO_PADDED_IM65", aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1);
    for (0..aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1) |k| {
        spec.re[k] = re_golden[k];
        spec.im[k] = if (k == 0 or k == aec3.Aec3Common.FFT_LENGTH_BY_2) 0.0 else im_golden[k];
    }

    const out = fft.ifft(spec);
    const out_golden = test_utils.parseNamedF32(golden_text, "AEC3_ZERO_PADDED_IFFT128", aec3.Aec3Common.FFT_LENGTH);

    try test_utils.expectErrorStatsWithin(
        std.testing.allocator,
        &out_golden,
        out[0..],
        FFT_RUST_ORACLE_THRESHOLDS,
        "aec3 ifft oracle-vs-rust",
    );
}

test "golden_rust_ns_forward_inverse_vectors" {
    var fft = aec3.NrFft.initOracle();
    var input = buildNsInput();

    var re = [_]f32{0.0} ** NS_FFT_SIZE;
    var im = [_]f32{0.0} ** NS_FFT_SIZE;
    fft.fft(&input, &re, &im);

    const re_golden = test_utils.parseNamedF32(golden_text, "NS_RE129", NS_FFT_SIZE_BY_2_PLUS_1);
    const im_golden = test_utils.parseNamedF32(golden_text, "NS_IM129", NS_FFT_SIZE_BY_2_PLUS_1);

    try test_utils.expectErrorStatsWithin(
        std.testing.allocator,
        &re_golden,
        re[0..NS_FFT_SIZE_BY_2_PLUS_1],
        FFT_RUST_ORACLE_THRESHOLDS,
        "ns fft re oracle-vs-rust",
    );
    try test_utils.expectErrorStatsWithin(
        std.testing.allocator,
        &im_golden,
        im[0..NS_FFT_SIZE_BY_2_PLUS_1],
        FFT_RUST_ORACLE_THRESHOLDS,
        "ns fft im oracle-vs-rust",
    );

    var out = [_]f32{0.0} ** NS_FFT_SIZE;
    try fft.ifft(re[0..], im[0..], out[0..]);
    const out_golden = test_utils.parseNamedF32(golden_text, "NS_IFFT256", NS_FFT_SIZE);

    try test_utils.expectErrorStatsWithin(
        std.testing.allocator,
        &out_golden,
        out[0..],
        FFT_RUST_ORACLE_THRESHOLDS,
        "ns ifft oracle-vs-rust",
    );
}

test "golden_rust_aec3_zero_padded_forward_vector_fixed" {
    var fft = aec3.Aec3Fft.init();
    const input = buildAec3Input();
    const spec = try fft.zero_padded_fft(input[0..], .rectangular);

    const re_golden = test_utils.parseNamedF32(golden_text, "AEC3_ZERO_PADDED_RE65", aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1);
    const im_golden = test_utils.parseNamedF32(golden_text, "AEC3_ZERO_PADDED_IM65", aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1);

    try test_utils.expectErrorStatsWithin(
        std.testing.allocator,
        &re_golden,
        spec.re[0..aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1],
        FFT_RUST_FIXED_THRESHOLDS,
        "aec3 zero_padded_fft re fixed-vs-rust",
    );
    try test_utils.expectErrorStatsWithin(
        std.testing.allocator,
        &im_golden,
        spec.im[0..aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1],
        FFT_RUST_FIXED_THRESHOLDS,
        "aec3 zero_padded_fft im fixed-vs-rust",
    );
}

test "golden_rust_aec3_zero_padded_ifft_vector_fixed" {
    var fft = aec3.Aec3Fft.init();

    var spec = aec3.Aec3FftData{};
    const re_golden = test_utils.parseNamedF32(golden_text, "AEC3_ZERO_PADDED_RE65", aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1);
    const im_golden = test_utils.parseNamedF32(golden_text, "AEC3_ZERO_PADDED_IM65", aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1);
    for (0..aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1) |k| {
        spec.re[k] = re_golden[k];
        spec.im[k] = if (k == 0 or k == aec3.Aec3Common.FFT_LENGTH_BY_2) 0.0 else im_golden[k];
    }

    const out = fft.ifft(spec);
    const out_golden = test_utils.parseNamedF32(golden_text, "AEC3_ZERO_PADDED_IFFT128", aec3.Aec3Common.FFT_LENGTH);

    try test_utils.expectErrorStatsWithin(
        std.testing.allocator,
        &out_golden,
        out[0..],
        FFT_RUST_FIXED_THRESHOLDS,
        "aec3 ifft fixed-vs-rust",
    );
}

test "golden_rust_ns_forward_inverse_vectors_fixed" {
    var fft = aec3.NrFft.init();
    var input = buildNsInput();

    var re = [_]f32{0.0} ** NS_FFT_SIZE;
    var im = [_]f32{0.0} ** NS_FFT_SIZE;
    fft.fft(&input, &re, &im);

    const re_golden = test_utils.parseNamedF32(golden_text, "NS_RE129", NS_FFT_SIZE_BY_2_PLUS_1);
    const im_golden = test_utils.parseNamedF32(golden_text, "NS_IM129", NS_FFT_SIZE_BY_2_PLUS_1);

    try test_utils.expectErrorStatsWithin(
        std.testing.allocator,
        &re_golden,
        re[0..NS_FFT_SIZE_BY_2_PLUS_1],
        FFT_RUST_FIXED_THRESHOLDS,
        "ns fft re fixed-vs-rust",
    );
    try test_utils.expectErrorStatsWithin(
        std.testing.allocator,
        &im_golden,
        im[0..NS_FFT_SIZE_BY_2_PLUS_1],
        FFT_RUST_FIXED_THRESHOLDS,
        "ns fft im fixed-vs-rust",
    );

    var out = [_]f32{0.0} ** NS_FFT_SIZE;
    try fft.ifft(re[0..], im[0..], out[0..]);
    const out_golden = test_utils.parseNamedF32(golden_text, "NS_IFFT256", NS_FFT_SIZE);

    try test_utils.expectErrorStatsWithin(
        std.testing.allocator,
        &out_golden,
        out[0..],
        FFT_RUST_FIXED_THRESHOLDS,
        "ns ifft fixed-vs-rust",
    );
}

test "golden_fft_fixed_vs_float_oracle_cross_validation" {
    const aec_input = buildAec3Input();
    var aec_fixed = aec3.Aec3Fft.init();
    var aec_oracle = aec3.Aec3Fft.initOracle();
    const aec_fixed_spec = try aec_fixed.zero_padded_fft(aec_input[0..], .rectangular);
    const aec_oracle_spec = try aec_oracle.zero_padded_fft(aec_input[0..], .rectangular);

    try test_utils.expectErrorStatsWithin(
        std.testing.allocator,
        aec_oracle_spec.re[0..aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1],
        aec_fixed_spec.re[0..aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1],
        FFT_FIXED_VS_FLOAT_THRESHOLDS,
        "aec3 zero_padded_fft re fixed-vs-float",
    );
    try test_utils.expectErrorStatsWithin(
        std.testing.allocator,
        aec_oracle_spec.im[0..aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1],
        aec_fixed_spec.im[0..aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1],
        FFT_FIXED_VS_FLOAT_THRESHOLDS,
        "aec3 zero_padded_fft im fixed-vs-float",
    );

    const aec_fixed_ifft = aec_fixed.ifft(aec_fixed_spec);
    const aec_oracle_ifft = aec_oracle.ifft(aec_oracle_spec);
    try test_utils.expectErrorStatsWithin(
        std.testing.allocator,
        aec_oracle_ifft[0..],
        aec_fixed_ifft[0..],
        FFT_FIXED_VS_FLOAT_THRESHOLDS,
        "aec3 ifft fixed-vs-float",
    );

    var ns_input = buildNsInput();
    var ns_fixed = aec3.NrFft.init();
    var ns_oracle = aec3.NrFft.initOracle();
    var fixed_re = [_]f32{0.0} ** NS_FFT_SIZE;
    var fixed_im = [_]f32{0.0} ** NS_FFT_SIZE;
    var oracle_re = [_]f32{0.0} ** NS_FFT_SIZE;
    var oracle_im = [_]f32{0.0} ** NS_FFT_SIZE;
    ns_fixed.fft(&ns_input, &fixed_re, &fixed_im);
    ns_oracle.fft(&ns_input, &oracle_re, &oracle_im);

    try test_utils.expectErrorStatsWithin(
        std.testing.allocator,
        oracle_re[0..NS_FFT_SIZE_BY_2_PLUS_1],
        fixed_re[0..NS_FFT_SIZE_BY_2_PLUS_1],
        FFT_FIXED_VS_FLOAT_THRESHOLDS,
        "ns fft re fixed-vs-float",
    );
    try test_utils.expectErrorStatsWithin(
        std.testing.allocator,
        oracle_im[0..NS_FFT_SIZE_BY_2_PLUS_1],
        fixed_im[0..NS_FFT_SIZE_BY_2_PLUS_1],
        FFT_FIXED_VS_FLOAT_THRESHOLDS,
        "ns fft im fixed-vs-float",
    );

    var fixed_out = [_]f32{0.0} ** NS_FFT_SIZE;
    var oracle_out = [_]f32{0.0} ** NS_FFT_SIZE;
    try ns_fixed.ifft(fixed_re[0..], fixed_im[0..], fixed_out[0..]);
    try ns_oracle.ifft(oracle_re[0..], oracle_im[0..], oracle_out[0..]);
    try test_utils.expectErrorStatsWithin(
        std.testing.allocator,
        oracle_out[0..],
        fixed_out[0..],
        FFT_FIXED_VS_FLOAT_THRESHOLDS,
        "ns ifft fixed-vs-float",
    );
}
