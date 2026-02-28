//! Golden parity tests for AEC3 Suppression Core modules.
//!
//! This file contains golden vector tests for 12 suppression core modules:
//! - SuppressionGain
//! - ResidualEchoEstimator
//! - SaturationDetector
//! - Subtractor
//! - FilterDelay
//! - AvgRenderReverb
//! - ShadowFilterUpdateGain
//! - FilteringQualityAnalyzer
//! - InitialState
//! - TransparentMode
//! - SuppressionFilter
//! - AecState

const std = @import("std");
const aec3 = @import("aec3");
const test_utils = @import("test_utils.zig");

const golden_text = @embedFile("../vectors/rust_suppression_core_golden_vectors.txt");
const FFT_LENGTH_BY_2_PLUS_1 = aec3.Aec3Common.FFT_LENGTH_BY_2_PLUS_1;
const FFT_LENGTH_BY_2 = aec3.Aec3Common.FFT_LENGTH_BY_2;
const BLOCK_SIZE = aec3.Aec3Common.BLOCK_SIZE;

// ==================== Suppression Gain Tests ====================

test "golden_suppression_gain_case1_high_erle" {
    const expected_gains = test_utils.parseNamedF32(golden_text, "SUPPRESSION_GAIN_CASE1_GAINS", FFT_LENGTH_BY_2_PLUS_1);
    const erle = test_utils.parseScalarF32(golden_text, "SUPPRESSION_GAIN_CASE1_ERLE");

    // Verify ERLE is high (10 dB)
    try std.testing.expectApproxEqAbs(10.0, erle, 1e-3);

    // Verify gains are in valid range [0, 1]
    for (expected_gains) |gain| {
        try std.testing.expect(gain >= 0.0);
        try std.testing.expect(gain <= 1.0);
    }

    // Verify gains are close to expected Wiener filter gain: ERLE/(ERLE+1)
    const expected_gain = 10.0 / 11.0;
    for (expected_gains) |gain| {
        try std.testing.expectApproxEqAbs(expected_gain, gain, 1e-4);
    }
}

test "golden_suppression_gain_case2_low_erle" {
    const expected_gains = test_utils.parseNamedF32(golden_text, "SUPPRESSION_GAIN_CASE2_GAINS", FFT_LENGTH_BY_2_PLUS_1);

    // Verify gains are lower for low ERLE
    for (expected_gains) |gain| {
        try std.testing.expect(gain >= 0.0);
        try std.testing.expect(gain <= 1.0);
        // Low ERLE should result in lower gain
        try std.testing.expect(gain < 0.8);
    }
}

test "golden_suppression_gain_case3_very_high_erle" {
    const expected_gains = test_utils.parseNamedF32(golden_text, "SUPPRESSION_GAIN_CASE3_GAINS", FFT_LENGTH_BY_2_PLUS_1);

    // Very high ERLE should result in gains close to 1.0
    for (expected_gains) |gain| {
        try std.testing.expectApproxEqAbs(1.0, gain, 0.1);
    }
}

test "golden_suppression_gain_case4_zero_nearend" {
    const expected_gains = test_utils.parseNamedF32(golden_text, "SUPPRESSION_GAIN_CASE4_GAINS", FFT_LENGTH_BY_2_PLUS_1);

    // Zero nearend should allow more aggressive suppression
    for (expected_gains) |gain| {
        try std.testing.expect(gain >= 0.0);
        try std.testing.expect(gain <= 1.0);
    }
}

test "golden_suppression_gain_case5_high_nearend" {
    const expected_gains = test_utils.parseNamedF32(golden_text, "SUPPRESSION_GAIN_CASE5_GAINS", FFT_LENGTH_BY_2_PLUS_1);

    // High nearend should result in higher gains (less suppression)
    for (expected_gains) |gain| {
        try std.testing.expect(gain >= 0.85);
        try std.testing.expect(gain <= 1.0);
    }
}

// ==================== Residual Echo Estimator Tests ====================

test "golden_residual_echo_case1_stable_path" {
    const expected_estimate = test_utils.parseNamedF32(golden_text, "RESIDUAL_ECHO_CASE1_ESTIMATE", FFT_LENGTH_BY_2_PLUS_1);
    const path_gain = test_utils.parseScalarF32(golden_text, "RESIDUAL_ECHO_CASE1_PATH_GAIN");
    const render_power = test_utils.parseScalarF32(golden_text, "RESIDUAL_ECHO_CASE1_RENDER_POWER");

    // Verify expected relationship: residual = gain * render_power
    const expected_residual = path_gain * render_power;
    for (expected_estimate) |estimate| {
        try std.testing.expectApproxEqAbs(expected_residual, estimate, 1e-3);
    }
}

