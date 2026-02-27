const std = @import("std");

pub const RenderDelaySnapshot = struct {
    samples: u64,
    mean_delay: f32,
    variance: f32,
    jump_count: u64,
};

pub const RenderDelayControllerMetrics = struct {
    jump_threshold: i32,
    previous_delay: ?i32 = null,
    samples: u64 = 0,
    jump_count: u64 = 0,
    sum: f32 = 0.0,
    sum_sq: f32 = 0.0,

    pub fn init(jump_threshold: i32) !RenderDelayControllerMetrics {
        if (jump_threshold <= 0) return error.InvalidJumpThreshold;
        return .{ .jump_threshold = jump_threshold };
    }

    pub fn updateDelay(self: *RenderDelayControllerMetrics, delay_samples: i32) !void {
        if (delay_samples < 0) return error.InvalidDelay;

        if (self.previous_delay) |prev| {
            if (@abs(delay_samples - prev) >= self.jump_threshold) {
                self.jump_count += 1;
            }
        }

        const d = @as(f32, @floatFromInt(delay_samples));
        self.samples += 1;
        self.sum += d;
        self.sum_sq += d * d;
        self.previous_delay = delay_samples;
    }

    pub fn snapshot(self: *const RenderDelayControllerMetrics) RenderDelaySnapshot {
        if (self.samples == 0) {
            return .{ .samples = 0, .mean_delay = 0.0, .variance = 0.0, .jump_count = self.jump_count };
        }

        const n = @as(f32, @floatFromInt(self.samples));
        const mean = self.sum / n;
        return .{
            .samples = self.samples,
            .mean_delay = mean,
            .variance = @max(0.0, self.sum_sq / n - mean * mean),
            .jump_count = self.jump_count,
        };
    }
};

test "render_delay_controller_metrics convergence tracking" {
    var metrics = try RenderDelayControllerMetrics.init(20);
    try metrics.updateDelay(50);
    try metrics.updateDelay(51);
    try metrics.updateDelay(50);
    const s = metrics.snapshot();
    try std.testing.expectEqual(@as(u64, 3), s.samples);
    try std.testing.expect(s.variance < 1.0);
}

test "render_delay_controller_metrics delay jump detection" {
    var metrics = try RenderDelayControllerMetrics.init(10);
    try metrics.updateDelay(30);
    try metrics.updateDelay(32);
    try metrics.updateDelay(60);
    try std.testing.expectEqual(@as(u64, 1), metrics.snapshot().jump_count);
}

test "render_delay_controller_metrics invalid init threshold" {
    try std.testing.expectError(error.InvalidJumpThreshold, RenderDelayControllerMetrics.init(0));
}

test "render_delay_controller_metrics invalid delay" {
    var metrics = try RenderDelayControllerMetrics.init(10);
    try std.testing.expectError(error.InvalidDelay, metrics.updateDelay(-1));
}
