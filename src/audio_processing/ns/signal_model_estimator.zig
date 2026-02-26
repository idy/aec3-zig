//! Signal model estimator used for speech probability.
const std = @import("std");
const ns_common = @import("ns_common.zig");
const fast_math = @import("fast_math.zig");
const SignalModel = @import("signal_model.zig").SignalModel;
const PriorSignalModel = @import("prior_signal_model.zig").PriorSignalModel;
const PriorSignalModelEstimator = @import("prior_signal_model_estimator.zig").PriorSignalModelEstimator;
const Histograms = @import("histograms.zig").Histograms;

const ONE_BY_FFT_SIZE_BY_2_PLUS_1: f32 = 1.0 / @as(f32, ns_common.FFT_SIZE_BY_2_PLUS_1);

fn computeSpectralDiff(
    conservative_noise_spectrum: []const f32,
    signal_spectrum: []const f32,
    signal_spectral_sum: f32,
    diff_normalization: f32,
) f32 {
    var noise_average: f32 = 0.0;
    for (conservative_noise_spectrum) |v| {
        noise_average += v;
    }
    noise_average *= ONE_BY_FFT_SIZE_BY_2_PLUS_1;

    const signal_average = signal_spectral_sum * ONE_BY_FFT_SIZE_BY_2_PLUS_1;

    var covariance: f32 = 0.0;
    var noise_variance: f32 = 0.0;
    var signal_variance: f32 = 0.0;

    for (0..ns_common.FFT_SIZE_BY_2_PLUS_1) |i| {
        const signal_diff = signal_spectrum[i] - signal_average;
        const noise_diff = conservative_noise_spectrum[i] - noise_average;
        covariance += signal_diff * noise_diff;
        noise_variance += noise_diff * noise_diff;
        signal_variance += signal_diff * signal_diff;
    }

    covariance *= ONE_BY_FFT_SIZE_BY_2_PLUS_1;
    noise_variance *= ONE_BY_FFT_SIZE_BY_2_PLUS_1;
    signal_variance *= ONE_BY_FFT_SIZE_BY_2_PLUS_1;

    const spectral_diff = signal_variance - (covariance * covariance) / (noise_variance + 0.0001);
    return spectral_diff / (diff_normalization + 0.0001);
}

fn updateSpectralFlatness(
    signal_spectrum: []const f32,
    signal_spectral_sum: f32,
    spectral_flatness: *f32,
) void {
    const AVERAGING: f32 = 0.3;

    // Check if any value (except DC) is zero
    for (signal_spectrum[1..]) |x| {
        if (x == 0.0) {
            spectral_flatness.* -= AVERAGING * spectral_flatness.*;
            return;
        }
    }

    var avg_num: f32 = 0.0;
    for (signal_spectrum[1..]) |x| {
        avg_num += fast_math.logApproximation(x);
    }
    avg_num *= ONE_BY_FFT_SIZE_BY_2_PLUS_1;

    const avg_denom = (signal_spectral_sum - signal_spectrum[0]) * ONE_BY_FFT_SIZE_BY_2_PLUS_1;

    const spectral_tmp = fast_math.expApproximation(avg_num) / avg_denom;
    spectral_flatness.* += AVERAGING * (spectral_tmp - spectral_flatness.*);
}

fn updateSpectralLrt(
    prior_snr: []const f32,
    post_snr: []const f32,
    avg_log_lrt: []f32,
    lrt: *f32,
) void {
    for (0..ns_common.FFT_SIZE_BY_2_PLUS_1) |i| {
        const tmp1 = 1.0 + 2.0 * prior_snr[i];
        const tmp2 = 2.0 * prior_snr[i] / (tmp1 + 0.0001);
        const bessel_tmp = (post_snr[i] + 1.0) * tmp2;
        avg_log_lrt[i] += 0.5 * (bessel_tmp - fast_math.logApproximation(tmp1) - avg_log_lrt[i]);
    }

    var sum: f32 = 0.0;
    for (avg_log_lrt) |v| {
        sum += v;
    }
    lrt.* = sum * ONE_BY_FFT_SIZE_BY_2_PLUS_1;
}

pub const SignalModelEstimator = struct {
    diff_normalization: f32,
    signal_energy_sum: f32,
    histograms: Histograms,
    histogram_analysis_counter: i32,
    prior_model_estimator: PriorSignalModelEstimator,
    features: SignalModel,

    pub fn init() SignalModelEstimator {
        return .{
            .diff_normalization = 0.0,
            .signal_energy_sum = 0.0,
            .histograms = Histograms.init(),
            .histogram_analysis_counter = ns_common.FEATURE_UPDATE_WINDOW_SIZE,
            .prior_model_estimator = PriorSignalModelEstimator.init(ns_common.LRT_FEATURE_THR),
            .features = SignalModel.init(),
        };
    }

    pub fn adjustNormalization(self: *SignalModelEstimator, num_analyzed_frames: i32, signal_energy: f32) void {
        self.diff_normalization *= @as(f32, @floatFromInt(num_analyzed_frames));
        self.diff_normalization += signal_energy;
        self.diff_normalization /= @as(f32, @floatFromInt(num_analyzed_frames)) + 1.0;
    }

    pub fn update(
        self: *SignalModelEstimator,
        prior_snr: []const f32,
        post_snr: []const f32,
        conservative_noise_spectrum: []const f32,
        signal_spectrum: []const f32,
        signal_spectral_sum: f32,
        signal_energy: f32,
    ) void {
        updateSpectralFlatness(signal_spectrum, signal_spectral_sum, &self.features.spectral_flatness);

        const spectral_diff = computeSpectralDiff(
            conservative_noise_spectrum,
            signal_spectrum,
            signal_spectral_sum,
            self.diff_normalization,
        );
        self.features.spectral_diff += 0.3 * (spectral_diff - self.features.spectral_diff);

        self.signal_energy_sum += signal_energy;

        self.histogram_analysis_counter -= 1;
        if (self.histogram_analysis_counter > 0) {
            self.histograms.update(&self.features);
        } else {
            self.prior_model_estimator.update(&self.histograms);
            self.histograms.clear();
            self.histogram_analysis_counter = ns_common.FEATURE_UPDATE_WINDOW_SIZE;

            self.signal_energy_sum /= @as(f32, ns_common.FEATURE_UPDATE_WINDOW_SIZE);
            self.diff_normalization = 0.5 * (self.signal_energy_sum + self.diff_normalization);
            self.signal_energy_sum = 0.0;
        }

        updateSpectralLrt(prior_snr, post_snr, &self.features.avg_log_lrt, &self.features.lrt);
    }

    pub fn priorModel(self: *const SignalModelEstimator) *const PriorSignalModel {
        return self.prior_model_estimator.priorModel();
    }

    pub fn model(self: *const SignalModelEstimator) *const SignalModel {
        return &self.features;
    }
};
