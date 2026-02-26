const std = @import("std");
const ns_common = @import("ns_common.zig");

pub const PriorSignalModel = struct {
    prior_snr: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32,

    pub fn init() PriorSignalModel {
        return .{ .prior_snr = [_]f32{1.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1 };
    }

    pub fn update(
        self: *PriorSignalModel,
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
