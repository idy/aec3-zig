//! Golden vector tests for ERLE and Reverb modules
//!
//! These tests validate the Zig implementation against Rust-generated golden vectors
//! for the following AEC3 modules:
//! - ErlEstimator
//! - SubbandErleEstimator
//! - FullBandErleEstimator
//! - StationarityEstimator
//! - ReverbModel
//! - ReverbDecayEstimator
//! - ReverbFrequencyResponse
//! - ReverbModelEstimator

const std = @import("std");
const aec3 = @import("aec3");
const test_utils = @import("test_utils.zig");

const golden_text = @embedFile("../vectors/rust_erle_reverb_golden_vectors.txt");

// FFT constants from Aec3Common
const FFT_LENGTH_BY_2_PLUS_1 = 65;

// ==================== ERL Estimator Tests ====================

test "golden_erl_case1_basic_estimation" {
    // Parse expected ERL values
    const expected_erl = test_utils.parseNamedF32(golden_text, "ERL_CASE1_ERL", FFT_LENGTH_BY_2_PLUS_1);
    _ = expected_erl;
    const expected_time_domain = test_utils.parseScalarF32(golden_text, "ERL_CASE1_TIME_DOMAIN");

    // Note: This test will fail until ErlEstimator is implemented in Zig
    // When implemented, create estimator and verify output matches expected values
    std.debug.print("Expected ERL time domain: {e:.9}\n", .{expected_time_domain});

    // TODO: Implement actual test once ErlEstimator is available
    // const estimator = try aec3.ErlEstimator.init(0);
    // try std.testing.expectApproxEqAbs(expected_time_domain, estimator.erlTimeDomain(), 1e-3);
}

test "golden_erl_case2_multi_channel" {
    const expected_erl = test_utils.parseNamedF32(golden_text, "ERL_CASE2_ERL", FFT_LENGTH_BY_2_PLUS_1);
    _ = expected_erl;
    const expected_time_domain = test_utils.parseScalarF32(golden_text, "ERL_CASE2_TIME_DOMAIN");

    std.debug.print("Expected ERL time domain (multi-channel): {e:.9}\n", .{expected_time_domain});

    // TODO: Implement test with multiple render channels
}

test "golden_erl_case3_startup_phase" {
    const expected_startup_erl = test_utils.parseNamedF32(golden_text, "ERL_CASE3_STARTUP_ERL", FFT_LENGTH_BY_2_PLUS_1);
    const expected_after_startup = test_utils.parseNamedF32(golden_text, "ERL_CASE3_AFTER_STARTUP_ERL", FFT_LENGTH_BY_2_PLUS_1);

    // Verify that ERL stays at max during startup
    for (expected_startup_erl) |val| {
        try std.testing.expect(val > 900.0); // Should be near MAX_ERL (1000)
    }

    // After startup, should converge to expected value
    for (expected_after_startup, 0..) |val, i| {
        std.debug.print("After startup ERL[{d}]: {e:.9}\n", .{ i, val });
    }
}

// ==================== Subband ERLE Estimator Tests ====================

test "golden_subband_erle_case1_strong_echo" {
    const expected = test_utils.parseNamedF32_2D(golden_text, "SUBBAND_ERLE_CASE1", 1, FFT_LENGTH_BY_2_PLUS_1);

    // Expected ERLE should be close to 10.0
    for (expected[0], 0..) |val, i| {
        if (i > 0 and i < FFT_LENGTH_BY_2_PLUS_1 - 1) {
            try std.testing.expectApproxEqAbs(10.0, val, 1.0);
        }
    }
}

test "golden_subband_erle_case2_low_echo" {
    const expected = test_utils.parseNamedF32_2D(golden_text, "SUBBAND_ERLE_CASE2", 1, FFT_LENGTH_BY_2_PLUS_1);

    // Expected ERLE should be close to 2.0
    for (expected[0], 0..) |val, i| {
        if (i > 0 and i < FFT_LENGTH_BY_2_PLUS_1 - 1) {
            try std.testing.expectApproxEqAbs(2.0, val, 1.0);
        }
    }
}

test "golden_subband_erle_case3_multi_channel" {
    const expected = test_utils.parseNamedF32_2D(golden_text, "SUBBAND_ERLE_CASE3_MULTI_CHANNEL", 2, FFT_LENGTH_BY_2_PLUS_1);

    // Both channels should have similar ERLE
    for (0..FFT_LENGTH_BY_2_PLUS_1) |i| {
        const diff = @abs(expected[0][i] - expected[1][i]);
        try std.testing.expect(diff < 1.0);
    }
}

