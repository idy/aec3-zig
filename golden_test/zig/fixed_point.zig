const std = @import("std");
const FixedPoint = @import("aec3").FixedPoint;

const Q15 = FixedPoint(15);
const Q30 = FixedPoint(30);

test "FixedPoint basic conversion and arithmetic" {
    const a = Q15.fromFloatRuntime(0.5);
    const b = Q15.fromFloatRuntime(0.25);

    // Test conversion
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), a.toFloat(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), b.toFloat(), 0.001);

    // Test addSat
    const c = Q15.addSat(a, b);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), c.toFloat(), 0.001);

    // Test subSat
    const d = Q15.subSat(a, b);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), d.toFloat(), 0.001);

    // Test mulSat
    const e = Q15.mulSat(a, b);
    try std.testing.expectApproxEqAbs(@as(f32, 0.125), e.toFloat(), 0.001);

    // Test div
    const f = Q15.div(b, a);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), f.toFloat(), 0.001);
}

test "FixedPoint saturation bounds" {
    const max_val = Q15.fromRaw(std.math.maxInt(i32));
    const min_val = Q15.fromRaw(std.math.minInt(i32));
    const small = Q15.fromFloatRuntime(0.1);

    // addSat over max saturates to max
    try std.testing.expectEqual(max_val.raw, Q15.addSat(max_val, small).raw);

    // subSat under min saturates to min
    try std.testing.expectEqual(min_val.raw, Q15.subSat(min_val, small).raw);

    // mulSat max * max is near 1.0 (but fits in Q15)
    // max in Q15 is (2^15-1)/2^15
    const max_sq = Q15.mulSat(max_val, max_val);
    try std.testing.expect(max_sq.raw > 0);
    try std.testing.expect(max_sq.raw <= max_val.raw);
}

test "FixedPoint division edge cases" {
    const a = Q15.fromFloatRuntime(0.5);
    const zero = Q15.zero();

    // Division by zero in our fixed point library saturates to max or min depending on sign
    const div_zero = Q15.div(a, zero);
    try std.testing.expectEqual(@as(i32, std.math.maxInt(i32)), div_zero.raw);
}
