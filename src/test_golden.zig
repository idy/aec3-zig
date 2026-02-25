const std = @import("std");

const aec3_common = @import("audio_processing/aec3/aec3_common.zig");
const fft_data = @import("audio_processing/aec3/fft_data.zig");
const config = @import("api/config.zig");

fn openGolden(name: []const u8) !std.fs.File {
    var buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&buf, "tests/golden/{s}", .{name});
    return std.fs.cwd().openFile(path, .{});
}

fn orderedUlpBits(x: f32) i32 {
    const bits_u32: u32 = @bitCast(x);
    const bits_i32: i32 = @bitCast(bits_u32);
    return if (bits_i32 < 0) std.math.minInt(i32) - bits_i32 else bits_i32;
}

fn ulpDiff(a: f32, b: f32) u32 {
    const oa = orderedUlpBits(a);
    const ob = orderedUlpBits(b);
    return @intCast(@abs(oa - ob));
}

fn expectUlpEq(a: f32, b: f32, max_ulp: u32) !void {
    if (std.math.isNan(a) or std.math.isNan(b)) {
        return std.testing.expect(false);
    }
    const diff = ulpDiff(a, b);
    try std.testing.expect(diff <= max_ulp);
}

test "golden_aec3_common" {
    var file = openGolden("golden_aec3_common.bin") catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };
    defer file.close();
    var read_buf: [4096]u8 = undefined;
    var file_reader = file.reader(&read_buf);
    const reader = &file_reader.interface;

    const num_rates = try reader.takeInt(u32, .little);
    var i: u32 = 0;
    while (i < num_rates) : (i += 1) {
        const rate = try reader.takeInt(i32, .little);
        const expected = try reader.takeInt(u64, .little);
        const actual = aec3_common.num_bands_for_rate(rate);
        try std.testing.expectEqual(expected, actual);
    }

    const count = try reader.takeInt(u32, .little);
    i = 0;
    while (i < count) : (i += 1) {
        const x = @as(f32, @bitCast(try reader.takeInt(u32, .little)));
        const expected = @as(f32, @bitCast(try reader.takeInt(u32, .little)));
        const actual = aec3_common.fast_approx_log2f(x);
        try expectUlpEq(expected, actual, 1);
    }
}

test "golden_fft_data_spectrum" {
    var file = openGolden("golden_fft_data_spectrum.bin") catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };
    defer file.close();
    var read_buf: [4096]u8 = undefined;
    var file_reader = file.reader(&read_buf);
    const reader = &file_reader.interface;

    const cases = try reader.takeInt(u32, .little);
    var c: u32 = 0;
    while (c < cases) : (c += 1) {
        var packed_array: [aec3_common.FFT_LENGTH]f32 = undefined;
        for (&packed_array) |*v| v.* = @as(f32, @bitCast(try reader.takeInt(u32, .little)));

        var expected: [aec3_common.FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;
        for (&expected) |*v| v.* = @as(f32, @bitCast(try reader.takeInt(u32, .little)));

        var d = fft_data.FftData.new();
        d.copy_from_packed_array(&packed_array);
        var out: [aec3_common.FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;
        d.spectrum(.none, &out);

        for (expected, out) |e, a| {
            try expectUlpEq(e, a, 1);
        }
    }
}

test "golden_config_default" {
    var file = openGolden("golden_config_default.bin") catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };
    defer file.close();
    var read_buf: [4096]u8 = undefined;
    var file_reader = file.reader(&read_buf);
    const reader = &file_reader.interface;

    const n = try reader.takeInt(u32, .little);
    try std.testing.expectEqual(@as(u32, 20), n);

    var expected: [20]f64 = undefined;
    for (&expected) |*v| v.* = @as(f64, @bitCast(try reader.takeInt(u64, .little)));

    const cfg = config.EchoCanceller3Config.default();
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