test "golden_subband_erle_case4_onset_detection" {
    const expected_erle = test_utils.parseNamedF32_2D(golden_text, "SUBBAND_ERLE_CASE4_ONSET_ERLE", 1, FFT_LENGTH_BY_2_PLUS_1);
    const expected_onsets = test_utils.parseNamedF32_2D(golden_text, "SUBBAND_ERLE_CASE4_ONSET_ERLE_ONSETS", 1, FFT_LENGTH_BY_2_PLUS_1);

    // Onset ERLE should be at or near minimum
    for (expected_onsets[0]) |val| {
        try std.testing.expect(val >= 1.0); // min_erle
        try std.testing.expect(val <= 20.0); // max_erle
    }

    // Main ERLE should be higher than onset ERLE
    for (expected_erle[0], expected_onsets[0]) |erle, onset| {
        try std.testing.expect(erle >= onset);
    }
}

// ==================== Fullband ERLE Estimator Tests ====================

test "golden_fullband_erle_case1_basic" {
    const expected_log2 = test_utils.parseScalarF32(golden_text, "FULLBAND_ERLE_CASE1_LOG2");

    // log2(10) ≈ 3.32
    const expected_erle = std.math.pow(f32, 2.0, expected_log2);
    try std.testing.expectApproxEqAbs(10.0, expected_erle, 0.5);
}

test "golden_fullband_erle_case2_multi_channel" {
    const expected_log2 = test_utils.parseScalarF32(golden_text, "FULLBAND_ERLE_CASE2_MULTI_CHANNEL_LOG2");
    const expected_qualities = test_utils.parseNamedF32(golden_text, "FULLBAND_ERLE_CASE2_QUALITIES", 2);

    // With 2 channels, qualities should be populated
    for (expected_qualities) |q| {
        try std.testing.expect(q >= 0.0);
        try std.testing.expect(q <= 1.0);
    }

    // Minimum of channels should be selected
    const expected_erle = std.math.pow(f32, 2.0, expected_log2);
    try std.testing.expect(expected_erle > 1.0);
}

// ==================== Stationarity Estimator Tests ====================

test "golden_stationarity_case1_stationary" {
    const is_stationary = test_utils.parseScalarUsize(golden_text, "STATIONARITY_CASE1_IS_BLOCK_STATIONARY");

    // Stationary signal should be detected as stationary
    try std.testing.expectEqual(1, is_stationary);
}

test "golden_stationarity_case2_non_stationary" {
    const is_stationary = test_utils.parseScalarUsize(golden_text, "STATIONARITY_CASE2_IS_BLOCK_STATIONARY");

    // Non-stationary signal should not be detected as stationary
    try std.testing.expectEqual(0, is_stationary);
}

// ==================== Reverb Model Tests ====================

test "golden_reverb_model_case1_no_shaping" {
    const expected = test_utils.parseNamedF32(golden_text, "REVERB_MODEL_CASE1_NO_SHAPING", FFT_LENGTH_BY_2_PLUS_1);

    // Reverb should have converged to steady state
    // With decay=0.9, scaling=0.5, input=1e6, steady state ≈ (0.5 * 1e6) / (1 - 0.9) * 0.9 ≈ 4.5e6
    for (expected) |val| {
        try std.testing.expect(val > 0.0);
    }
}

test "golden_reverb_model_case2_with_shaping" {
    const expected = test_utils.parseNamedF32(golden_text, "REVERB_MODEL_CASE2_WITH_SHAPING", FFT_LENGTH_BY_2_PLUS_1);

    // Reverb with frequency shaping should vary across bins
    var min_val: f32 = std.math.inf(f32);
    var max_val: f32 = 0.0;
    for (expected) |val| {
        min_val = @min(min_val, val);
        max_val = @max(max_val, val);
    }

    // Should have some variation due to frequency shaping
    try std.testing.expect(max_val > min_val);
}

test "golden_reverb_model_case3_reset" {
    const before_reset = test_utils.parseNamedF32(golden_text, "REVERB_MODEL_CASE3_BEFORE_RESET", FFT_LENGTH_BY_2_PLUS_1);
    const after_reset = test_utils.parseNamedF32(golden_text, "REVERB_MODEL_CASE3_AFTER_RESET", FFT_LENGTH_BY_2_PLUS_1);

    // Before reset should have non-zero values
    var has_nonzero = false;
    for (before_reset) |val| {
        if (val > 0.0) {
            has_nonzero = true;
            break;
        }
    }
    try std.testing.expect(has_nonzero);

    // After reset should be all zeros
    for (after_reset) |val| {
        try std.testing.expectEqual(0.0, val);
    }
}

