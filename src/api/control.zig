//! Ported from: docs/aec3-rs-src/api/control.rs
const std = @import("std");

/// Performance metrics for the echo canceller.
pub const Metrics = struct {
    echo_return_loss: f64 = 0.0,
    echo_return_loss_enhancement: f64 = 0.0,
    delay_ms: i32 = 0,
    render_jitter_min: i32 = 0,
    render_jitter_max: i32 = 0,
    capture_jitter_min: i32 = 0,
    capture_jitter_max: i32 = 0,
};

/// Echo control interface (vtable-based).
pub fn EchoControl(comptime Buffer: type) type {
    return struct {
        const Self = @This();

        ctx: *anyopaque,
        vtable: *const VTable,

        /// VTable for EchoControl interface.
        pub const VTable = struct {
            analyze_render: *const fn (ctx: *anyopaque, render: *Buffer) void,
            analyze_capture: *const fn (ctx: *anyopaque, capture: *Buffer) void,
            process_capture: *const fn (ctx: *anyopaque, capture: *Buffer, level_change: bool) void,
            process_capture_with_linear_output: *const fn (ctx: *anyopaque, capture: *Buffer, linear_output: *Buffer, level_change: bool) void,
            metrics: *const fn (ctx: *const anyopaque) Metrics,
            set_audio_buffer_delay: *const fn (ctx: *anyopaque, delay_ms: i32) void,
            active_processing: *const fn (ctx: *const anyopaque) bool,
        };

        /// Analyzes the render (far-end) signal.
        pub fn analyze_render(self: Self, render: *Buffer) void {
            self.vtable.analyze_render(self.ctx, render);
        }

        /// Analyzes the capture (near-end) signal.
        pub fn analyze_capture(self: Self, capture: *Buffer) void {
            self.vtable.analyze_capture(self.ctx, capture);
        }

        /// Processes the capture signal.
        pub fn process_capture(self: Self, capture: *Buffer, level_change: bool) void {
            self.vtable.process_capture(self.ctx, capture, level_change);
        }

        /// Processes the capture signal with linear output.
        pub fn process_capture_with_linear_output(self: Self, capture: *Buffer, linear_output: *Buffer, level_change: bool) void {
            self.vtable.process_capture_with_linear_output(self.ctx, capture, linear_output, level_change);
        }

        /// Returns the current metrics.
        pub fn metrics(self: Self) Metrics {
            return self.vtable.metrics(self.ctx);
        }

        /// Sets the audio buffer delay.
        pub fn set_audio_buffer_delay(self: Self, delay_ms: i32) void {
            self.vtable.set_audio_buffer_delay(self.ctx, delay_ms);
        }

        /// Returns true if processing is active.
        pub fn active_processing(self: Self) bool {
            return self.vtable.active_processing(self.ctx);
        }
    };
}

test "test_metrics_default" {
    const m = Metrics{};
    try std.testing.expectEqual(@as(f64, 0.0), m.echo_return_loss);
    try std.testing.expectEqual(@as(f64, 0.0), m.echo_return_loss_enhancement);
    try std.testing.expectEqual(@as(i32, 0), m.delay_ms);
    try std.testing.expectEqual(@as(i32, 0), m.render_jitter_min);
    try std.testing.expectEqual(@as(i32, 0), m.render_jitter_max);
    try std.testing.expectEqual(@as(i32, 0), m.capture_jitter_min);
    try std.testing.expectEqual(@as(i32, 0), m.capture_jitter_max);
}

test "test_echo_control_wrappers_with_boundary_inputs" {
    const Buffer = [1]f32;
    const Ctl = EchoControl(Buffer);

    const State = struct {
        calls: usize = 0,
        delay_ms: i32 = 0,
        active: bool = false,
    };

    const Impl = struct {
        fn analyze_render(ctx: *anyopaque, _: *Buffer) void {
            const s: *State = @ptrCast(@alignCast(ctx));
            s.calls += 1;
        }
        fn analyze_capture(ctx: *anyopaque, _: *Buffer) void {
            const s: *State = @ptrCast(@alignCast(ctx));
            s.calls += 1;
        }
        fn process_capture(ctx: *anyopaque, _: *Buffer, _: bool) void {
            const s: *State = @ptrCast(@alignCast(ctx));
            s.calls += 1;
        }
        fn process_capture_with_linear_output(ctx: *anyopaque, _: *Buffer, _: *Buffer, _: bool) void {
            const s: *State = @ptrCast(@alignCast(ctx));
            s.calls += 1;
        }
        fn metrics(_: *const anyopaque) Metrics {
            return .{ .delay_ms = -2147483648, .render_jitter_max = 2147483647 };
        }
        fn set_audio_buffer_delay(ctx: *anyopaque, delay_ms: i32) void {
            const s: *State = @ptrCast(@alignCast(ctx));
            s.delay_ms = delay_ms;
        }
        fn active_processing(ctx: *const anyopaque) bool {
            const s: *const State = @ptrCast(@alignCast(ctx));
            return s.active;
        }
    };

    var state = State{};
    const vt = Ctl.VTable{
        .analyze_render = Impl.analyze_render,
        .analyze_capture = Impl.analyze_capture,
        .process_capture = Impl.process_capture,
        .process_capture_with_linear_output = Impl.process_capture_with_linear_output,
        .metrics = Impl.metrics,
        .set_audio_buffer_delay = Impl.set_audio_buffer_delay,
        .active_processing = Impl.active_processing,
    };
    const ec = Ctl{ .ctx = &state, .vtable = &vt };

    var capture: Buffer = .{0};
    var linear: Buffer = .{0};
    ec.analyze_render(&capture);
    ec.analyze_capture(&capture);
    ec.process_capture(&capture, false);
    ec.process_capture_with_linear_output(&capture, &linear, true);
    ec.set_audio_buffer_delay(std.math.minInt(i32));
    const m = ec.metrics();

    try std.testing.expectEqual(@as(usize, 4), state.calls);
    try std.testing.expectEqual(std.math.minInt(i32), state.delay_ms);
    try std.testing.expectEqual(std.math.minInt(i32), m.delay_ms);
    try std.testing.expectEqual(std.math.maxInt(i32), m.render_jitter_max);
    try std.testing.expect(!ec.active_processing());
}
