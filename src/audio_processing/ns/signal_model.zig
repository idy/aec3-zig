const std = @import("std");
const ns_common = @import("ns_common.zig");

pub const SignalModel = struct {
    posterior_snr: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32,

    pub fn init() SignalModel {
        return .{ .posterior_snr = [_]f32{1.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1 };
    }

    pub fn update(self: *SignalModel, magnitude2: []const f32, noise: []const f32) void {
        std.debug.assert(magnitude2.len >= ns_common.FFT_SIZE_BY_2_PLUS_1);
        std.debug.assert(noise.len >= ns_common.FFT_SIZE_BY_2_PLUS_1);

        for (0..ns_common.FFT_SIZE_BY_2_PLUS_1) |i| {
            const n = @max(noise[i], ns_common.EPSILON);
            self.posterior_snr[i] = std.math.clamp(magnitude2[i] / n, 0.0, 1e3);
        }
    }
};