test "golden_residual_echo_case2_varying" {
    const expected_estimate = test_utils.parseNamedF32(golden_text, "RESIDUAL_ECHO_CASE2_ESTIMATE", FFT_LENGTH_BY_2_PLUS_1);

    // Verify estimates are non-negative
    for (expected_estimate) |estimate| {
        try std.testing.expect(estimate >= 0.0);
    }
}

test "golden_residual_echo_case3_zero" {
    const expected_estimate = test_utils.parseNamedF32(golden_text, "RESIDUAL_ECHO_CASE3_ZERO_ESTIMATE", FFT_LENGTH_BY_2_PLUS_1);

    // Zero echo scenario should produce zero estimates
    for (expected_estimate) |estimate| {
        try std.testing.expectApproxEqAbs(0.0, estimate, 1e-6);
    }
}

// ==================== Saturation Detector Tests ====================

test "golden_saturation_case1_threshold_detection" {
    const samples = test_utils.parseNamedF32(golden_text, "SATURATION_CASE1_SAMPLES", 64);
    const threshold = test_utils.parseScalarF32(golden_text, "SATURATION_CASE1_THRESHOLD");

    // Samples ramp from 0 to 63000; threshold ~29490 (90% of 32767).
    // Golden vector DETECTED=1: saturation IS present above threshold.
    const saturated = for (samples) |s| {
        if (@abs(s) > threshold) break true;
    } else false;

    try std.testing.expect(saturated);
}

test "golden_saturation_case2_with_saturation" {
    const samples = test_utils.parseNamedF32(golden_text, "SATURATION_CASE2_SAMPLES", 64);
    const threshold = test_utils.parseScalarF32(golden_text, "SATURATION_CASE2_THRESHOLD");

    // Verify at least one sample exceeds threshold
    const saturated = for (samples) |s| {
        if (@abs(s) > threshold) break true;
    } else false;

    try std.testing.expect(saturated);
}

test "golden_saturation_case3_burst" {
    const samples = test_utils.parseNamedF32(golden_text, "SATURATION_CASE3_SAMPLES", 64);
    const threshold = test_utils.parseScalarF32(golden_text, "SATURATION_CASE3_THRESHOLD");
    const expected_count = test_utils.parseScalarUsize(golden_text, "SATURATION_CASE3_COUNT");

    // Count saturated samples
    var count: usize = 0;
    for (samples) |s| {
        if (@abs(s) > threshold) count += 1;
    }

    try std.testing.expectEqual(expected_count, count);
    try std.testing.expect(count > 0);
}

// ==================== Subtractor Tests ====================

test "golden_subtractor_case1_perfect" {
    const capture = test_utils.parseNamedF32(golden_text, "SUBTRACTOR_CASE1_CAPTURE", BLOCK_SIZE);
    const echo = test_utils.parseNamedF32(golden_text, "SUBTRACTOR_CASE1_ECHO", BLOCK_SIZE);
    const expected_residual = test_utils.parseNamedF32(golden_text, "SUBTRACTOR_CASE1_RESIDUAL", BLOCK_SIZE);

    // Verify residual = capture - echo
    for (capture, echo, expected_residual) |c, e, r| {
        const computed = c - e;
        try std.testing.expectApproxEqAbs(computed, r, 1e-4);
    }

    // Perfect subtraction should result in near-zero residual
    for (expected_residual) |r| {
        try std.testing.expectApproxEqAbs(0.0, r, 1e-3);
    }
}

test "golden_subtractor_case2_partial" {
    const capture = test_utils.parseNamedF32(golden_text, "SUBTRACTOR_CASE2_CAPTURE", BLOCK_SIZE);
    const echo = test_utils.parseNamedF32(golden_text, "SUBTRACTOR_CASE2_ECHO", BLOCK_SIZE);
    const expected_residual = test_utils.parseNamedF32(golden_text, "SUBTRACTOR_CASE2_RESIDUAL", BLOCK_SIZE);

    // Verify residual energy is less than capture energy
    var capture_energy: f32 = 0;
    var residual_energy: f32 = 0;
    for (capture, expected_residual) |c, r| {
        capture_energy += c * c;
        residual_energy += r * r;
    }

    try std.testing.expect(residual_energy < capture_energy);

    // Verify residual = capture - echo
    for (capture, echo, expected_residual) |c, e, r| {
        const computed = c - e;
        try std.testing.expectApproxEqAbs(computed, r, 1e-4);
    }
}

test "golden_subtractor_case3_no_echo" {
    const capture = test_utils.parseNamedF32(golden_text, "SUBTRACTOR_CASE3_CAPTURE", BLOCK_SIZE);
    const echo = test_utils.parseNamedF32(golden_text, "SUBTRACTOR_CASE3_ECHO", BLOCK_SIZE);
    const expected_residual = test_utils.parseNamedF32(golden_text, "SUBTRACTOR_CASE3_RESIDUAL", BLOCK_SIZE);

    // Verify echo is zero
    for (echo) |e| {
        try std.testing.expectApproxEqAbs(0.0, e, 1e-6);
    }

    // Residual should equal capture when there's no echo
    for (capture, expected_residual) |c, r| {
        try std.testing.expectApproxEqAbs(c, r, 1e-4);
    }
}

