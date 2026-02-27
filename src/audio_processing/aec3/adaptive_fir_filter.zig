const std = @import("std");
const FixedPoint = @import("../../fixed_point.zig").FixedPoint;

const Q15 = FixedPoint(15);

pub const AdaptiveFirFilter = struct {
    allocator: std.mem.Allocator,
    taps: []i32,
    history: []i32,
    cursor: usize,
    mu_q15: i32,
    epsilon_q15: i32,

    pub fn init(allocator: std.mem.Allocator, num_taps: usize, mu: f32) !AdaptiveFirFilter {
        if (num_taps == 0) return error.InvalidConfiguration;
        if (!(mu > 0.0 and mu <= 1.0)) return error.InvalidConfiguration;

        const taps = try allocator.alloc(i32, num_taps);
        errdefer allocator.free(taps);
        @memset(taps, 0);

        const history = try allocator.alloc(i32, num_taps);
        errdefer allocator.free(history);
        @memset(history, 0);

        return .{
            .allocator = allocator,
            .taps = taps,
            .history = history,
            .cursor = 0,
            .mu_q15 = Q15.fromFloatRuntime(mu).raw,
            .epsilon_q15 = Q15.fromFloatRuntime(1e-6).raw,
        };
    }

    pub fn deinit(self: *AdaptiveFirFilter) void {
        self.allocator.free(self.taps);
        self.allocator.free(self.history);
        self.* = undefined;
    }

    pub fn reset(self: *AdaptiveFirFilter) void {
        @memset(self.taps, 0);
        @memset(self.history, 0);
        self.cursor = 0;
    }

    pub fn process_sample(self: *AdaptiveFirFilter, x: f32, d: f32) f32 {
        self.history[self.cursor] = Q15.fromFloatRuntime(x).raw;
        const d_q15 = Q15.fromFloatRuntime(d).raw;
        var y_q15: i64 = 0;
        var power_q15: i64 = self.epsilon_q15;

        var idx = self.cursor;
        for (self.taps) |h| {
            const xv = self.history[idx];
            y_q15 += (@as(i64, h) * xv) >> 15;
            power_q15 += (@as(i64, xv) * xv) >> 15;
            idx = if (idx == 0) self.history.len - 1 else idx - 1;
        }

        const err_q15 = @as(i64, d_q15) - y_q15;
        const alpha_q15 = if (power_q15 == 0)
            @as(i64, 0)
        else
            @divTrunc(@as(i64, self.mu_q15) * err_q15, power_q15);

        idx = self.cursor;
        for (self.taps) |*h| {
            const delta = @divTrunc(alpha_q15 * self.history[idx], 1 << 15);
            const updated = @as(i64, h.*) + delta;
            h.* = @intCast(std.math.clamp(updated, @as(i64, std.math.minInt(i32)), @as(i64, std.math.maxInt(i32))));
            idx = if (idx == 0) self.history.len - 1 else idx - 1;
        }

        self.cursor = (self.cursor + 1) % self.history.len;
        return Q15.fromRaw(@intCast(std.math.clamp(err_q15, @as(i64, std.math.minInt(i32)), @as(i64, std.math.maxInt(i32))))).toFloat();
    }

    pub fn taps_raw_view(self: *const AdaptiveFirFilter) []const i32 {
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
        for (af.taps_raw_view(), true_taps) |a_raw, b| {
            const a = Q15.fromRaw(a_raw).toFloat();
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
