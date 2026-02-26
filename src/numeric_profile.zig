//! 数值配置映射 - 模式到具体实现的映射
//! 封闭设计：不开放外部 profile 参数组合

const std = @import("std");
const NumericMode = @import("numeric_mode.zig").NumericMode;
const FixedPoint = @import("fixed_point.zig").FixedPoint;

/// Fixed-point-first default numeric mode used by public entry points.
pub const DEFAULT_NUMERIC_MODE: NumericMode = .fixed_mcu_q15;

/// Default profile bound to `DEFAULT_NUMERIC_MODE`.
pub const DefaultProfile = profileFor(DEFAULT_NUMERIC_MODE);

/// 为给定的数值模式获取对应的 profile
/// 封闭设计：只允许两种预定义模式的合法映射
pub fn profileFor(comptime mode: NumericMode) type {
    return switch (mode) {
        .float32 => FloatProfile,
        .fixed_mcu_q15 => FixedMcuQ15Profile,
    };
}

/// float32 模式配置
pub const FloatProfile = struct {
    pub const Sample = f32;
    pub const ComplexSample = @import("complex.zig").Complex(f32);
};

/// fixed_mcu_q15 模式配置
/// Q15: i32 存储，15位小数位
pub const FixedMcuQ15Profile = struct {
    pub const Sample = FixedPoint(15);
    pub const ComplexSample = @import("complex.zig").Complex(FixedPoint(15));
};

test "default numeric mode is fixed_mcu_q15" {
    try std.testing.expectEqual(NumericMode.fixed_mcu_q15, DEFAULT_NUMERIC_MODE);
}

test "default profile sample type is Q15" {
    const Q15 = FixedPoint(15);
    try std.testing.expect(@TypeOf(DefaultProfile.Sample.zero()) == Q15);
}
