const std = @import("std");
const ns_common = @import("ns_common.zig");
const FastMath = @import("fast_math.zig").FastMath;
const profileFor = @import("../../numeric_profile.zig").profileFor;
const NumericMode = @import("../../numeric_mode.zig").NumericMode;

/// 语音概率估计器 - 支持 float32 和 fixed_mcu_q15 两种模式
pub const SpeechProbabilityEstimator = struct {
    numeric_mode: NumericMode,

    pub fn init(mode: NumericMode) SpeechProbabilityEstimator {
        return .{ .numeric_mode = mode };
    }

    /// 估计语音概率
    /// 公式: p = 0.5 * (1 + tanh(0.5 * (prior_snr - 1)))
    pub fn estimate(self: *const SpeechProbabilityEstimator, prior_snr: []const f32, out_prob: *[ns_common.FFT_SIZE_BY_2_PLUS_1]f32) void {
        std.debug.assert(prior_snr.len >= ns_common.FFT_SIZE_BY_2_PLUS_1);

        if (self.numeric_mode == .float32) {
            // float32 路径: 直接使用标准 math 库
            const M = FastMath(f32);
            for (0..ns_common.FFT_SIZE_BY_2_PLUS_1) |i| {
                const x = 0.5 * (prior_snr[i] - 1.0);
                const tx = M.tanh(x);
                out_prob[i] = std.math.clamp(0.5 * (1.0 + tx), 0.0, 1.0);
            }
        } else {
            // fixed_mcu_q15 路径: 使用定点 LUT 近似
            const Q15 = profileFor(.fixed_mcu_q15).Sample;
            const M = FastMath(Q15);

            for (0..ns_common.FFT_SIZE_BY_2_PLUS_1) |i| {
                const x = 0.5 * (prior_snr[i] - 1.0);
                const tx = M.tanh(Q15.fromFloatRuntime(x)).toFloat();
                out_prob[i] = std.math.clamp(0.5 * (1.0 + tx), 0.0, 1.0);
            }
        }
    }
};
