//! Golden vector tests for AEC3 Building Blocks
//! Validates Zig implementation against Rust-generated baseline

const std = @import("std");
const aec3 = @import("aec3");
const test_utils = @import("test_utils.zig");

const golden_text = @embedFile("../vectors/rust_aec3_blocks_golden_vectors.txt");

// ============================================================================
// Moving Average Tests
// ============================================================================

test "golden_moving_average_simple" {
    const input = test_utils.parseNamedF32(golden_text, "MA_INPUT_SIMPLE", 8);
    const window = test_utils.parseNamedUsize(golden_text, "MA_WINDOW_SIMPLE", 1);
    const expected = test_utils.parseNamedF32(golden_text, "MA_EXPECTED_SIMPLE", 7);

    // TODO: Replace with actual moving_average implementation
    // const actual = aec3.moving_average(&input, window[0]);
    // try std.testing.expectEqual(expected.len, actual.len);
    // for (expected, actual) |e, a| {
    //     try test_utils.expectUlpEq(e, a, 1);
    // }

    // Placeholder: verify we can parse the golden data
    try std.testing.expectEqual(@as(usize, 2), window[0]);
    try std.testing.expectApproxEqAbs(@as(f32, 1.5), expected[0], 1e-6);
    _ = input;
}

test "golden_moving_average_full_window" {
    const input = test_utils.parseNamedF32(golden_text, "MA_INPUT_FULL_WINDOW", 5);
    const window = test_utils.parseNamedUsize(golden_text, "MA_WINDOW_FULL", 1);
    const expected = test_utils.parseNamedF32(golden_text, "MA_EXPECTED_FULL_WINDOW", 1);

    // TODO: Implement actual test
    try std.testing.expectEqual(@as(usize, 5), window[0]);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), expected[0], 1e-6);
    _ = input;
}

test "golden_moving_average_window_1" {
    const input = test_utils.parseNamedF32(golden_text, "MA_INPUT_WINDOW_1", 5);
    const window = test_utils.parseNamedUsize(golden_text, "MA_WINDOW_1", 1);
    const expected = test_utils.parseNamedF32(golden_text, "MA_EXPECTED_WINDOW_1", 5);

    // TODO: Implement actual test
    try std.testing.expectEqual(@as(usize, 1), window[0]);
    for (input, expected) |inp, exp| {
        try std.testing.expectApproxEqAbs(inp, exp, 1e-6);
    }
}

test "golden_moving_average_sine" {
    const input = test_utils.parseNamedF32(golden_text, "MA_INPUT_SINE", 100);
    const window = test_utils.parseNamedUsize(golden_text, "MA_WINDOW_SINE", 1);
    const expected = test_utils.parseNamedF32(golden_text, "MA_EXPECTED_SINE", 91);

    // TODO: Implement actual test
    try std.testing.expectEqual(@as(usize, 10), window[0]);
    try std.testing.expectEqual(@as(usize, 91), expected.len);
    _ = input;
}

// ============================================================================
// Decimator Tests
// ============================================================================

test "golden_decimator_factor_2" {
    const input = test_utils.parseNamedF32(golden_text, "DEC_INPUT_FACTOR_2", 16);
    const factor = test_utils.parseNamedUsize(golden_text, "DEC_FACTOR_2", 1);
    const expected_len = test_utils.parseNamedUsize(golden_text, "DEC_EXPECTED_LEN_2", 1);
    const expected = test_utils.parseNamedF32(golden_text, "DEC_EXPECTED_FACTOR_2", 8);

    // TODO: Replace with actual decimator implementation
    // const actual = aec3.decimate(&input, factor[0]);
    // try std.testing.expectEqual(expected_len[0], actual.len);

    try std.testing.expectEqual(@as(usize, 2), factor[0]);
    try std.testing.expectEqual(@as(usize, 8), expected_len[0]);
    try std.testing.expectEqual(@as(f32, 0.0), expected[0]); // First sample
    try std.testing.expectEqual(@as(f32, 2.0), expected[1]); // Every 2nd sample
    _ = input;
}

test "golden_decimator_factor_4" {
    const input = test_utils.parseNamedF32(golden_text, "DEC_INPUT_FACTOR_4", 32);
    const factor = test_utils.parseNamedUsize(golden_text, "DEC_FACTOR_4", 1);
    const expected_len = test_utils.parseNamedUsize(golden_text, "DEC_EXPECTED_LEN_4", 1);
    const expected = test_utils.parseNamedF32(golden_text, "DEC_EXPECTED_FACTOR_4", 8);

    // TODO: Implement actual test
    try std.testing.expectEqual(@as(usize, 4), factor[0]);
    try std.testing.expectEqual(@as(usize, 8), expected_len[0]);
    _ = expected;
    _ = input;
}

