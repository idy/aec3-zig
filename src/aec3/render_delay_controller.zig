const std = @import("std");
const common = @import("common/aec3_common.zig");
const metrics_mod = @import("metrics/render_delay_controller_metrics.zig");

pub const RenderDelayController = struct {
    const Self = @This();

    sample_rate_hz: i32,
    estimated_delay_ms_: i32,
    jump_threshold_ms: i32,
    metrics: metrics_mod.RenderDelayControllerMetrics,

    pub fn init(sample_rate_hz: i32, initial_delay_ms: i32, jump_threshold_ms: i32) !Self {
        if (!common.valid_full_band_rate(sample_rate_hz)) return error.InvalidSampleRate;
        if (initial_delay_ms < 0) return error.InvalidInitialDelay;
        if (jump_threshold_ms <= 0) return error.InvalidJumpThreshold;

        return .{
            .sample_rate_hz = sample_rate_hz,
            .estimated_delay_ms_ = initial_delay_ms,
            .jump_threshold_ms = jump_threshold_ms,
            .metrics = try metrics_mod.RenderDelayControllerMetrics.init(jump_threshold_ms),
        };
    }

    pub fn process_capture(self: *Self, observed_delay_samples: usize) !i32 {
        const observed_ms_f = @as(f32, @floatFromInt(observed_delay_samples)) * 1000.0 / @as(f32, @floatFromInt(self.sample_rate_hz));
        const observed_ms = @as(i32, @intFromFloat(@round(observed_ms_f)));
        const delta = observed_ms - self.estimated_delay_ms_;

        const alpha: f32 = if (@abs(delta) >= self.jump_threshold_ms) 0.45 else 0.12;
        const next = @as(f32, @floatFromInt(self.estimated_delay_ms_)) + alpha * @as(f32, @floatFromInt(delta));
        self.estimated_delay_ms_ = @max(0, @as(i32, @intFromFloat(@round(next))));

        const delay_samples_i32: i32 = @intCast(@divTrunc(self.estimated_delay_ms_ * self.sample_rate_hz, 1000));
        try self.metrics.updateDelay(delay_samples_i32);
        return self.estimated_delay_ms_;
    }

    pub fn set_audio_buffer_delay(self: *Self, delay_ms: i32) !void {
        if (delay_ms < 0) return error.InvalidDelay;
        self.estimated_delay_ms_ = delay_ms;
    }

    pub fn estimated_delay_ms(self: *const Self) i32 {
        return self.estimated_delay_ms_;
    }

    pub fn metrics_snapshot(self: *const Self) metrics_mod.RenderDelaySnapshot {
        return self.metrics.snapshot();
    }
};

test "render_delay_controller converges to fixed delay" {
    var controller = try RenderDelayController.init(16_000, 0, 25);

    var converged = false;
    for (0..500) |i| {
        _ = try controller.process_capture(960); // 60ms @ 16k
        if (i > 100 and @abs(controller.estimated_delay_ms() - 60) <= 10) {
            converged = true;
            break;
        }
    }

    try std.testing.expect(converged);
}

test "render_delay_controller jump handling" {
    var controller = try RenderDelayController.init(16_000, 20, 15);
    _ = try controller.process_capture(320); // 20ms
    const before = controller.estimated_delay_ms();
    _ = try controller.process_capture(1600); // 100ms
    const after = controller.estimated_delay_ms();

    try std.testing.expect(after > before);
    try std.testing.expect(controller.metrics_snapshot().jump_count >= 1);
}

test "render_delay_controller rejects invalid parameters" {
    try std.testing.expectError(error.InvalidSampleRate, RenderDelayController.init(44_100, 0, 10));
    try std.testing.expectError(error.InvalidInitialDelay, RenderDelayController.init(16_000, -1, 10));
    try std.testing.expectError(error.InvalidJumpThreshold, RenderDelayController.init(16_000, 0, 0));

    var controller = try RenderDelayController.init(16_000, 1, 10);
    try std.testing.expectError(error.InvalidDelay, controller.set_audio_buffer_delay(-1));
}
