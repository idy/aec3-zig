const std = @import("std");
const ns_common = @import("ns_common.zig");
const QuantileNoiseEstimator = @import("quantile_noise_estimator.zig").QuantileNoiseEstimator;
const SuppressionParams = @import("suppression_params.zig").SuppressionParams;

pub const NoiseEstimator = struct {
    quantile: QuantileNoiseEstimator,
    params: SuppressionParams,
    min_noise_floor: f32,
    noise_psd: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32,

    pub fn init(params: SuppressionParams, min_noise_floor: f32) NoiseEstimator {
        return .{
            .quantile = QuantileNoiseEstimator.init(),
            .params = params,
            .min_noise_floor = min_noise_floor,
            .noise_psd = [_]f32{min_noise_floor} ** ns_common.FFT_SIZE_BY_2_PLUS_1,
        };
    }

    pub fn update(self: *NoiseEstimator, magnitude2: []const f32) void {
        self.quantile.update(magnitude2);
        const qn = self.quantile.noise();
        for (0..ns_common.FFT_SIZE_BY_2_PLUS_1) |i| {
            const next = self.params.noise_update_rate * self.noise_psd[i] + (1.0 - self.params.noise_update_rate) * qn[i];
            self.noise_psd[i] = @max(next, self.min_noise_floor);
        }
    }

    pub fn noise(self: *const NoiseEstimator) []const f32 {
        return &self.noise_psd;
    }
};

test "noise estimator keeps floor" {
    var ne = NoiseEstimator.init(.{ .floor_gain = 0.1, .max_gain = 1.0, .prior_snr_smoothing = 0.9, .noise_update_rate = 0.98 }, 1e-3);
    const zeros = [_]f32{0.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1;
    ne.update(&zeros);
    for (ne.noise()) |n| {
        try std.testing.expect(n >= 1e-3);
    }
}
