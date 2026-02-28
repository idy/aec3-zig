const std = @import("std");
const ns_common = @import("ns_common.zig");
const QuantileNoiseEstimator = @import("quantile_noise_estimator.zig").QuantileNoiseEstimator;
const SuppressionParams = @import("suppression_params.zig").SuppressionParams;
const fast_math = @import("fast_math.zig");

/// Noise spectrum estimator (matches aec3-rs implementation)
pub const NoiseEstimator = struct {
    suppression_params: SuppressionParams,
    white_noise_level: f32,
    pink_noise_numerator: f32,
    pink_noise_exp: f32,
    prev_noise_spectrum: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32,
    conservative_noise_spectrum: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32,
    parametric_noise_spectrum: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32,
    noise_spectrum: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32,
    quantile_noise_estimator: QuantileNoiseEstimator,

    pub fn init(suppression_params: SuppressionParams) NoiseEstimator {
        return .{
            .suppression_params = suppression_params,
            .white_noise_level = 0.0,
            .pink_noise_numerator = 0.0,
            .pink_noise_exp = 0.0,
            .prev_noise_spectrum = [_]f32{0.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1,
            .conservative_noise_spectrum = [_]f32{0.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1,
            .parametric_noise_spectrum = [_]f32{0.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1,
            .noise_spectrum = [_]f32{0.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1,
            .quantile_noise_estimator = QuantileNoiseEstimator.init(),
        };
    }

    pub fn prepareAnalysis(self: *NoiseEstimator) void {
        @memcpy(&self.prev_noise_spectrum, &self.noise_spectrum);
    }

    pub fn preUpdate(
        self: *NoiseEstimator,
        num_analyzed_frames: i32,
        signal_spectrum: []const f32,
        signal_spectral_sum: f32,
    ) void {
        self.quantile_noise_estimator.estimate(
            signal_spectrum[0..ns_common.FFT_SIZE_BY_2_PLUS_1],
            &self.noise_spectrum,
        );

        if (num_analyzed_frames < ns_common.SHORT_STARTUP_PHASE_BLOCKS) {
            const START_BAND: usize = 5;
            var sum_log_i_log_magn: f32 = 0.0;
            var sum_log_i: f32 = 0.0;
            var sum_log_i_square: f32 = 0.0;
            var sum_log_magn: f32 = 0.0;

            for (START_BAND..ns_common.FFT_SIZE_BY_2_PLUS_1) |i| {
                const log_i = @log(@as(f32, @floatFromInt(i)));
                sum_log_i += log_i;
                sum_log_i_square += log_i * log_i;
                const log_signal = fast_math.logApproximation(signal_spectrum[i]);
                sum_log_magn += log_signal;
                sum_log_i_log_magn += log_i * log_signal;
            }

            const ONE_BY_FFT: f32 = 1.0 / @as(f32, ns_common.FFT_SIZE_BY_2_PLUS_1);
            self.white_noise_level += signal_spectral_sum * ONE_BY_FFT * self.suppression_params.over_subtraction_factor;

            const bins: f32 = @as(f32, @floatFromInt(ns_common.FFT_SIZE_BY_2_PLUS_1 - START_BAND));
            const denom = sum_log_i_square * bins - sum_log_i * sum_log_i;
            var pink_adj = (sum_log_i_square * sum_log_magn - sum_log_i * sum_log_i_log_magn) / denom;
            pink_adj = @max(0.0, pink_adj);
            self.pink_noise_numerator += pink_adj;

            pink_adj = (sum_log_i * sum_log_magn - bins * sum_log_i_log_magn) / denom;
            pink_adj = std.math.clamp(pink_adj, 0.0, 1.0);
            self.pink_noise_exp += pink_adj;

            const one_by_num_analyzed_frames_plus_1: f32 = 1.0 / (@as(f32, @floatFromInt(num_analyzed_frames)) + 1.0);
            var parametric_exp: f32 = 0.0;
            var parametric_num: f32 = 0.0;
            if (self.pink_noise_exp > 0.0) {
                parametric_num = fast_math.expApproximation(self.pink_noise_numerator * one_by_num_analyzed_frames_plus_1);
                parametric_num *= @as(f32, @floatFromInt(num_analyzed_frames)) + 1.0;
                parametric_exp = self.pink_noise_exp * one_by_num_analyzed_frames_plus_1;
            }

            for (0..ns_common.FFT_SIZE_BY_2_PLUS_1) |i| {
                self.parametric_noise_spectrum[i] = if (self.pink_noise_exp == 0.0)
                    self.white_noise_level
                else blk: {
                    const use_band: f32 = @as(f32, @floatFromInt(@max(START_BAND, i)));
                    const parametric_denom = fast_math.powApproximation(use_band, parametric_exp);
                    break :blk parametric_num / parametric_denom;
                };
            }

            const ONE_BY_SHORT_STARTUP: f32 = 1.0 / @as(f32, ns_common.SHORT_STARTUP_PHASE_BLOCKS);
            for (0..ns_common.FFT_SIZE_BY_2_PLUS_1) |i| {
                var tmp = self.noise_spectrum[i] * @as(f32, @floatFromInt(num_analyzed_frames));
                const tmp2 = self.parametric_noise_spectrum[i] * @as(f32, @floatFromInt(ns_common.SHORT_STARTUP_PHASE_BLOCKS - num_analyzed_frames));
                tmp += tmp2 * one_by_num_analyzed_frames_plus_1;
                tmp *= ONE_BY_SHORT_STARTUP;
                self.noise_spectrum[i] = tmp;
            }
        }
    }

    pub fn postUpdate(
        self: *NoiseEstimator,
        speech_probability: []const f32,
        signal_spectrum: []const f32,
    ) void {
        const NOISE_UPDATE: f32 = 0.9;
        var gamma: f32 = NOISE_UPDATE;

        for (0..ns_common.FFT_SIZE_BY_2_PLUS_1) |i| {
            const prob_speech = speech_probability[i];
            const prob_non_speech = 1.0 - prob_speech;

            const noise_update_tmp = gamma * self.prev_noise_spectrum[i] + (1.0 - gamma) *
                (prob_non_speech * signal_spectrum[i] + prob_speech * self.prev_noise_spectrum[i]);

            const gamma_old = gamma;
            const PROB_RANGE: f32 = 0.2;
            gamma = if (prob_speech > PROB_RANGE) 0.99 else NOISE_UPDATE;

            if (prob_speech < PROB_RANGE) {
                self.conservative_noise_spectrum[i] += 0.05 * (signal_spectrum[i] - self.conservative_noise_spectrum[i]);
            }

            if (gamma == gamma_old) {
                self.noise_spectrum[i] = noise_update_tmp;
            } else {
                var new_noise = gamma * self.prev_noise_spectrum[i] + (1.0 - gamma) *
                    (prob_non_speech * signal_spectrum[i] + prob_speech * self.prev_noise_spectrum[i]);
                new_noise = @min(new_noise, noise_update_tmp);
                self.noise_spectrum[i] = new_noise;
            }
        }
    }

    pub fn noiseSpectrum(self: *const NoiseEstimator) []const f32 {
        return &self.noise_spectrum;
    }

    pub fn prevNoiseSpectrum(self: *const NoiseEstimator) []const f32 {
        return &self.prev_noise_spectrum;
    }

    pub fn parametricNoiseSpectrum(self: *const NoiseEstimator) []const f32 {
        return &self.parametric_noise_spectrum;
    }

    pub fn conservativeNoiseSpectrum(self: *const NoiseEstimator) []const f32 {
        return &self.conservative_noise_spectrum;
    }
};
