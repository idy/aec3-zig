const std = @import("std");
const ns_common = @import("ns_common.zig");
const SuppressionParams = @import("suppression_params.zig").SuppressionParams;

pub const WienerFilter = struct {
    params: SuppressionParams,

    pub fn init(params: SuppressionParams) WienerFilter {
        return .{ .params = params };
    }

    pub fn computeGain(self: *const WienerFilter, prior_snr: []const f32, speech_prob: []const f32, out_gain: *[ns_common.FFT_SIZE_BY_2_PLUS_1]f32) void {
        std.debug.assert(prior_snr.len >= ns_common.FFT_SIZE_BY_2_PLUS_1);
        std.debug.assert(speech_prob.len >= ns_common.FFT_SIZE_BY_2_PLUS_1);
        for (0..ns_common.FFT_SIZE_BY_2_PLUS_1) |i| {
            const s = @max(prior_snr[i], 0.0);
            const p = std.math.clamp(speech_prob[i], 0.0, 1.0);
            const h = p * s / (1.0 + s);
            out_gain[i] = std.math.clamp(h, self.params.floor_gain, self.params.max_gain);
        }
    }
};

test "wiener filter follows H = p*s/(1+s)" {
    const params = SuppressionParams{ .floor_gain = 0.0, .max_gain = 1.0, .prior_snr_smoothing = 0.9, .noise_update_rate = 0.98 };
    var wf = WienerFilter.init(params);
    var prior = [_]f32{0.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1;
    var prob = [_]f32{0.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1;
    var gain = [_]f32{0.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1;

    prior[1] = 3.0;
    prob[1] = 0.7;
    wf.computeGain(&prior, &prob, &gain);

    const expected = 0.7 * 3.0 / 4.0;
    try std.testing.expect(@abs(gain[1] - expected) < 1e-6);
}
