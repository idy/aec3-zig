const std = @import("std");
const config = @import("../../api/config.zig");
const delay_estimate = @import("../delay/delay_estimate.zig");
const matched_filter = @import("matched_filter.zig");

const HISTOGRAM_DATA_SIZE: usize = 250;

pub const MatchedFilterLagAggregator = struct {
    allocator: std.mem.Allocator,
    histogram: []i32,
    histogram_data: [HISTOGRAM_DATA_SIZE]usize,
    histogram_data_index: usize,
    significant_candidate_found: bool,
    thresholds: config.DelaySelectionThresholds,

    pub fn init(
        allocator: std.mem.Allocator,
        max_filter_lag: usize,
        thresholds: config.DelaySelectionThresholds,
    ) !MatchedFilterLagAggregator {
        const histogram = try allocator.alloc(i32, max_filter_lag + 1);
        errdefer allocator.free(histogram);
        @memset(histogram, 0);
        return .{
            .allocator = allocator,
            .histogram = histogram,
            .histogram_data = [_]usize{0} ** HISTOGRAM_DATA_SIZE,
            .histogram_data_index = 0,
            .significant_candidate_found = false,
            .thresholds = thresholds,
        };
    }

    pub fn deinit(self: *MatchedFilterLagAggregator) void {
        self.allocator.free(self.histogram);
        self.* = undefined;
    }

    pub fn reset(self: *MatchedFilterLagAggregator, hard_reset: bool) void {
        @memset(self.histogram, 0);
        self.histogram_data = [_]usize{0} ** HISTOGRAM_DATA_SIZE;
        self.histogram_data_index = 0;
        if (hard_reset) self.significant_candidate_found = false;
    }

    pub fn aggregate(self: *MatchedFilterLagAggregator, lag_estimates: []const matched_filter.LagEstimate) ?delay_estimate.DelayEstimate {
        var best_accuracy: f32 = 0.0;
        var best_lag_index: ?usize = null;
        for (lag_estimates, 0..) |estimate, idx| {
            if (estimate.updated and estimate.reliable and estimate.accuracy > best_accuracy) {
                best_accuracy = estimate.accuracy;
                best_lag_index = idx;
            }
        }

        const best_idx = best_lag_index orelse return null;

        const old_lag = self.histogram_data[self.histogram_data_index];
        if (old_lag < self.histogram.len) self.histogram[old_lag] -= 1;

        var lag = lag_estimates[best_idx].lag;
        if (lag >= self.histogram.len) lag = self.histogram.len - 1;
        self.histogram_data[self.histogram_data_index] = lag;
        self.histogram[lag] += 1;
        self.histogram_data_index = (self.histogram_data_index + 1) % HISTOGRAM_DATA_SIZE;

        var candidate: usize = 0;
        var count: i32 = std.math.minInt(i32);
        for (self.histogram, 0..) |c, idx| {
            if (c > count or (c == count and idx > candidate)) {
                count = c;
                candidate = idx;
            }
        }

        if (count > self.thresholds.converged) self.significant_candidate_found = true;

        if (count > self.thresholds.converged or (count > self.thresholds.initial and !self.significant_candidate_found)) {
            const quality: delay_estimate.DelayEstimateQuality = if (self.significant_candidate_found) .refined else .coarse;
            return delay_estimate.DelayEstimate.new(quality, candidate);
        }

        return null;
    }
};

test "aggregator chooses strongest stable lag" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var agg = try MatchedFilterLagAggregator.init(arena.allocator(), 256, .{ .initial = 5, .converged = 20 });
    var estimates = [_]matched_filter.LagEstimate{
        matched_filter.LagEstimate.new(0.9, true, 80, true),
        matched_filter.LagEstimate.new(0.2, true, 100, true),
    };

    var got: ?delay_estimate.DelayEstimate = null;
    for (0..32) |_| got = agg.aggregate(estimates[0..]);
    try std.testing.expect(got != null);
    try std.testing.expectEqual(@as(usize, 80), got.?.delay);
}

test "aggregator returns null on unreliable updates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var agg = try MatchedFilterLagAggregator.init(arena.allocator(), 32, .{ .initial = 2, .converged = 4 });
    const estimates = [_]matched_filter.LagEstimate{matched_filter.LagEstimate.new(0.9, false, 10, true)};
    try std.testing.expect(agg.aggregate(estimates[0..]) == null);
}

test "aggregator init handles out of memory" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const alloc = failing.allocator();

    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, MatchedFilterLagAggregator.init(alloc, 64, .{ .initial = 5, .converged = 20 }));

    failing.fail_index = std.math.maxInt(usize);
    var agg = try MatchedFilterLagAggregator.init(alloc, 64, .{ .initial = 5, .converged = 20 });
    defer agg.deinit();
}

test "aggregator rejects stable output during rapid lag jitter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var agg = try MatchedFilterLagAggregator.init(arena.allocator(), 256, .{ .initial = 5, .converged = 20 });
    const estimates = [_]matched_filter.LagEstimate{matched_filter.LagEstimate.new(0.95, true, 0, true)};

    var stable_count: usize = 0;
    for (0..2000) |i| {
        const lag = (i * 17) % 200;
        var frame_est = estimates;
        frame_est[0] = matched_filter.LagEstimate.new(0.95, true, lag, true);
        const out = agg.aggregate(frame_est[0..]);
        if (out != null) stable_count += 1;
    }

    try std.testing.expect(stable_count == 0);
}