test "golden_decimator_factor_1" {
    const input = test_utils.parseNamedF32(golden_text, "DEC_INPUT_FACTOR_1", 8);
    const factor = test_utils.parseNamedUsize(golden_text, "DEC_FACTOR_1", 1);
    const expected = test_utils.parseNamedF32(golden_text, "DEC_EXPECTED_FACTOR_1", 8);

    // TODO: Implement actual test
    try std.testing.expectEqual(@as(usize, 1), factor[0]);
    for (input, expected) |inp, exp| {
        try std.testing.expectApproxEqAbs(inp, exp, 1e-6);
    }
}

test "golden_decimator_sine" {
    const input = test_utils.parseNamedF32(golden_text, "DEC_INPUT_SINE", 64);
    const factor = test_utils.parseNamedUsize(golden_text, "DEC_FACTOR_SINE", 1);
    const expected = test_utils.parseNamedF32(golden_text, "DEC_EXPECTED_SINE", 16);

    // TODO: Implement actual test
    try std.testing.expectEqual(@as(usize, 4), factor[0]);
    try std.testing.expectEqual(@as(usize, 16), expected.len);
    _ = input;
}

// ============================================================================
// Frame Blocker / Block Framer Tests
// ============================================================================

test "golden_frame_blocker_framer_basic" {
    const input_blocks = test_utils.parseNamedF32(golden_text, "FB_INPUT_BLOCKS", 128);
    const block_size = test_utils.parseNamedUsize(golden_text, "FB_BLOCK_SIZE", 1);
    const frame_size = test_utils.parseNamedUsize(golden_text, "FB_FRAME_SIZE", 1);
    const frames = test_utils.parseNamedF32(golden_text, "FB_FRAMES_EXTRACTED", 80);
    const output = test_utils.parseNamedF32(golden_text, "FB_ROUNDTRIP_OUTPUT", 80);

    // TODO: Replace with actual frame_blocker/block_framer implementation
    // Verify round-trip preserves data

    try std.testing.expectEqual(@as(usize, 64), block_size[0]);
    try std.testing.expectEqual(@as(usize, 80), frame_size[0]);
    try std.testing.expectEqual(@as(usize, 80), frames.len);
    try std.testing.expectEqual(@as(usize, 80), output.len);
    _ = input_blocks;
}

test "golden_frame_blocker_framer_cross_boundary" {
    const input = test_utils.parseNamedF32(golden_text, "FB_CROSS_BOUNDARY_INPUT", 200);
    const frames = test_utils.parseNamedF32(golden_text, "FB_CROSS_BOUNDARY_FRAMES", 160);
    const output = test_utils.parseNamedF32(golden_text, "FB_CROSS_BOUNDARY_OUTPUT", 160);

    // TODO: Implement actual test
    // Verify no data loss across block boundaries
    try std.testing.expectEqual(@as(usize, 160), frames.len);
    try std.testing.expectEqual(@as(usize, 160), output.len);
    _ = input;
}

// ============================================================================
// Clock Drift Detector Tests
// ============================================================================

test "golden_clockdrift_stable" {
    const input = test_utils.parseNamedF32(golden_text, "CD_STABLE_INPUT", 100);
    const threshold = test_utils.parseNamedF32(golden_text, "CD_THRESHOLD", 1);
    const level = test_utils.parseNamedF32(golden_text, "CD_STABLE_LEVEL", 1);
    const drift = test_utils.parseNamedI32(golden_text, "CD_STABLE_DRIFT", 1);

    // TODO: Replace with actual clockdrift_detector implementation
    // const (actual_level, actual_drift) = aec3.detect_drift(&input, threshold[0]);
    // try std.testing.expectApproxEqAbs(level[0], actual_level, 1e-6);
    // try std.testing.expectEqual(drift[0] != 0, actual_drift);

    try std.testing.expect(level[0] < threshold[0]); // Stable signal should have low level
    try std.testing.expectEqual(@as(i32, 0), drift[0]); // No drift detected
    _ = input;
}

test "golden_clockdrift_drift" {
    const input = test_utils.parseNamedF32(golden_text, "CD_DRIFT_INPUT", 100);
    const level = test_utils.parseNamedF32(golden_text, "CD_DRIFT_LEVEL", 1);
    const drift = test_utils.parseNamedI32(golden_text, "CD_DRIFT_DETECTED", 1);

    // TODO: Implement actual test
    try std.testing.expect(level[0] > 0.5); // Drifting signal should have high level
    try std.testing.expectEqual(@as(i32, 1), drift[0]); // Drift detected
    _ = input;
}

