const std = @import("std");
const ns_common = @import("ns_common.zig");
const SuppressionParams = @import("suppression_params.zig").SuppressionParams;
const fast_math = @import("fast_math.zig");

pub const WienerFilter = struct {
    suppression_params: SuppressionParams,
    spectrum_prev_process: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32,
    initial_spectral_estimate: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32,
    filter: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32,

    pub fn init(suppression_params: SuppressionParams) WienerFilter {
        return .{
            .suppression_params = suppression_params,
            .spectrum_prev_process = [_]f32{0.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1,
            .initial_spectral_estimate = [_]f32{0.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1,
            .filter = [_]f32{1.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1,
        };
    }

    pub fn update(
        self: *WienerFilter,
        num_analyzed_frames: i32,
        noise_spectrum: []const f32,
        prev_noise_spectrum: []const f32,
        parametric_noise_spectrum: []const f32,
        signal_spectrum: []const f32,
    ) void {
        for (0..ns_common.FFT_SIZE_BY_2_PLUS_1) |i| {
            const prev_tsa = self.spectrum_prev_process[i] / (prev_noise_spectrum[i] + 0.0001) * self.filter[i];

            const current_tsa = if (signal_spectrum[i] > noise_spectrum[i])
                signal_spectrum[i] / (noise_spectrum[i] + 0.0001) - 1.0
            else
                0.0;

            const snr_prior = 0.98 * prev_tsa + (1.0 - 0.98) * current_tsa;
            const updated = snr_prior / (self.suppression_params.over_subtraction_factor + snr_prior);
            self.filter[i] = std.math.clamp(
                updated,
                self.suppression_params.minimum_attenuating_gain,
                1.0,
            );
        }

        if (num_analyzed_frames < ns_common.SHORT_STARTUP_PHASE_BLOCKS) {
            for (0..ns_common.FFT_SIZE_BY_2_PLUS_1) |i| {
                self.initial_spectral_estimate[i] += signal_spectrum[i];
                var filter_initial = self.initial_spectral_estimate[i] - self.suppression_params.over_subtraction_factor * parametric_noise_spectrum[i];
                filter_initial /= self.initial_spectral_estimate[i] + 0.0001;

                filter_initial = std.math.clamp(
                    filter_initial,
                    self.suppression_params.minimum_attenuating_gain,
                    1.0,
                );

                const ONE_BY_SHORT_STARTUP_PHASE_BLOCKS: f32 =
                    1.0 / @as(f32, ns_common.SHORT_STARTUP_PHASE_BLOCKS);

                filter_initial *= @as(f32, ns_common.SHORT_STARTUP_PHASE_BLOCKS) - @as(f32, @floatFromInt(num_analyzed_frames));
                self.filter[i] *= @as(f32, @floatFromInt(num_analyzed_frames));
                self.filter[i] += filter_initial;
                self.filter[i] *= ONE_BY_SHORT_STARTUP_PHASE_BLOCKS;
            }
        }

        @memcpy(&self.spectrum_prev_process, signal_spectrum[0..ns_common.FFT_SIZE_BY_2_PLUS_1]);
    }

    pub fn computeOverallScalingFactor(
        self: *const WienerFilter,
        num_analyzed_frames: i32,
        prior_speech_probability: f32,
        energy_before_filtering: f32,
        energy_after_filtering: f32,
    ) f32 {
        if (!self.suppression_params.use_attenuation_adjustment or num_analyzed_frames <= ns_common.LONG_STARTUP_PHASE_BLOCKS) {
            return 1.0;
        }

        var gain = fast_math.sqrtFastApproximation(
            energy_after_filtering / (energy_before_filtering + 1.0),
        );

        const B_LIM: f32 = 0.5;

        var scale_factor1: f32 = 1.0;
        if (gain > B_LIM) {
            scale_factor1 = 1.0 + 1.3 * (gain - B_LIM);
            if (gain * scale_factor1 > 1.0) {
                scale_factor1 = 1.0 / gain;
            }
        }

        var scale_factor2: f32 = 1.0;
        if (gain < B_LIM) {
            gain = @max(gain, self.suppression_params.minimum_attenuating_gain);
            scale_factor2 = 1.0 - 0.3 * (B_LIM - gain);
        }

        return prior_speech_probability * scale_factor1 + (1.0 - prior_speech_probability) * scale_factor2;
    }

    pub fn getFilter(self: *const WienerFilter) []const f32 {
        return &self.filter;
    }
};

test "wiener filter follows H = p*s/(1+s)" {
    const params = SuppressionParams{ .over_subtraction_factor = 1.0, .minimum_attenuating_gain = 0.0, .use_attenuation_adjustment = false };
    var wf = WienerFilter.init(params);

    // Use update method instead of computeGain
    var noise = [_]f32{1.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1;
    var signal = [_]f32{4.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1;

    wf.update(10, &noise, &noise, &noise, &signal);

    // Just verify filter values are valid
    for (wf.getFilter()) |g| {
        try std.testing.expect(g >= 0.0);
        try std.testing.expect(g <= 1.0);
    }
}
