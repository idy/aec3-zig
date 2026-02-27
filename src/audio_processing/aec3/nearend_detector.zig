const std = @import("std");

pub const NearendDetector = struct {
    enter_threshold: f32,
    exit_threshold: f32,
    nearend: bool = false,

    pub fn init(enter_threshold: f32, exit_threshold: f32) !NearendDetector {
        if (enter_threshold <= 0.0 or exit_threshold <= 0.0) return error.InvalidThreshold;
        if (enter_threshold < exit_threshold) return error.InvalidThreshold;
        return .{ .enter_threshold = enter_threshold, .exit_threshold = exit_threshold };
    }

    pub fn detect(self: *NearendDetector, nearend_energy: f32, echo_energy: f32, noise_energy: f32) bool {
        const denom = @max(echo_energy + noise_energy, 1e-9);
        const ratio = nearend_energy / denom;

        if (!self.nearend and ratio >= self.enter_threshold) {
            self.nearend = true;
        } else if (self.nearend and ratio < self.exit_threshold) {
            self.nearend = false;
        }
        return self.nearend;
    }
};

test "nearend_detector near-end detection" {
    var detector = try NearendDetector.init(2.0, 1.5);
    try std.testing.expect(detector.detect(10.0, 3.0, 1.0));
}

test "nearend_detector echo-only rejection" {
    var detector = try NearendDetector.init(2.0, 1.5);
    try std.testing.expect(!detector.detect(1.0, 3.0, 0.5));
}

test "nearend_detector threshold hysteresis" {
    var detector = try NearendDetector.init(2.0, 1.5);
    _ = detector.detect(10.0, 3.0, 1.0);
    try std.testing.expect(detector.detect(6.0, 3.0, 1.0));
    try std.testing.expect(!detector.detect(1.0, 3.0, 1.0));
}

test "nearend_detector noise immunity" {
    var detector = try NearendDetector.init(2.0, 1.5);
    try std.testing.expect(!detector.detect(0.05, 0.01, 0.1));
}
