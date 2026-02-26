const std = @import("std");
const ns_common = @import("ns_common.zig");

// LRT feature threshold from ns_common
const LRT_FEATURE_THR: f32 = 0.5;

/// Original SignalModel (kept for compatibility)
pub const PosteriorSignalModel = struct {
    posterior_snr: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32,

    pub fn init() PosteriorSignalModel {
        return .{ .posterior_snr = [_]f32{1.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1 };
    }

    pub fn update(self: *PosteriorSignalModel, magnitude2: []const f32, noise: []const f32) void {
        std.debug.assert(magnitude2.len >= ns_common.FFT_SIZE_BY_2_PLUS_1);
        std.debug.assert(noise.len >= ns_common.FFT_SIZE_BY_2_PLUS_1);

        for (0..ns_common.FFT_SIZE_BY_2_PLUS_1) |i| {
            const n = @max(noise[i], ns_common.EPSILON);
            self.posterior_snr[i] = std.math.clamp(magnitude2[i] / n, 0.0, 1e3);
        }
    }
};

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
