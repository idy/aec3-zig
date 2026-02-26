const std = @import("std");
const ns_common = @import("ns_common.zig");

// LRT feature threshold from ns_common
const LRT_FEATURE_THR: f32 = 0.5;

/// Signal model features used by the NS speech-probability estimator (matches aec3-rs)
pub const SignalModel = struct {
    lrt: f32,
    spectral_diff: f32,
    spectral_flatness: f32,
    avg_log_lrt: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32,

    pub fn init() SignalModel {
        return .{
            .lrt = LRT_FEATURE_THR,
            .spectral_diff = 0.5,
            .spectral_flatness = 0.5,
            .avg_log_lrt = [_]f32{LRT_FEATURE_THR} ** ns_common.FFT_SIZE_BY_2_PLUS_1,
        };
    }
};
