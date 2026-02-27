const std = @import("std");

pub const DominantNearendDetector = struct {
    enter_ratio: f32,
    exit_ratio: f32,
    state: bool = false,

    pub fn init(enter_ratio: f32, exit_ratio: f32) !DominantNearendDetector {
        if (enter_ratio <= 0.0 or exit_ratio <= 0.0 or enter_ratio < exit_ratio) {
            return error.InvalidThreshold;
        }
        return .{ .enter_ratio = enter_ratio, .exit_ratio = exit_ratio };
    }

    pub fn detect(self: *DominantNearendDetector, nearend_energy: f32, echo_energy: f32) bool {
        const ratio = nearend_energy / @max(echo_energy, 1e-9);
        if (!self.state and ratio >= self.enter_ratio) {
            self.state = true;
        } else if (self.state and ratio < self.exit_ratio) {
            self.state = false;
        }
        return self.state;
    }
};

test "dominant_nearend_detector dominant near-end" {
    var detector = try DominantNearendDetector.init(2.0, 1.5);
    try std.testing.expect(detector.detect(10.0, 2.0));
}

test "dominant_nearend_detector dominant echo rejection" {
    var detector = try DominantNearendDetector.init(2.0, 1.5);
    try std.testing.expect(!detector.detect(1.0, 3.0));
}

test "dominant_nearend_detector balanced energy hysteresis" {
    var detector = try DominantNearendDetector.init(2.0, 1.5);
    _ = detector.detect(4.0, 1.5);
    try std.testing.expect(detector.detect(3.2, 1.8));
    try std.testing.expect(!detector.detect(2.0, 2.0));
}

test "dominant_nearend_detector sequence detection" {
    var detector = try DominantNearendDetector.init(2.0, 1.5);
    const near = [_]f32{ 1.0, 5.0, 6.0, 1.0 };
    const echo = [_]f32{ 3.0, 2.0, 2.0, 3.0 };
    const expected = [_]bool{ false, true, true, false };

    for (near, echo, expected) |n, e, want| {
        try std.testing.expectEqual(want, detector.detect(n, e));
    }
}

test "dominant_nearend_detector invalid threshold" {
    try std.testing.expectError(error.InvalidThreshold, DominantNearendDetector.init(0.0, 0.0));
    try std.testing.expectError(error.InvalidThreshold, DominantNearendDetector.init(1.0, 2.0));
}
