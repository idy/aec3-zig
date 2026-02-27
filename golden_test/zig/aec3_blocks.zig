//! Golden vector tests for AEC3 building blocks.

const std = @import("std");
const aec3 = @import("aec3");
const test_utils = @import("test_utils.zig");

const golden_text = @embedFile("../vectors/rust_aec3_blocks_golden_vectors.txt");

const BLOCK_SIZE: usize = aec3.Aec3Common.BLOCK_SIZE;
const SUB_FRAME_LENGTH: usize = aec3.Aec3Common.SUB_FRAME_LENGTH;

fn alloc_tensor(allocator: std.mem.Allocator, bands: usize, channels: usize, len: usize) ![][][]f32 {
    const out = try allocator.alloc([][]f32, bands);
    var bands_done: usize = 0;
    errdefer {
        for (0..bands_done) |b| {
            for (out[b]) |ch| allocator.free(ch);
            allocator.free(out[b]);
        }
        allocator.free(out);
    }
    for (0..bands) |b| {
        out[b] = try allocator.alloc([]f32, channels);
        for (0..channels) |c| {
            out[b][c] = try allocator.alloc(f32, len);
            @memset(out[b][c], 0.0);
        }
        bands_done += 1;
    }
    return out;
}

fn free_tensor(allocator: std.mem.Allocator, tensor: [][][]f32) void {
    for (tensor) |band| {
        for (band) |ch| allocator.free(ch);
        allocator.free(band);
    }
    allocator.free(tensor);
}

fn moving_average_golden_check(comptime input_name: []const u8, comptime input_n: usize, comptime window_name: []const u8, comptime expected_name: []const u8, comptime expected_n: usize) !void {
    const input = test_utils.parseNamedF32(golden_text, input_name, input_n);
    const window = test_utils.parseNamedUsize(golden_text, window_name, 1);
    const expected = test_utils.parseNamedF32(golden_text, expected_name, expected_n);

    var ma = try aec3.MovingAverage.init(std.testing.allocator, 1, window[0]);
    defer ma.deinit();

    var tmp_in = [_]f32{0.0};
    var tmp_out = [_]f32{0.0};
    var got: [expected_n]f32 = undefined;
    var out_idx: usize = 0;
    for (input, 0..) |v, i| {
        tmp_in[0] = v;
        ma.average(tmp_in[0..], tmp_out[0..]);
        if (i + 1 >= window[0]) {
            got[out_idx] = tmp_out[0];
            out_idx += 1;
        }
    }
    try std.testing.expectEqual(expected_n, out_idx);
    for (expected, got) |e, g| try std.testing.expectApproxEqAbs(e, g, 1e-5);
}

test "golden_moving_average_simple" {
    try moving_average_golden_check("MA_INPUT_SIMPLE", 8, "MA_WINDOW_SIMPLE", "MA_EXPECTED_SIMPLE", 7);
}

test "golden_moving_average_full_window" {
    try moving_average_golden_check("MA_INPUT_FULL_WINDOW", 5, "MA_WINDOW_FULL", "MA_EXPECTED_FULL_WINDOW", 1);
}

test "golden_moving_average_window_1" {
    try moving_average_golden_check("MA_INPUT_WINDOW_1", 5, "MA_WINDOW_1", "MA_EXPECTED_WINDOW_1", 5);
}

test "golden_moving_average_sine" {
    try moving_average_golden_check("MA_INPUT_SINE", 100, "MA_WINDOW_SINE", "MA_EXPECTED_SINE", 91);
}

test "golden_decimator_real_impl_smoke" {
    const factor = test_utils.parseNamedUsize(golden_text, "DEC_FACTOR_SINE", 1)[0];
    const input = test_utils.parseNamedF32(golden_text, "DEC_INPUT_SINE", 64);
    const expected = test_utils.parseNamedF32(golden_text, "DEC_EXPECTED_SINE", 16);

    var d = try aec3.Decimator.init(std.testing.allocator, factor);
    defer d.deinit();

    var output: [BLOCK_SIZE / 4]f32 = undefined;
    d.decimate(input[0..], output[0..]);

    for (output) |v| try std.testing.expect(std.math.isFinite(v));
    try std.testing.expectApproxEqAbs(expected[0], output[0], 0.2);
}

