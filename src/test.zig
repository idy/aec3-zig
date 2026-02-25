//! 单元测试

test "sample_ops f32 basic arithmetic" {
    const std = @import("std");
    const ops = @import("sample_ops.zig").SampleOps(f32);

    // add/sub/mul/div
    try std.testing.expectEqual(@as(f32, 3.0), ops.add(1.0, 2.0));
    try std.testing.expectEqual(@as(f32, 5.0), ops.sub(7.0, 2.0));
    try std.testing.expectEqual(@as(f32, 6.0), ops.mul(2.0, 3.0));
    try std.testing.expectEqual(@as(f32, 4.0), ops.div(8.0, 2.0));
}

test "sample_ops f32 fromFloat" {
    const std = @import("std");
    const ops = @import("sample_ops.zig").SampleOps(f32);

    try std.testing.expectEqual(@as(f32, 1.5), ops.fromFloatComptime(1.5));
}

test "sample_ops f32 special values" {
    const std = @import("std");
    const ops = @import("sample_ops.zig").SampleOps(f32);

    try std.testing.expectEqual(@as(f32, 0.0), ops.zero());
    try std.testing.expectEqual(@as(f32, 1.0), ops.one());
    try std.testing.expect(ops.maxValue() > 1e30);
    // f32 minValue() returns most negative number (-maxValue)
    try std.testing.expect(ops.minValue() < -1e30);
}

test "sample_ops f32 abs/neg/clamp" {
    const std = @import("std");
    const ops = @import("sample_ops.zig").SampleOps(f32);

    try std.testing.expectEqual(@as(f32, 5.0), ops.abs(-5.0));
    try std.testing.expectEqual(@as(f32, -3.0), ops.neg(3.0));
    try std.testing.expectEqual(@as(f32, 5.0), ops.clamp(10.0, 0.0, 5.0));
    try std.testing.expectEqual(@as(f32, 0.0), ops.clamp(-5.0, 0.0, 5.0));
    try std.testing.expectEqual(@as(f32, 3.0), ops.clamp(3.0, 0.0, 5.0));
}

test "fixed_point fromFloat round-trip" {
    const std = @import("std");
    const FixedPoint = @import("fixed_point.zig").FixedPoint;

    const Q15 = FixedPoint(15);
    const original: f32 = 0.5;
    const fp = Q15.fromFloat(original);
    const result = fp.toFloat();

    // 误差 < 1 LSB (1/32768 ≈ 0.00003)
    const lsb = 1.0 / 32768.0;
    try std.testing.expect(@abs(result - original) < lsb);
}

test "fixed_point Q15 add" {
    const std = @import("std");
    const FixedPoint = @import("fixed_point.zig").FixedPoint;

    const Q15 = FixedPoint(15);
    const a = Q15.fromFloat(0.25);
    const b = Q15.fromFloat(0.75);
    const result = Q15.addWrap(a, b);

    try std.testing.expectApproxEqAbs(@as(f32, 1.0), result.toFloat(), 0.0001);
}

test "fixed_point Q15 mul" {
    const std = @import("std");
    const FixedPoint = @import("fixed_point.zig").FixedPoint;

    const Q15 = FixedPoint(15);
    const a = Q15.fromFloat(0.5);
    const b = Q15.fromFloat(0.5);
    const result = Q15.mulWrap(a, b);

    try std.testing.expectApproxEqAbs(@as(f32, 0.25), result.toFloat(), 0.0001);
}

test "fixed_point Q15 mul saturation" {
    const std = @import("std");
    const FixedPoint = @import("fixed_point.zig").FixedPoint;

    const Q15 = FixedPoint(15);
    // 两个大数相乘应该饱和而不是溢出
    const a = Q15.fromFloat(0.9);
    const b = Q15.fromFloat(0.9);
    const result = Q15.mulSat(a, b);

    // 0.9 * 0.9 = 0.81，应该在范围内
    try std.testing.expect(result.toFloat() > 0.8);
    try std.testing.expect(result.toFloat() <= 0.81);
}

test "sample_ops FixedPoint Q15" {
    const std = @import("std");
    const FixedPoint = @import("fixed_point.zig").FixedPoint;
    const ops = @import("sample_ops.zig").SampleOps(FixedPoint(15));

    const a = ops.fromFloatComptime(0.5);
    const b = ops.fromFloatComptime(0.25);

    // add
    const sum = ops.add(a, b);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), sum.toFloat(), 0.0001);

    // mul
    const prod = ops.mul(a, b);
    try std.testing.expectApproxEqAbs(@as(f32, 0.125), prod.toFloat(), 0.0001);

    // abs
    const neg_a = ops.neg(a);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), ops.abs(neg_a).toFloat(), 0.0001);
}

test "complex f32 mul" {
    const std = @import("std");
    const Complex = @import("complex.zig").Complex;

    const C = Complex(f32);
    const a = C.init(3.0, 4.0); // 3+4i
    const b = C.init(1.0, 2.0); // 1+2i
    const result = C.mul(a, b);

    // (3+4i)*(1+2i) = (3-8) + (6+4)i = -5 + 10i
    try std.testing.expectApproxEqAbs(@as(f32, -5.0), result.re, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), result.im, 0.0001);
}

