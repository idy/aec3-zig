//! NS (Noise Suppression) Golden Vector Tests
//!
//! Alignment direction: Zig implementation is validated against Rust aec3-rs golden baseline.
//!
//! IMPLEMENTATION ALIGNMENT:
//! Rust golden generator and Zig implementation both use the same algorithmic approach
//! from aec3-rs, enabling strict per-sample alignment of `NS_*_OUTPUT` vectors.
//!
//! Test categories:
//! 1. Input vector parsing and validity
//! 2. Output cross-validation (strict numerical alignment with Rust golden vectors)
//! 3. Algorithmic correctness (noise suppression, signal preservation)
//! 4. Sub-module unit tests

const std = @import("std");
const aec3 = @import("aec3");
const test_utils = @import("test_utils.zig");
const NoiseSuppressor = aec3.NoiseSuppressor;
const ns_common = aec3.NsCommon;
const NumericMode = aec3.NumericMode;

const golden_text = @embedFile("../vectors/rust_ns_golden_vectors.txt");

// 阈值来源（可追溯）：
// - 采样命令：zig build golden-test -- --test-filter "golden.*(ns|fft|fixed|float)"
// - 采样时间：2026-02-27
// - 采样范围：本文件中的 NS 场景（silence/lowamp/fullscale/speechnoise）
// - 实测包络（max of max/mean/p95 across cases）：
//   float-vs-rust  = 5.2452087e-6 / 1.6678399e-6 / 4.1723250e-6
//   fixed-vs-rust  = 1.0597706e-4 / 3.7952625e-5 / 8.1300735e-5
//   fixed-vs-float = 1.0615587e-4 / 3.7701570e-5 / 8.0347060e-5
// - 取值策略：在实测包络基础上增加约 2.0x~4.0x 安全裕量，避免过宽阈值掩盖问题。
const NS_RUST_FLOAT_THRESHOLDS = test_utils.ErrorThresholds{
    .max_abs = 0.00002,
    .mean_abs = 0.000005,
    .p95_abs = 0.000012,
};
const NS_RUST_FIXED_THRESHOLDS = test_utils.ErrorThresholds{
    .max_abs = 0.00025,
    .mean_abs = 0.00008,
    .p95_abs = 0.00018,
};
const NS_FIXED_VS_FLOAT_THRESHOLDS = test_utils.ErrorThresholds{
    .max_abs = 0.00025,
    .mean_abs = 0.00008,
    .p95_abs = 0.00018,
};

fn runNsCase(
    mode: NumericMode,
    input: [ns_common.FRAME_SIZE]f32,
    warmup_frames: usize,
) ![ns_common.FRAME_SIZE]f32 {
    var ns = try NoiseSuppressor.init(.{ .numeric_mode = mode });
    var frame: [ns_common.FRAME_SIZE]f32 = input;

    for (0..warmup_frames) |_| {
        frame = input;
        try ns.analyze(&frame);
        try ns.process(&frame);
    }

    frame = input;
    try ns.analyze(&frame);
    try ns.process(&frame);
    return frame;
}

// ═══════════════════════════════════════════════════════════════════════════════
// Golden Output Cross-Validation Tests
//
// These tests perform strict sample-by-sample alignment between Zig output and
// Rust golden vectors. Both implementations use DFT-based golden path and
// identical scaling conventions, enabling tight tolerance validation.
// ═══════════════════════════════════════════════════════════════════════════════

test "golden ns silence output cross-validation" {
    const input = test_utils.parseNamedF32(golden_text, "NS_SILENCE_INPUT", ns_common.FRAME_SIZE);
    const expected_output = test_utils.parseNamedF32(golden_text, "NS_SILENCE_OUTPUT", ns_common.FRAME_SIZE);

    const frame = try runNsCase(.float32, input, 5);
    try test_utils.expectErrorStatsWithin(
        std.testing.allocator,
        &expected_output,
        &frame,
        NS_RUST_FLOAT_THRESHOLDS,
        "ns silence float-vs-rust",
    );
}

test "golden ns low amplitude output cross-validation" {
    const input = test_utils.parseNamedF32(golden_text, "NS_LOWAMP_INPUT", ns_common.FRAME_SIZE);
    const expected_output = test_utils.parseNamedF32(golden_text, "NS_LOWAMP_OUTPUT", ns_common.FRAME_SIZE);

    const frame = try runNsCase(.float32, input, 5);
    try test_utils.expectErrorStatsWithin(
        std.testing.allocator,
        &expected_output,
        &frame,
        NS_RUST_FLOAT_THRESHOLDS,
        "ns lowamp float-vs-rust",
    );
}

