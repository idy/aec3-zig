const std = @import("std");

/// Tracks and reports the filter delay of the AEC system.
///
/// The delay is measured in blocks and is kept clamped to non-negative values.
/// An external delay (e.g. from a system API) can be reported once and queried
/// later to inform the convergence logic.
pub const FilterDelay = struct {
    delay_blocks: i32,
    min_delay: i32,
    external_delay_reported: bool,

    pub fn init() FilterDelay {
        return .{
            .delay_blocks = 0,
            .min_delay = 0,
            .external_delay_reported = false,
        };
    }

    /// Updates the tracked delay, clamping to >= 0.
    pub fn update(self: *FilterDelay, filter_delay_blocks: i32) void {
        self.delay_blocks = @max(filter_delay_blocks, 0);
        if (self.delay_blocks < self.min_delay or self.min_delay == 0) {
            self.min_delay = self.delay_blocks;
        }
    }

    /// Records that an externally-estimated delay has been provided.
    pub fn report_external_delay(self: *FilterDelay, delay: i32) void {
        self.delay_blocks = @max(delay, 0);
        self.external_delay_reported = true;
    }

    pub fn get_delay(self: *const FilterDelay) i32 {
        return self.delay_blocks;
    }

    pub fn get_min_delay(self: *const FilterDelay) i32 {
        return self.min_delay;
    }

    pub fn is_external_delay_reported(self: *const FilterDelay) bool {
        return self.external_delay_reported;
    }

    /// Returns the index of the peak absolute value in `impulse_response`.
    /// For an empty slice returns 0.
    pub fn find_peak_delay(impulse_response: []const f32) usize {
        if (impulse_response.len == 0) return 0;

        var best_idx: usize = 0;
        var best_abs: f32 = @abs(impulse_response[0]);
        for (impulse_response[1..], 1..) |sample, idx| {
            const a = @abs(sample);
            if (a > best_abs) {
                best_abs = a;
                best_idx = idx;
            }
        }
        return best_idx;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "filter_delay single peak detection" {
    const ir = [_]f32{ 0.0, 0.1, 0.5, 0.2, 0.0 };
    try std.testing.expectEqual(@as(usize, 2), FilterDelay.find_peak_delay(&ir));
}

test "filter_delay negative peak detection" {
    const ir = [_]f32{ 0.0, -0.9, 0.5, 0.2 };
    try std.testing.expectEqual(@as(usize, 1), FilterDelay.find_peak_delay(&ir));
}

test "filter_delay multiple equal peaks returns first" {
    const ir = [_]f32{ 0.0, 1.0, 0.0, 1.0 };
    try std.testing.expectEqual(@as(usize, 1), FilterDelay.find_peak_delay(&ir));
}

test "filter_delay zero response returns zero" {
    const ir = [_]f32{ 0.0, 0.0, 0.0 };
    try std.testing.expectEqual(@as(usize, 0), FilterDelay.find_peak_delay(&ir));
}

test "filter_delay empty response returns zero" {
    const ir = [_]f32{};
    try std.testing.expectEqual(@as(usize, 0), FilterDelay.find_peak_delay(&ir));
}

test "filter_delay update clamps negative" {
    var fd = FilterDelay.init();
    fd.update(-10);
    try std.testing.expectEqual(@as(i32, 0), fd.get_delay());
}

test "filter_delay update positive" {
    var fd = FilterDelay.init();
    fd.update(5);
    try std.testing.expectEqual(@as(i32, 5), fd.get_delay());
}

test "filter_delay min_delay tracking" {
    var fd = FilterDelay.init();
    fd.update(10);
    fd.update(3);
    fd.update(7);
    try std.testing.expectEqual(@as(i32, 3), fd.get_min_delay());
}

test "filter_delay external delay reported" {
    var fd = FilterDelay.init();
    try std.testing.expect(!fd.is_external_delay_reported());
    fd.report_external_delay(8);
    try std.testing.expect(fd.is_external_delay_reported());
    try std.testing.expectEqual(@as(i32, 8), fd.get_delay());
}

test "filter_delay external delay clamps negative" {
    var fd = FilterDelay.init();
    fd.report_external_delay(-5);
    try std.testing.expectEqual(@as(i32, 0), fd.get_delay());
    try std.testing.expect(fd.is_external_delay_reported());
}
