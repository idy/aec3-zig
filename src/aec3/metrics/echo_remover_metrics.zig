const std = @import("std");

pub const EchoRemoverSnapshot = struct {
    samples: u64,
    mean_erle: f32,
    peak_erle: f32,
    echo_toggle_count: u64,
    echo_present: bool,
};

pub const EchoRemoverMetrics = struct {
    samples: u64 = 0,
    sum_erle: f32 = 0.0,
    peak_erle: f32 = 0.0,
    echo_toggle_count: u64 = 0,
    echo_present: bool = false,
    has_state: bool = false,

    pub fn update(self: *EchoRemoverMetrics, erle: f32, current_echo_present: bool) !void {
        if (erle < 0.0) return error.InvalidErle;
        self.samples += 1;
        self.sum_erle += erle;
        self.peak_erle = @max(self.peak_erle, erle);

        if (self.has_state and self.echo_present != current_echo_present) {
            self.echo_toggle_count += 1;
        }
        self.echo_present = current_echo_present;
        self.has_state = true;
    }

    pub fn snapshot(self: *const EchoRemoverMetrics) EchoRemoverSnapshot {
        if (self.samples == 0) {
            return .{ .samples = 0, .mean_erle = 0.0, .peak_erle = 0.0, .echo_toggle_count = 0, .echo_present = false };
        }

        return .{
            .samples = self.samples,
            .mean_erle = self.sum_erle / @as(f32, @floatFromInt(self.samples)),
            .peak_erle = self.peak_erle,
            .echo_toggle_count = self.echo_toggle_count,
            .echo_present = self.echo_present,
        };
    }
};

test "echo_remover_metrics erle tracking" {
    var metrics = EchoRemoverMetrics{};
    try metrics.update(3.0, true);
    try metrics.update(6.0, true);
    const s = metrics.snapshot();
    try std.testing.expectApproxEqAbs(@as(f32, 4.5), s.mean_erle, 1e-6);
    try std.testing.expectEqual(@as(f32, 6.0), s.peak_erle);
}

test "echo_remover_metrics zero echo detection" {
    var metrics = EchoRemoverMetrics{};
    try metrics.update(0.0, false);
    try std.testing.expect(!metrics.snapshot().echo_present);
}

test "echo_remover_metrics echo toggle counting" {
    var metrics = EchoRemoverMetrics{};
    try metrics.update(1.0, false);
    try metrics.update(1.0, true);
    try metrics.update(1.0, false);
    try std.testing.expectEqual(@as(u64, 2), metrics.snapshot().echo_toggle_count);
}