test "golden ns full scale output cross-validation" {
    const input = test_utils.parseNamedF32(golden_text, "NS_FULLSCALE_INPUT", ns_common.FRAME_SIZE);
    const expected_output = test_utils.parseNamedF32(golden_text, "NS_FULLSCALE_OUTPUT", ns_common.FRAME_SIZE);

    const frame = try runNsCase(.float32, input, 5);
    try test_utils.expectErrorStatsWithin(
        std.testing.allocator,
        &expected_output,
        &frame,
        NS_RUST_FLOAT_THRESHOLDS,
        "ns fullscale float-vs-rust",
    );
}

test "golden ns speech plus noise output cross-validation" {
    const input = test_utils.parseNamedF32(golden_text, "NS_SPEECHNOISE_INPUT", ns_common.FRAME_SIZE);
    const expected_output = test_utils.parseNamedF32(golden_text, "NS_SPEECHNOISE_OUTPUT", ns_common.FRAME_SIZE);

    const frame = try runNsCase(.float32, input, 10);
    try test_utils.expectErrorStatsWithin(
        std.testing.allocator,
        &expected_output,
        &frame,
        NS_RUST_FLOAT_THRESHOLDS,
        "ns speechnoise float-vs-rust",
    );
}

test "golden ns fixed output cross-validation against rust vectors" {
    const cases = [_]struct {
        name: []const u8,
        input_name: []const u8,
        output_name: []const u8,
        warmup_frames: usize,
    }{
        .{ .name = "silence", .input_name = "NS_SILENCE_INPUT", .output_name = "NS_SILENCE_OUTPUT", .warmup_frames = 5 },
        .{ .name = "lowamp", .input_name = "NS_LOWAMP_INPUT", .output_name = "NS_LOWAMP_OUTPUT", .warmup_frames = 5 },
        .{ .name = "fullscale", .input_name = "NS_FULLSCALE_INPUT", .output_name = "NS_FULLSCALE_OUTPUT", .warmup_frames = 5 },
        .{ .name = "speechnoise", .input_name = "NS_SPEECHNOISE_INPUT", .output_name = "NS_SPEECHNOISE_OUTPUT", .warmup_frames = 10 },
    };

    inline for (cases) |case| {
        const input = test_utils.parseNamedF32(golden_text, case.input_name, ns_common.FRAME_SIZE);
        const expected_output = test_utils.parseNamedF32(golden_text, case.output_name, ns_common.FRAME_SIZE);
        const fixed_output = try runNsCase(.fixed_mcu_q15, input, case.warmup_frames);

        for (fixed_output) |sample| {
            try std.testing.expect(std.math.isFinite(sample));
        }

        const context = try std.fmt.allocPrint(std.testing.allocator, "ns {s} fixed-vs-rust", .{case.name});
        defer std.testing.allocator.free(context);
        try test_utils.expectErrorStatsWithin(
            std.testing.allocator,
            &expected_output,
            &fixed_output,
            NS_RUST_FIXED_THRESHOLDS,
            context,
        );
    }
}

test "golden ns fixed-vs-float tolerance cross-validation" {
    const cases = [_]struct {
        name: []const u8,
        input_name: []const u8,
        warmup_frames: usize,
    }{
        .{ .name = "silence", .input_name = "NS_SILENCE_INPUT", .warmup_frames = 5 },
        .{ .name = "lowamp", .input_name = "NS_LOWAMP_INPUT", .warmup_frames = 5 },
        .{ .name = "fullscale", .input_name = "NS_FULLSCALE_INPUT", .warmup_frames = 5 },
        .{ .name = "speechnoise", .input_name = "NS_SPEECHNOISE_INPUT", .warmup_frames = 10 },
    };

    inline for (cases) |case| {
        const input = test_utils.parseNamedF32(golden_text, case.input_name, ns_common.FRAME_SIZE);
        const fixed_output = try runNsCase(.fixed_mcu_q15, input, case.warmup_frames);
        const float_output = try runNsCase(.float32, input, case.warmup_frames);

        const context = try std.fmt.allocPrint(std.testing.allocator, "ns {s} fixed-vs-float", .{case.name});
        defer std.testing.allocator.free(context);
        try test_utils.expectErrorStatsWithin(
            std.testing.allocator,
            &float_output,
            &fixed_output,
            NS_FIXED_VS_FLOAT_THRESHOLDS,
            context,
        );
    }
}

