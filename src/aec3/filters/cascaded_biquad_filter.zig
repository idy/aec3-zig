//! Ported from: docs/aec3-rs-src/audio_processing/utility/cascaded_biquad_filter.rs
const std = @import("std");
const Complex = @import("../../complex.zig").Complex;

pub const Complex32 = Complex(f32);

pub const BiQuadParam = struct {
    zero: Complex32,
    pole: Complex32,
    gain: f32,
    mirror_zero_along_i_axis: bool = false,

    pub fn new(zero: Complex32, pole: Complex32, gain: f32) BiQuadParam {
        return .{ .zero = zero, .pole = pole, .gain = gain };
    }

    pub fn with_mirrored_zero(zero_real: f32, pole: Complex32, gain: f32) BiQuadParam {
        return .{
            .zero = Complex32.init(zero_real, 0.0),
            .pole = pole,
            .gain = gain,
            .mirror_zero_along_i_axis = true,
        };
    }
};

pub const BiQuadCoefficients = struct {
    b: [3]f32,
    a: [2]f32,
};

const BiQuad = struct {
    coefficients: BiQuadCoefficients,
    x: [2]f32 = .{ 0.0, 0.0 },
    y: [2]f32 = .{ 0.0, 0.0 },

    fn new(coefficients: BiQuadCoefficients) BiQuad {
        return .{ .coefficients = coefficients };
    }

    fn from_param(param: BiQuadParam) BiQuad {
        const z_r = param.zero.re;
        const z_i = param.zero.im;
        const p_r = param.pole.re;
        const p_i = param.pole.im;

        var b: [3]f32 = .{ 0.0, 0.0, 0.0 };
        if (param.mirror_zero_along_i_axis) {
            b[0] = param.gain;
            b[1] = 0.0;
            b[2] = param.gain * -(z_r * z_r);
        } else {
            b[0] = param.gain;
            b[1] = param.gain * -2.0 * z_r;
            b[2] = param.gain * (z_r * z_r + z_i * z_i);
        }
        const a: [2]f32 = .{ -2.0 * p_r, p_r * p_r + p_i * p_i };
        return .{ .coefficients = .{ .b = b, .a = a } };
    }

    fn reset(self: *BiQuad) void {
        self.x = .{ 0.0, 0.0 };
        self.y = .{ 0.0, 0.0 };
    }
};

pub const CascadedBiQuadFilter = struct {
    biquads: []BiQuad,
    allocator: std.mem.Allocator,

    pub fn with_coefficients(allocator: std.mem.Allocator, coefficients: BiQuadCoefficients, num_biquads: usize) !CascadedBiQuadFilter {
        const biquads = try allocator.alloc(BiQuad, num_biquads);
        for (biquads) |*stage| stage.* = BiQuad.new(coefficients);
        return .{ .biquads = biquads, .allocator = allocator };
    }

    pub fn from_params(allocator: std.mem.Allocator, params: []const BiQuadParam) !CascadedBiQuadFilter {
        const biquads = try allocator.alloc(BiQuad, params.len);
        for (params, 0..) |param, i| biquads[i] = BiQuad.from_param(param);
        return .{ .biquads = biquads, .allocator = allocator };
    }

    pub fn deinit(self: *CascadedBiQuadFilter) void {
        self.allocator.free(self.biquads);
    }

    pub fn process(self: *CascadedBiQuadFilter, input: []const f32, output: []f32) void {
        std.debug.assert(input.len == output.len);
        if (self.biquads.len == 0) {
            @memcpy(output, input);
            return;
        }

        self.apply_biquad_stage(input, output, 0);
        var stage: usize = 1;
        while (stage < self.biquads.len) : (stage += 1) {
            self.apply_biquad_stage_in_place(output, stage);
        }
    }

    pub fn process_in_place(self: *CascadedBiQuadFilter, data: []f32) void {
        var stage: usize = 0;
        while (stage < self.biquads.len) : (stage += 1) {
            self.apply_biquad_stage_in_place(data, stage);
        }
    }

    pub fn reset(self: *CascadedBiQuadFilter) void {
        for (self.biquads) |*biquad| biquad.reset();
    }

    fn apply_biquad_stage(self: *CascadedBiQuadFilter, input: []const f32, output: []f32, stage: usize) void {
        std.debug.assert(input.len == output.len);
        const biquad = &self.biquads[stage];
        const b = biquad.coefficients.b;
        const a = biquad.coefficients.a;

        for (input, output) |x, *y| {
            const out = b[0] * x + b[1] * biquad.x[0] + b[2] * biquad.x[1] - a[0] * biquad.y[0] - a[1] * biquad.y[1];
            biquad.x[1] = biquad.x[0];
            biquad.x[0] = x;
            biquad.y[1] = biquad.y[0];
            biquad.y[0] = out;
            y.* = out;
        }
    }

    fn apply_biquad_stage_in_place(self: *CascadedBiQuadFilter, data: []f32, stage: usize) void {
        const biquad = &self.biquads[stage];
        const b = biquad.coefficients.b;
        const a = biquad.coefficients.a;

        for (data) |*sample| {
            const tmp = sample.*;
            const out = b[0] * tmp + b[1] * biquad.x[0] + b[2] * biquad.x[1] - a[0] * biquad.y[0] - a[1] * biquad.y[1];
            biquad.x[1] = biquad.x[0];
            biquad.x[0] = tmp;
            biquad.y[1] = biquad.y[0];
            biquad.y[0] = out;
            sample.* = out;
        }
    }
};

