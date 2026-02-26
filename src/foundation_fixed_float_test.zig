const std = @import("std");

const NumericMode = @import("numeric_mode.zig").NumericMode;
const numeric_profile = @import("numeric_profile.zig");
const FixedPoint = @import("fixed_point.zig").FixedPoint;
const audio_util = @import("audio_processing/audio_util.zig");
const aec3_common = @import("audio_processing/aec3/aec3_common.zig");
const fft_data = @import("audio_processing/aec3/fft_data.zig").FftData;

test "default numeric mode is fixed_mcu_q15 (fixed-point-first)" {
    try std.testing.expectEqual(NumericMode.fixed_mcu_q15, numeric_profile.DEFAULT_NUMERIC_MODE);
}

test "fixed-vs-float matrix: audio_util roundtrip" {
    const Q15 = FixedPoint(15);
    const src = [_]f32{ -1.0, -0.5, -0.125, 0.0, 0.125, 0.5, 1.0 };

    for (src) |x| {
        const fixed = Q15.fromFloatRuntime(x);
        const fixed_as_f32 = fixed.toFloat();
        const float_s16 = audio_util.float_to_float_s16(fixed_as_f32);
        const recovered = audio_util.float_s16_to_float(float_s16);
        try std.testing.expectApproxEqAbs(fixed_as_f32, recovered, 1.0 / 32768.0);
    }
}

test "fixed-vs-float matrix: fft spectrum under Q15 quantization" {
    var float_fft = fft_data.new();
    var quant_fft = fft_data.new();

    var k: usize = 0;
    while (k < aec3_common.FFT_LENGTH_BY_2_PLUS_1) : (k += 1) {
        const re = @sin(@as(f32, @floatFromInt(k)) * 0.1) * 0.9;
        const im = @cos(@as(f32, @floatFromInt(k)) * 0.1) * 0.9;
        float_fft.re[k] = re;
        float_fft.im[k] = im;

        const q_re = FixedPoint(15).fromFloatRuntime(re).toFloat();
        const q_im = FixedPoint(15).fromFloatRuntime(im).toFloat();
        quant_fft.re[k] = q_re;
        quant_fft.im[k] = q_im;
    }

    var float_ps: [aec3_common.FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;
    var quant_ps: [aec3_common.FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;
    float_fft.spectrum(.none, &float_ps);
    quant_fft.spectrum(.none, &quant_ps);

    for (float_ps, quant_ps) |a, b| {
        try std.testing.expectApproxEqAbs(a, b, 5e-4);
    }
}
