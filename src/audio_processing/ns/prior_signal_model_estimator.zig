//! Prior model estimator using feature histograms.
const std = @import("std");
const ns_common = @import("ns_common.zig");
const Histograms = @import("histograms.zig").Histograms;
const HISTOGRAM_SIZE = @import("histograms.zig").HISTOGRAM_SIZE;
const PriorSignalModel = @import("prior_signal_model.zig").PriorSignalModel;

// Constants from ns_common
const BIN_SIZE_LRT: f32 = 0.1;
const BIN_SIZE_SPEC_FLAT: f32 = 0.05;
const BIN_SIZE_SPEC_DIFF: f32 = 0.1;
const FEATURE_UPDATE_WINDOW_SIZE: i32 = 500;

fn findFirstOfTwoLargestPeaks(
    bin_size: f32,
    histogram: []const i32,
) struct { position: f32, weight: i32 } {
    var peak_value: i32 = 0;
    var secondary_peak_value: i32 = 0;
    var peak_position: f32 = 0.0;
    var secondary_peak_position: f32 = 0.0;
    var peak_weight: i32 = 0;
    var secondary_peak_weight: i32 = 0;

    for (0..HISTOGRAM_SIZE) |i| {
        const bin_mid = (@as(f32, @floatFromInt(i)) + 0.5) * bin_size;
        const value = histogram[i];
        if (value > peak_value) {
            secondary_peak_value = peak_value;
            secondary_peak_weight = peak_weight;
            secondary_peak_position = peak_position;

            peak_value = value;
            peak_weight = value;
            peak_position = bin_mid;
        } else if (value > secondary_peak_value) {
            secondary_peak_value = value;
            secondary_peak_weight = value;
            secondary_peak_position = bin_mid;
        }
    }

    if (@abs(secondary_peak_position - peak_position) < 2.0 * bin_size and @as(f32, @floatFromInt(secondary_peak_weight)) > 0.5 * @as(f32, @floatFromInt(peak_weight))) {
        peak_weight += secondary_peak_weight;
        peak_position = 0.5 * (peak_position + secondary_peak_position);
    }

    return .{ .position = peak_position, .weight = peak_weight };
}

fn updateLrt(
    lrt_histogram: []const i32,
    prior_model_lrt: *f32,
    low_lrt_fluctuations: *bool,
) void {
    var average: f32 = 0.0;
    var average_compl: f32 = 0.0;
    var average_squared: f32 = 0.0;
    var count: i32 = 0;

    for (0..10) |i| {
        const bin_mid = (@as(f32, @floatFromInt(i)) + 0.5) * BIN_SIZE_LRT;
        const value = lrt_histogram[i];
        average += @as(f32, @floatFromInt(value)) * bin_mid;
        count += value;
    }
    if (count > 0) {
        average /= @as(f32, @floatFromInt(count));
    }

    for (0..HISTOGRAM_SIZE) |i| {
        const bin_mid = (@as(f32, @floatFromInt(i)) + 0.5) * BIN_SIZE_LRT;
        const value = lrt_histogram[i];
        average_squared += @as(f32, @floatFromInt(value)) * bin_mid * bin_mid;
        average_compl += @as(f32, @floatFromInt(value)) * bin_mid;
    }

    const one_by_window: f32 = 1.0 / @as(f32, FEATURE_UPDATE_WINDOW_SIZE);
    average_squared *= one_by_window;
    average_compl *= one_by_window;

    low_lrt_fluctuations.* = average_squared - average * average_compl < 0.05;

    const MAX_LRT: f32 = 1.0;
    const MIN_LRT: f32 = 0.2;
    if (low_lrt_fluctuations.*) {
        prior_model_lrt.* = MAX_LRT;
    } else {
        prior_model_lrt.* = std.math.clamp(1.2 * average, MIN_LRT, MAX_LRT);
    }
}

pub const PriorSignalModelEstimator = struct {
    prior_model: PriorSignalModel,

    pub fn init(lrt_initial_value: f32) PriorSignalModelEstimator {
        return .{
            .prior_model = PriorSignalModel.init(lrt_initial_value),
        };
    }

    pub fn update(self: *PriorSignalModelEstimator, histograms: *const Histograms) void {
        var low_lrt_fluctuations: bool = false;
        updateLrt(
            histograms.getLrt(),
            &self.prior_model.lrt,
            &low_lrt_fluctuations,
        );

        const flat_result = findFirstOfTwoLargestPeaks(BIN_SIZE_SPEC_FLAT, histograms.getSpectralFlatness());
        const spectral_flatness_peak_position = flat_result.position;
        const spectral_flatness_peak_weight = flat_result.weight;

        const diff_result = findFirstOfTwoLargestPeaks(BIN_SIZE_SPEC_DIFF, histograms.getSpectralDiff());
        const spectral_diff_peak_position = diff_result.position;
        const spectral_diff_peak_weight = diff_result.weight;

        const flat_cond = (@as(f32, @floatFromInt(spectral_flatness_peak_weight)) < 0.3 * 500.0) or (spectral_flatness_peak_position < 0.6);
        const use_spec_flat: i32 = if (flat_cond) 0 else 1;

        const diff_cond = (@as(f32, @floatFromInt(spectral_diff_peak_weight)) < 0.3 * 500.0) or low_lrt_fluctuations;
        const use_spec_diff: i32 = if (diff_cond) 0 else 1;

        self.prior_model.template_diff_threshold =
            std.math.clamp(1.2 * spectral_diff_peak_position, 0.16, 1.0);

        const one_by_feature_sum: f32 = 1.0 / (1.0 + @as(f32, @floatFromInt(use_spec_flat)) + @as(f32, @floatFromInt(use_spec_diff)));
        self.prior_model.lrt_weighting = one_by_feature_sum;

        if (use_spec_flat == 1) {
            self.prior_model.flatness_threshold =
                std.math.clamp(0.9 * spectral_flatness_peak_position, 0.1, 0.95);
            self.prior_model.flatness_weighting = one_by_feature_sum;
        } else {
            self.prior_model.flatness_weighting = 0.0;
        }

        if (use_spec_diff == 1) {
            self.prior_model.difference_weighting = one_by_feature_sum;
        } else {
            self.prior_model.difference_weighting = 0.0;
        }
    }

    pub fn priorModel(self: *const PriorSignalModelEstimator) *const PriorSignalModel {
        return &self.prior_model;
    }
};