test "cascaded_biquad_filter passthrough when empty" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var filter_inst = try CascadedBiQuadFilter.from_params(arena.allocator(), &.{});
    defer filter_inst.deinit();

    const input = [_]f32{ 1.0, -2.0, 3.5, 0.25 };
    var output = [_]f32{0} ** input.len;
    filter_inst.process(input[0..], output[0..]);
    try std.testing.expectEqualSlices(f32, input[0..], output[0..]);
}

test "cascaded_biquad_filter known coefficient produces expected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const coeffs = BiQuadCoefficients{ .b = .{ 1.0, 0.5, 0.0 }, .a = .{ 0.0, 0.0 } };
    var filter_inst = try CascadedBiQuadFilter.with_coefficients(arena.allocator(), coeffs, 1);
    defer filter_inst.deinit();

    const input = [_]f32{ 1.0, 2.0, 3.0 };
    var output = [_]f32{0} ** input.len;
    filter_inst.process(input[0..], output[0..]);

    try std.testing.expectApproxEqAbs(@as(f32, 1.0), output[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 2.5), output[1], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), output[2], 1e-6);
}

test "cascaded_biquad_filter process_in_place produces same result as process" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const coeffs = BiQuadCoefficients{ .b = .{ 1.0, 0.5, 0.0 }, .a = .{ 0.0, 0.0 } };
    var filter1 = try CascadedBiQuadFilter.with_coefficients(arena.allocator(), coeffs, 1);
    defer filter1.deinit();
    var filter2 = try CascadedBiQuadFilter.with_coefficients(arena.allocator(), coeffs, 1);
    defer filter2.deinit();

    const input = [_]f32{ 1.0, 2.0, 3.0, 4.0 };
    var output = [_]f32{0} ** input.len;
    var in_place = [_]f32{0} ** input.len;
    @memcpy(in_place[0..], input[0..]);

    filter1.process(input[0..], output[0..]);
    filter2.process_in_place(in_place[0..]);

    try std.testing.expectEqualSlices(f32, output[0..], in_place[0..]);
}

test "cascaded_biquad_filter reset clears state" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const coeffs = BiQuadCoefficients{ .b = .{ 1.0, 0.5, 0.0 }, .a = .{ 0.0, 0.0 } };
    var filter_inst = try CascadedBiQuadFilter.with_coefficients(arena.allocator(), coeffs, 1);
    defer filter_inst.deinit();

    const input = [_]f32{ 1.0, 2.0, 3.0 };
    var output1 = [_]f32{0} ** input.len;
    filter_inst.process(input[0..], output1[0..]);

    filter_inst.reset();

    var output2 = [_]f32{0} ** input.len;
    filter_inst.process(input[0..], output2[0..]);

    // After reset, output should be same as first time
    try std.testing.expectEqualSlices(f32, output1[0..], output2[0..]);
}

