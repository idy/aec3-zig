const std = @import("std");

pub const ClockDriftLevel = enum {
    none,
    probable,
    verified,
};

pub const ClockDriftDetector = struct {
    const Self = @This();

    delay_history: [3]i32 = .{ 0, 0, 0 },
    level_state: ClockDriftLevel = .none,
    stability_counter: usize = 0,

    pub fn init() Self {
        return .{};
    }

    pub fn level(self: Self) ClockDriftLevel {
        return self.level_state;
    }

    pub fn update(self: *Self, delay_estimate: i32) void {
        if (delay_estimate == self.delay_history[0]) {
            self.stability_counter += 1;
            if (self.stability_counter > 7500) self.level_state = .none;
            return;
        }

        self.stability_counter = 0;
        const d1 = self.delay_history[0] - delay_estimate;
        const d2 = self.delay_history[1] - delay_estimate;
        const d3 = self.delay_history[2] - delay_estimate;

        const probable_up = (d1 == -1 and d2 == -2) or (d1 == -2 and d2 == -1);
        const drift_up = probable_up and d3 == -3;
        const probable_down = (d1 == 1 and d2 == 2) or (d1 == 2 and d2 == 1);
        const drift_down = probable_down and d3 == 3;

        if (drift_up or drift_down) {
            self.level_state = .verified;
        } else if ((probable_up or probable_down) and self.level_state == .none) {
            self.level_state = .probable;
        }

        self.delay_history[2] = self.delay_history[1];
        self.delay_history[1] = self.delay_history[0];
        self.delay_history[0] = delay_estimate;
    }
};

test "clockdrift_detector transition" {
    var d = ClockDriftDetector.init();
    try std.testing.expectEqual(ClockDriftLevel.none, d.level());
    d.update(1000);
    d.update(1001);
    d.update(1002);
    try std.testing.expectEqual(ClockDriftLevel.probable, d.level());
    d.update(1003);
    try std.testing.expectEqual(ClockDriftLevel.verified, d.level());
}
