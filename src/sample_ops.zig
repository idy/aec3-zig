//! SampleOps - 统一的数值运算接口
//! 只声明已实现的方法，禁止预留未实现函数

const std = @import("std");
const FixedPoint = @import("fixed_point.zig").FixedPoint;

/// 统一的数值运算接口
/// comptime 泛型，支持 f32 和 FixedPoint(Q)
pub fn SampleOps(comptime T: type) type {
    return struct {
        // ===== 基础算术 =====

        pub inline fn add(a: T, b: T) T {
            if (T == f32) {
                return a + b;
            } else {
                return T.add(a, b);
            }
        }

        pub inline fn sub(a: T, b: T) T {
            if (T == f32) {
                return a - b;
            } else {
                return T.sub(a, b);
            }
        }

        pub inline fn mul(a: T, b: T) T {
            if (T == f32) {
                return a * b;
            } else {
                return T.mul(a, b);
            }
        }

        pub inline fn div(a: T, b: T) T {
            if (T == f32) {
                return a / b;
            } else {
                return T.div(a, b);
            }
        }

        pub inline fn neg(a: T) T {
            if (T == f32) {
                return -a;
            } else {
                return T.neg(a);
            }
        }

        pub inline fn abs(a: T) T {
            if (T == f32) {
                return @abs(a);
            } else {
                return T.abs(a);
            }
        }

        // ===== 类型转换 =====

        /// comptime 版本（用于常量初始化）
        pub inline fn fromFloatComptime(comptime v: f32) T {
            if (T == f32) {
                return v;
            } else {
                return T.fromFloat(v);
            }
        }

        /// 运行时版本（用于动态值）
        pub inline fn fromFloat(v: f32) T {
            if (T == f32) {
                return v;
            } else {
                return T.fromFloatRuntime(v);
            }
        }

        pub inline fn fromInt(v: i32) T {
            if (T == f32) {
                return @as(f32, @floatFromInt(v));
            } else {
                return T.fromInt(v);
            }
        }

        pub inline fn toFloat(v: T) f32 {
            if (T == f32) {
                return v;
            } else {
                return v.toFloat();
            }
        }

        // ===== 常量 =====

        pub inline fn zero() T {
            if (T == f32) {
                return 0.0;
            } else {
                return T.zero();
            }
        }

        pub inline fn one() T {
            if (T == f32) {
                return 1.0;
            } else {
                return T.one();
            }
        }

        pub inline fn maxValue() T {
            if (T == f32) {
                return std.math.floatMax(f32);
            } else {
                return T.maxValue();
            }
        }

        pub inline fn minValue() T {
            if (T == f32) {
                return std.math.floatMin(f32);
            } else {
                return T.minValue();
            }
        }

        // ===== 比较 =====

        pub inline fn lessThan(a: T, b: T) bool {
            if (T == f32) {
                return a < b;
            } else {
                return T.lessThan(a, b);
            }
        }

        pub inline fn max(a: T, b: T) T {
            if (T == f32) {
                return @max(a, b);
            } else {
                return T.max(a, b);
            }
        }

        pub inline fn min(a: T, b: T) T {
            if (T == f32) {
                return @min(a, b);
            } else {
                return T.min(a, b);
            }
        }

        pub inline fn clamp(v: T, lo: T, hi: T) T {
            if (T == f32) {
                return std.math.clamp(v, lo, hi);
            } else {
                return T.clamp(v, lo, hi);
            }
        }
    };
}
