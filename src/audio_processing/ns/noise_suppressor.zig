const std = @import("std");
const ns_common = @import("ns_common.zig");
const NsConfig = @import("ns_config.zig").NsConfig;
const SuppressionParams = @import("suppression_params.zig").SuppressionParams;
const NrFft = @import("ns_fft.zig").NrFft;
const NoiseEstimator = @import("noise_estimator.zig").NoiseEstimator;
const SpeechProbabilityEstimator = @import("speech_probability_estimator.zig").SpeechProbabilityEstimator;
const WienerFilter = @import("wiener_filter.zig").WienerFilter;
const fast_math = @import("fast_math.zig");

/// Filter bank window first half (matches aec3-rs BLOCKS_160W_256_FIRST_HALF)
const WINDOW_FIRST_HALF = [_]f32{
    0.00000000, 0.01636173, 0.03271908, 0.04906767, 0.06540313, 0.08172107,
    0.09801714, 0.11428696, 0.13052619, 0.14673047, 0.16289547, 0.17901686,
    0.19509032, 0.21111155, 0.22707626, 0.24298018, 0.25881905, 0.27458862,
    0.29028468, 0.30590302, 0.32143947, 0.33688985, 0.35225005, 0.36751594,
    0.38268343, 0.39774847, 0.41270703, 0.42755509, 0.44228869, 0.45690388,
    0.47139674, 0.48576339, 0.50000000, 0.51410274, 0.52806785, 0.54189158,
    0.55557023, 0.56910015, 0.58247770, 0.59569930, 0.60876143, 0.62166057,
    0.63439328, 0.64695615, 0.65934582, 0.67155895, 0.68359230, 0.69544264,
    0.70710678, 0.71858162, 0.72986407, 0.74095113, 0.75183981, 0.76252720,
    0.77301045, 0.78328675, 0.79335334, 0.80320753, 0.81284668, 0.82226822,
    0.83146961, 0.84044840, 0.84920218, 0.85772861, 0.86602540, 0.87409034,
    0.88192126, 0.88951608, 0.89687274, 0.90398929, 0.91086382, 0.91749450,
    0.92387953, 0.93001722, 0.93590593, 0.94154407, 0.94693013, 0.95206268,
    0.95694034, 0.96156180, 0.96592583, 0.97003125, 0.97387698, 0.97746197,
    0.98078528, 0.98384601, 0.98664333, 0.98917651, 0.99144486, 0.99344778,
    0.99518473, 0.99665524, 0.99785892, 0.99879546, 0.99946459, 0.99986614,
};

fn applyFilterBankWindow(extended_frame: *[ns_common.FFT_SIZE]f32) void {
    // First half: 0..OVERLAP_SIZE (96 elements)
    for (0..ns_common.OVERLAP_SIZE) |i| {
        extended_frame[i] *= WINDOW_FIRST_HALF[i];
    }
    // Second half: matches Rust (1..=95).rev()
    // i goes from FRAME_SIZE+1 (161) to FFT_SIZE-1 (255) = 95 elements
    // k goes from 95 down to 1 = 95 elements
    var i: usize = ns_common.FRAME_SIZE + 1; // 161
    var k: usize = ns_common.OVERLAP_SIZE - 1; // 95
    while (i < ns_common.FFT_SIZE and k >= 1) : ({
        i += 1;
        k -= 1;
    }) {
        extended_frame[i] *= WINDOW_FIRST_HALF[k];
    }
}

fn formExtendedFrame(
    frame: []const f32,
    old_data: *[ns_common.OVERLAP_SIZE]f32,
    extended_frame: *[ns_common.FFT_SIZE]f32,
) void {
    @memcpy(extended_frame[0..ns_common.OVERLAP_SIZE], old_data);
    @memcpy(extended_frame[ns_common.OVERLAP_SIZE..ns_common.FFT_SIZE], frame);
    @memcpy(old_data, extended_frame[ns_common.FRAME_SIZE..ns_common.FFT_SIZE]);
}

