const std = @import("std");
const aec3 = @import("aec3");

test "golden_aec3_core_fixed_vs_float_pipeline" {
    var fixed_pipeline = aec3.Aec3Core.FixedI16Pipeline.init();
    var float_fft = aec3.Aec3Fft.initOracle(); // float path

    var prng = std.Random.DefaultPrng.init(0xAEC3_0002);
    const random = prng.random();

    var frame: [aec3.Aec3Common.FFT_LENGTH]i16 = undefined;
    var float_frame: [aec3.Aec3Common.FFT_LENGTH]f32 = undefined;

    // Fill with random audio-like data
    for (0..aec3.Aec3Common.FFT_LENGTH) |i| {
        frame[i] = random.intRangeAtMost(i16, -10000, 10000);
        // our Q15 fixed point treats raw i16 values directly.
        // For float equivalent, we just use the raw value as f32 since the pipeline operates on raw values scaled appropriately.
        float_frame[i] = @as(f32, @floatFromInt(frame[i]));
    }

    const gain_q15 = aec3.profileFor(.fixed_mcu_q15).Sample.fromFloatRuntime(0.75);
    const gain_f32: f32 = 0.75;

    // 1. Run Fixed Pipeline
    const fixed_out = fixed_pipeline.process_capture_i16(&frame, gain_q15);

    // 2. Run equivalent Float Pipeline
    var spec_float = float_fft.fft(&float_frame);
    for (0..aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1) |k| {
        spec_float.re[k] *= gain_f32;
        spec_float.im[k] *= gain_f32;
    }
    const float_out_f32 = float_fft.ifft(spec_float);

    var float_out: [aec3.Aec3Common.FFT_LENGTH]i16 = undefined;
    for (0..aec3.Aec3Common.FFT_LENGTH) |i| {
        // float_fft.ifft multiplies by FFT_LENGTH / 2 (i.e. 64), so we divide it out to match fixed pipeline which has 1:1 roundtrip
        const corrected = float_out_f32[i] / @as(f32, @floatFromInt(aec3.Aec3Common.FFT_LENGTH_BY_2));
        const clamped = std.math.clamp(@as(i32, @intFromFloat(@round(corrected))), std.math.minInt(i16), std.math.maxInt(i16));
        float_out[i] = @intCast(clamped);
    }

    // 3. Compare them
    var max_err: u32 = 0;
    var err_sum: u64 = 0;
    for (0..aec3.Aec3Common.FFT_LENGTH) |i| {
        const diff = @abs(@as(i32, fixed_out[i]) - @as(i32, float_out[i]));
        if (diff > max_err) max_err = diff;
        err_sum += diff;
    }

    const mean_err = @as(f64, @floatFromInt(err_sum)) / @as(f64, @floatFromInt(aec3.Aec3Common.FFT_LENGTH));

    // Allow small divergence due to fixed point quantization and Q15 bounds
    try std.testing.expect(max_err <= 150); // maximum absolute error
    try std.testing.expect(mean_err <= 30.0); // mean absolute error
}