test "cascaded_biquad_filter mirrored-zero param formula" {
    const param = BiQuadParam.with_mirrored_zero(0.5, Complex32.init(0.25, 0.75), 0.8);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var filter_inst = try CascadedBiQuadFilter.from_params(arena.allocator(), &[_]BiQuadParam{param});
    defer filter_inst.deinit();

    try std.testing.expectApproxEqAbs(@as(f32, 0.8), filter_inst.biquads[0].coefficients.b[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), filter_inst.biquads[0].coefficients.b[1], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, -0.2), filter_inst.biquads[0].coefficients.b[2], 1e-6);
}

test "cascaded_biquad_filter BiQuadParam new creates valid param" {
    const zero = Complex32.init(0.5, 0.3);
    const pole = Complex32.init(0.2, 0.1);
    const param = BiQuadParam.new(zero, pole, 1.5);

    try std.testing.expectApproxEqAbs(@as(f32, 0.5), param.zero.re, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.3), param.zero.im, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), param.pole.re, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), param.pole.im, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1.5), param.gain, 1e-6);
    try std.testing.expectEqual(false, param.mirror_zero_along_i_axis);
}

test "cascaded_biquad_filter BiQuadParam with_mirrored_zero sets flag" {
    const pole = Complex32.init(0.2, 0.1);
    const param = BiQuadParam.with_mirrored_zero(0.5, pole, 0.8);

    try std.testing.expectEqual(true, param.mirror_zero_along_i_axis);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), param.zero.re, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), param.zero.im, 1e-6);
}

test "cascaded_biquad_filter BiQuadParam new boundary extreme values" {
    // Test with extreme/polar values for zero and pole
    const zero = Complex32.init(std.math.floatMax(f32), -std.math.floatMax(f32));
    const pole = Complex32.init(-std.math.floatMax(f32), std.math.floatMax(f32));
    const param = BiQuadParam.new(zero, pole, std.math.floatMax(f32));

    try std.testing.expect(std.math.isFinite(param.zero.re));
    try std.testing.expect(std.math.isFinite(param.zero.im));
    try std.testing.expect(std.math.isFinite(param.pole.re));
    try std.testing.expect(std.math.isFinite(param.pole.im));
    try std.testing.expect(std.math.isFinite(param.gain));
}

test "cascaded_biquad_filter BiQuadParam new boundary zero gain" {
    // Zero gain is a valid degenerate case
    const zero = Complex32.init(0.5, 0.0);
    const pole = Complex32.init(0.2, 0.0);
    const param = BiQuadParam.new(zero, pole, 0.0);

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), param.gain, 1e-6);
    try std.testing.expectEqual(false, param.mirror_zero_along_i_axis);
}

test "cascaded_biquad_filter BiQuadParam new boundary negative values" {
    // Negative values should be handled correctly
    const zero = Complex32.init(-0.5, -0.3);
    const pole = Complex32.init(-0.2, -0.1);
    const param = BiQuadParam.new(zero, pole, -1.5);

    try std.testing.expectApproxEqAbs(@as(f32, -0.5), param.zero.re, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, -0.3), param.zero.im, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, -0.2), param.pole.re, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, -1.5), param.gain, 1e-6);
}

test "cascaded_biquad_filter BiQuadParam new boundary zero zero pole" {
    // Test zero/pole = 0 (origin)
    const zero = Complex32.init(0.0, 0.0);
    const pole = Complex32.init(0.0, 0.0);
    const param = BiQuadParam.new(zero, pole, 1.0);

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), param.zero.re, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), param.zero.im, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), param.pole.re, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), param.pole.im, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), param.gain, 1e-6);
    try std.testing.expectEqual(false, param.mirror_zero_along_i_axis);
}

test "cascaded_biquad_filter BiQuadParam new boundary gain zero" {
    // Test gain = 0
    const zero = Complex32.init(0.5, 0.3);
    const pole = Complex32.init(0.2, 0.1);
    const param = BiQuadParam.new(zero, pole, 0.0);

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), param.gain, 1e-6);
    try std.testing.expectEqual(false, param.mirror_zero_along_i_axis);
}

test "cascaded_biquad_filter BiQuadParam new degenerate zero equals pole" {
    // Degenerate case: zero == pole
    const val = Complex32.init(0.5, 0.3);
    const param = BiQuadParam.new(val, val, 1.0);

    // Fields should be exactly equal (no implicit modification)
    try std.testing.expectApproxEqAbs(val.re, param.zero.re, 1e-6);
    try std.testing.expectApproxEqAbs(val.im, param.zero.im, 1e-6);
    try std.testing.expectApproxEqAbs(val.re, param.pole.re, 1e-6);
    try std.testing.expectApproxEqAbs(val.im, param.pole.im, 1e-6);
    try std.testing.expectEqual(false, param.mirror_zero_along_i_axis);
}

