const std = @import("std");
const aec3_common = @import("../common/aec3_common.zig");

pub const SubbandDetection = struct {
    per_band: [aec3_common.MAX_NUM_BANDS]bool,
    overall_nearend: bool,
};

pub const SubbandNearendDetector = struct {
    band_count: usize,
    enter_ratio: f32,
    exit_ratio: f32,
    states: [aec3_common.MAX_NUM_BANDS]bool = [_]bool{false} ** aec3_common.MAX_NUM_BANDS,

    pub fn init(band_count: usize, enter_ratio: f32, exit_ratio: f32) !SubbandNearendDetector {
        if (band_count == 0 or band_count > aec3_common.MAX_NUM_BANDS) return error.InvalidBandCount;
        if (enter_ratio <= 0.0 or exit_ratio <= 0.0 or enter_ratio < exit_ratio) return error.InvalidThreshold;
        return .{ .band_count = band_count, .enter_ratio = enter_ratio, .exit_ratio = exit_ratio };
    }

    pub fn detect(self: *SubbandNearendDetector, near: []const f32, echo: []const f32) !SubbandDetection {
        if (near.len != self.band_count or echo.len != self.band_count) return error.InvalidBandCount;

        var out = [_]bool{false} ** aec3_common.MAX_NUM_BANDS;
        var overall = false;
        for (0..self.band_count) |i| {
            const ratio = near[i] / @max(echo[i], 1e-9);
            if (!self.states[i] and ratio >= self.enter_ratio) {
                self.states[i] = true;
            } else if (self.states[i] and ratio < self.exit_ratio) {
                self.states[i] = false;
            }
            out[i] = self.states[i];
            overall = overall or self.states[i];
        }

        return .{ .per_band = out, .overall_nearend = overall };
    }
};

test "subband_nearend_detector subband independence" {
    var detector = try SubbandNearendDetector.init(3, 2.0, 1.5);
    const d = try detector.detect(&[_]f32{ 5.0, 1.0, 1.0 }, &[_]f32{ 1.0, 1.0, 1.0 });
    try std.testing.expect(d.per_band[0]);
    try std.testing.expect(!d.per_band[1]);
    try std.testing.expect(!d.per_band[2]);
}

test "subband_nearend_detector fusion logic" {
    var detector = try SubbandNearendDetector.init(3, 2.0, 1.5);
    const d = try detector.detect(&[_]f32{ 1.0, 3.0, 1.0 }, &[_]f32{ 1.0, 1.0, 1.0 });
    try std.testing.expect(d.overall_nearend);
}

test "subband_nearend_detector single band detection" {
    var detector = try SubbandNearendDetector.init(3, 2.0, 1.5);
    const d = try detector.detect(&[_]f32{ 1.0, 1.0, 4.0 }, &[_]f32{ 1.0, 1.0, 1.0 });
    try std.testing.expect(d.per_band[2]);
}

test "subband_nearend_detector invalid band count error" {
    try std.testing.expectError(error.InvalidBandCount, SubbandNearendDetector.init(0, 2.0, 1.5));
    var detector = try SubbandNearendDetector.init(2, 2.0, 1.5);
    try std.testing.expectError(error.InvalidBandCount, detector.detect(&[_]f32{ 1.0, 2.0, 3.0 }, &[_]f32{ 1.0, 2.0, 3.0 }));
}
