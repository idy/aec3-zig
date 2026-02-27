const std = @import("std");
const test_utils = @import("test_utils.zig");

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

test "nearend_detector test_utils frame integration" {
    const allocator = std.testing.allocator;
    const near = try test_utils.generateTestFrame(allocator, 4, .ramp);
    defer allocator.free(near);
    const echo = try test_utils.generateTestFrame(allocator, 4, .zeros);
    defer allocator.free(echo);
    const noise = try test_utils.generateTestFrame(allocator, 4, .zeros);
    defer allocator.free(noise);

    var detector = try NearendDetector.init(0.1, 0.05);
    try std.testing.expect(detector.detect(near[3], echo[3], noise[3]));
}

test "nearend_detector invalid threshold" {
    try std.testing.expectError(error.InvalidThreshold, NearendDetector.init(0.0, 0.0));
    try std.testing.expectError(error.InvalidThreshold, NearendDetector.init(1.0, 2.0));
}
