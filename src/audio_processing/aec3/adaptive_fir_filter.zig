const std = @import("std");

pub const AdaptiveFirFilter = struct {
    allocator: std.mem.Allocator,
    taps: []f32,
    history: []f32,
    cursor: usize,
    mu: f32,
    epsilon: f32,

    pub fn init(allocator: std.mem.Allocator, num_taps: usize, mu: f32) !AdaptiveFirFilter {
        if (num_taps == 0) return error.InvalidConfiguration;
        if (!(mu > 0.0 and mu <= 1.0)) return error.InvalidConfiguration;

        const taps = try allocator.alloc(f32, num_taps);
        errdefer allocator.free(taps);
        @memset(taps, 0.0);

        const history = try allocator.alloc(f32, num_taps);
        errdefer allocator.free(history);
        @memset(history, 0.0);

        return .{
            .allocator = allocator,
            .taps = taps,
            .history = history,
            .cursor = 0,
            .mu = mu,
            .epsilon = 1e-6,
        };
    }

    pub fn deinit(self: *AdaptiveFirFilter) void {
        self.allocator.free(self.taps);
        self.allocator.free(self.history);
        self.* = undefined;
    }

    pub fn reset(self: *AdaptiveFirFilter) void {
        @memset(self.taps, 0.0);
        @memset(self.history, 0.0);
        self.cursor = 0;
    }

    pub fn process_sample(self: *AdaptiveFirFilter, x: f32, d: f32) f32 {
        self.history[self.cursor] = x;
        var y: f32 = 0.0;
        var power: f32 = self.epsilon;

        var idx = self.cursor;
        for (self.taps) |h| {
            const xv = self.history[idx];
            y += h * xv;
            power += xv * xv;
            idx = if (idx == 0) self.history.len - 1 else idx - 1;
        }

        const err = d - y;
        const alpha = self.mu * err / power;

        idx = self.cursor;
        for (self.taps) |*h| {
            h.* += alpha * self.history[idx];
            idx = if (idx == 0) self.history.len - 1 else idx - 1;
        }

        self.cursor = (self.cursor + 1) % self.history.len;
        return err;
    }

    pub fn taps_view(self: *const AdaptiveFirFilter) []const f32 {
        return self.taps;
    }
};

test "adaptive_fir_filter converges on simple delay path" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var af = try AdaptiveFirFilter.init(arena.allocator(), 8, 0.6);
    var delay_line = [_]f32{0.0} ** 8;
    const true_taps = [_]f32{ 0.0, 0.0, 0.75, -0.25, 0.0, 0.0, 0.0, 0.0 };

    var mse_before: f32 = 0.0;
    var mse_after: f32 = 0.0;
    for (0..2000) |n| {
        const x = @sin(@as(f32, @floatFromInt(n)) * 0.03) * 0.8 + @cos(@as(f32, @floatFromInt(n)) * 0.07) * 0.4;
        delay_line = .{ x, delay_line[0], delay_line[1], delay_line[2], delay_line[3], delay_line[4], delay_line[5], delay_line[6] };
        var d: f32 = 0.0;
        for (true_taps, delay_line) |h, xv| d += h * xv;
        _ = af.process_sample(x, d);

        var mse: f32 = 0.0;
        for (af.taps_view(), true_taps) |a, b| {
            const diff = a - b;
            mse += diff * diff;
        }
        if (n < 100) mse_before += mse;
        if (n >= 1900) mse_after += mse;
    }

    try std.testing.expect(mse_after < mse_before * 0.1);
}

test "adaptive_fir_filter rejects invalid configuration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectError(error.InvalidConfiguration, AdaptiveFirFilter.init(arena.allocator(), 0, 0.5));
    try std.testing.expectError(error.InvalidConfiguration, AdaptiveFirFilter.init(arena.allocator(), 8, 0.0));
    try std.testing.expectError(error.InvalidConfiguration, AdaptiveFirFilter.init(arena.allocator(), 8, 1.5));
}

test "adaptive_fir_filter init handles allocator failure" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const alloc = failing.allocator();

    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, AdaptiveFirFilter.init(alloc, 8, 0.5));

    failing.fail_index = failing.alloc_index + 1;
    try std.testing.expectError(error.OutOfMemory, AdaptiveFirFilter.init(alloc, 8, 0.5));

    failing.fail_index = std.math.maxInt(usize);
    var ok = try AdaptiveFirFilter.init(alloc, 8, 0.5);
    defer ok.deinit();
}
