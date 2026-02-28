const std = @import("std");
const aec3 = @import("aec3");
const test_utils = @import("test_utils.zig");

const golden_text = @embedFile("../vectors/rust_echo_canceller3_golden_vectors.txt");

fn fill_buffer_from_frame(buffer: *aec3.FrameAudioBuffer, frame: []const f32) void {
    const ch = buffer.channel_mut(0);
    std.debug.assert(ch.len % frame.len == 0);
    var offset: usize = 0;
    while (offset < ch.len) : (offset += frame.len) {
        @memcpy(ch[offset .. offset + frame.len], frame);
    }
}

test "golden_ec3_analyze_render_basic" {
    const render_frame = test_utils.parseNamedF32(golden_text, "EC3_RENDER_BASIC_INPUT", 160);

    var ec3 = try aec3.EchoCanceller3.init(16_000, 1, 1);
    var render = try aec3.FrameAudioBuffer.from_sample_rates(std.testing.allocator, 16_000, 1, 16_000, 1, 16_000);
    defer render.deinit();

    fill_buffer_from_frame(&render, render_frame[0..]);
    try ec3.analyze_render(&render);

    try std.testing.expectEqual(@as(usize, 1), ec3.block_processor.render_delay_buffer.queued_frames());
}

test "golden_ec3_process_capture_basic" {
    const render_frame = test_utils.parseNamedF32(golden_text, "EC3_RENDER_BASIC_INPUT", 160);
    const capture_in = test_utils.parseNamedF32(golden_text, "EC3_CAPTURE_BASIC_INPUT", 160);
    const expected = test_utils.parseNamedF32(golden_text, "EC3_CAPTURE_BASIC_EXPECTED", 160);

    var ec3 = try aec3.EchoCanceller3.init(16_000, 1, 1);
    var render = try aec3.FrameAudioBuffer.from_sample_rates(std.testing.allocator, 16_000, 1, 16_000, 1, 16_000);
    defer render.deinit();
    var capture = try aec3.FrameAudioBuffer.from_sample_rates(std.testing.allocator, 16_000, 1, 16_000, 1, 16_000);
    defer capture.deinit();

    fill_buffer_from_frame(&render, render_frame[0..]);
    fill_buffer_from_frame(&capture, capture_in[0..]);

    try ec3.analyze_render(&render);
    const status = try ec3.process_capture(&capture, 0.2, false);

    try std.testing.expect(status.status == .ready or status.status == .overflow_recovered);
    for (capture.channel(0), expected) |got, exp| {
        try std.testing.expectApproxEqAbs(exp, got, 1e-3);
    }
}

fn run_bitexact_rate_test(rate: usize, comptime vector_name: []const u8) !void {
    const input = test_utils.parseNamedF32(golden_text, vector_name, 160);

    var a = try aec3.EchoCanceller3.init(@intCast(rate), 1, 1);
    var b = try aec3.EchoCanceller3.init(@intCast(rate), 1, 1);

    var render_a = try aec3.FrameAudioBuffer.from_sample_rates(std.testing.allocator, rate, 1, rate, 1, rate);
    defer render_a.deinit();
    var capture_a = try aec3.FrameAudioBuffer.from_sample_rates(std.testing.allocator, rate, 1, rate, 1, rate);
    defer capture_a.deinit();

    var render_b = try aec3.FrameAudioBuffer.from_sample_rates(std.testing.allocator, rate, 1, rate, 1, rate);
    defer render_b.deinit();
    var capture_b = try aec3.FrameAudioBuffer.from_sample_rates(std.testing.allocator, rate, 1, rate, 1, rate);
    defer capture_b.deinit();

    fill_buffer_from_frame(&render_a, input[0..]);
    fill_buffer_from_frame(&capture_a, input[0..]);
    fill_buffer_from_frame(&render_b, input[0..]);
    fill_buffer_from_frame(&capture_b, input[0..]);

    for (0..10) |_| {
        try a.analyze_render(&render_a);
        try b.analyze_render(&render_b);
        _ = try a.process_capture(&capture_a, 0.2, false);
        _ = try b.process_capture(&capture_b, 0.2, false);
    }

    try std.testing.expectEqualSlices(f32, capture_a.channel(0), capture_b.channel(0));
}

test "golden_ec3_capture_bitexact_16k" {
    try run_bitexact_rate_test(16_000, "EC3_BITEXACT_16K_INPUT");
}

test "golden_ec3_capture_bitexact_32k" {
    try run_bitexact_rate_test(32_000, "EC3_BITEXACT_32K_INPUT");
}

test "golden_ec3_capture_bitexact_48k" {
    try run_bitexact_rate_test(48_000, "EC3_BITEXACT_48K_INPUT");
}

test "golden_ec3_swap_queue_overload" {
    const inserts = test_utils.parseNamedUsize(golden_text, "EC3_SWAP_OVERLOAD_INSERTS", 1)[0];
    const expected_min = test_utils.parseNamedUsize(golden_text, "EC3_SWAP_OVERLOAD_EXPECTED_MIN", 1)[0];
    const render_frame = test_utils.parseNamedF32(golden_text, "EC3_RENDER_BASIC_INPUT", 160);

    var ec3 = try aec3.EchoCanceller3.init(16_000, 1, 1);
    var render = try aec3.FrameAudioBuffer.from_sample_rates(std.testing.allocator, 16_000, 1, 16_000, 1, 16_000);
    defer render.deinit();
    var capture = try aec3.FrameAudioBuffer.from_sample_rates(std.testing.allocator, 16_000, 1, 16_000, 1, 16_000);
    defer capture.deinit();

    fill_buffer_from_frame(&render, render_frame[0..]);
    fill_buffer_from_frame(&capture, render_frame[0..]);

    for (0..inserts) |_| {
        try ec3.analyze_render(&render);
    }

    const status = try ec3.process_capture(&capture, 0.2, false);
    try std.testing.expect(status.overload_count >= expected_min);
}