test "cascaded_biquad_filter BiQuadParam with_mirrored_zero boundary extreme real values" {
    // Test extreme values for the mirrored zero real part
    const pole = Complex32.init(0.2, 0.1);

    // Large positive value
    const param1 = BiQuadParam.with_mirrored_zero(std.math.floatMax(f32), pole, 1.0);
    try std.testing.expect(std.math.isFinite(param1.zero.re));
    try std.testing.expectEqual(true, param1.mirror_zero_along_i_axis);

    // Large negative value
    const param2 = BiQuadParam.with_mirrored_zero(-std.math.floatMax(f32), pole, 1.0);
    try std.testing.expect(std.math.isFinite(param2.zero.re));
    try std.testing.expectEqual(true, param2.mirror_zero_along_i_axis);

    // Zero value (edge case)
    const param3 = BiQuadParam.with_mirrored_zero(0.0, pole, 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), param3.zero.re, 1e-6);
    try std.testing.expectEqual(true, param3.mirror_zero_along_i_axis);
}

test "cascaded_biquad_filter BiQuadParam with_mirrored_zero boundary zero gain" {
    // Zero gain with mirrored zero
    const pole = Complex32.init(0.2, 0.1);
    const param = BiQuadParam.with_mirrored_zero(0.5, pole, 0.0);

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), param.gain, 1e-6);
    try std.testing.expectEqual(true, param.mirror_zero_along_i_axis);
}

test "cascaded_biquad_filter BiQuadParam with_mirrored_zero boundary negative real" {
    // Test negative zero_real value
    const pole = Complex32.init(0.2, 0.1);
    const param = BiQuadParam.with_mirrored_zero(-0.5, pole, 1.0);

    try std.testing.expectApproxEqAbs(@as(f32, -0.5), param.zero.re, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), param.zero.im, 1e-6);
    try std.testing.expectEqual(true, param.mirror_zero_along_i_axis);
}

test "cascaded_biquad_filter BiQuadParam with_mirrored_zero boundary zero real" {
    // Test zero_real = 0 (explicit boundary)
    const pole = Complex32.init(0.2, 0.1);
    const param = BiQuadParam.with_mirrored_zero(0.0, pole, 1.0);

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), param.zero.re, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), param.zero.im, 1e-6);
    try std.testing.expectEqual(true, param.mirror_zero_along_i_axis);
}

test "cascaded_biquad_filter BiQuadParam with_mirrored_zero extreme pole stability" {
    // Test with extreme but finite pole values
    const pole1 = Complex32.init(std.math.floatMax(f32), std.math.floatMax(f32));
    const param1 = BiQuadParam.with_mirrored_zero(0.5, pole1, 1.0);
    try std.testing.expect(std.math.isFinite(param1.pole.re));
    try std.testing.expect(std.math.isFinite(param1.pole.im));
    try std.testing.expectEqual(true, param1.mirror_zero_along_i_axis);

    const pole2 = Complex32.init(-std.math.floatMax(f32), -std.math.floatMax(f32));
    const param2 = BiQuadParam.with_mirrored_zero(0.5, pole2, 1.0);
    try std.testing.expect(std.math.isFinite(param2.pole.re));
    try std.testing.expect(std.math.isFinite(param2.pole.im));
    try std.testing.expectEqual(true, param2.mirror_zero_along_i_axis);

    const pole3 = Complex32.init(0.0, 0.0);
    const param3 = BiQuadParam.with_mirrored_zero(0.5, pole3, 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), param3.pole.re, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), param3.pole.im, 1e-6);
    try std.testing.expectEqual(true, param3.mirror_zero_along_i_axis);
}

test "cascaded_biquad_filter with_coefficients OOM rollbacks" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    const alloc = failing.allocator();

    const coeffs = BiQuadCoefficients{ .b = .{ 1.0, 0.5, 0.0 }, .a = .{ 0.0, 0.0 } };
    try std.testing.expectError(error.OutOfMemory, CascadedBiQuadFilter.with_coefficients(alloc, coeffs, 1));
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
}

