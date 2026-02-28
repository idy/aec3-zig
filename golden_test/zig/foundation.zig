const std = @import("std");
const aec3 = @import("aec3");
const test_utils = @import("test_utils.zig");

const golden_text = @embedFile("../vectors/rust_foundation_golden_vectors.txt");

test "golden_num_bands_for_rate" {
    const rates = test_utils.parseNamedI32(golden_text, "NUM_BANDS_RATES", 4);
    const expected = test_utils.parseNamedUsize(golden_text, "NUM_BANDS_EXPECTED", 4);
    for (rates, expected) |rate, exp| {
        const actual = aec3.Aec3Common.num_bands_for_rate(rate);
        try std.testing.expectEqual(exp, actual);
    }
}

test "golden_fast_approx_log2f" {
    const inputs = test_utils.parseNamedF32(golden_text, "FAST_LOG2_INPUT", 1000);
    const expected = test_utils.parseNamedF32(golden_text, "FAST_LOG2_EXPECTED", 1000);
    for (inputs, expected) |x, exp| {
        const actual = aec3.Aec3Common.fast_approx_log2f(x);
        try test_utils.expectUlpEq(exp, actual, 1);
    }
}

test "golden_fft_data_spectrum_0" {
    const packed_array = test_utils.parseNamedF32(golden_text, "SPECTRUM_PACKED_0", aec3.Aec3Common.FFT_LENGTH);
    const expected = test_utils.parseNamedF32(golden_text, "SPECTRUM_EXPECTED_0", aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1);

    var d = aec3.Aec3FftData.new();
    d.copy_from_packed_array(&packed_array);
    var out: [aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;
    d.spectrum(.none, &out);

    for (expected, out) |e, a| {
        try test_utils.expectUlpEq(e, a, 1);
    }
}

test "golden_fft_data_fixed_vs_float_spectrum" {
    const packed_array = test_utils.parseNamedF32(golden_text, "SPECTRUM_PACKED_0", aec3.Aec3Common.FFT_LENGTH);

    // Compute float spectrum
    var d_float = aec3.Aec3FftData.new();
    d_float.copy_from_packed_array(&packed_array);
    var out_float: [aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;
    d_float.spectrum(.none, &out_float);

    // Compute fixed spectrum
    const Q15 = aec3.profileFor(.fixed_mcu_q15).Sample;
    var d_fixed = aec3.Aec3FftDataFixed.new();
    d_fixed.re_q15[0] = Q15.fromFloatRuntime(packed_array[0]);
    d_fixed.re_q15[aec3.Aec3Common.FFT_LENGTH_BY_2] = Q15.fromFloatRuntime(packed_array[1]);
    var idx: usize = 2;
    for (1..aec3.Aec3Common.FFT_LENGTH_BY_2) |k| {
        d_fixed.re_q15[k] = Q15.fromFloatRuntime(packed_array[idx]);
        d_fixed.im_q15[k] = Q15.fromFloatRuntime(packed_array[idx + 1]);
        idx += 2;
    }

    var out_fixed: [aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1]i64 = undefined;
    d_fixed.spectrumQ30(&out_fixed);

    // Compare
    // Since Q15 numbers are scaled by 2^15, their squares are scaled by 2^30.
    // So fixed_value / 2^30 should be approximately equal to float_value.
    const scaling = 1.0 / @as(f64, @floatFromInt(@as(u64, 1) << 30));
    for (out_float, out_fixed) |flt_val, fix_val| {
        const fix_flt = @as(f64, @floatFromInt(fix_val)) * scaling;
        try std.testing.expectApproxEqAbs(@as(f64, @floatCast(flt_val)), fix_flt, 0.005);
    }
}

test "golden_config_defaults" {
    const expected = test_utils.parseNamedF64(golden_text, "CONFIG_DEFAULTS", 20);
    const cfg = aec3.Config.EchoCanceller3Config.default();
    const actual = [_]f64{
        @floatFromInt(cfg.buffering.excess_render_detection_interval_blocks),
        @floatFromInt(cfg.buffering.max_allowed_excess_render_blocks),
        @floatFromInt(cfg.delay.default_delay),
        @floatFromInt(cfg.delay.down_sampling_factor),
        @floatFromInt(cfg.filter.main.length_blocks),
        @floatFromInt(cfg.filter.main_initial.length_blocks),
        cfg.erle.min,
        cfg.erle.max_l,
        cfg.erle.max_h,
        cfg.ep_strength.default_gain,
        cfg.ep_strength.default_len,
        cfg.render_levels.active_render_limit,
        cfg.render_levels.poor_excitation_render_limit,
        @floatFromInt(cfg.echo_model.noise_floor_hold),
        cfg.echo_model.min_noise_floor_power,
        @floatFromInt(cfg.suppressor.nearend_average_blocks),
        cfg.suppressor.normal_tuning.mask_lf.enr_transparent,
        cfg.suppressor.normal_tuning.mask_lf.enr_suppress,
        cfg.suppressor.normal_tuning.max_inc_factor,
        cfg.suppressor.normal_tuning.max_dec_factor_lf,
    };

    for (expected, actual) |e, a| {
        try std.testing.expectApproxEqAbs(e, a, 1e-6);
    }
}
