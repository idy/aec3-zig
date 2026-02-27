const std = @import("std");

pub const MainFilterUpdateGain = struct {
    smoothing: f32,
    previous_gain: f32 = 0.0,

    pub fn init(smoothing: f32) !MainFilterUpdateGain {
        if (smoothing < 0.0 or smoothing > 1.0) return error.InvalidSmoothing;
        return .{ .smoothing = smoothing };
    }

    pub fn compute(self: *MainFilterUpdateGain, erle: f32, echo_present: bool) !f32 {
        if (erle < 0.0) return error.InvalidErle;

        const target = if (!echo_present) 0.0 else std.math.clamp(1.0 / (1.0 + erle), 0.0, 1.0);
        const gain = self.previous_gain * self.smoothing + target * (1.0 - self.smoothing);
        self.previous_gain = gain;
        return gain;
    }
};

test "main_filter_update_gain gain computation" {
    var gain = try MainFilterUpdateGain.init(0.0);
    const g = try gain.compute(1.0, true);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), g, 1e-6);
}

test "main_filter_update_gain high erle low gain" {
    var gain = try MainFilterUpdateGain.init(0.0);
    const g = try gain.compute(100.0, true);
    try std.testing.expect(g < 0.02);
}

test "main_filter_update_gain low erle high gain" {
    var gain = try MainFilterUpdateGain.init(0.0);
    const g = try gain.compute(0.1, true);
    try std.testing.expect(g > 0.9);
}

test "main_filter_update_gain invalid erle error" {
    var gain = try MainFilterUpdateGain.init(0.0);
    try std.testing.expectError(error.InvalidErle, gain.compute(-1.0, true));
}

test "main_filter_update_gain smooth output" {
    var gain = try MainFilterUpdateGain.init(0.9);
    const g1 = try gain.compute(1.0, true);
    const g2 = try gain.compute(0.0, true);
    try std.testing.expect(g2 > g1);
    try std.testing.expect(g2 < 1.0);
}
