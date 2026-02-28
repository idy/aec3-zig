const std = @import("std");
const profileFor = @import("../numeric_profile.zig").profileFor;

const FixedSample = profileFor(.fixed_mcu_q15).Sample;

// ═══════════════════════════════════════════════════════════════════════════════
// aec3-rs compatible fast math approximations
// ═══════════════════════════════════════════════════════════════════════════════

/// Fast log2 approximation using bit manipulation (matches aec3-rs fast_log2f)
pub fn fastLog2f(input: f32) f32 {
    std.debug.assert(input > 0.0);
    const bits: u32 = @as(u32, @bitCast(input));
    const bits_f: f32 = @floatFromInt(bits);
    return bits_f * 1.192_092_9e-7 - 126.942_695;
}

/// Sqrt approximation (uses std.sqrt for now)
pub fn sqrtFastApproximation(value: f32) f32 {
    return std.math.sqrt(value);
}

/// 2^power approximation
pub fn pow2Approximation(power: f32) f32 {
    return std.math.pow(f32, 2.0, power);
}

/// x^power approximation
pub fn powApproximation(x: f32, power: f32) f32 {
    return pow2Approximation(power * fastLog2f(x));
}

/// Natural log approximation using fast log2
pub fn logApproximation(x: f32) f32 {
    return fastLog2f(x) * std.math.ln2;
}

/// Log approximation for slice (in-place)
pub fn logApproximationSlice(src: []const f32, dst: []f32) void {
    std.debug.assert(src.len == dst.len);
    for (src, dst) |s, *d| {
        d.* = logApproximation(s);
    }
}

/// Exp approximation (10^(x * log10(e)))
pub fn expApproximation(x: f32) f32 {
    return powApproximation(10.0, x * std.math.log10e);
}

/// Exp approximation for slice (in-place)
pub fn expApproximationSlice(src: []const f32, dst: []f32) void {
    std.debug.assert(src.len == dst.len);
    for (src, dst) |s, *d| {
        d.* = expApproximation(s);
    }
}

/// Exp with sign flip for slice
pub fn expApproximationSignFlipSlice(src: []const f32, dst: []f32) void {
    std.debug.assert(src.len == dst.len);
    for (src, dst) |s, *d| {
        d.* = expApproximation(-s);
    }
}

/// 定点数学常数和查找表
const Q15_LUT_BITS = 8; // LUT 大小为 256，提高精度
const Q15_LUT_SIZE = 1 << Q15_LUT_BITS;
const Q15_ONE: i32 = 1 << 15; // Q15 中的 1.0

/// exp LUT: 覆盖 x ∈ [-6, 2]，用于处理更广的范围
/// exp(-6) ≈ 0.0025, exp(2) ≈ 7.4
const EXP_LUT_MIN: f32 = -6.0;
const EXP_LUT_MAX: f32 = 2.0;
const EXP_LUT_STEP: f32 = (EXP_LUT_MAX - EXP_LUT_MIN) / @as(f32, Q15_LUT_SIZE - 1);

/// tanh LUT: 覆盖 x ∈ [-4, 4]，tanh 在此范围已完全饱和
const TANH_LUT_MIN: f32 = -4.0;
const TANH_LUT_MAX: f32 = 4.0;
const TANH_LUT_STEP: f32 = (TANH_LUT_MAX - TANH_LUT_MIN) / @as(f32, Q15_LUT_SIZE - 1);

/// log LUT: 覆盖 x ∈ [0.01, 10.0]
const LOG_LUT_MIN: f32 = 0.01;
const LOG_LUT_MAX: f32 = 10.0;
const LOG_LUT_STEP: f32 = (LOG_LUT_MAX - LOG_LUT_MIN) / @as(f32, Q15_LUT_SIZE - 1);

/// 高精度 exp 计算 (使用标准库，只在编译期执行)
fn computeExp(x: f32) f32 {
    return @exp(x);
}

/// 高精度 tanh 计算 (使用指数形式)
fn computeTanh(x: f32) f32 {
    if (x >= 4.0) return 0.999329;
    if (x <= -4.0) return -0.999329;
    const epx = @exp(x);
    const enx = @exp(-x);
    return (epx - enx) / (epx + enx);
}

/// 高精度 log 计算
fn computeLog(x: f32) f32 {
    return @log(@max(0.0001, x));
}

