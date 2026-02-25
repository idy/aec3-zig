//! Smoke 测试 - 3-tap FIR 滤波器
//! 对比 fixed_mcu_q15 与 float32 输出，误差 < 2 LSB

const std = @import("std");
const SampleOps = @import("../sample_ops.zig").SampleOps;
const FixedPoint = @import("../fixed_point.zig").FixedPoint;

/// 3-tap FIR 滤波器实现（泛型）
fn FirFilter3(comptime T: type) type {
    return struct {
        const Self = @This();
        const ops = SampleOps(T);

        coeffs: [3]T,
        state: [2]T, // 延迟线（z^-1, z^-2）

        pub fn init(c0: f32, c1: f32, c2: f32) Self {
            return .{
                .coeffs = .{
                    ops.fromFloat(c0),
                    ops.fromFloat(c1),
                    ops.fromFloat(c2),
                },
                .state = .{ ops.zero(), ops.zero() },
            };
        }

        pub fn process(self: *Self, input: T) T {
            // y[n] = c0*x[n] + c1*x[n-1] + c2*x[n-2]
            const x_n = input;
            const x_n1 = self.state[0];
            const x_n2 = self.state[1];

            const term0 = ops.mul(self.coeffs[0], x_n);
            const term1 = ops.mul(self.coeffs[1], x_n1);
            const term2 = ops.mul(self.coeffs[2], x_n2);

            const sum1 = ops.add(term0, term1);
            const output = ops.add(sum1, term2);

            // 更新延迟线
            self.state[1] = x_n1;
            self.state[0] = x_n;

            return output;
        }
    };
}

/// 运行 FIR 并收集输出
fn runFir(comptime T: type, input: []const f32, output: []T, c0: f32, c1: f32, c2: f32) void {
    const ops = SampleOps(T);
    var fir = FirFilter3(T).init(c0, c1, c2);

    for (input, 0..) |x, i| {
        output[i] = fir.process(ops.fromFloat(x));
    }
}

test "3-tap FIR smoke test - fixed vs float" {
    // 测试参数
    const sample_rate: f32 = 16000.0;
    const freq: f32 = 1000.0; // 1kHz 正弦波
    const num_samples = 64;

    // 生成输入：1kHz 正弦波 @ 16kHz
    var input: [num_samples]f32 = undefined;
    for (0..num_samples) |i| {
        const t = @as(f32, @floatFromInt(i)) / sample_rate;
        input[i] = @sin(2.0 * std.math.pi * freq * t);
    }

    // 滤波器系数：简单的低通（移动平均）
    const c0: f32 = 0.25;
    const c1: f32 = 0.5;
    const c2: f32 = 0.25;

    // float32 输出（oracle）
    var output_f32: [num_samples]f32 = undefined;
    runFir(f32, &input, &output_f32, c0, c1, c2);

    // fixed_mcu_q15 输出
    const Q15 = FixedPoint(15);
    var output_q15: [num_samples]Q15 = undefined;
    runFir(Q15, &input, &output_q15, c0, c1, c2);

    // 对比输出，计算误差
    const scale: f32 = 32768.0; // Q15 scale factor
    const lsb = 1.0 / scale; // 1 LSB in float
    const max_allowed_error = 2.0 * lsb; // < 2 LSB

    var max_error: f32 = 0.0;
    var err_count: usize = 0;

    for (output_f32, output_q15, 0..) |expected, actual_fp, i| {
        const actual = actual_fp.toFloat();
        const err = @abs(actual - expected);

        if (err > max_error) {
            max_error = err;
        }

        if (err > max_allowed_error) {
            err_count += 1;
            if (err_count <= 3) { // 只打印前3个错误
                std.debug.print(
                    "Sample {}: expected={d:.6}, actual={d:.6}, error={d:.6} LSBs\n",
                    .{ i, expected, actual, err / lsb },
                );
            }
        }
    }

    std.debug.print("\nFIR Smoke Test Results:\n", .{});
    std.debug.print("  Max error: {d:.4} LSBs (limit: 2 LSBs)\n", .{max_error / lsb});
    std.debug.print("  Error count: {}/{} samples\n", .{ err_count, num_samples });

    // 验证所有样本误差 < 2 LSB
    try std.testing.expectEqual(@as(usize, 0), err_count);
    try std.testing.expect(max_error < max_allowed_error);
}
