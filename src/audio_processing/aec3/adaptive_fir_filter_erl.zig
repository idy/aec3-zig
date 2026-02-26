const std = @import("std");
const adaptive_fir_filter = @import("adaptive_fir_filter.zig");

pub const AdaptiveFirFilterErl = struct {
    base: adaptive_fir_filter.AdaptiveFirFilter,
    max_gain_linear: f32,

    pub fn init(allocator: std.mem.Allocator, num_taps: usize, mu: f32, max_gain_linear: f32) !AdaptiveFirFilterErl {
        if (max_gain_linear <= 0.0) return error.InvalidConfiguration;
        const base = try adaptive_fir_filter.AdaptiveFirFilter.init(allocator, num_taps, mu);
        return .{ .base = base, .max_gain_linear = max_gain_linear };
    }

    pub fn deinit(self: *AdaptiveFirFilterErl) void {
        self.base.deinit();
        self.* = undefined;
    }

    pub fn process_sample(self: *AdaptiveFirFilterErl, x: f32, d: f32) f32 {
        const err = self.base.process_sample(x, d);
        self.apply_erl_constraint();
        return err;
    }

    pub fn taps_view(self: *const AdaptiveFirFilterErl) []const f32 {
        return self.base.taps_view();
    }

    fn apply_erl_constraint(self: *AdaptiveFirFilterErl) void {
        var energy: f32 = 0.0;
        for (self.base.taps) |h| energy += h * h;
        if (energy <= self.max_gain_linear * self.max_gain_linear) return;
        const scale = self.max_gain_linear / @sqrt(energy);
        for (self.base.taps) |*h| h.* *= scale;
    }
};

test "adaptive_fir_filter_erl limits tap energy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var filter = try AdaptiveFirFilterErl.init(arena.allocator(), 4, 0.9, 0.5);
    for (0..200) |_| {
        _ = filter.process_sample(1.0, 2.0);
    }

    var energy: f32 = 0.0;
    for (filter.taps_view()) |h| energy += h * h;
    try std.testing.expect(energy <= 0.25001);
}

test "adaptive_fir_filter_erl rejects invalid gain" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectError(error.InvalidConfiguration, AdaptiveFirFilterErl.init(arena.allocator(), 4, 0.6, 0.0));
}
