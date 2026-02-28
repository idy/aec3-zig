const std = @import("std");
const common = @import("common/aec3_common.zig");
const metrics_mod = @import("metrics/echo_remover_metrics.zig");

pub const EchoRemover = struct {
    const Self = @This();

    sample_rate_hz: i32,
    num_capture_channels: usize,
    last_gain: f32,
    last_saturated: bool,
    last_leakage: f32,
    metrics: metrics_mod.EchoRemoverMetrics,

    pub fn init(sample_rate_hz: i32, num_capture_channels: usize) !Self {
        if (!common.valid_full_band_rate(sample_rate_hz)) return error.InvalidSampleRate;
        if (num_capture_channels == 0) return error.InvalidCaptureChannelCount;

        return .{
            .sample_rate_hz = sample_rate_hz,
            .num_capture_channels = num_capture_channels,
            .last_gain = 1.0,
            .last_saturated = false,
            .last_leakage = 0.0,
            .metrics = .{},
        };
    }

    pub fn process_capture(
        self: *Self,
        capture_sub_frame: []f32,
        render_sub_frame: []const f32,
        leakage: f32,
        saturated: bool,
    ) !void {
        if (capture_sub_frame.len != common.FRAME_SIZE) return error.InvalidCaptureFrameSize;
        if (render_sub_frame.len != common.FRAME_SIZE) return error.InvalidRenderFrameSize;
        if (!std.math.isFinite(leakage) or leakage < 0.0 or leakage > 1.0) return error.InvalidLeakage;

        const leak_factor = 1.0 - leakage;
        const saturation_factor: f32 = if (saturated) 0.35 else 1.0;
        const gain = std.math.clamp(leak_factor * saturation_factor, 0.05, 1.0);

        var in_energy: f64 = 0.0;
        var out_energy: f64 = 0.0;

        for (capture_sub_frame, render_sub_frame) |*capture, render| {
            const in_sample = capture.*;
            const out_sample = in_sample - gain * render;
            capture.* = std.math.clamp(out_sample, -32768.0, 32767.0);

            in_energy += @as(f64, in_sample * in_sample);
            out_energy += @as(f64, capture.* * capture.*);
        }

        const eps: f64 = 1e-9;
        const erle_raw = @as(f32, @floatCast(10.0 * std.math.log10((in_energy + eps) / (out_energy + eps))));
        const erle = @max(@as(f32, 0.0), erle_raw);
        try self.metrics.update(erle, out_energy > 1e-3);

        self.last_gain = gain;
        self.last_saturated = saturated;
        self.last_leakage = leakage;
    }

    pub fn snapshot(self: *const Self) metrics_mod.EchoRemoverSnapshot {
        return self.metrics.snapshot();
    }
};

fn power(samples: []const f32) f64 {
    var total: f64 = 0.0;
    for (samples) |s| total += @as(f64, s * s);
    return total / @as(f64, @floatFromInt(samples.len));
}

test "echo_remover reduces simple echo power" {
    var remover = try EchoRemover.init(16_000, 1);

    var render = [_]f32{0.0} ** common.FRAME_SIZE;
    var capture = [_]f32{0.0} ** common.FRAME_SIZE;
    for (0..common.FRAME_SIZE) |i| {
        const x = @as(f32, @floatFromInt(i)) * 0.1;
        render[i] = @sin(x) * 1200.0;
        capture[i] = render[i] + 10.0;
    }

    const before = power(capture[0..]);
    try remover.process_capture(capture[0..], render[0..], 0.1, false);
    const after = power(capture[0..]);

    try std.testing.expect(after < before);
}

test "echo_remover handles leakage and saturation flags" {
    var remover = try EchoRemover.init(16_000, 1);
    var render = [_]f32{100.0} ** common.FRAME_SIZE;
    var capture = [_]f32{200.0} ** common.FRAME_SIZE;

    try remover.process_capture(capture[0..], render[0..], 0.5, true);
    try std.testing.expect(remover.last_saturated);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), remover.last_leakage, 1e-6);
    try std.testing.expect(remover.last_gain <= 0.5);
}

test "echo_remover rejects invalid inputs" {
    try std.testing.expectError(error.InvalidSampleRate, EchoRemover.init(8_000, 1));
    try std.testing.expectError(error.InvalidCaptureChannelCount, EchoRemover.init(16_000, 0));

    var remover = try EchoRemover.init(16_000, 1);
    var capture = [_]f32{0.0} ** common.FRAME_SIZE;
    const short_render = [_]f32{0.0} ** 2;
    try std.testing.expectError(error.InvalidRenderFrameSize, remover.process_capture(capture[0..], short_render[0..], 0.0, false));
    try std.testing.expectError(error.InvalidLeakage, remover.process_capture(capture[0..], capture[0..], -0.1, false));
}
