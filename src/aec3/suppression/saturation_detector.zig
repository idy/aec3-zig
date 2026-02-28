const std = @import("std");

/// Detects signal saturation by comparing sample magnitudes against a
/// configurable threshold.
pub const SaturationDetector = struct {
    saturated_echo: bool,
    threshold: f32,

    pub fn init(threshold: f32) !SaturationDetector {
        if (!(threshold > 0.0)) return error.InvalidThreshold;
        return .{
            .saturated_echo = false,
            .threshold = threshold,
        };
    }

    /// Returns `true` if any sample's absolute value exceeds the threshold.
    pub fn detect(self: *const SaturationDetector, samples: []const f32) bool {
        for (samples) |s| {
            if (@abs(s) > self.threshold) return true;
        }
        return false;
    }

    /// Counts how many samples exceed the saturation threshold.
    pub fn count_saturated(self: *const SaturationDetector, samples: []const f32) usize {
        var count: usize = 0;
        for (samples) |s| {
            if (@abs(s) > self.threshold) count += 1;
        }
        return count;
    }

    /// Updates the `saturated_echo` flag based on the given samples.
    pub fn update_echo_saturation(self: *SaturationDetector, samples: []const f32) void {
        self.saturated_echo = self.detect(samples);
    }

    pub fn is_saturated_echo(self: *const SaturationDetector) bool {
        return self.saturated_echo;
    }

    pub fn reset(self: *SaturationDetector) void {
        self.saturated_echo = false;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "saturation_detector no saturation" {
    const det = try SaturationDetector.init(1.0);
    const samples = [_]f32{ 0.1, 0.5, -0.9, 0.0 };
    try std.testing.expect(!det.detect(&samples));
}

test "saturation_detector with saturation" {
    const det = try SaturationDetector.init(1.0);
    const samples = [_]f32{ 0.1, 1.5, -0.9, 0.0 };
    try std.testing.expect(det.detect(&samples));
}

test "saturation_detector negative saturation" {
    const det = try SaturationDetector.init(1.0);
    const samples = [_]f32{ 0.0, -1.1 };
    try std.testing.expect(det.detect(&samples));
}

test "saturation_detector burst counting" {
    const det = try SaturationDetector.init(0.5);
    const samples = [_]f32{ 0.6, 0.3, -0.7, 0.4, 0.8 };
    try std.testing.expectEqual(@as(usize, 3), det.count_saturated(&samples));
}

test "saturation_detector count zero when clean" {
    const det = try SaturationDetector.init(1.0);
    const samples = [_]f32{ 0.1, 0.2, 0.3 };
    try std.testing.expectEqual(@as(usize, 0), det.count_saturated(&samples));
}

test "saturation_detector boundary exactly at threshold" {
    const det = try SaturationDetector.init(1.0);
    // Exactly at threshold is NOT saturated (>  not >=).
    const samples = [_]f32{1.0};
    try std.testing.expect(!det.detect(&samples));
}

test "saturation_detector update echo saturation" {
    var det = try SaturationDetector.init(0.5);
    const clean = [_]f32{ 0.1, 0.2 };
    det.update_echo_saturation(&clean);
    try std.testing.expect(!det.is_saturated_echo());

    const loud = [_]f32{ 0.1, 0.6 };
    det.update_echo_saturation(&loud);
    try std.testing.expect(det.is_saturated_echo());
}

test "saturation_detector reset clears flag" {
    var det = try SaturationDetector.init(0.5);
    det.update_echo_saturation(&[_]f32{1.0});
    try std.testing.expect(det.is_saturated_echo());
    det.reset();
    try std.testing.expect(!det.is_saturated_echo());
}

test "saturation_detector empty slice" {
    const det = try SaturationDetector.init(1.0);
    try std.testing.expect(!det.detect(&[_]f32{}));
    try std.testing.expectEqual(@as(usize, 0), det.count_saturated(&[_]f32{}));
}

test "saturation_detector invalid threshold" {
    try std.testing.expectError(error.InvalidThreshold, SaturationDetector.init(0.0));
    try std.testing.expectError(error.InvalidThreshold, SaturationDetector.init(-1.0));
}
