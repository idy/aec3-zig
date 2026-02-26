const std = @import("std");
const ns_common = @import("ns_common.zig");

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
