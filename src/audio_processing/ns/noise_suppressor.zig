const std = @import("std");
const ns_common = @import("ns_common.zig");
const NsConfig = @import("ns_config.zig").NsConfig;
const SuppressionParams = @import("suppression_params.zig").SuppressionParams;
const NrFft = @import("ns_fft.zig").NrFft;
const NoiseEstimator = @import("noise_estimator.zig").NoiseEstimator;
const SignalModelEstimator = @import("signal_model_estimator.zig").SignalModelEstimator;
const SpeechProbabilityEstimator = @import("speech_probability_estimator.zig").SpeechProbabilityEstimator;
const WienerFilter = @import("wiener_filter.zig").WienerFilter;

pub const NoiseSuppressor = struct {
    fft: NrFft,
    noise_estimator: NoiseEstimator,
    signal_model_estimator: SignalModelEstimator,
    speech_prob_estimator: SpeechProbabilityEstimator,
    wiener_filter: WienerFilter,
    prev_gain: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32,

    pub fn init(config: NsConfig) !NoiseSuppressor {
        try config.validate();
        const params = SuppressionParams.fromConfig(config);
        return .{
            .fft = if (config.numeric_mode == .float32) NrFft.initOracle() else NrFft.init(),
            .noise_estimator = NoiseEstimator.init(params, config.min_noise_floor),
            .signal_model_estimator = SignalModelEstimator.init(params),
            .speech_prob_estimator = SpeechProbabilityEstimator.init(config.numeric_mode),
            .wiener_filter = WienerFilter.init(params),
            .prev_gain = [_]f32{1.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1,
        };
    }

    pub fn analyze(self: *NoiseSuppressor, frame: []const f32) !void {
        if (frame.len != ns_common.FRAME_SIZE) return error.InvalidFrameLength;

        var in: [ns_common.FFT_SIZE]f32 = undefined;
        @memcpy(&in, frame[0..ns_common.FFT_SIZE]);

        var real: [ns_common.FFT_SIZE]f32 = [_]f32{0.0} ** ns_common.FFT_SIZE;
        var imag: [ns_common.FFT_SIZE]f32 = [_]f32{0.0} ** ns_common.FFT_SIZE;
        self.fft.fft(&in, &real, &imag);

        var magnitude2: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32 = undefined;
        for (0..ns_common.FFT_SIZE_BY_2_PLUS_1) |i| {
            magnitude2[i] = real[i] * real[i] + imag[i] * imag[i];
        }
        self.noise_estimator.update(&magnitude2);
    }

    pub fn process(self: *NoiseSuppressor, frame: []f32) !void {
        if (frame.len != ns_common.FRAME_SIZE) return error.InvalidFrameLength;

        var in: [ns_common.FFT_SIZE]f32 = undefined;
        @memcpy(&in, frame[0..ns_common.FFT_SIZE]);

        var real: [ns_common.FFT_SIZE]f32 = [_]f32{0.0} ** ns_common.FFT_SIZE;
        var imag: [ns_common.FFT_SIZE]f32 = [_]f32{0.0} ** ns_common.FFT_SIZE;
        self.fft.fft(&in, &real, &imag);

        var magnitude2: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32 = undefined;
        for (0..ns_common.FFT_SIZE_BY_2_PLUS_1) |i| {
            magnitude2[i] = real[i] * real[i] + imag[i] * imag[i];
        }

        const estimates = self.signal_model_estimator.update(&magnitude2, self.noise_estimator.noise(), &self.prev_gain);
        var speech_prob: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32 = undefined;
        self.speech_prob_estimator.estimate(&estimates.prior_snr, &speech_prob);

        var gain: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32 = undefined;
        self.wiener_filter.computeGain(&estimates.prior_snr, &speech_prob, &gain);

        for (0..ns_common.FFT_SIZE_BY_2_PLUS_1) |i| {
            real[i] *= gain[i];
            imag[i] *= gain[i];
            self.prev_gain[i] = gain[i];
        }

        var out: [ns_common.FFT_SIZE]f32 = [_]f32{0.0} ** ns_common.FFT_SIZE;
        try self.fft.ifft(real[0..ns_common.FFT_SIZE_BY_2_PLUS_1], imag[0..ns_common.FFT_SIZE_BY_2_PLUS_1], &out);

        const post_ifft_scale = self.fft.synthesisScale();
        for (0..ns_common.FFT_SIZE) |i| {
            frame[i] = std.math.clamp(out[i] * post_ifft_scale, -1.0, 1.0);
        }
    }
};

test "noise suppressor silence stability" {
    var ns = try NoiseSuppressor.init(.{});
    var frame = [_]f32{0.0} ** ns_common.FRAME_SIZE;

    var n: usize = 0;
    while (n < 100) : (n += 1) {
        try ns.analyze(&frame);
        try ns.process(&frame);
        for (frame) |v| {
            try std.testing.expect(std.math.isFinite(v));
            try std.testing.expect(@abs(v) <= 1e-6);
        }
    }
}

test "noise suppressor reduces broadband power on mixed frame" {
    var ns = try NoiseSuppressor.init(.{});
    var frame = [_]f32{0.0} ** ns_common.FRAME_SIZE;

    for (0..ns_common.FRAME_SIZE) |i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(ns_common.SAMPLE_RATE_HZ));
        const tone = 0.2 * std.math.sin(2.0 * std.math.pi * 400.0 * t);
        const pseudo_noise = 0.05 * std.math.sin(2.0 * std.math.pi * 3200.0 * t);
        frame[i] = tone + pseudo_noise;
    }

    var before: f32 = 0.0;
    for (frame) |v| before += v * v;

    try ns.analyze(&frame);
    try ns.process(&frame);

    var after: f32 = 0.0;
    for (frame) |v| after += v * v;

    try std.testing.expect(after <= before);
}