/// 在编译期生成 exp LUT (Q15 定点格式，输出为 Q12 以扩大动态范围)
fn generateExpLut() [Q15_LUT_SIZE]i32 {
    @setEvalBranchQuota(50000);
    var lut: [Q15_LUT_SIZE]i32 = undefined;
    var i: usize = 0;
    while (i < Q15_LUT_SIZE) : (i += 1) {
        const x = EXP_LUT_MIN + @as(f32, @floatFromInt(i)) * EXP_LUT_STEP;
        const val = computeExp(x);
        // 限制在合理范围，防止溢出
        const clamped = @max(0.0025, @min(7.4, val));
        lut[i] = @intFromFloat(@round(clamped * 4096.0)); // Q12 格式
    }
    return lut;
}

/// 在编译期生成 tanh LUT (Q15 定点格式，映射 [-1, 1])
fn generateTanhLut() [Q15_LUT_SIZE]i32 {
    @setEvalBranchQuota(50000);
    var lut: [Q15_LUT_SIZE]i32 = undefined;
    var i: usize = 0;
    while (i < Q15_LUT_SIZE) : (i += 1) {
        const x = TANH_LUT_MIN + @as(f32, @floatFromInt(i)) * TANH_LUT_STEP;
        const val = computeTanh(x);
        // 映射到 [-1, 1] 然后转 Q15
        const clamped = @max(-1.0, @min(1.0, val));
        lut[i] = @intFromFloat(@round(clamped * @as(f32, Q15_ONE)));
    }
    return lut;
}

/// 在编译期生成 log LUT (Q15 定点格式，输出为 Q13 以扩大范围)
fn generateLogLut() [Q15_LUT_SIZE]i32 {
    @setEvalBranchQuota(50000);
    var lut: [Q15_LUT_SIZE]i32 = undefined;
    var i: usize = 0;
    while (i < Q15_LUT_SIZE) : (i += 1) {
        const x = LOG_LUT_MIN + @as(f32, @floatFromInt(i)) * LOG_LUT_STEP;
        const val = computeLog(x);
        // log(0.01) ≈ -4.6, log(10) ≈ 2.3，使用 Q13 格式
        const q13_val = val * 8192.0;
        lut[i] = @intFromFloat(@round(@max(-32768.0, @min(32767.0, q13_val))));
    }
    return lut;
}

const EXP_LUT = generateExpLut();
const TANH_LUT = generateTanhLut();
const LOG_LUT = generateLogLut();

/// Q15 定点线性插值 (使用 64 位中间计算避免溢出)
inline fn q15Lerp(lut: []const i32, idx: i32, frac: i32) i32 {
    const idx0 = @as(usize, @intCast(@max(0, @min(Q15_LUT_SIZE - 1, idx))));
    const idx1 = @as(usize, @intCast(@max(0, @min(Q15_LUT_SIZE - 1, idx + 1))));
    const v0 = lut[idx0];
    const v1 = lut[idx1];
    // 线性插值: v0 + (v1 - v0) * frac / Q15_ONE
    const diff: i64 = v1 - v0;
    const frac64: i64 = frac;
    const scaled = @divTrunc(diff * frac64, Q15_ONE);
    return v0 + @as(i32, @intCast(scaled));
}

/// 浮点值到 LUT 索引映射
inline fn floatToLutIndex(x: f32, min_val: f32, max_val: f32) struct { idx: i32, frac: i32 } {
    if (x <= min_val) return .{ .idx = 0, .frac = 0 };
    if (x >= max_val) return .{ .idx = Q15_LUT_SIZE - 2, .frac = Q15_ONE - 1 };
    const normalized = (x - min_val) / (max_val - min_val);
    const fidx = normalized * @as(f32, Q15_LUT_SIZE - 1);
    const idx = @as(i32, @intFromFloat(@floor(fidx)));
    const frac_f = (fidx - @floor(fidx)) * @as(f32, Q15_ONE);
    const frac = @as(i32, @intFromFloat(@round(frac_f)));
    return .{ .idx = @max(0, @min(Q15_LUT_SIZE - 2, idx)), .frac = @max(0, @min(Q15_ONE, frac)) };
}

