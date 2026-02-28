const std = @import("std");
const common = @import("common/aec3_common.zig");

pub const RenderDelayBufferEvent = enum {
    buffering,
    ready,
    overflow_recovered,
};

pub const RenderDelayBuffer = struct {
    const Self = @This();

    sample_rate_hz: i32,
    num_render_channels: usize,
    frames: [common.RENDER_TRANSFER_QUEUE_SIZE_FRAMES][common.FRAME_SIZE]f32,
    write_index: usize,
    read_index: usize,
    count: usize,
    overload_events: usize,
    overflow_since_last_prepare: bool,
    prepared_render: [common.FRAME_SIZE]f32,
    prepared_valid: bool,
    delay_estimate_samples_: usize,

    pub fn init(sample_rate_hz: i32, num_render_channels: usize) !Self {
        if (!common.valid_full_band_rate(sample_rate_hz)) return error.InvalidSampleRate;
        if (num_render_channels == 0) return error.InvalidRenderChannelCount;

        return .{
            .sample_rate_hz = sample_rate_hz,
            .num_render_channels = num_render_channels,
            .frames = [_][common.FRAME_SIZE]f32{[_]f32{0.0} ** common.FRAME_SIZE} ** common.RENDER_TRANSFER_QUEUE_SIZE_FRAMES,
            .write_index = 0,
            .read_index = 0,
            .count = 0,
            .overload_events = 0,
            .overflow_since_last_prepare = false,
            .prepared_render = [_]f32{0.0} ** common.FRAME_SIZE,
            .prepared_valid = false,
            .delay_estimate_samples_ = 0,
        };
    }

    pub fn insert_render(self: *Self, render_sub_frame: []const f32) !void {
        if (render_sub_frame.len != common.FRAME_SIZE) return error.InvalidRenderFrameSize;

        if (self.count == common.RENDER_TRANSFER_QUEUE_SIZE_FRAMES) {
            self.read_index = (self.read_index + 1) % common.RENDER_TRANSFER_QUEUE_SIZE_FRAMES;
            self.count -= 1;
            self.overload_events += 1;
            self.overflow_since_last_prepare = true;
        }

        @memcpy(self.frames[self.write_index][0..], render_sub_frame);
        self.write_index = (self.write_index + 1) % common.RENDER_TRANSFER_QUEUE_SIZE_FRAMES;
        self.count += 1;
        self.delay_estimate_samples_ = self.count * common.FRAME_SIZE;
    }

    pub fn prepare_capture_processing(self: *Self) RenderDelayBufferEvent {
        if (self.count == 0) {
            self.prepared_valid = false;
            self.delay_estimate_samples_ = 0;
            return .buffering;
        }

        @memcpy(self.prepared_render[0..], self.frames[self.read_index][0..]);
        self.read_index = (self.read_index + 1) % common.RENDER_TRANSFER_QUEUE_SIZE_FRAMES;
        self.count -= 1;
        self.prepared_valid = true;
        self.delay_estimate_samples_ = self.count * common.FRAME_SIZE;

        if (self.overflow_since_last_prepare) {
            self.overflow_since_last_prepare = false;
            return .overflow_recovered;
        }

        return .ready;
    }

    pub fn prepared_render_sub_frame(self: *const Self) ?[]const f32 {
        if (!self.prepared_valid) return null;
        return self.prepared_render[0..];
    }

    pub fn delay_estimate_samples(self: *const Self) usize {
        return self.delay_estimate_samples_;
    }

    pub fn queued_frames(self: *const Self) usize {
        return self.count;
    }

    pub fn overload_count(self: *const Self) usize {
        return self.overload_events;
    }
};

test "render_delay_buffer basic insert and prepare" {
    var buffer = try RenderDelayBuffer.init(16_000, 1);
    const frame = [_]f32{0.5} ** common.FRAME_SIZE;

    try buffer.insert_render(frame[0..]);
    try std.testing.expectEqual(@as(usize, 1), buffer.queued_frames());

    try std.testing.expectEqual(RenderDelayBufferEvent.ready, buffer.prepare_capture_processing());
    const prepared = buffer.prepared_render_sub_frame() orelse return error.TestExpectedPreparedFrame;
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), prepared[0], 1e-6);
    try std.testing.expectEqual(@as(usize, 0), buffer.queued_frames());
}

test "render_delay_buffer overload follows overwrite strategy" {
    var buffer = try RenderDelayBuffer.init(16_000, 1);

    var frame: [common.FRAME_SIZE]f32 = undefined;
    for (0..common.RENDER_TRANSFER_QUEUE_SIZE_FRAMES + 20) |k| {
        const v: f32 = @floatFromInt(k);
        @memset(frame[0..], v);
        try buffer.insert_render(frame[0..]);
    }

    try std.testing.expectEqual(@as(usize, 20), buffer.overload_count());
    try std.testing.expectEqual(@as(usize, common.RENDER_TRANSFER_QUEUE_SIZE_FRAMES), buffer.queued_frames());
    try std.testing.expectEqual(RenderDelayBufferEvent.overflow_recovered, buffer.prepare_capture_processing());
}

test "render_delay_buffer rejects invalid init and frame size" {
    try std.testing.expectError(error.InvalidSampleRate, RenderDelayBuffer.init(8_000, 1));
    try std.testing.expectError(error.InvalidRenderChannelCount, RenderDelayBuffer.init(16_000, 0));

    var buffer = try RenderDelayBuffer.init(16_000, 1);
    const short = [_]f32{0.0} ** 8;
    try std.testing.expectError(error.InvalidRenderFrameSize, buffer.insert_render(short[0..]));
}