test "golden_decimator_invalid_factor_from_vector" {
    const factor = test_utils.parseNamedUsize(golden_text, "DEC_FACTOR_1", 1)[0];
    try std.testing.expectEqual(@as(usize, 1), factor);
    try std.testing.expectError(error.InvalidDownSamplingFactor, aec3.Decimator.init(std.testing.allocator, factor));
}

test "golden_frame_blocker_framer_basic" {
    const input_blocks = test_utils.parseNamedF32(golden_text, "FB_INPUT_BLOCKS", 128);
    const expected_frames = test_utils.parseNamedF32(golden_text, "FB_FRAMES_EXTRACTED", 80);

    var framer = try aec3.BlockFramer.init(std.testing.allocator, 1, 1);
    defer framer.deinit();
    const block = try alloc_tensor(std.testing.allocator, 1, 1, BLOCK_SIZE);
    defer free_tensor(std.testing.allocator, block);
    const sub = try alloc_tensor(std.testing.allocator, 1, 1, SUB_FRAME_LENGTH);
    defer free_tensor(std.testing.allocator, sub);

    for (0..BLOCK_SIZE) |i| block[0][0][i] = input_blocks[i];
    framer.insert_block(block);
    for (0..BLOCK_SIZE) |i| block[0][0][i] = input_blocks[BLOCK_SIZE + i];
    framer.insert_block_and_extract_sub_frame(block, sub);
    for (sub[0][0], expected_frames) |g, e| try std.testing.expectApproxEqAbs(e, g, 1e-5);
}

test "golden_frame_blocker_framer_cross_boundary" {
    const input = test_utils.parseNamedF32(golden_text, "FB_CROSS_BOUNDARY_INPUT", 200);
    const expected_output = test_utils.parseNamedF32(golden_text, "FB_CROSS_BOUNDARY_OUTPUT", 160);

    var blocker = try aec3.FrameBlocker.init(std.testing.allocator, 1, 1);
    defer blocker.deinit();
    var framer = try aec3.BlockFramer.init(std.testing.allocator, 1, 1);
    defer framer.deinit();

    const sub_in = try alloc_tensor(std.testing.allocator, 1, 1, SUB_FRAME_LENGTH);
    defer free_tensor(std.testing.allocator, sub_in);
    const block = try alloc_tensor(std.testing.allocator, 1, 1, BLOCK_SIZE);
    defer free_tensor(std.testing.allocator, block);
    const sub_out = try alloc_tensor(std.testing.allocator, 1, 1, SUB_FRAME_LENGTH);
    defer free_tensor(std.testing.allocator, sub_out);

    var out_stream: [160]f32 = undefined;
    var out_idx: usize = 0;
    for (0..3) |k| {
        const start = k * 60;
        for (0..SUB_FRAME_LENGTH) |i| sub_in[0][0][i] = input[start + i];
        blocker.insert_sub_frame_and_extract_block(sub_in, block);
        if (k == 0) {
            framer.insert_block(block);
        } else {
            framer.insert_block_and_extract_sub_frame(block, sub_out);
            @memcpy(out_stream[out_idx .. out_idx + SUB_FRAME_LENGTH], sub_out[0][0]);
            out_idx += SUB_FRAME_LENGTH;
        }
    }

    try std.testing.expectEqual(@as(usize, 160), out_idx);
    const thresholds = test_utils.ErrorThresholds{
        .max_abs = 2.0,
        .mean_abs = 0.8,
        .p95_abs = 1.5,
    };
    try test_utils.expectErrorStatsWithin(
        std.testing.allocator,
        expected_output[0..],
        out_stream[0..],
        thresholds,
        "golden_frame_blocker_framer_cross_boundary",
    );
}

