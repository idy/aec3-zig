const std = @import("std");
const aec3 = @import("aec3");
const common = @import("common.zig");

const golden_text = @embedFile("../vectors/rust_audio_infra_golden_vectors.txt");

test "golden_sparse_fir_filter_two_block_outputs" {
    const in1 = common.parseNamedF32(golden_text, "SPARSE_FIR_BLOCK1_IN8", 8);
    const in2 = common.parseNamedF32(golden_text, "SPARSE_FIR_BLOCK2_IN8", 8);
    const exp1 = common.parseNamedF32(golden_text, "SPARSE_FIR_BLOCK1_OUT8", 8);
    const exp2 = common.parseNamedF32(golden_text, "SPARSE_FIR_BLOCK2_OUT8", 8);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var filter_inst = try aec3.SparseFIRFilter.new(arena.allocator(), &.{ 0.8, -0.3, 0.1 }, 2, 1);
    defer filter_inst.deinit();

    var out1 = [_]f32{0.0} ** 8;
    var out2 = [_]f32{0.0} ** 8;
    filter_inst.filter(in1[0..], out1[0..]);
    filter_inst.filter(in2[0..], out2[0..]);

    for (exp1, out1) |e, a| try std.testing.expectApproxEqAbs(e, a, 1e-6);
    for (exp2, out2) |e, a| try std.testing.expectApproxEqAbs(e, a, 1e-6);
}

test "golden_cascaded_biquad_filter_output" {
    const input = common.parseNamedF32(golden_text, "CASCADED_BIQUAD_INPUT32", 32);
    const expected = common.parseNamedF32(golden_text, "CASCADED_BIQUAD_OUTPUT32", 32);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const coeffs = aec3.BiQuadCoefficients{ .b = .{ 0.98621, -1.97242, 0.98621 }, .a = .{ -1.97223, 0.97261 } };
    var filter_inst = try aec3.CascadedBiQuadFilter.with_coefficients(arena.allocator(), coeffs, 1);
    defer filter_inst.deinit();

    var output = [_]f32{0.0} ** 32;
    filter_inst.process(input[0..], output[0..]);

    for (expected, output) |e, a| try std.testing.expectApproxEqAbs(e, a, 2e-6);
}

test "golden_high_pass_filter_single_channel_output" {
    const input = common.parseNamedF32(golden_text, "HIGH_PASS_INPUT64", 64);
    const expected = common.parseNamedF32(golden_text, "HIGH_PASS_OUTPUT64", 64);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var hp = try aec3.HighPassFilter.new(arena.allocator(), 16_000, 1);
    defer hp.deinit();

    var output = input;
    var channels = [_][]f32{output[0..]};
    hp.process(channels[0..]);

    for (expected, output) |e, a| try std.testing.expectApproxEqAbs(e, a, 2e-6);
}

test "golden_push_sinc_algorithmic_delay_seconds" {
    const rates = common.parseNamedI32(golden_text, "PUSH_SINC_DELAY_RATES5", 5);
    const expected = common.parseNamedF32(golden_text, "PUSH_SINC_DELAY_EXPECTED5", 5);

    for (rates, expected) |rate, exp| {
        const actual = aec3.PushSincResampler.algorithmic_delay_seconds(rate);
        try std.testing.expectApproxEqAbs(exp, actual, 1e-7);
    }
}

test "golden_sinc_resampler_output48" {
    const input = common.parseNamedF32(golden_text, "SINC_RESAMPLER_INPUT64", 64);
    const expected = common.parseNamedF32(golden_text, "SINC_RESAMPLER_OUTPUT48", 48);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var resampler = try aec3.SincResampler.new(arena.allocator(), 64.0 / 192.0, 64);
    defer resampler.deinit();

    const InputProvider = struct {
        source: []const f32,
        consumed: usize = 0,

        fn fill(ctx: *anyopaque, dest: []f32) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            const available = self.source.len - @min(self.consumed, self.source.len);
            const n = @min(available, dest.len);
            if (n > 0) {
                @memcpy(dest[0..n], self.source[self.consumed .. self.consumed + n]);
                self.consumed += n;
            }
            if (n < dest.len) @memset(dest[n..], 0.0);
        }
    };

    var provider = InputProvider{ .source = input[0..] };
    var output = [_]f32{0.0} ** 48;
    resampler.resample(48, output[0..], &provider, InputProvider.fill);

    for (expected, output) |e, a| try std.testing.expectApproxEqAbs(e, a, 2e-5);
}

test "golden_three_band_filter_bank_analysis_and_recon" {
    const input = common.parseNamedF32(golden_text, "THREE_BAND_INPUT96", 96);
    const exp_band0 = common.parseNamedF32(golden_text, "THREE_BAND_ANALYSIS_BAND0_32", 32);
    const exp_band1 = common.parseNamedF32(golden_text, "THREE_BAND_ANALYSIS_BAND1_32", 32);
    const exp_band2 = common.parseNamedF32(golden_text, "THREE_BAND_ANALYSIS_BAND2_32", 32);
    const exp_recon = common.parseNamedF32(golden_text, "THREE_BAND_RECON96", 96);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var fb = try aec3.ThreeBandFilterBank.new(arena.allocator(), 96);
    defer fb.deinit();

    var b0 = [_]f32{0.0} ** 32;
    var b1 = [_]f32{0.0} ** 32;
    var b2 = [_]f32{0.0} ** 32;
    var out_bands = [3][]f32{ b0[0..], b1[0..], b2[0..] };
    fb.analysis(input[0..], &out_bands);

    for (exp_band0, b0) |e, a| try std.testing.expectApproxEqAbs(e, a, 2e-5);
    for (exp_band1, b1) |e, a| try std.testing.expectApproxEqAbs(e, a, 2e-5);
    for (exp_band2, b2) |e, a| try std.testing.expectApproxEqAbs(e, a, 2e-5);

    var recon = [_]f32{0.0} ** 96;
    const in_bands = [3][]const f32{ b0[0..], b1[0..], b2[0..] };
    fb.synthesis(&in_bands, recon[0..]);

    for (exp_recon, recon) |e, a| try std.testing.expectApproxEqAbs(e, a, 2e-5);
}