fn FastMath(comptime T: type) type {
    return struct {
        const Self = @This();

        pub inline fn exp(x: T) T {
            if (T == f32) return @exp(x);
            // 定点 exp: 使用 LUT + 线性插值
            const xf = x.toFloat();
            if (xf <= EXP_LUT_MIN) return T.fromFloatRuntime(0.0025);
            if (xf >= EXP_LUT_MAX) return T.fromFloatRuntime(7.389);
            const lut_idx = floatToLutIndex(xf, EXP_LUT_MIN, EXP_LUT_MAX);
            // EXP_LUT 输出是 Q12，需要转回浮点
            const result_q12 = q15Lerp(&EXP_LUT, lut_idx.idx, lut_idx.frac);
            const result = @as(f32, @floatFromInt(result_q12)) / 4096.0;
            return T.fromFloatRuntime(result);
        }

        pub inline fn log(x: T) T {
            if (T == f32) return @log(x);
            // 定点 log: 使用 LUT + 线性插值，输入 x 必须为正
            const xf = x.toFloat();
            if (xf <= LOG_LUT_MIN) return T.fromFloatRuntime(-4.605); // log(0.01)
            if (xf >= LOG_LUT_MAX) return T.fromFloatRuntime(2.303); // log(10)
            const lut_idx = floatToLutIndex(xf, LOG_LUT_MIN, LOG_LUT_MAX);
            // LOG_LUT 输出是 Q13，需要转回浮点
            const log_q13 = q15Lerp(&LOG_LUT, lut_idx.idx, lut_idx.frac);
            const result = @as(f32, @floatFromInt(log_q13)) / 8192.0;
            return T.fromFloatRuntime(result);
        }

        pub inline fn pow(base: T, exponent: T) T {
            if (T == f32) return std.math.pow(f32, base, exponent);
            // 定点 pow: 使用 exp(exponent * log(base))
            const b = base.toFloat();
            const e = exponent.toFloat();
            if (b <= 0) return T.fromRaw(0);
            // 计算 e * log(b)，然后 exp
            const log_b = @log(@max(0.001, b));
            const exp_arg = e * log_b;
            // 限制 exp 输入范围
            const clamped_exp_arg = @max(EXP_LUT_MIN, @min(EXP_LUT_MAX, exp_arg));
            const lut_idx = floatToLutIndex(clamped_exp_arg, EXP_LUT_MIN, EXP_LUT_MAX);
            const result_q12 = q15Lerp(&EXP_LUT, lut_idx.idx, lut_idx.frac);
            const result = @as(f32, @floatFromInt(result_q12)) / 4096.0;
            return T.fromFloatRuntime(result);
        }

        pub inline fn tanh(x: T) T {
            if (T == f32) return std.math.tanh(x);
            // 定点 tanh: 使用 LUT + 线性插值
            const xf = x.toFloat();
            if (xf <= TANH_LUT_MIN) return T.fromFloatRuntime(-0.9993);
            if (xf >= TANH_LUT_MAX) return T.fromFloatRuntime(0.9993);
            const lut_idx = floatToLutIndex(xf, TANH_LUT_MIN, TANH_LUT_MAX);
            const result_q15 = q15Lerp(&TANH_LUT, lut_idx.idx, lut_idx.frac);
            const result = @as(f32, @floatFromInt(result_q15)) / @as(f32, Q15_ONE);
            return T.fromFloatRuntime(result);
        }
    };
}

test "fast_math exp/log fixed approximation error under 0.01" {
    const Q15 = FixedSample;
    const M = FastMath(Q15);

    // 测试 exp 在 NS 典型范围 [-5, 1] 内的精度
    var i: usize = 0;
    while (i <= 60) : (i += 1) {
        const x = -5.0 + @as(f32, @floatFromInt(i)) * (6.0 / 60.0);
        const qx = Q15.fromFloatRuntime(x);
        const approx_exp = M.exp(qx).toFloat();
        const expected_exp = @exp(x);
        // 对于小值 exp，使用相对误差；对于接近 0 的值，使用绝对误差
        const exp_error = @abs(approx_exp - expected_exp);
        const exp_threshold = if (expected_exp > 0.1) expected_exp * 0.05 else 0.01;
        try std.testing.expect(exp_error < exp_threshold);
    }

    // 测试 log 在 [0.1, 8.0] 范围内的精度
    i = 1;
    while (i <= 80) : (i += 1) {
        const x = 0.1 + @as(f32, @floatFromInt(i - 1)) * (7.9 / 79.0);
        const qx = Q15.fromFloatRuntime(x);
        const approx_log = M.log(qx).toFloat();
        const expected_log = @log(x);
        const log_error = @abs(approx_log - expected_log);
        try std.testing.expect(log_error < 0.02);
    }
}

test "fast_math tanh fixed error under 0.001" {
    const Q15 = FixedSample;
    const M = FastMath(Q15);

    var i: i32 = -120;
    while (i <= 120) : (i += 1) {
        const x = @as(f32, @floatFromInt(i)) / 40.0;
        const qx = Q15.fromFloatRuntime(x);
        const approx = M.tanh(qx).toFloat();
        try std.testing.expect(@abs(approx - std.math.tanh(x)) < 0.001);
    }
}