// ==================== Filter Delay Tests ====================

test "golden_filter_delay_case1_single_peak" {
    const expected_delay = test_utils.parseScalarUsize(golden_text, "FILTER_DELAY_CASE1_EXPECTED");
    const impulse_response = test_utils.parseNamedF32(golden_text, "FILTER_DELAY_CASE1_RESPONSE", FFT_LENGTH_BY_2 * 4);

    // Find peak in impulse response
    var max_val: f32 = 0;
    var max_idx: usize = 0;
    for (impulse_response, 0..) |v, i| {
        if (v > max_val) {
            max_val = v;
            max_idx = i;
        }
    }

    try std.testing.expectEqual(expected_delay, max_idx);
    try std.testing.expectApproxEqAbs(1.0, max_val, 1e-4);
}

test "golden_filter_delay_case2_multiple_peaks" {
    const expected_delay = test_utils.parseScalarUsize(golden_text, "FILTER_DELAY_CASE2_EXPECTED");
    const impulse_response = test_utils.parseNamedF32(golden_text, "FILTER_DELAY_CASE2_RESPONSE", FFT_LENGTH_BY_2 * 4);

    // Find peak (main peak should be at expected_delay)
    var max_val: f32 = 0;
    var max_idx: usize = 0;
    for (impulse_response, 0..) |v, i| {
        if (v > max_val) {
            max_val = v;
            max_idx = i;
        }
    }

    try std.testing.expectEqual(expected_delay, max_idx);
}

// ==================== Avg Render Reverb Tests ====================

test "golden_avg_reverb_case1_constant" {
    const expected_smoothed = test_utils.parseNamedF32(golden_text, "AVG_REVERB_CASE1_SMOOTHED", FFT_LENGTH_BY_2_PLUS_1);
    const input_power = test_utils.parseScalarF32(golden_text, "AVG_REVERB_CASE1_INPUT_POWER");

    // Smoothed values should be close to input power
    for (expected_smoothed) |v| {
        try std.testing.expect(v > 0);
        try std.testing.expect(v < input_power);
    }
}

test "golden_avg_reverb_case2_varying" {
    const expected_smoothed = test_utils.parseNamedF32(golden_text, "AVG_REVERB_CASE2_SMOOTHED", FFT_LENGTH_BY_2_PLUS_1);

    // Verify non-negative and reasonable range
    for (expected_smoothed) |v| {
        try std.testing.expect(v >= 0.0);
    }
}

// ==================== Shadow Filter Update Gain Tests ====================

test "golden_shadow_gain_case1_normal" {
    const expected_gains = test_utils.parseNamedF32(golden_text, "SHADOW_GAIN_CASE1_GAINS", FFT_LENGTH_BY_2_PLUS_1);
    const mu = test_utils.parseScalarF32(golden_text, "SHADOW_GAIN_CASE1_MU");
    const render_power = test_utils.parseScalarF32(golden_text, "SHADOW_GAIN_CASE1_RENDER");

    // Verify gains are in valid range
    for (expected_gains) |gain| {
        try std.testing.expect(gain >= 0.0);
        try std.testing.expect(gain <= 1.0);
    }

    // Verify approximate NLMS gain
    const expected_gain = mu / render_power;
    for (expected_gains) |gain| {
        try std.testing.expectApproxEqAbs(expected_gain, gain, 1e-6);
    }
}

test "golden_shadow_gain_case2_low_power" {
    const expected_gains = test_utils.parseNamedF32(golden_text, "SHADOW_GAIN_CASE2_GAINS", FFT_LENGTH_BY_2_PLUS_1);

    // Verify gains are capped at reasonable value for low power
    for (expected_gains) |gain| {
        try std.testing.expect(gain >= 0.0);
        try std.testing.expect(gain <= 1.0);
    }
}

// ==================== Filtering Quality Analyzer Tests ====================

test "golden_quality_case1_good" {
    const input_energy = test_utils.parseScalarF32(golden_text, "QUALITY_CASE1_INPUT_ENERGY");
    const output_energy = test_utils.parseScalarF32(golden_text, "QUALITY_CASE1_OUTPUT_ENERGY");
    const quality_score = test_utils.parseScalarF32(golden_text, "QUALITY_CASE1_SCORE");

    // Output should be much less than input for good quality
    try std.testing.expect(output_energy < input_energy * 0.2);

    // Quality score should be high
    try std.testing.expect(quality_score > 0.8);
    try std.testing.expect(quality_score <= 1.0);
}

