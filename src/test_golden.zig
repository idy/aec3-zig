const std = @import("std");

const aec3_common = @import("audio_processing/aec3/aec3_common.zig");
const fft_data_mod = @import("audio_processing/aec3/fft_data.zig");
const config = @import("api/config.zig");

const golden_text = @embedFile("test_support/rust_foundation_golden_vectors.txt");

fn parseGoldenF32(comptime name: []const u8, comptime N: usize) [N]f32 {
    var out: [N]f32 = undefined;
    var seen = [_]bool{false} ** N;
    const prefix = std.fmt.comptimePrint("{s}[", .{name});

    var it = std.mem.splitScalar(u8, golden_text, '\n');
    while (it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (!std.mem.startsWith(u8, line, prefix)) continue;

        const close = std.mem.indexOfScalarPos(u8, line, prefix.len, ']') orelse @panic("invalid index line");
        const eq = std.mem.indexOfScalarPos(u8, line, close + 1, '=') orelse @panic("invalid value line");

        const idx = std.fmt.parseInt(usize, line[prefix.len..close], 10) catch @panic("invalid index parse");
        if (idx >= N) @panic("index out of range");
        const val = std.fmt.parseFloat(f32, line[eq + 1 ..]) catch @panic("invalid float parse");

        out[idx] = val;
        seen[idx] = true;
    }

    for (seen) |ok| {
        if (!ok) @panic("golden vector incomplete");
    }
    return out;
}

fn parseGoldenF64(comptime name: []const u8, comptime N: usize) [N]f64 {
    var out: [N]f64 = undefined;
    var seen = [_]bool{false} ** N;
    const prefix = std.fmt.comptimePrint("{s}[", .{name});

    var it = std.mem.splitScalar(u8, golden_text, '\n');
    while (it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (!std.mem.startsWith(u8, line, prefix)) continue;

        const close = std.mem.indexOfScalarPos(u8, line, prefix.len, ']') orelse @panic("invalid index line");
        const eq = std.mem.indexOfScalarPos(u8, line, close + 1, '=') orelse @panic("invalid value line");

        const idx = std.fmt.parseInt(usize, line[prefix.len..close], 10) catch @panic("invalid index parse");
        if (idx >= N) @panic("index out of range");
        const val = std.fmt.parseFloat(f64, line[eq + 1 ..]) catch @panic("invalid float parse");

        out[idx] = val;
        seen[idx] = true;
    }

    for (seen) |ok| {
        if (!ok) @panic("golden vector incomplete");
    }
    return out;
}

fn parseGoldenUsize(comptime name: []const u8, comptime N: usize) [N]usize {
    var out: [N]usize = undefined;
    var seen = [_]bool{false} ** N;
    const prefix = std.fmt.comptimePrint("{s}[", .{name});

    var it = std.mem.splitScalar(u8, golden_text, '\n');
    while (it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (!std.mem.startsWith(u8, line, prefix)) continue;

        const close = std.mem.indexOfScalarPos(u8, line, prefix.len, ']') orelse @panic("invalid index line");
        const eq = std.mem.indexOfScalarPos(u8, line, close + 1, '=') orelse @panic("invalid value line");

        const idx = std.fmt.parseInt(usize, line[prefix.len..close], 10) catch @panic("invalid index parse");
        if (idx >= N) @panic("index out of range");
        const val = std.fmt.parseInt(usize, line[eq + 1 ..], 10) catch @panic("invalid int parse");

        out[idx] = val;
        seen[idx] = true;
    }

    for (seen) |ok| {
        if (!ok) @panic("golden vector incomplete");
    }
    return out;
}

fn parseGoldenI32(comptime name: []const u8, comptime N: usize) [N]i32 {
    var out: [N]i32 = undefined;
    var seen = [_]bool{false} ** N;
    const prefix = std.fmt.comptimePrint("{s}[", .{name});

    var it = std.mem.splitScalar(u8, golden_text, '\n');
    while (it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (!std.mem.startsWith(u8, line, prefix)) continue;

        const close = std.mem.indexOfScalarPos(u8, line, prefix.len, ']') orelse @panic("invalid index line");
        const eq = std.mem.indexOfScalarPos(u8, line, close + 1, '=') orelse @panic("invalid value line");

        const idx = std.fmt.parseInt(usize, line[prefix.len..close], 10) catch @panic("invalid index parse");
        if (idx >= N) @panic("index out of range");
        const val = std.fmt.parseInt(i32, line[eq + 1 ..], 10) catch @panic("invalid int parse");

        out[idx] = val;
        seen[idx] = true;
    }

    for (seen) |ok| {
        if (!ok) @panic("golden vector incomplete");
    }
    return out;
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

test "golden_num_bands_for_rate" {
    const rates = parseGoldenI32("NUM_BANDS_RATES", 4);
    const expected = parseGoldenUsize("NUM_BANDS_EXPECTED", 4);
    for (rates, expected) |rate, exp| {
        const actual = aec3_common.num_bands_for_rate(rate);
        try std.testing.expectEqual(exp, actual);
    }
}

test "golden_fast_approx_log2f" {
    const inputs = parseGoldenF32("FAST_LOG2_INPUT", 1000);
    const expected = parseGoldenF32("FAST_LOG2_EXPECTED", 1000);
    for (inputs, expected) |x, exp| {
        const actual = aec3_common.fast_approx_log2f(x);
        try expectUlpEq(exp, actual, 1);
    }
}

test "golden_fft_data_spectrum_0" {
    const packed_array = parseGoldenF32("SPECTRUM_PACKED_0", aec3_common.FFT_LENGTH);
    const expected = parseGoldenF32("SPECTRUM_EXPECTED_0", aec3_common.FFT_LENGTH_BY_2_PLUS_1);

    var d = fft_data_mod.FftData.new();
    d.copy_from_packed_array(&packed_array);
    var out: [aec3_common.FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;
    d.spectrum(.none, &out);

    for (expected, out) |e, a| {
        try expectUlpEq(e, a, 1);
    }
}

test "golden_config_defaults" {
    const expected = parseGoldenF64("CONFIG_DEFAULTS", 20);
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