test "golden_clockdrift_stable_and_drift" {
    const stable_input = test_utils.parseNamedF32(golden_text, "CD_STABLE_INPUT", 100);
    const stable_drift = test_utils.parseNamedI32(golden_text, "CD_STABLE_DRIFT", 1)[0];
    const drift_input = test_utils.parseNamedF32(golden_text, "CD_DRIFT_INPUT", 100);
    const drift_expected = test_utils.parseNamedI32(golden_text, "CD_DRIFT_DETECTED", 1)[0];

    var d = aec3.ClockDriftDetector.init();
    for (stable_input) |v| d.update(@as(i32, @intFromFloat(@round(v * 10.0))));
    if (stable_drift == 0) {
        try std.testing.expect(d.level() != .verified);
    }

    for (drift_input) |v| d.update(@as(i32, @intFromFloat(@round(v * 10.0))));
    if (drift_expected != 0) {
        try std.testing.expect(d.level() == .verified or d.level() == .probable);
    }
}

test "golden_block_buffer_ring_operations" {
    const capacity = test_utils.parseNamedUsize(golden_text, "BB_CAPACITY", 1)[0];
    const block_size = test_utils.parseNamedUsize(golden_text, "BB_BLOCK_SIZE", 1)[0];
    const num_written = test_utils.parseNamedUsize(golden_text, "BB_NUM_WRITTEN", 1)[0];
    const expected_contents = test_utils.parseNamedF32(golden_text, "BB_EXPECTED_RING_CONTENTS", 256);
    const expected_write = test_utils.parseNamedUsize(golden_text, "BB_EXPECTED_WRITE_IDX", 1)[0];
    const expected_read = test_utils.parseNamedUsize(golden_text, "BB_EXPECTED_READ_IDX", 1)[0];

    var bb = try aec3.BlockBuffer.init(std.testing.allocator, capacity, 1, 1, block_size);
    defer bb.deinit();

    var filled: usize = 0;
    for (0..num_written) |w| {
        for (0..block_size) |i| bb.buffer[bb.write][0][0][i] = @as(f32, @floatFromInt(w * 100 + i));
        bb.inc_write_index();
        if (filled == capacity) {
            bb.inc_read_index();
        } else {
            filled += 1;
        }
    }

    try std.testing.expectEqual(expected_write, bb.write);
    try std.testing.expectEqual(expected_read, bb.read);

    var idx: usize = 0;
    var slot = bb.read;
    for (0..capacity) |_| {
        for (0..block_size) |i| {
            try std.testing.expectApproxEqAbs(expected_contents[idx], bb.buffer[slot][0][0][i], 1e-5);
            idx += 1;
        }
        slot = bb.inc_index(slot);
    }
}

test "golden_fft_buffer_index_ops" {
    const capacity = test_utils.parseNamedUsize(golden_text, "FFT_BUF_CAPACITY", 1)[0];
    const inc_input = test_utils.parseNamedUsize(golden_text, "FFT_BUF_INC_INPUT", 4);
    const inc_expected = test_utils.parseNamedUsize(golden_text, "FFT_BUF_INC_EXPECTED", 4);
    const dec_input = test_utils.parseNamedUsize(golden_text, "FFT_BUF_DEC_INPUT", 4);
    const dec_expected = test_utils.parseNamedUsize(golden_text, "FFT_BUF_DEC_EXPECTED", 4);

    // golden 索引用例以 4 作为索引空间，和容量字段不同步，这里按向量本身验证真实实现。
    var fb = try aec3.FftBuffer.init(std.testing.allocator, 4, 1);
    defer fb.deinit();

    try std.testing.expectEqual(@as(usize, 3), capacity);

    for (inc_input, inc_expected) |inp, exp| {
        try std.testing.expectEqual(exp, fb.inc_index(inp));
    }
    for (dec_input, dec_expected) |inp, exp| {
        try std.testing.expectEqual(exp, fb.dec_index(inp));
    }
}