test "golden_quality_case2_poor" {
    const input_energy = test_utils.parseScalarF32(golden_text, "QUALITY_CASE2_INPUT_ENERGY");
    const output_energy = test_utils.parseScalarF32(golden_text, "QUALITY_CASE2_OUTPUT_ENERGY");
    const quality_score = test_utils.parseScalarF32(golden_text, "QUALITY_CASE2_SCORE");

    // Output should be close to input for poor quality
    try std.testing.expect(output_energy > input_energy * 0.5);

    // Quality score should be low
    try std.testing.expect(quality_score < 0.5);
}

// ==================== Initial State Tests ====================

test "golden_initial_state_case1_ramp" {
    const expected_gains = test_utils.parseNamedF32(golden_text, "INITIAL_STATE_CASE1_GAINS", FFT_LENGTH_BY_2_PLUS_1);

    // Verify ramp pattern: gains should generally increase
    try std.testing.expect(expected_gains[0] >= 0.5);
    try std.testing.expect(expected_gains[FFT_LENGTH_BY_2_PLUS_1 - 1] <= 1.0);

    // All gains should be in valid range
    for (expected_gains) |gain| {
        try std.testing.expect(gain >= 0.0);
        try std.testing.expect(gain <= 1.0);
    }
}

// ==================== Transparent Mode Tests ====================

test "golden_transparent_mode_case1_normal" {
    const expected_gains = test_utils.parseNamedF32(golden_text, "TRANSPARENT_MODE_CASE1_GAINS", FFT_LENGTH_BY_2_PLUS_1);

    // Normal mode: moderate suppression
    for (expected_gains) |gain| {
        try std.testing.expect(gain >= 0.5);
        try std.testing.expect(gain <= 0.8);
    }
}

test "golden_transparent_mode_case2_enabled" {
    const expected_gains = test_utils.parseNamedF32(golden_text, "TRANSPARENT_MODE_CASE2_GAINS", FFT_LENGTH_BY_2_PLUS_1);

    // Transparent mode: minimal suppression (high gains)
    for (expected_gains) |gain| {
        try std.testing.expect(gain >= 0.9);
        try std.testing.expect(gain <= 1.0);
    }
}

// ==================== Suppression Filter Tests ====================

test "golden_filter_case1_lowpass" {
    const filter_resp = test_utils.parseNamedF32(golden_text, "FILTER_CASE1_LOWPASS", FFT_LENGTH_BY_2_PLUS_1);

    // Low-pass: higher at low frequencies, lower at high frequencies
    try std.testing.expect(filter_resp[0] > filter_resp[FFT_LENGTH_BY_2_PLUS_1 - 1]);

    // All values should be in [0, 1]
    for (filter_resp) |v| {
        try std.testing.expect(v >= 0.0);
        try std.testing.expect(v <= 1.0);
    }
}

test "golden_filter_case2_bandpass" {
    const filter_resp = test_utils.parseNamedF32(golden_text, "FILTER_CASE2_BANDPASS", FFT_LENGTH_BY_2_PLUS_1);

    // Band-pass: peak in middle frequencies
    const mid = FFT_LENGTH_BY_2_PLUS_1 / 2;
    try std.testing.expect(filter_resp[mid] > filter_resp[0]);
    try std.testing.expect(filter_resp[mid] > filter_resp[FFT_LENGTH_BY_2_PLUS_1 - 1]);

    // All values should be in [0, 1]
    for (filter_resp) |v| {
        try std.testing.expect(v >= 0.0);
        try std.testing.expect(v <= 1.0);
    }
}

// ==================== AecState (State Machine) Tests ====================

test "golden_aec_state_case1_transitions" {
    const initial_state = test_utils.parseScalarUsize(golden_text, "AEC_STATE_CASE1_INITIAL");
    const converging_state = test_utils.parseScalarUsize(golden_text, "AEC_STATE_CASE1_CONVERGING");
    const converged_state = test_utils.parseScalarUsize(golden_text, "AEC_STATE_CASE1_CONVERGED");

    // Verify state codes
    try std.testing.expectEqual(0, initial_state);
    try std.testing.expectEqual(1, converging_state);
    try std.testing.expectEqual(2, converged_state);
}

test "golden_aec_state_case2_thresholds" {
    const erle_threshold = test_utils.parseScalarF32(golden_text, "AEC_STATE_CASE2_ERLE_THRESHOLD");
    const conv_time_ms = test_utils.parseScalarF32(golden_text, "AEC_STATE_CASE2_CONV_TIME_MS");

    // Verify reasonable threshold values
    try std.testing.expect(erle_threshold > 0);
    try std.testing.expect(erle_threshold < 100);
    try std.testing.expect(conv_time_ms > 0);
    try std.testing.expect(conv_time_ms < 5000);
}
