const std = @import("std");
const ns_common = @import("ns_common.zig");
const Histogram = @import("histograms.zig").Histogram;

pub const QuantileNoiseEstimator = struct {
    hist: [ns_common.FFT_SIZE_BY_2_PLUS_1]Histogram,
    noise_quantile: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32,
    quantile: f32,

    pub fn init() QuantileNoiseEstimator {
        var hist: [ns_common.FFT_SIZE_BY_2_PLUS_1]Histogram = undefined;
        for (0..ns_common.FFT_SIZE_BY_2_PLUS_1) |i| {
            hist[i] = Histogram.init(0.0, 100.0);
        }
        return .{
            .hist = hist,
            .noise_quantile = [_]f32{1e-3} ** ns_common.FFT_SIZE_BY_2_PLUS_1,
            .quantile = 0.2,
        };
    }

    pub fn update(self: *QuantileNoiseEstimator, magnitude2: []const f32) void {
        std.debug.assert(magnitude2.len >= ns_common.FFT_SIZE_BY_2_PLUS_1);
        for (0..ns_common.FFT_SIZE_BY_2_PLUS_1) |i| {
            self.hist[i].observe(magnitude2[i]);
            self.noise_quantile[i] = @max(self.hist[i].quantile(self.quantile), ns_common.EPSILON);
        }
    }

    pub fn noise(self: *const QuantileNoiseEstimator) []const f32 {
        return &self.noise_quantile;
    }
};