fn overlapAndAdd(
    extended_frame: []const f32,
    overlap_memory: *[ns_common.OVERLAP_SIZE]f32,
    output_frame: []f32,
) void {
    for (0..ns_common.OVERLAP_SIZE) |i| {
        output_frame[i] = overlap_memory[i] + extended_frame[i];
    }
    @memcpy(output_frame[ns_common.OVERLAP_SIZE..ns_common.FRAME_SIZE], extended_frame[ns_common.OVERLAP_SIZE..ns_common.FRAME_SIZE]);
    @memcpy(overlap_memory, extended_frame[ns_common.FRAME_SIZE..ns_common.FFT_SIZE]);
}

fn computeMagnitudeSpectrum(
    real: []const f32,
    imag: []const f32,
    signal_spectrum: *[ns_common.FFT_SIZE_BY_2_PLUS_1]f32,
) void {
    signal_spectrum[0] = @abs(real[0]) + 1.0;
    signal_spectrum[ns_common.FFT_SIZE_BY_2_PLUS_1 - 1] = @abs(real[ns_common.FFT_SIZE_BY_2_PLUS_1 - 1]) + 1.0;
    for (1..(ns_common.FFT_SIZE_BY_2_PLUS_1 - 1)) |i| {
        signal_spectrum[i] = fast_math.sqrtFastApproximation(real[i] * real[i] + imag[i] * imag[i]) + 1.0;
    }
}

fn computeEnergyOfExtendedFrame(extended_frame: []const f32) f32 {
    var energy: f32 = 0.0;
    for (extended_frame) |v| {
        energy += v * v;
    }
    return energy;
}

fn traceSlice(enabled: bool, tag: []const u8, x: []const f32, n: usize) void {
    if (!enabled) return;
    const take = @min(n, x.len);
    std.debug.print("TRACE|ZIG|{s}|", .{tag});
    for (0..take) |i| {
        if (i > 0) std.debug.print(",", .{});
        std.debug.print("{d:.9}", .{x[i]});
    }
    std.debug.print("\n", .{});
}

fn traceScalar(enabled: bool, tag: []const u8, value: f32) void {
    if (!enabled) return;
    std.debug.print("TRACE|ZIG|{s}|{d:.9}\n", .{ tag, value });
}