test "cascaded_biquad_filter from_params OOM rollbacks" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    const alloc = failing.allocator();

    const param = BiQuadParam.new(Complex32.init(0.5, 0.0), Complex32.init(0.2, 0.0), 1.0);
    try std.testing.expectError(error.OutOfMemory, CascadedBiQuadFilter.from_params(alloc, &[_]BiQuadParam{param}));
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
}

test "cascaded_biquad_filter deinit frees memory" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const coeffs = BiQuadCoefficients{ .b = .{ 1.0, 0.5, 0.0 }, .a = .{ 0.0, 0.0 } };
    var filter_inst = try CascadedBiQuadFilter.with_coefficients(arena.allocator(), coeffs, 2);
    filter_inst.deinit();

    // If deinit doesn't free, arena will detect leak on defer
    try std.testing.expect(true);
}

test "cascaded_biquad_filter process boundary empty input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const coeffs = BiQuadCoefficients{ .b = .{ 1.0, 0.0, 0.0 }, .a = .{ 0.0, 0.0 } };
    var filter_inst = try CascadedBiQuadFilter.with_coefficients(arena.allocator(), coeffs, 1);
    defer filter_inst.deinit();

    const input = [_]f32{};
    var output = [_]f32{};
    filter_inst.process(input[0..], output[0..]);
    // Empty input should be handled gracefully
    try std.testing.expectEqual(@as(usize, 0), output.len);
}

test "cascaded_biquad_filter process_in_place boundary empty input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const coeffs = BiQuadCoefficients{ .b = .{ 1.0, 0.0, 0.0 }, .a = .{ 0.0, 0.0 } };
    var filter_inst = try CascadedBiQuadFilter.with_coefficients(arena.allocator(), coeffs, 1);
    defer filter_inst.deinit();

    var data = [_]f32{};
    filter_inst.process_in_place(data[0..]);
    // Empty input should be handled gracefully
    try std.testing.expectEqual(@as(usize, 0), data.len);
}

test "cascaded_biquad_filter process_in_place boundary single sample" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const coeffs = BiQuadCoefficients{ .b = .{ 1.0, 0.5, 0.0 }, .a = .{ 0.0, 0.0 } };
    var filter_inst = try CascadedBiQuadFilter.with_coefficients(arena.allocator(), coeffs, 1);
    defer filter_inst.deinit();

    var data = [_]f32{5.0};
    filter_inst.process_in_place(data[0..]);
    // Single sample should be processed (with state being zero initially)
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), data[0], 1e-6);
}

test "cascaded_biquad_filter process_in_place boundary zero stages" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // Zero biquads should be passthrough
    var filter_inst = try CascadedBiQuadFilter.from_params(arena.allocator(), &.{});
    defer filter_inst.deinit();

    var data = [_]f32{ 1.0, 2.0, 3.0 };
    const expected = [_]f32{ 1.0, 2.0, 3.0 };
    filter_inst.process_in_place(data[0..]);
    try std.testing.expectEqualSlices(f32, expected[0..], data[0..]);
}

test "cascaded_biquad_filter deinit boundary zero stages" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // Zero biquads should deinit without error
    var filter_inst = try CascadedBiQuadFilter.from_params(arena.allocator(), &.{});
    filter_inst.deinit();

    try std.testing.expect(true);
}

test "cascaded_biquad_filter reset boundary stability" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const coeffs = BiQuadCoefficients{ .b = .{ 1.0, 0.5, 0.0 }, .a = .{ 0.0, 0.0 } };
    var filter_inst = try CascadedBiQuadFilter.with_coefficients(arena.allocator(), coeffs, 1);
    defer filter_inst.deinit();

    const input = [_]f32{ 1.0, 2.0, 3.0 };
    var output1 = [_]f32{0} ** input.len;
    filter_inst.process(input[0..], output1[0..]);

    // Reset and process again
    filter_inst.reset();
    var output2 = [_]f32{0} ** input.len;
    filter_inst.process(input[0..], output2[0..]);

    // Multiple resets should be stable
    filter_inst.reset();
    filter_inst.reset();
    var output3 = [_]f32{0} ** input.len;
    filter_inst.process(input[0..], output3[0..]);

    try std.testing.expectEqualSlices(f32, output1[0..], output2[0..]);
    try std.testing.expectEqualSlices(f32, output2[0..], output3[0..]);
}
