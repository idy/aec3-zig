const std = @import("std");
const ns_common = @import("ns_common.zig");

/// Original PriorSignalModel (kept for compatibility)
pub const DecisionDirectedPriorModel = struct {
    prior_snr: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32,

    pub fn init() DecisionDirectedPriorModel {
        return .{ .prior_snr = [_]f32{1.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1 };
    }

    pub fn update(
        self: *DecisionDirectedPriorModel,
        posterior_snr: []const f32,
        prev_gain: []const f32,
        smoothing: f32,
    ) void {
        std.debug.assert(posterior_snr.len >= ns_common.FFT_SIZE_BY_2_PLUS_1);
        std.debug.assert(prev_gain.len >= ns_common.FFT_SIZE_BY_2_PLUS_1);

        for (0..ns_common.FFT_SIZE_BY_2_PLUS_1) |i| {
            const decision_directed = prev_gain[i] * prev_gain[i] * posterior_snr[i];
            const candidate = smoothing * self.prior_snr[i] + (1.0 - smoothing) * decision_directed;
            self.prior_snr[i] = std.math.clamp(candidate, 0.0, 1e3);
        }
    }
};

/// Prior signal model used by speech probability estimation (matches aec3-rs)
pub const PriorSignalModel = struct {
    lrt: f32,
    flatness_threshold: f32,
    template_diff_threshold: f32,
    lrt_weighting: f32,
    flatness_weighting: f32,
    difference_weighting: f32,

    pub fn init(lrt_initial_value: f32) PriorSignalModel {
        return .{
            .lrt = lrt_initial_value,
            .flatness_threshold = 0.5,
            .template_diff_threshold = 0.5,
            .lrt_weighting = 1.0,
            .flatness_weighting = 0.0,
            .difference_weighting = 0.0,
        };
    }
};
