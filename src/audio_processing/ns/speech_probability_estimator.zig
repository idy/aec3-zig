const std = @import("std");
const ns_common = @import("ns_common.zig");
const SignalModelEstimator = @import("signal_model_estimator.zig").SignalModelEstimator;
const fast_math = @import("fast_math.zig");
const NumericMode = @import("../../numeric_mode.zig").NumericMode;

/// Feature update window size (from aec3-rs ns_common)
const FEATURE_UPDATE_WINDOW_SIZE: i32 = 500;

/// Long startup phase blocks (from aec3-rs ns_common)
const LONG_STARTUP_PHASE_BLOCKS: i32 = 200;

/// LRT feature threshold
const LRT_FEATURE_THR: f32 = 0.5;

/// Speech probability estimation for NS (matches aec3-rs implementation)
pub const SpeechProbabilityEstimator = struct {
    signal_model_estimator: SignalModelEstimator,
    prior_speech_prob: f32,
    speech_probability: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32,
    _numeric_mode: NumericMode,

    pub fn init(numeric_mode: NumericMode) SpeechProbabilityEstimator {
        return .{
            .signal_model_estimator = SignalModelEstimator.init(),
            .prior_speech_prob = 0.5,
            .speech_probability = [_]f32{0.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1,
            ._numeric_mode = numeric_mode,
        };
    }

    pub fn update(
        self: *SpeechProbabilityEstimator,
        num_analyzed_frames: i32,
        prior_snr: []const f32,
        post_snr: []const f32,
        conservative_noise_spectrum: []const f32,
        signal_spectrum: []const f32,
        signal_spectral_sum: f32,
        signal_energy: f32,
    ) void {
        if (num_analyzed_frames < LONG_STARTUP_PHASE_BLOCKS) {
            self.signal_model_estimator.adjustNormalization(num_analyzed_frames, signal_energy);
        }

        self.signal_model_estimator.update(
            prior_snr,
            post_snr,
            conservative_noise_spectrum,
            signal_spectrum,
            signal_spectral_sum,
            signal_energy,
        );

        const model = self.signal_model_estimator.model();
        const prior_model = self.signal_model_estimator.priorModel();

        const WIDTH_PRIOR_0: f32 = 4.0;
        const WIDTH_PRIOR_1: f32 = 2.0 * WIDTH_PRIOR_0;

        const width_prior_0: f32 = if (model.lrt < prior_model.lrt) WIDTH_PRIOR_1 else WIDTH_PRIOR_0;
        const indicator0 = 0.5 * (std.math.tanh(width_prior_0 * (model.lrt - prior_model.lrt)) + 1.0);

        const width_prior_1: f32 = if (model.spectral_flatness > prior_model.flatness_threshold) WIDTH_PRIOR_1 else WIDTH_PRIOR_0;
        const indicator1 = 0.5 * (std.math.tanh(width_prior_1 * (prior_model.flatness_threshold - model.spectral_flatness)) + 1.0);

        const width_prior_2: f32 = if (model.spectral_diff < prior_model.template_diff_threshold) WIDTH_PRIOR_1 else WIDTH_PRIOR_0;
        const indicator2 = 0.5 * (std.math.tanh(width_prior_2 * (model.spectral_diff - prior_model.template_diff_threshold)) + 1.0);

        const ind_prior = prior_model.lrt_weighting * indicator0 + prior_model.flatness_weighting * indicator1 + prior_model.difference_weighting * indicator2;

        self.prior_speech_prob += 0.1 * (ind_prior - self.prior_speech_prob);
        self.prior_speech_prob = std.math.clamp(self.prior_speech_prob, 0.01, 1.0);

        const gain_prior = (1.0 - self.prior_speech_prob) / (self.prior_speech_prob + 0.0001);

        var inv_lrt: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32 = undefined;
        fast_math.expApproximationSignFlipSlice(&model.avg_log_lrt, &inv_lrt);

        for (0..ns_common.FFT_SIZE_BY_2_PLUS_1) |i| {
            self.speech_probability[i] = 1.0 / (1.0 + gain_prior * inv_lrt[i]);
        }
    }

    pub fn priorProbability(self: *const SpeechProbabilityEstimator) f32 {
        return self.prior_speech_prob;
    }

    pub fn probability(self: *const SpeechProbabilityEstimator) []const f32 {
        return &self.speech_probability;
    }
};
