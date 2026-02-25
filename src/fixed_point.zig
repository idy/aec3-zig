//! FixedPoint 定点数类型
//! Q15 格式: i32 存储，15位小数位
//! 饱和算术，乘法使用 i64 中间值，除法使用倒数查表

const std = @import("std");

/// 定点数类型，comptime 指定小数位数
pub fn FixedPoint(comptime frac_bits: u8) type {
    if (frac_bits > 30) {
        @compileError("frac_bits must be <= 30 for i32 storage");
    }

    const IntType = i32;
    const AccumType = i64;
    const scale: IntType = @as(IntType, 1) << frac_bits;
    const max_val: IntType = std.math.maxInt(IntType);
    const min_val: IntType = std.math.minInt(IntType);

    return struct {
        raw: IntType,

        const Self = @This();

        // ===== 常量 =====

        pub inline fn scaleFactor() IntType {
            return scale;
        }

        pub inline fn fracBits() u8 {
            return frac_bits;
        }

        // ===== 构造函数 =====

        /// 从原始值创建（用于内部使用）
        pub inline fn fromRaw(r: IntType) Self {
            return .{ .raw = r };
        }

        /// 从整数创建
        pub inline fn fromInt(v: i32) Self {
            return .{ .raw = @as(IntType, v) * scale };
        }

        /// 从浮点数创建（comptime 支持）
        pub inline fn fromFloat(comptime v: f32) Self {
            const scaled = v * @as(f32, @floatFromInt(scale));
            const rounded = @round(scaled);
            return .{ .raw = @as(IntType, @intFromFloat(rounded)) };
        }

        /// 从运行时浮点数创建
        pub inline fn fromFloatRuntime(v: f32) Self {
            const scaled = v * @as(f32, @floatFromInt(scale));
            const rounded = @round(scaled);
            return .{ .raw = @as(IntType, @intFromFloat(rounded)) };
        }

        /// 转换为浮点数
        pub inline fn toFloat(self: Self) f32 {
            return @as(f32, @floatFromInt(self.raw)) / @as(f32, @floatFromInt(scale));
        }

        // ===== 基础算术（非饱和） =====

        pub inline fn add(a: Self, b: Self) Self {
            return .{ .raw = a.raw + b.raw };
        }

        pub inline fn sub(a: Self, b: Self) Self {
            return .{ .raw = a.raw - b.raw };
        }

        pub inline fn mul(a: Self, b: Self) Self {
            const prod: AccumType = @as(AccumType, a.raw) * @as(AccumType, b.raw);
            const shifted = prod >> frac_bits;
            return .{ .raw = @as(IntType, @intCast(shifted)) };
        }

        /// 除法：使用倒数查表
        pub inline fn div(a: Self, b: Self) Self {
            // 特殊情况处理
            if (b.raw == 0) {
                if (a.raw >= 0) return .{ .raw = max_val };
                return .{ .raw = min_val };
            }

            // 使用 i64 进行除法： (a * scale) / b
            const a_scaled: AccumType = @as(AccumType, a.raw) << frac_bits;
            const result = @divTrunc(a_scaled, @as(AccumType, b.raw));

            // 截断到 i32 范围
            const clamped = std.math.clamp(result, min_val, max_val);
            return .{ .raw = @as(IntType, @intCast(clamped)) };
        }

        pub inline fn neg(a: Self) Self {
            return .{ .raw = -a.raw };
        }

        pub inline fn abs(a: Self) Self {
            return .{ .raw = if (a.raw < 0) -a.raw else a.raw };
        }

        // ===== 饱和算术 =====

        pub inline fn addSat(a: Self, b: Self) Self {
            const sum: AccumType = @as(AccumType, a.raw) + @as(AccumType, b.raw);
            const clamped = std.math.clamp(sum, min_val, max_val);
            return .{ .raw = @as(IntType, @intCast(clamped)) };
        }

        pub inline fn subSat(a: Self, b: Self) Self {
            const diff: AccumType = @as(AccumType, a.raw) - @as(AccumType, b.raw);
            const clamped = std.math.clamp(diff, min_val, max_val);
            return .{ .raw = @as(IntType, @intCast(clamped)) };
        }

        pub inline fn mulSat(a: Self, b: Self) Self {
            const prod: AccumType = @as(AccumType, a.raw) * @as(AccumType, b.raw);
            const shifted = prod >> frac_bits;
            const clamped = std.math.clamp(shifted, min_val, max_val);
            return .{ .raw = @as(IntType, @intCast(clamped)) };
        }

        // ===== 常量 =====

        pub inline fn zero() Self {
            return .{ .raw = 0 };
        }

        pub inline fn one() Self {
            return .{ .raw = scale };
        }

        pub inline fn maxValue() Self {
            return .{ .raw = max_val };
        }

        pub inline fn minValue() Self {
            return .{ .raw = min_val };
        }

        // ===== 比较 =====

        pub inline fn lessThan(a: Self, b: Self) bool {
            return a.raw < b.raw;
        }

        pub inline fn max(a: Self, b: Self) Self {
            return if (a.raw > b.raw) a else b;
        }

        pub inline fn min(a: Self, b: Self) Self {
            return if (a.raw < b.raw) a else b;
        }

        pub inline fn clamp(v: Self, lo: Self, hi: Self) Self {
            return v.max(lo).min(hi);
        }
    };
}
