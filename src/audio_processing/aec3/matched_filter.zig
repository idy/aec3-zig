const std = @import("std");
const aec3_common = @import("aec3_common.zig");

const SATURATION_LIMIT: f32 = 32_000.0;

pub const DownsampledRenderBuffer = struct {
    buffer: []f32,
    read: usize,

    pub fn init(storage: []f32) DownsampledRenderBuffer {
        return .{ .buffer = storage, .read = 0 };
    }
};

pub const LagEstimate = struct {
    accuracy: f32,
    reliable: bool,
    lag: usize,
    updated: bool,

    pub fn new(accuracy: f32, reliable: bool, lag: usize, updated: bool) LagEstimate {
        return .{ .accuracy = accuracy, .reliable = reliable, .lag = lag, .updated = updated };
    }
};

pub const MatchedFilter = struct {
    allocator: std.mem.Allocator,
    sub_block_size: usize,
    filter_intra_lag_shift: usize,
    excitation_limit: f32,
    smoothing: f32,
    matching_filter_threshold: f32,
    filters: []f32,
    lag_estimates_buf: []LagEstimate,
    filter_length: usize,
    num_filters: usize,

    pub fn init(
        allocator: std.mem.Allocator,
        sub_block_size: usize,
        window_size_sub_blocks: usize,
        num_matched_filters: usize,
        alignment_shift_sub_blocks: usize,
        excitation_limit: f32,
        smoothing: f32,
        matching_filter_threshold: f32,
    ) !MatchedFilter {
        if (sub_block_size == 0 or window_size_sub_blocks == 0) return error.InvalidConfiguration;
        if (aec3_common.BLOCK_SIZE % sub_block_size != 0) return error.InvalidConfiguration;
        const filter_length = window_size_sub_blocks * sub_block_size;
        const filters = try allocator.alloc(f32, num_matched_filters * filter_length);
        errdefer allocator.free(filters);
        @memset(filters, 0.0);

        const lag_estimates_buf = try allocator.alloc(LagEstimate, num_matched_filters);
        errdefer allocator.free(lag_estimates_buf);
        for (lag_estimates_buf) |*it| it.* = LagEstimate.new(0.0, false, 0, false);

        return .{
            .allocator = allocator,
            .sub_block_size = sub_block_size,
            .filter_intra_lag_shift = alignment_shift_sub_blocks * sub_block_size,
            .excitation_limit = excitation_limit,
            .smoothing = smoothing,
            .matching_filter_threshold = matching_filter_threshold,
            .filters = filters,
            .lag_estimates_buf = lag_estimates_buf,
            .filter_length = filter_length,
            .num_filters = num_matched_filters,
        };
    }

    pub fn deinit(self: *MatchedFilter) void {
        self.allocator.free(self.filters);
        self.allocator.free(self.lag_estimates_buf);
        self.* = undefined;
    }

    pub fn reset(self: *MatchedFilter) void {
        @memset(self.filters, 0.0);
        for (self.lag_estimates_buf) |*it| it.* = LagEstimate.new(0.0, false, 0, false);
    }

    pub fn update(self: *MatchedFilter, render_buffer: *const DownsampledRenderBuffer, capture: []const f32) void {
        if (self.num_filters == 0) return;
        if (capture.len != self.sub_block_size or render_buffer.buffer.len == 0) return;

        const x2_sum_threshold = @as(f32, @floatFromInt(self.filter_length)) * self.excitation_limit * self.excitation_limit;
        var error_sum_anchor: f32 = 0.0;
        for (capture) |y| error_sum_anchor += y * y;

        const buffer_size = render_buffer.buffer.len;
        var alignment_shift: usize = 0;
        var filter_start: usize = 0;
        for (0..self.num_filters) |index| {
            const start = (render_buffer.read + alignment_shift + self.sub_block_size - 1) % buffer_size;
            const filter = self.filters[filter_start .. filter_start + self.filter_length];
            const core = matched_filter_core(start, x2_sum_threshold, self.smoothing, render_buffer.buffer, capture, filter);
            const peak_index = detect_peak(filter);
            const absolute_lag = peak_index + alignment_shift;
            const reliable = peak_index > 2 and
                peak_index + 10 < self.filter_length and
                core.error_sum < self.matching_filter_threshold * error_sum_anchor;

            self.lag_estimates_buf[index] = LagEstimate.new(
                error_sum_anchor - core.error_sum,
                reliable,
                absolute_lag,
                core.filters_updated,
            );
            alignment_shift += self.filter_intra_lag_shift;
            filter_start += self.filter_length;
        }
    }

    pub fn lag_estimates(self: *const MatchedFilter) []const LagEstimate {
        return self.lag_estimates_buf;
    }

    pub fn max_filter_lag(self: *const MatchedFilter) usize {
        if (self.num_filters == 0) return 0;
        return self.num_filters * self.filter_intra_lag_shift + self.filter_length;
    }
};

