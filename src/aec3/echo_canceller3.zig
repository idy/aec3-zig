const std = @import("std");
const common = @import("common/aec3_common.zig");
const frame_audio_buffer = @import("../buffer/frame_audio_buffer.zig");
const block_processor_mod = @import("block_processor.zig");

pub const ProcessStatus = block_processor_mod.ProcessCaptureResult;

pub const EchoCanceller3 = struct {
    const Self = @This();

    sample_rate_hz: i32,
    num_bands: usize,
    block_processor: block_processor_mod.BlockProcessor,
    audio_buffer_delay_ms: i32,

    pub fn init(sample_rate_hz: i32, num_render_channels: usize, num_capture_channels: usize) !Self {
        if (!common.valid_full_band_rate(sample_rate_hz)) return error.InvalidSampleRate;
        if (num_render_channels == 0) return error.InvalidRenderChannelCount;
        if (num_capture_channels == 0) return error.InvalidCaptureChannelCount;

        const bands = common.num_bands_for_rate(sample_rate_hz);
        return .{
            .sample_rate_hz = sample_rate_hz,
            .num_bands = bands,
            .block_processor = try block_processor_mod.BlockProcessor.init(sample_rate_hz, num_render_channels, num_capture_channels),
            .audio_buffer_delay_ms = 0,
        };
    }

    pub fn analyze_render(self: *Self, render: *frame_audio_buffer.FrameAudioBuffer) !void {
        try self.validate_buffer_shape(render.*);
        render.split_into_frequency_bands();
        try self.block_processor.analyze_render(render.split_band(0, 0));
    }

    pub fn process_capture(self: *Self, capture: *frame_audio_buffer.FrameAudioBuffer, leakage: f32, saturated: bool) !ProcessStatus {
        try self.validate_buffer_shape(capture.*);
        capture.split_into_frequency_bands();
        const result = try self.block_processor.process_capture(capture.split_band_mut(0, 0), leakage, saturated);
        capture.merge_frequency_bands();
        return result;
    }

    pub fn set_audio_buffer_delay(self: *Self, delay_ms: i32) !void {
        if (delay_ms < 0) return error.InvalidAudioBufferDelay;
        self.audio_buffer_delay_ms = delay_ms;
        try self.block_processor.render_delay_controller.set_audio_buffer_delay(delay_ms);
    }

    fn validate_buffer_shape(self: Self, buffer: frame_audio_buffer.FrameAudioBuffer) !void {
        if (buffer.num_bands() != self.num_bands) return error.InvalidBandCount;
        if (buffer.num_frames_per_band() != common.FRAME_SIZE) return error.InvalidFrameSize;
        if (buffer.num_channels() == 0) return error.InvalidChannelCount;
    }
};

fn fill_sine(buffer: *frame_audio_buffer.FrameAudioBuffer, phase: f32, amplitude: f32) void {
    const ch = buffer.channel_mut(0);
    for (ch, 0..) |*sample, i| {
        const x = phase + @as(f32, @floatFromInt(i)) * 0.05;
        sample.* = @sin(x) * amplitude;
    }
}

test "echo_canceller3 analyze_render and process_capture basic chain" {
    var ec3 = try EchoCanceller3.init(16_000, 1, 1);

    var render = try frame_audio_buffer.FrameAudioBuffer.from_sample_rates(std.testing.allocator, 16_000, 1, 16_000, 1, 16_000);
    defer render.deinit();
    var capture = try frame_audio_buffer.FrameAudioBuffer.from_sample_rates(std.testing.allocator, 16_000, 1, 16_000, 1, 16_000);
    defer capture.deinit();

    fill_sine(&render, 0.0, 900.0);
    fill_sine(&capture, 0.0, 1000.0);

    try ec3.analyze_render(&render);
    const status = try ec3.process_capture(&capture, 0.1, false);
    try std.testing.expect(status.delay_ms >= 0);
}

test "echo_canceller3 supports 16k 32k 48k" {
    inline for (.{ 16_000, 32_000, 48_000 }) |rate| {
        var ec3 = try EchoCanceller3.init(rate, 1, 1);
        var render = try frame_audio_buffer.FrameAudioBuffer.from_sample_rates(std.testing.allocator, rate, 1, rate, 1, rate);
        defer render.deinit();
        var capture = try frame_audio_buffer.FrameAudioBuffer.from_sample_rates(std.testing.allocator, rate, 1, rate, 1, rate);
        defer capture.deinit();

        fill_sine(&render, 0.1, 1000.0);
        fill_sine(&capture, 0.2, 1200.0);
        try ec3.analyze_render(&render);
        _ = try ec3.process_capture(&capture, 0.2, false);
    }
}

test "echo_canceller3 survives 1000 frame loop" {
    var ec3 = try EchoCanceller3.init(48_000, 1, 1);
    var render = try frame_audio_buffer.FrameAudioBuffer.from_sample_rates(std.testing.allocator, 48_000, 1, 48_000, 1, 48_000);
    defer render.deinit();
    var capture = try frame_audio_buffer.FrameAudioBuffer.from_sample_rates(std.testing.allocator, 48_000, 1, 48_000, 1, 48_000);
    defer capture.deinit();

    var phase: f32 = 0.0;
    for (0..1000) |_| {
        fill_sine(&render, phase, 700.0);
        fill_sine(&capture, phase + 0.4, 850.0);
        try ec3.analyze_render(&render);
        _ = try ec3.process_capture(&capture, 0.15, false);

        for (capture.channel(0)) |s| {
            try std.testing.expect(std.math.isFinite(s));
            try std.testing.expect(s <= 32767.0 and s >= -32768.0);
        }

        phase += 0.03;
    }
}

test "echo_canceller3 rejects invalid config and delay" {
    try std.testing.expectError(error.InvalidSampleRate, EchoCanceller3.init(44_100, 1, 1));
    try std.testing.expectError(error.InvalidRenderChannelCount, EchoCanceller3.init(16_000, 0, 1));
    try std.testing.expectError(error.InvalidCaptureChannelCount, EchoCanceller3.init(16_000, 1, 0));

    var ec3 = try EchoCanceller3.init(16_000, 1, 1);
    try std.testing.expectError(error.InvalidAudioBufferDelay, ec3.set_audio_buffer_delay(-1));
}