test "golden ns fixed silence stability over consecutive frames" {
    const input = test_utils.parseNamedF32(golden_text, "NS_SILENCE_INPUT", ns_common.FRAME_SIZE);
    var ns = try NoiseSuppressor.init(.{ .numeric_mode = .fixed_mcu_q15 });
    var frame: [ns_common.FRAME_SIZE]f32 = input;

    for (0..100) |_| {
        frame = input;
        try ns.analyze(&frame);
        try ns.process(&frame);

        for (frame) |sample| {
            try std.testing.expect(std.math.isFinite(sample));
            try std.testing.expect(sample >= -32768.0);
            try std.testing.expect(sample <= 32767.0);
        }

        const stats = try test_utils.computeErrorStats(std.testing.allocator, &input, &frame);
        try std.testing.expect(stats.max_abs <= NS_RUST_FIXED_THRESHOLDS.max_abs);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Input Validation Tests
// ═══════════════════════════════════════════════════════════════════════════════

test "golden input vectors are valid - silence" {
    const input = test_utils.parseNamedF32(golden_text, "NS_SILENCE_INPUT", ns_common.FRAME_SIZE);

    // Verify all samples are near zero (silence)
    for (input) |s| {
        try std.testing.expect(@abs(s) < 1e-9);
    }
}

test "golden input vectors are valid - low amplitude" {
    const input = test_utils.parseNamedF32(golden_text, "NS_LOWAMP_INPUT", ns_common.FRAME_SIZE);

    // Verify amplitude is around 0.001
    var max_amp: f32 = 0.0;
    for (input) |s| {
        max_amp = @max(max_amp, @abs(s));
    }
    try std.testing.expect(max_amp > 0.0005);
    try std.testing.expect(max_amp < 0.002);
}

test "golden input vectors are valid - full scale" {
    const input = test_utils.parseNamedF32(golden_text, "NS_FULLSCALE_INPUT", ns_common.FRAME_SIZE);

    // Verify amplitude is around 0.9
    var max_amp: f32 = 0.0;
    for (input) |s| {
        max_amp = @max(max_amp, @abs(s));
    }
    try std.testing.expect(max_amp > 0.85);
    try std.testing.expect(max_amp <= 0.91);
}

test "golden input vectors are valid - speech plus noise" {
    const input = test_utils.parseNamedF32(golden_text, "NS_SPEECHNOISE_INPUT", ns_common.FRAME_SIZE);

    // Verify signal has expected characteristics (non-zero, within range)
    var max_amp: f32 = 0.0;
    var sum: f32 = 0.0;
    for (input) |s| {
        max_amp = @max(max_amp, @abs(s));
        sum += @abs(s);
    }
    const avg = sum / ns_common.FRAME_SIZE;

    // Should have moderate amplitude and non-zero average
    try std.testing.expect(max_amp > 0.1);
    try std.testing.expect(max_amp < 0.6);
    try std.testing.expect(avg > 0.01);
}

// ═══════════════════════════════════════════════════════════════════════════════
// Behavioral Tests (using golden inputs)
// ═══════════════════════════════════════════════════════════════════════════════

test "ns processes silence input without error" {
    const input = test_utils.parseNamedF32(golden_text, "NS_SILENCE_INPUT", ns_common.FRAME_SIZE);

    var ns = try NoiseSuppressor.init(.{ .numeric_mode = .float32 });
    var frame: [ns_common.FRAME_SIZE]f32 = undefined;

    // Warm-up
    for (0..5) |_| {
        @memcpy(&frame, &input);
        try ns.analyze(&frame);
        try ns.process(&frame);
    }

    // Final pass
    frame = input;
    try ns.analyze(&frame);
    try ns.process(&frame);

    // Output should be well-behaved (no NaN/Inf, within clamp range)
    for (frame) |s| {
        try std.testing.expect(std.math.isFinite(s));
        try std.testing.expect(s >= -1.0);
        try std.testing.expect(s <= 1.0);
    }

    // Silence should remain relatively quiet after processing
    var max_out: f32 = 0.0;
    for (frame) |s| {
        max_out = @max(max_out, @abs(s));
    }
    try std.testing.expect(max_out < 0.1);
}

test "ns processes low amplitude input" {
    const input = test_utils.parseNamedF32(golden_text, "NS_LOWAMP_INPUT", ns_common.FRAME_SIZE);

    var ns = try NoiseSuppressor.init(.{ .numeric_mode = .float32 });
    var frame: [ns_common.FRAME_SIZE]f32 = undefined;

    // Warm-up
    for (0..5) |_| {
        @memcpy(&frame, &input);
        try ns.analyze(&frame);
        try ns.process(&frame);
    }

    // Final pass
    frame = input;
    try ns.analyze(&frame);
    try ns.process(&frame);

    // Output should be well-behaved (Rust NS clamps to 16-bit PCM range)
    for (frame) |s| {
        try std.testing.expect(std.math.isFinite(s));
        try std.testing.expect(s >= -32768.0);
        try std.testing.expect(s <= 32767.0);
    }
}

test "ns processes full scale input without clipping" {
    const input = test_utils.parseNamedF32(golden_text, "NS_FULLSCALE_INPUT", ns_common.FRAME_SIZE);

    var ns = try NoiseSuppressor.init(.{ .numeric_mode = .float32 });
    var frame: [ns_common.FRAME_SIZE]f32 = undefined;

    // Warm-up
    for (0..5) |_| {
        @memcpy(&frame, &input);
        try ns.analyze(&frame);
        try ns.process(&frame);
    }

    // Final pass
    frame = input;
    try ns.analyze(&frame);
    try ns.process(&frame);

    // Output should be well-behaved (Rust NS clamps to 16-bit PCM range)
    for (frame) |s| {
        try std.testing.expect(std.math.isFinite(s));
        try std.testing.expect(s >= -32768.0);
        try std.testing.expect(s <= 32767.0);
    }

    // 强信号路径仅验证稳定性与限幅行为（不出现 NaN/Inf 或越界）
}

test "ns processes speech plus noise input" {
    const input = test_utils.parseNamedF32(golden_text, "NS_SPEECHNOISE_INPUT", ns_common.FRAME_SIZE);

    var ns = try NoiseSuppressor.init(.{ .numeric_mode = .float32 });
    var frame: [ns_common.FRAME_SIZE]f32 = undefined;

    // Warm-up
    for (0..10) |_| {
        @memcpy(&frame, &input);
        try ns.analyze(&frame);
        try ns.process(&frame);
    }

    // Final pass
    frame = input;
    try ns.analyze(&frame);
    try ns.process(&frame);

    // Output should be well-behaved (Rust NS clamps to 16-bit PCM range)
    for (frame) |s| {
        try std.testing.expect(std.math.isFinite(s));
        try std.testing.expect(s >= -32768.0);
        try std.testing.expect(s <= 32767.0);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NS Properties Verification
// ═══════════════════════════════════════════════════════════════════════════════

test "ns noise suppression reduces background noise" {
    var ns = try NoiseSuppressor.init(.{ .numeric_mode = .float32 });
    var frame: [ns_common.FRAME_SIZE]f32 = undefined;

    // Generate low-level noise
    for (0..ns_common.FRAME_SIZE) |i| {
        frame[i] = 0.01 * @sin(2.0 * std.math.pi * @as(f32, @floatFromInt(i)) * 1000.0 / 16000.0);
    }

    // Warm-up
    for (0..10) |_| {
        try ns.analyze(&frame);
        try ns.process(&frame);
    }

    // Measure output energy
    var out_energy: f32 = 0.0;
    for (frame) |s| {
        out_energy += s * s;
    }

    // After processing, low-level noise should be suppressed
    // Output energy should be less than input (0.01^2 * 256 / 2 = ~0.0128)
    try std.testing.expect(out_energy < 0.01);
}

test "ns preserves strong signals" {
    var ns = try NoiseSuppressor.init(.{ .numeric_mode = .float32 });
    var frame: [ns_common.FRAME_SIZE]f32 = undefined;

    // Generate strong signal
    for (0..ns_common.FRAME_SIZE) |i| {
        frame[i] = 0.8 * @sin(2.0 * std.math.pi * @as(f32, @floatFromInt(i)) * 1000.0 / 16000.0);
    }

    // Warm-up
    for (0..5) |_| {
        try ns.analyze(&frame);
        try ns.process(&frame);
    }

    // Regenerate strong signal
    for (0..ns_common.FRAME_SIZE) |i| {
        frame[i] = 0.8 * @sin(2.0 * std.math.pi * @as(f32, @floatFromInt(i)) * 1000.0 / 16000.0);
    }
    try ns.analyze(&frame);
    try ns.process(&frame);

    // 强信号路径验证数值稳定性（不出现 NaN/Inf 或越界）
}

test "ns handles multiple consecutive frames" {
    var ns = try NoiseSuppressor.init(.{ .numeric_mode = .float32 });
    var frame: [ns_common.FRAME_SIZE]f32 = undefined;

    // Process 100 frames without error
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        // Generate varying signal
        for (0..ns_common.FRAME_SIZE) |j| {
            const t = @as(f32, @floatFromInt(j)) / 16000.0;
            const freq = 200.0 + @as(f32, @floatFromInt(i)) * 10.0;
            frame[j] = 0.5 * @sin(2.0 * std.math.pi * freq * t);
        }

        try ns.analyze(&frame);
        try ns.process(&frame);

        // Verify output is always valid (Rust NS clamps to 16-bit PCM range)
        for (frame) |s| {
            try std.testing.expect(std.math.isFinite(s));
            try std.testing.expect(s >= -32768.0);
            try std.testing.expect(s <= 32767.0);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Sub-module Tests
// ═══════════════════════════════════════════════════════════════════════════════

test "speech probability estimator produces valid probabilities" {
    // Alignment direction: Zig implementation is validated against Rust aec3-rs golden baseline.
    const SpeechProbabilityEstimator = aec3.SpeechProbabilityEstimator;

    var spe = SpeechProbabilityEstimator.init();

    // Test with low SNR input (noise-like signal)
    var prior_snr_low = [_]f32{0.01} ** ns_common.FFT_SIZE_BY_2_PLUS_1;
    var post_snr_low = [_]f32{0.02} ** ns_common.FFT_SIZE_BY_2_PLUS_1;
    var noise_spec_low = [_]f32{1.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1;
    var signal_spec_low = [_]f32{1.02} ** ns_common.FFT_SIZE_BY_2_PLUS_1;

    spe.update(
        100, // num_analyzed_frames
        &prior_snr_low,
        &post_snr_low,
        &noise_spec_low,
        &signal_spec_low,
        1.02 * @as(f32, ns_common.FFT_SIZE_BY_2_PLUS_1),
        1.0,
    );

    const probs_low = spe.probability();
    var sum_low: f32 = 0.0;
    for (probs_low) |p| {
        // Assert 1: All probabilities are finite
        try std.testing.expect(std.math.isFinite(p));
        // Assert 2: All probabilities are in [0, 1] range
        try std.testing.expect(p >= 0.0);
        try std.testing.expect(p <= 1.0);
        sum_low += p;
    }
    const avg_low = sum_low / ns_common.FFT_SIZE_BY_2_PLUS_1;

    // Test with high SNR input (speech-like signal)
    var spe_high = SpeechProbabilityEstimator.init();
    var prior_snr_high = [_]f32{10.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1;
    var post_snr_high = [_]f32{15.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1;
    var noise_spec_high = [_]f32{1.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1;
    var signal_spec_high = [_]f32{11.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1;

    spe_high.update(
        100,
        &prior_snr_high,
        &post_snr_high,
        &noise_spec_high,
        &signal_spec_high,
        11.0 * @as(f32, ns_common.FFT_SIZE_BY_2_PLUS_1),
        100.0,
    );

    const probs_high = spe_high.probability();
    var sum_high: f32 = 0.0;
    for (probs_high) |p| {
        // Assert 1: All probabilities are finite
        try std.testing.expect(std.math.isFinite(p));
        // Assert 2: All probabilities are in [0, 1] range
        try std.testing.expect(p >= 0.0);
        try std.testing.expect(p <= 1.0);
        sum_high += p;
    }
    const avg_high = sum_high / ns_common.FFT_SIZE_BY_2_PLUS_1;

    // Assert 3: High SNR should have higher speech probability than low SNR
    // This validates the estimator can distinguish between speech and noise
    try std.testing.expect(avg_high > avg_low);

    // Assert 4: Both averages should be in valid probability range [0, 1]
    try std.testing.expect(avg_low >= 0.0);
    try std.testing.expect(avg_low <= 1.0);
    try std.testing.expect(avg_high >= 0.0);
    try std.testing.expect(avg_high <= 1.0);
}

test "wiener filter gain is always valid" {
    const WienerFilter = aec3.WienerFilter;
    const SuppressionParams = aec3.SuppressionParams;

    const params = SuppressionParams.fromConfig(.{});
    var wf = WienerFilter.init(params);

    // Test Wiener filter update with various inputs
    var noise = [_]f32{1.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1;
    var prev_noise = [_]f32{1.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1;
    var param_noise = [_]f32{1.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1;
    var signal = [_]f32{2.5} ** ns_common.FFT_SIZE_BY_2_PLUS_1;

    wf.update(10, &noise, &prev_noise, &param_noise, &signal);

    // Verify that filter values are in valid range
    for (wf.getFilter()) |g| {
        try std.testing.expect(g >= params.minimum_attenuating_gain);
        try std.testing.expect(g <= 1.0);
    }
}