const MatchedFilterCoreResult = struct {
    filters_updated: bool,
    error_sum: f32,
};

fn detect_peak(filter: []const f32) usize {
    var best_index: usize = 0;
    var best_value: f32 = 0.0;
    for (filter, 0..) |x, i| {
        const ax = @abs(x);
        if (ax > best_value) {
            best_value = ax;
            best_index = i;
        }
    }
    return best_index;
}

fn matched_filter_core(
    x_start_index_in: usize,
    x2_sum_threshold: f32,
    smoothing: f32,
    x: []const f32,
    y: []const f32,
    h: []f32,
) MatchedFilterCoreResult {
    var x_start_index = x_start_index_in;
    var filters_updated = false;
    var error_sum: f32 = 0.0;

    for (y) |y_sample| {
        var x2_sum: f32 = 0.0;
        var s: f32 = 0.0;
        var x_index = x_start_index;
        for (h) |h_k| {
            const x_k = x[x_index];
            x2_sum += x_k * x_k;
            s += h_k * x_k;
            x_index = if (x_index + 1 < x.len) x_index + 1 else 0;
        }

        const err = y_sample - s;
        const saturation = y_sample >= SATURATION_LIMIT or y_sample <= -SATURATION_LIMIT;
        error_sum += err * err;

        if (x2_sum > x2_sum_threshold and !saturation) {
            const alpha = smoothing * err / x2_sum;
            x_index = x_start_index;
            for (h) |*h_k| {
                h_k.* += alpha * x[x_index];
                x_index = if (x_index + 1 < x.len) x_index + 1 else 0;
            }
            filters_updated = true;
        }

        x_start_index = if (x_start_index > 0) x_start_index - 1 else x.len - 1;
    }

    return .{ .filters_updated = filters_updated, .error_sum = error_sum };
}

test "matched_filter can detect fixed lag" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var backing = [_]f32{0.0} ** 1024;
    for (backing, 0..) |*x, i| x.* = @sin(@as(f32, @floatFromInt(i)) * 0.12);
    var render = DownsampledRenderBuffer.init(backing[0..]);
    render.read = 200;

    var capture = [_]f32{0.0} ** 16;
    const lag: usize = 41;
    for (capture, 0..) |*y, i| {
        const idx = (render.read + lag + capture.len - 1 - i) % backing.len;
        y.* = backing[idx];
    }

    var mf = try MatchedFilter.init(arena.allocator(), 16, 8, 1, 4, 0.05, 0.7, 0.8);
    mf.update(&render, capture[0..]);
    const est = mf.lag_estimates()[0];
    try std.testing.expect(est.updated);
    try std.testing.expect(est.reliable);
    try std.testing.expect(@abs(@as(i32, @intCast(est.lag)) - @as(i32, @intCast(lag))) <= 2);
}

test "matched_filter rejects invalid config" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectError(error.InvalidConfiguration, MatchedFilter.init(arena.allocator(), 0, 8, 1, 4, 1.0, 0.7, 0.5));
    try std.testing.expectError(error.InvalidConfiguration, MatchedFilter.init(arena.allocator(), 7, 8, 1, 4, 1.0, 0.7, 0.5));
}

test "matched_filter init rollback on allocation failure" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const alloc = failing.allocator();

    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, MatchedFilter.init(alloc, 16, 8, 4, 4, 1.0, 0.7, 0.5));

    failing.fail_index = failing.alloc_index + 1;
    try std.testing.expectError(error.OutOfMemory, MatchedFilter.init(alloc, 16, 8, 4, 4, 1.0, 0.7, 0.5));

    failing.fail_index = std.math.maxInt(usize);
    var mf = try MatchedFilter.init(alloc, 16, 8, 4, 4, 1.0, 0.7, 0.5);
    defer mf.deinit();
}
