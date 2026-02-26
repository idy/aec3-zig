const ns_common = @import("ns_common.zig");
const PriorSignalModel = @import("prior_signal_model.zig").PriorSignalModel;
const SuppressionParams = @import("suppression_params.zig").SuppressionParams;

pub const PriorSignalModelEstimator = struct {
    model: PriorSignalModel,
    params: SuppressionParams,

    pub fn init(params: SuppressionParams) PriorSignalModelEstimator {
        return .{
            .model = PriorSignalModel.init(),
            .params = params,
        };
    }

    pub fn update(self: *PriorSignalModelEstimator, posterior_snr: []const f32, prev_gain: []const f32) []const f32 {
        self.model.update(posterior_snr, prev_gain, self.params.prior_snr_smoothing);
        return &self.model.prior_snr;
    }
};