pub const NoiseSuppressor = struct {
    fft: NrFft,
    noise_estimator: NoiseEstimator,
    speech_prob_estimator: SpeechProbabilityEstimator,
    wiener_filter: WienerFilter,
    prev_analysis_signal_spectrum: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32,

    // State for overlap-add
    analyze_analysis_memory: [ns_common.OVERLAP_SIZE]f32,
    process_analysis_memory: [ns_common.OVERLAP_SIZE]f32,
    process_synthesis_memory: [ns_common.OVERLAP_SIZE]f32,

    // Frame counter
    num_analyzed_frames: i32,
    trace_enabled: bool,

    pub fn init(config: NsConfig) !NoiseSuppressor {
        try config.validate();
        const params = SuppressionParams.fromConfig(config);
        return .{
            .fft = if (config.numeric_mode == .float32) NrFft.initOracle() else NrFft.init(),
            .noise_estimator = NoiseEstimator.init(params),
            .speech_prob_estimator = SpeechProbabilityEstimator.init(config.numeric_mode),
            .wiener_filter = WienerFilter.init(params),
            .prev_analysis_signal_spectrum = [_]f32{1.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1,
            .analyze_analysis_memory = [_]f32{0.0} ** ns_common.OVERLAP_SIZE,
            .process_analysis_memory = [_]f32{0.0} ** ns_common.OVERLAP_SIZE,
            .process_synthesis_memory = [_]f32{0.0} ** ns_common.OVERLAP_SIZE,
            .num_analyzed_frames = -1,
            .trace_enabled = false,
        };
    }

    pub fn setTraceEnabled(self: *NoiseSuppressor, enabled: bool) void {
        self.trace_enabled = enabled;
    }

    pub fn analyze(self: *NoiseSuppressor, frame: []const f32) !void {
        if (frame.len != ns_common.FRAME_SIZE) return error.InvalidFrameLength;

        // Form extended frame with overlap
        var extended_frame: [ns_common.FFT_SIZE]f32 = undefined;
        formExtendedFrame(frame, &self.analyze_analysis_memory, &extended_frame);

        // Apply filter bank window
        applyFilterBankWindow(&extended_frame);

        // FFT
        var real: [ns_common.FFT_SIZE]f32 = [_]f32{0.0} ** ns_common.FFT_SIZE;
        var imag: [ns_common.FFT_SIZE]f32 = [_]f32{0.0} ** ns_common.FFT_SIZE;
        self.fft.fft(&extended_frame, &real, &imag);

        // Compute magnitude spectrum
        var signal_spectrum: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32 = undefined;
        computeMagnitudeSpectrum(&real, &imag, &signal_spectrum);
        traceSlice(self.trace_enabled, "analyze.signal_spectrum", &signal_spectrum, 8);

        // Compute signal energy
        var signal_energy: f32 = 0.0;
        for (0..ns_common.FFT_SIZE_BY_2_PLUS_1) |i| {
            signal_energy += real[i] * real[i] + imag[i] * imag[i];
        }
        signal_energy /= @as(f32, @floatFromInt(ns_common.FFT_SIZE_BY_2_PLUS_1));

        const signal_spectral_sum: f32 = blk: {
            var sum: f32 = 0.0;
            for (signal_spectrum) |v| sum += v;
            break :blk sum;
        };
        traceScalar(self.trace_enabled, "analyze.signal_spectral_sum", signal_spectral_sum);
        traceScalar(self.trace_enabled, "analyze.signal_energy", signal_energy);

        // Update frame counter (matches aec3-rs logic)
        self.num_analyzed_frames += 1;
        if (self.num_analyzed_frames < 0) {
            self.num_analyzed_frames = 0;
        }

        // Update noise estimator
        self.noise_estimator.prepareAnalysis();
        self.noise_estimator.preUpdate(self.num_analyzed_frames, &signal_spectrum, signal_spectral_sum);
        traceSlice(self.trace_enabled, "analyze.noise_spectrum.pre", self.noise_estimator.noiseSpectrum(), 8);

        // Compute SNR
        var prior_snr: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32 = undefined;
        var post_snr: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32 = undefined;
        computeSnr(
            self.wiener_filter.getFilter(),
            &self.prev_analysis_signal_spectrum,
            &signal_spectrum,
            self.noise_estimator.prevNoiseSpectrum(),
            self.noise_estimator.noiseSpectrum(),
            &prior_snr,
            &post_snr,
        );
        traceSlice(self.trace_enabled, "analyze.prior_snr", &prior_snr, 8);
        traceSlice(self.trace_enabled, "analyze.post_snr", &post_snr, 8);

        // Update speech probability
        self.speech_prob_estimator.update(
            self.num_analyzed_frames,
            &prior_snr,
            &post_snr,
            self.noise_estimator.conservativeNoiseSpectrum(),
            &signal_spectrum,
            signal_spectral_sum,
            signal_energy,
        );
        traceSlice(self.trace_enabled, "analyze.speech_probability", self.speech_prob_estimator.probability(), 8);
        traceScalar(self.trace_enabled, "analyze.prior_probability", self.speech_prob_estimator.priorProbability());

        // Post-update noise estimator
        self.noise_estimator.postUpdate(
            self.speech_prob_estimator.probability(),
            &signal_spectrum,
        );
        traceSlice(self.trace_enabled, "analyze.noise_spectrum.post", self.noise_estimator.noiseSpectrum(), 8);
        traceSlice(self.trace_enabled, "analyze.prev_noise_spectrum", self.noise_estimator.prevNoiseSpectrum(), 8);

        // Store for next frame
        @memcpy(&self.prev_analysis_signal_spectrum, &signal_spectrum);
    }

    pub fn process(self: *NoiseSuppressor, frame: []f32) !void {
        if (frame.len != ns_common.FRAME_SIZE) return error.InvalidFrameLength;

        // Form extended frame with overlap
        var extended_frame: [ns_common.FFT_SIZE]f32 = undefined;
        formExtendedFrame(frame, &self.process_analysis_memory, &extended_frame);

        // Apply filter bank window
        applyFilterBankWindow(&extended_frame);

        // Store pre-filter energy
        const energy_before_filtering = computeEnergyOfExtendedFrame(&extended_frame);
        traceScalar(self.trace_enabled, "process.energy_before_filtering", energy_before_filtering);

        // FFT
        var real: [ns_common.FFT_SIZE]f32 = [_]f32{0.0} ** ns_common.FFT_SIZE;
        var imag: [ns_common.FFT_SIZE]f32 = [_]f32{0.0} ** ns_common.FFT_SIZE;
        self.fft.fft(&extended_frame, &real, &imag);

        // Compute magnitude spectrum
        var signal_spectrum: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32 = undefined;
        computeMagnitudeSpectrum(&real, &imag, &signal_spectrum);
        traceSlice(self.trace_enabled, "process.signal_spectrum", &signal_spectrum, 8);

        // Update Wiener filter
        self.wiener_filter.update(
            self.num_analyzed_frames,
            self.noise_estimator.noiseSpectrum(),
            self.noise_estimator.prevNoiseSpectrum(),
            self.noise_estimator.parametricNoiseSpectrum(),
            &signal_spectrum,
        );
        traceSlice(self.trace_enabled, "process.wiener_filter", self.wiener_filter.getFilter(), 8);

        // Get filter gain
        const filter = self.wiener_filter.getFilter();

        // Apply gain to spectrum
        for (0..ns_common.FFT_SIZE_BY_2_PLUS_1) |i| {
            real[i] *= filter[i];
            imag[i] *= filter[i];
        }

        // IFFT
        var out: [ns_common.FFT_SIZE]f32 = [_]f32{0.0} ** ns_common.FFT_SIZE;
        try self.fft.ifft(real[0..ns_common.FFT_SIZE_BY_2_PLUS_1], imag[0..ns_common.FFT_SIZE_BY_2_PLUS_1], &out);

        // Compute energy after filtering
        const energy_after_filtering = computeEnergyOfExtendedFrame(&out);
        traceScalar(self.trace_enabled, "process.energy_after_filtering", energy_after_filtering);

        // Apply filter bank window again (after IFFT)
        applyFilterBankWindow(&out);

        // Compute gain adjustment
        const gain_adjustment = self.wiener_filter.computeOverallScalingFactor(
            self.num_analyzed_frames,
            self.speech_prob_estimator.priorProbability(),
            energy_before_filtering,
            energy_after_filtering,
        );
        traceScalar(self.trace_enabled, "process.gain_adjustment.min", gain_adjustment);

        // Apply gain adjustment
        for (&out) |*v| {
            v.* *= gain_adjustment;
        }

        // Overlap and add
        overlapAndAdd(&out, &self.process_synthesis_memory, frame);
        traceSlice(self.trace_enabled, "process.output_frame", frame, 16);

        // Clamp output (match aec3-rs: -32768.0 to 32767.0)
        for (frame) |*v| {
            v.* = std.math.clamp(v.*, -32768.0, 32767.0);
        }
    }
};

fn computeSnr(
    filter: []const f32,
    prev_signal_spectrum: []const f32,
    signal_spectrum: []const f32,
    prev_noise_spectrum: []const f32,
    noise_spectrum: []const f32,
    prior_snr: *[ns_common.FFT_SIZE_BY_2_PLUS_1]f32,
    post_snr: *[ns_common.FFT_SIZE_BY_2_PLUS_1]f32,
) void {
    for (0..ns_common.FFT_SIZE_BY_2_PLUS_1) |i| {
        const prev_estimate = prev_signal_spectrum[i] / (prev_noise_spectrum[i] + 0.0001) * filter[i];
        post_snr[i] = if (signal_spectrum[i] > noise_spectrum[i])
            signal_spectrum[i] / (noise_spectrum[i] + 0.0001) - 1.0
        else
            0.0;
        prior_snr[i] = 0.98 * prev_estimate + 0.02 * post_snr[i];
    }
}

test "noise suppressor silence stability" {
    var ns = try NoiseSuppressor.init(.{ .numeric_mode = .float32 });
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
    var ns = try NoiseSuppressor.init(.{ .numeric_mode = .float32 });
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