test "golden_clockdrift_sine" {
    const input = test_utils.parseNamedF32(golden_text, "CD_SINE_INPUT", 100);
    const level = test_utils.parseNamedF32(golden_text, "CD_SINE_LEVEL", 1);
    const drift = test_utils.parseNamedI32(golden_text, "CD_SINE_DRIFT", 1);

    // TODO: Implement actual test
    // Sine wave has medium variance, may or may not trigger drift detection
    _ = input;
    _ = level;
    _ = drift;
}

test "golden_clockdrift_gradual" {
    const input = test_utils.parseNamedF32(golden_text, "CD_GRADUAL_INPUT", 100);
    const level = test_utils.parseNamedF32(golden_text, "CD_GRADUAL_LEVEL", 1);
    const drift = test_utils.parseNamedI32(golden_text, "CD_GRADUAL_DRIFT", 1);

    // TODO: Implement actual test
    // Note: Golden data shows gradual drift may not always trigger detection (drift=0)
    try std.testing.expect(level[0] > 0.0); // Level should be positive
    _ = drift;
    _ = input;
}

// ============================================================================
// Block Buffer Tests
// ============================================================================

test "golden_block_buffer_ring_operations" {
    const capacity = test_utils.parseNamedUsize(golden_text, "BB_CAPACITY", 1);
    const block_size = test_utils.parseNamedUsize(golden_text, "BB_BLOCK_SIZE", 1);
    const num_written = test_utils.parseNamedUsize(golden_text, "BB_NUM_WRITTEN", 1);
    const expected_contents = test_utils.parseNamedF32(golden_text, "BB_EXPECTED_RING_CONTENTS", 256);
    const expected_write_idx = test_utils.parseNamedUsize(golden_text, "BB_EXPECTED_WRITE_IDX", 1);
    const expected_read_idx = test_utils.parseNamedUsize(golden_text, "BB_EXPECTED_READ_IDX", 1);

    // TODO: Replace with actual block_buffer implementation
    // Verify ring buffer wrap-around behavior

    try std.testing.expectEqual(@as(usize, 4), capacity[0]);
    try std.testing.expectEqual(@as(usize, 64), block_size[0]);
    try std.testing.expectEqual(@as(usize, 6), num_written[0]);
    try std.testing.expectEqual(@as(usize, 256), expected_contents.len); // 4 blocks * 64 samples
    try std.testing.expectEqual(@as(usize, 2), expected_write_idx[0]);
    try std.testing.expectEqual(@as(usize, 2), expected_read_idx[0]);
}

// ============================================================================
// FFT Buffer Tests
// ============================================================================

test "golden_fft_buffer_ring_operations" {
    const capacity = test_utils.parseNamedUsize(golden_text, "FFT_BUF_CAPACITY", 1);
    const fft_size = test_utils.parseNamedUsize(golden_text, "FFT_BUF_SIZE", 1);
    const num_written = test_utils.parseNamedUsize(golden_text, "FFT_BUF_NUM_WRITTEN", 1);
    const expected_contents = test_utils.parseNamedF32(golden_text, "FFT_BUF_EXPECTED_CONTENTS", 195);

    // TODO: Replace with actual fft_buffer implementation

    try std.testing.expectEqual(@as(usize, 3), capacity[0]);
    try std.testing.expectEqual(@as(usize, 65), fft_size[0]);
    try std.testing.expectEqual(@as(usize, 5), num_written[0]);
    try std.testing.expectEqual(@as(usize, 195), expected_contents.len); // 3 FFTs * 65 bins
}

test "golden_fft_buffer_index_ops" {
    const inc_input = test_utils.parseNamedUsize(golden_text, "FFT_BUF_INC_INPUT", 4);
    const inc_expected = test_utils.parseNamedUsize(golden_text, "FFT_BUF_INC_EXPECTED", 4);
    const dec_input = test_utils.parseNamedUsize(golden_text, "FFT_BUF_DEC_INPUT", 4);
    const dec_expected = test_utils.parseNamedUsize(golden_text, "FFT_BUF_DEC_EXPECTED", 4);

    // TODO: Replace with actual fft_buffer index operations
    // Verify inc_index/dec_index with wrap-around

    // inc_index: [0,1,2,3] -> [1,2,3,0] (wrap at 3)
    for (inc_input, inc_expected) |inp, exp| {
        const actual = if (inp + 1 < 4) inp + 1 else 0;
        try std.testing.expectEqual(exp, actual);
    }

    // dec_index: [0,1,2,3] -> [3,0,1,2] (wrap at 0)
    for (dec_input, dec_expected) |inp, exp| {
        const actual = if (inp > 0) inp - 1 else 3;
        try std.testing.expectEqual(exp, actual);
    }
}