test "complex f32 norm_sq" {
    const std = @import("std");
    const Complex = @import("complex.zig").Complex;

    const C = Complex(f32);
    const a = C.init(3.0, 4.0); // 3+4i
    const norm_sq = C.normSq(a);

    // |3+4i|² = 9 + 16 = 25
    try std.testing.expectApproxEqAbs(@as(f32, 25.0), norm_sq, 0.0001);
}

test "complex FixedPoint Q15 mul" {
    const std = @import("std");
    const FixedPoint = @import("fixed_point.zig").FixedPoint;
    const Complex = @import("complex.zig").Complex;

    const Q15 = FixedPoint(15);
    const C = Complex(Q15);

    // 0.5 * 0.5 = 0.25
    const a = C.init(Q15.fromFloat(0.5), Q15.fromFloat(0.0));
    const b = C.init(Q15.fromFloat(0.5), Q15.fromFloat(0.0));
    const result = C.mul(a, b);

    try std.testing.expectApproxEqAbs(@as(f32, 0.25), result.re.toFloat(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), result.im.toFloat(), 0.001);
}

test "fixed_point Q15 div" {
    const std = @import("std");
    const FixedPoint = @import("fixed_point.zig").FixedPoint;

    const Q15 = FixedPoint(15);

    // Normal division cases
    // 0.5 / 0.5 = 1.0
    {
        const a = Q15.fromFloat(0.5);
        const b = Q15.fromFloat(0.5);
        const result = Q15.div(a, b);
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), result.toFloat(), 0.0001);
    }

    // 0.25 / 0.5 = 0.5
    {
        const a = Q15.fromFloat(0.25);
        const b = Q15.fromFloat(0.5);
        const result = Q15.div(a, b);
        try std.testing.expectApproxEqAbs(@as(f32, 0.5), result.toFloat(), 0.0001);
    }

    // 0.75 / 0.25 = 3.0
    {
        const a = Q15.fromFloat(0.75);
        const b = Q15.fromFloat(0.25);
        const result = Q15.div(a, b);
        try std.testing.expectApproxEqAbs(@as(f32, 3.0), result.toFloat(), 0.0001);
    }

    // Division by zero - positive / 0 should saturate to max_value
    {
        const a = Q15.fromFloat(1.0);
        const zero = Q15.fromFloat(0.0);
        const result = Q15.div(a, zero);
        try std.testing.expectEqual(Q15.maxValue().raw, result.raw);
    }

    // Division by zero - negative / 0 should saturate to min_value
    {
        const a = Q15.fromFloat(-1.0);
        const zero = Q15.fromFloat(0.0);
        const result = Q15.div(a, zero);
        try std.testing.expectEqual(Q15.minValue().raw, result.raw);
    }

    // Division by zero - zero / 0 should saturate to max_value (positive path)
    {
        const a = Q15.fromFloat(0.0);
        const zero = Q15.fromFloat(0.0);
        const result = Q15.div(a, zero);
        try std.testing.expectEqual(Q15.maxValue().raw, result.raw);
    }

    // Sign combinations
    // positive / positive = positive
    {
        const a = Q15.fromFloat(0.8);
        const b = Q15.fromFloat(0.2);
        const result = Q15.div(a, b);
        try std.testing.expect(result.toFloat() > 0);
        try std.testing.expectApproxEqAbs(@as(f32, 4.0), result.toFloat(), 0.001);
    }

    // negative / positive = negative
    {
        const a = Q15.fromFloat(-0.8);
        const b = Q15.fromFloat(0.2);
        const result = Q15.div(a, b);
        try std.testing.expect(result.toFloat() < 0);
        try std.testing.expectApproxEqAbs(@as(f32, -4.0), result.toFloat(), 0.001);
    }

    // positive / negative = negative
    {
        const a = Q15.fromFloat(0.8);
        const b = Q15.fromFloat(-0.2);
        const result = Q15.div(a, b);
        try std.testing.expect(result.toFloat() < 0);
        try std.testing.expectApproxEqAbs(@as(f32, -4.0), result.toFloat(), 0.001);
    }

    // negative / negative = positive
    {
        const a = Q15.fromFloat(-0.8);
        const b = Q15.fromFloat(-0.2);
        const result = Q15.div(a, b);
        try std.testing.expect(result.toFloat() > 0);
        try std.testing.expectApproxEqAbs(@as(f32, 4.0), result.toFloat(), 0.001);
    }

    // Edge cases
    // 0 / anything = 0
    {
        const zero = Q15.fromFloat(0.0);
        const b = Q15.fromFloat(0.5);
        const result = Q15.div(zero, b);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), result.toFloat(), 0.0001);
    }

    // 1 / 1 = 1
    {
        const one = Q15.fromFloat(1.0);
        const result = Q15.div(one, one);
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), result.toFloat(), 0.0001);
    }

    // Small value division
    {
        const a = Q15.fromFloat(0.1);
        const b = Q15.fromFloat(0.1);
        const result = Q15.div(a, b);
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), result.toFloat(), 0.001);
    }
}
