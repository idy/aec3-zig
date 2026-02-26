const std = @import("std");
const config = @import("../../api/config.zig");
const aec3_common = @import("aec3_common.zig");
const delay_estimate = @import("delay_estimate.zig");
const matched_filter = @import("matched_filter.zig");
const lag_aggregator = @import("matched_filter_lag_aggregator.zig");

pub const EchoPathDelayEstimator = struct {
    allocator: std.mem.Allocator,
    down_sampling_factor: usize,
    sub_block_size: usize,
    matched_filter_inst: matched_filter.MatchedFilter,
    lag_aggregator_inst: lag_aggregator.MatchedFilterLagAggregator,
    old_aggregated_lag: ?delay_estimate.DelayEstimate,
    consistent_estimate_counter: usize,

    pub fn init(
        allocator: std.mem.Allocator,
        cfg: *const config.EchoCanceller3Config,
    ) !EchoPathDelayEstimator {
        const factor = cfg.delay.down_sampling_factor;
        if (factor == 0 or aec3_common.BLOCK_SIZE % factor != 0) return error.InvalidConfiguration;
        const sub_block_size = aec3_common.BLOCK_SIZE / factor;

        var mf = try matched_filter.MatchedFilter.init(
            allocator,
            sub_block_size,
            aec3_common.MATCHED_FILTER_WINDOW_SIZE_SUB_BLOCKS,
            cfg.delay.num_filters,
            aec3_common.MATCHED_FILTER_ALIGNMENT_SHIFT_SIZE_SUB_BLOCKS,
            cfg.render_levels.poor_excitation_render_limit,
            cfg.delay.delay_estimate_smoothing,
            cfg.delay.delay_candidate_detection_threshold,
        );
        errdefer mf.deinit();
        var agg = try lag_aggregator.MatchedFilterLagAggregator.init(
            allocator,
            mf.max_filter_lag(),
            cfg.delay.delay_selection_thresholds,
        );
        errdefer agg.deinit();

        return .{
            .allocator = allocator,
            .down_sampling_factor = factor,
            .sub_block_size = sub_block_size,
            .matched_filter_inst = mf,
            .lag_aggregator_inst = agg,
            .old_aggregated_lag = null,
            .consistent_estimate_counter = 0,
        };
    }

    pub fn deinit(self: *EchoPathDelayEstimator) void {
        self.matched_filter_inst.deinit();
        self.lag_aggregator_inst.deinit();
        self.* = undefined;
    }

    pub fn reset(self: *EchoPathDelayEstimator, reset_delay_confidence: bool) void {
        self.lag_aggregator_inst.reset(reset_delay_confidence);
        self.matched_filter_inst.reset();
        self.old_aggregated_lag = null;
        self.consistent_estimate_counter = 0;
    }

    pub fn estimate_delay(
        self: *EchoPathDelayEstimator,
        render_buffer: *const matched_filter.DownsampledRenderBuffer,
        capture_block: []const f32,
        scratch_downsampled_capture: []f32,
    ) ?delay_estimate.DelayEstimate {
        if (capture_block.len != aec3_common.BLOCK_SIZE) return null;
        if (scratch_downsampled_capture.len < self.sub_block_size) return null;
        downsample_by_factor(capture_block, scratch_downsampled_capture[0..self.sub_block_size], self.down_sampling_factor);

        self.matched_filter_inst.update(render_buffer, scratch_downsampled_capture[0..self.sub_block_size]);
        var aggregated = self.lag_aggregator_inst.aggregate(self.matched_filter_inst.lag_estimates());
        if (aggregated) |*estimate| estimate.delay *= self.down_sampling_factor;

        if (self.old_aggregated_lag) |prev| {
            if (aggregated) |cur| {
                if (prev.delay == cur.delay) {
                    self.consistent_estimate_counter += 1;
                } else {
                    self.consistent_estimate_counter = 0;
                }
            }
        }
        self.old_aggregated_lag = aggregated;
        return aggregated;
    }
};

fn downsample_by_factor(input: []const f32, output: []f32, factor: usize) void {
    var out_i: usize = 0;
    var i: usize = 0;
    while (i < input.len and out_i < output.len) : (i += factor) {
        output[out_i] = input[i];
        out_i += 1;
    }
}

test "echo_path_delay_estimator tracks fixed delay" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var cfg = config.EchoCanceller3Config.default();
    cfg.delay.down_sampling_factor = 4;
    cfg.delay.num_filters = 10;

    var estimator = try EchoPathDelayEstimator.init(arena.allocator(), &cfg);

    var rb_storage = [_]f32{0.0} ** 4096;
    var render_buffer = matched_filter.DownsampledRenderBuffer.init(rb_storage[0..]);
    var capture = [_]f32{0.0} ** aec3_common.BLOCK_SIZE;
    var ds_capture = [_]f32{0.0} ** aec3_common.BLOCK_SIZE;

    const lag_ds: usize = 40;
    for (0..500) |frame| {
        for (0..16) |k| {
            const pos = (frame * 16 + k) % rb_storage.len;
            rb_storage[pos] = @sin(@as(f32, @floatFromInt(frame * 16 + k)) * 0.09) * 10_000.0;
            render_buffer.read = pos;
        }

        for (capture, 0..) |*y, i| {
            const idx = (render_buffer.read + lag_ds + capture.len - 1 - i / cfg.delay.down_sampling_factor) % rb_storage.len;
            y.* = rb_storage[idx];
        }

        _ = estimator.estimate_delay(&render_buffer, capture[0..], ds_capture[0..]);
    }

    const final = estimator.estimate_delay(&render_buffer, capture[0..], ds_capture[0..]);
    try std.testing.expect(final != null);
    try std.testing.expect(@abs(@as(i32, @intCast(final.?.delay)) - @as(i32, @intCast(lag_ds * cfg.delay.down_sampling_factor))) <= 8);
}

test "echo_path_delay_estimator init rollback on allocator failure" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const alloc = failing.allocator();

    var cfg = config.EchoCanceller3Config.default();
    cfg.delay.down_sampling_factor = 4;
    cfg.delay.num_filters = 8;

    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, EchoPathDelayEstimator.init(alloc, &cfg));

    failing.fail_index = failing.alloc_index + 1;
    try std.testing.expectError(error.OutOfMemory, EchoPathDelayEstimator.init(alloc, &cfg));

    failing.fail_index = std.math.maxInt(usize);
    var ok = try EchoPathDelayEstimator.init(alloc, &cfg);
    defer ok.deinit();
}
