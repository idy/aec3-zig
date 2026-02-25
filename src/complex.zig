//! Complex - 泛型复数类型
//! 支持任意数值类型 T（f32, FixedPoint等）

const std = @import("std");

/// 泛型复数类型
pub fn Complex(comptime T: type) type {
    return struct {
        re: T, // 实部
        im: T, // 虚部

        const Self = @This();

        /// 创建复数
        pub inline fn init(r: T, i: T) Self {
            return .{ .re = r, .im = i };
        }

        /// 零复数
        pub inline fn zero() Self {
            const ops = @import("sample_ops.zig").SampleOps(T);
            return .{ .re = ops.zero(), .im = ops.zero() };
        }

        /// 一加零i
        pub inline fn one() Self {
            const ops = @import("sample_ops.zig").SampleOps(T);
            return .{ .re = ops.one(), .im = ops.zero() };
        }

        /// 从实数创建
        pub inline fn fromReal(r: T) Self {
            const ops = @import("sample_ops.zig").SampleOps(T);
            return .{ .re = r, .im = ops.zero() };
        }

        /// 加法
        pub inline fn add(a: Self, b: Self) Self {
            const ops = @import("sample_ops.zig").SampleOps(T);
            return .{
                .re = ops.add(a.re, b.re),
                .im = ops.add(a.im, b.im),
            };
        }

        /// 减法
        pub inline fn sub(a: Self, b: Self) Self {
            const ops = @import("sample_ops.zig").SampleOps(T);
            return .{
                .re = ops.sub(a.re, b.re),
                .im = ops.sub(a.im, b.im),
            };
        }

        /// 乘法: (a+bi)*(c+di) = (ac-bd) + (ad+bc)i
        pub inline fn mul(a: Self, b: Self) Self {
            const ops = @import("sample_ops.zig").SampleOps(T);
            const ac = ops.mul(a.re, b.re);
            const bd = ops.mul(a.im, b.im);
            const ad = ops.mul(a.re, b.im);
            const bc = ops.mul(a.im, b.re);
            return .{
                .re = ops.sub(ac, bd),
                .im = ops.add(ad, bc),
            };
        }

        /// 共轭
        pub inline fn conj(a: Self) Self {
            const ops = @import("sample_ops.zig").SampleOps(T);
            return .{
                .re = a.re,
                .im = ops.neg(a.im),
            };
        }

        /// 模平方: |z|² = re² + im²
        pub inline fn normSq(a: Self) T {
            const ops = @import("sample_ops.zig").SampleOps(T);
            const re2 = ops.mul(a.re, a.re);
            const im2 = ops.mul(a.im, a.im);
            return ops.add(re2, im2);
        }

        /// 缩放
        pub inline fn scale(a: Self, s: T) Self {
            const ops = @import("sample_ops.zig").SampleOps(T);
            return .{
                .re = ops.mul(a.re, s),
                .im = ops.mul(a.im, s),
            };
        }
    };
}