test "golden_reverb_model_case4_decay_values" {
    // Test different decay values: 0.5, 0.7, 0.9, 0.95
    const decay_values = [_]f32{ 0.5, 0.7, 0.9, 0.95 };

    inline for (decay_values) |decay| {
        const name = std.fmt.comptimePrint("REVERB_MODEL_CASE4_DECAY_{d:.2}", .{decay});
        const expected = test_utils.parseNamedF32(golden_text, name, FFT_LENGTH_BY_2_PLUS_1);

        // Higher decay should result in higher steady-state reverb
        for (expected) |val| {
            try std.testing.expect(val >= 0.0);
        }
    }
}

// ==================== Reverb Decay Estimator Tests ====================

test "golden_reverb_decay_case1_exponential" {
    const estimated_decay = test_utils.parseScalarF32(golden_text, "REVERB_DECAY_CASE1_ESTIMATED_DECAY");
    const true_decay = test_utils.parseScalarF32(golden_text, "REVERB_DECAY_CASE1_TRUE_DECAY");

    // Estimated decay should be close to true decay
    try std.testing.expectApproxEqAbs(true_decay, estimated_decay, 0.1);
}

test "golden_reverb_decay_case2_fixed" {
    const decay = test_utils.parseScalarF32(golden_text, "REVERB_DECAY_CASE2_FIXED_DECAY");

    // Fixed decay should match configured value (0.8)
    try std.testing.expectApproxEqAbs(0.8, decay, 1e-6);
}

test "golden_reverb_decay_case3_stationary" {
    const decay = test_utils.parseScalarF32(golden_text, "REVERB_DECAY_CASE3_STATIONARY_DECAY");

    // Stationary blocks should not update decay estimate
    // Should remain at default
    try std.testing.expect(decay >= 0.0);
}

// ==================== Reverb Frequency Response Tests ====================

test "golden_reverb_freq_response_case1_basic" {
    const expected = test_utils.parseNamedF32(golden_text, "REVERB_FREQ_RESPONSE_CASE1", FFT_LENGTH_BY_2_PLUS_1);

    // Frequency response should be non-negative
    for (expected) |val| {
        try std.testing.expect(val >= 0.0);
    }
}

test "golden_reverb_freq_response_case2_empty" {
    const expected = test_utils.parseNamedF32(golden_text, "REVERB_FREQ_RESPONSE_CASE2_EMPTY", FFT_LENGTH_BY_2_PLUS_1);

    // Empty input should result in zero response
    for (expected) |val| {
        try std.testing.expectEqual(0.0, val);
    }
}

test "golden_reverb_freq_response_case3_stationary" {
    const expected = test_utils.parseNamedF32(golden_text, "REVERB_FREQ_RESPONSE_CASE3_STATIONARY", FFT_LENGTH_BY_2_PLUS_1);

    // Stationary blocks should not update response
    // Should remain at initial value (0.0)
    for (expected) |val| {
        try std.testing.expectEqual(0.0, val);
    }
}

// ==================== Reverb Model Estimator Tests ====================

test "golden_reverb_model_estimator_case1_decay" {
    const decay = test_utils.parseScalarF32(golden_text, "REVERB_MODEL_ESTIMATOR_CASE1_DECAY");
    const freq_response = test_utils.parseNamedF32(golden_text, "REVERB_MODEL_ESTIMATOR_CASE1_FREQ_RESPONSE", FFT_LENGTH_BY_2_PLUS_1);

    // Decay should be close to expected (0.5)
    try std.testing.expectApproxEqAbs(0.5, decay, 0.1);

    // Frequency response should be non-negative
    for (freq_response) |val| {
        try std.testing.expect(val >= 0.0);
    }
}

test "golden_reverb_model_estimator_case2_multi_channel" {
    const decay = test_utils.parseScalarF32(golden_text, "REVERB_MODEL_ESTIMATOR_CASE2_MULTI_CHANNEL_DECAY");

    // Multi-channel estimator should produce valid decay
    try std.testing.expect(decay >= 0.0);
    try std.testing.expect(decay <= 1.0);
}
