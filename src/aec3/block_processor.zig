const std = @import("std");
const common = @import("common/aec3_common.zig");
const render_delay_buffer_mod = @import("render_delay_buffer.zig");
const render_delay_controller_mod = @import("render_delay_controller.zig");
const echo_remover_mod = @import("echo_remover.zig");

pub const ProcessCaptureResult = struct {
    status: render_delay_buffer_mod.RenderDelayBufferEvent,
    delay_ms: i32,
    overload_count: usize,
};

pub const BlockProcessor = struct {
    const Self = @This();

    sample_rate_hz: i32,
    render_delay_buffer: render_delay_buffer_mod.RenderDelayBuffer,
    render_delay_controller: render_delay_controller_mod.RenderDelayController,
    echo_remover: echo_remover_mod.EchoRemover,

    pub fn init(sample_rate_hz: i32, num_render_channels: usize, num_capture_channels: usize) !Self {
        var render_delay_buffer = try render_delay_buffer_mod.RenderDelayBuffer.init(sample_rate_hz, num_render_channels);
        errdefer _ = &render_delay_buffer;

        return .{
            .sample_rate_hz = sample_rate_hz,
            .render_delay_buffer = render_delay_buffer,
            .render_delay_controller = try render_delay_controller_mod.RenderDelayController.init(sample_rate_hz, 0, 20),
            .echo_remover = try echo_remover_mod.EchoRemover.init(sample_rate_hz, num_capture_channels),
        };
    }

    pub fn analyze_render(self: *Self, render_sub_frame: []const f32) !void {
        try self.render_delay_buffer.insert_render(render_sub_frame);
    }

    pub fn process_capture(self: *Self, capture_sub_frame: []f32, leakage: f32, saturated: bool) !ProcessCaptureResult {
        const status = self.render_delay_buffer.prepare_capture_processing();
        const observed_delay = self.render_delay_buffer.delay_estimate_samples();
        const delay_ms = try self.render_delay_controller.process_capture(observed_delay);

        if (status != .buffering) {
            const prepared = self.render_delay_buffer.prepared_render_sub_frame() orelse return error.PreparedRenderUnavailable;
            try self.echo_remover.process_capture(capture_sub_frame, prepared, leakage, saturated);
        }

        return .{
            .status = status,
            .delay_ms = delay_ms,
            .overload_count = self.render_delay_buffer.overload_count(),
        };
    }
};

fn frame_with_value(v: f32) [common.FRAME_SIZE]f32 {
    return [_]f32{v} ** common.FRAME_SIZE;
}

test "block_processor render and capture pipeline works" {
    var processor = try BlockProcessor.init(16_000, 1, 1);
    const render = frame_with_value(100.0);
    var capture = frame_with_value(120.0);

    try processor.analyze_render(render[0..]);
    const result = try processor.process_capture(capture[0..], 0.1, false);

    try std.testing.expect(result.status == .ready or result.status == .overflow_recovered);
    try std.testing.expect(result.delay_ms >= 0);
}

test "block_processor swap queue overload does not crash" {
    var processor = try BlockProcessor.init(16_000, 1, 1);
    const render = frame_with_value(1.0);
    var capture = frame_with_value(1.0);

    for (0..common.RENDER_TRANSFER_QUEUE_SIZE_FRAMES * 2) |_| {
        try processor.analyze_render(render[0..]);
    }

    const result = try processor.process_capture(capture[0..], 0.0, false);
    try std.testing.expect(result.overload_count > 0);
}
