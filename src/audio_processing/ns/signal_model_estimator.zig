const ns_common = @import("ns_common.zig");
const SignalModel = @import("signal_model.zig").SignalModel;
const PriorSignalModelEstimator = @import("prior_signal_model_estimator.zig").PriorSignalModelEstimator;
const SuppressionParams = @import("suppression_params.zig").SuppressionParams;

pub const SignalEstimates = struct {
    posterior_snr: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32,
    prior_snr: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32,
};

pub const SignalModelEstimator = struct {
    signal_model: SignalModel,
    prior_estimator: PriorSignalModelEstimator,

    pub fn init(params: SuppressionParams) SignalModelEstimator {
        return .{
            .signal_model = SignalModel.init(),
            .prior_estimator = PriorSignalModelEstimator.init(params),
        };
    }

    pub fn update(self: *SignalModelEstimator, magnitude2: []const f32, noise_psd: []const f32, prev_gain: []const f32) SignalEstimates {
        self.signal_model.update(magnitude2, noise_psd);
        const prior = self.prior_estimator.update(&self.signal_model.posterior_snr, prev_gain);
        return .{
            .posterior_snr = self.signal_model.posterior_snr,
            .prior_snr = prior[0..ns_common.FFT_SIZE_BY_2_PLUS_1].*,
        };
    }
};
