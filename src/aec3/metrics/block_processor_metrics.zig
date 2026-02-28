const std = @import("std");

const LATENCY_CAPACITY = 64;

pub const BlockProcessorSnapshot = struct {
    frames_processed: u64,
    samples_processed: u64,
    mean_latency_ms: f32,
    min_latency_ms: f32,
    max_latency_ms: f32,
    p90_latency_ms: f32,
};

pub const BlockProcessorMetrics = struct {
    frames_processed: u64 = 0,
    samples_processed: u64 = 0,
    sum_latency_ms: f32 = 0.0,
    min_latency_ms: f32 = std.math.inf(f32),
    max_latency_ms: f32 = 0.0,
    latencies: [LATENCY_CAPACITY]f32 = [_]f32{0.0} ** LATENCY_CAPACITY,
    latency_count: usize = 0,

    pub fn recordFrame(self: *BlockProcessorMetrics, samples: usize, latency_ms: f32) !void {
        if (latency_ms < 0.0) return error.InvalidLatency;
        if (samples == 0) return;

        self.frames_processed += 1;
        self.samples_processed += @as(u64, @intCast(samples));
        self.sum_latency_ms += latency_ms;
        self.min_latency_ms = @min(self.min_latency_ms, latency_ms);
        self.max_latency_ms = @max(self.max_latency_ms, latency_ms);

        if (self.latency_count < LATENCY_CAPACITY) {
            self.latencies[self.latency_count] = latency_ms;
            self.latency_count += 1;
        } else {
            const index = @as(usize, @intCast((self.frames_processed - 1) % LATENCY_CAPACITY));
            self.latencies[index] = latency_ms;
        }
    }

    pub fn snapshot(self: *const BlockProcessorMetrics) BlockProcessorSnapshot {
        if (self.frames_processed == 0) {
            return .{
                .frames_processed = 0,
                .samples_processed = 0,
                .mean_latency_ms = 0.0,
                .min_latency_ms = 0.0,
                .max_latency_ms = 0.0,
                .p90_latency_ms = 0.0,
            };
        }

        var sorted = self.latencies;
        std.mem.sort(f32, sorted[0..self.latency_count], {}, comptime std.sort.asc(f32));
        const idx = ((self.latency_count - 1) * 9) / 10;

        return .{
            .frames_processed = self.frames_processed,
            .samples_processed = self.samples_processed,
            .mean_latency_ms = self.sum_latency_ms / @as(f32, @floatFromInt(self.frames_processed)),
            .min_latency_ms = self.min_latency_ms,
            .max_latency_ms = self.max_latency_ms,
            .p90_latency_ms = sorted[idx],
        };
    }
};

test "block_processor_metrics accumulation over frames" {
    var metrics = BlockProcessorMetrics{};
    try metrics.recordFrame(160, 1.0);
    try metrics.recordFrame(160, 3.0);

    const s = metrics.snapshot();
    try std.testing.expectEqual(@as(u64, 2), s.frames_processed);
    try std.testing.expectEqual(@as(u64, 320), s.samples_processed);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), s.mean_latency_ms, 1e-6);
}

test "block_processor_metrics zero-length input" {
    var metrics = BlockProcessorMetrics{};
    try metrics.recordFrame(0, 1.0);
    const s = metrics.snapshot();
    try std.testing.expectEqual(@as(u64, 0), s.frames_processed);
    try std.testing.expectEqual(@as(u64, 0), s.samples_processed);
}

test "block_processor_metrics latency distribution" {
    var metrics = BlockProcessorMetrics{};
    try metrics.recordFrame(80, 1.0);
    try metrics.recordFrame(80, 2.0);
    try metrics.recordFrame(80, 4.0);
    try metrics.recordFrame(80, 8.0);

    const s = metrics.snapshot();
    try std.testing.expectEqual(@as(f32, 1.0), s.min_latency_ms);
    try std.testing.expectEqual(@as(f32, 8.0), s.max_latency_ms);
    try std.testing.expectEqual(@as(f32, 8.0), s.p90_latency_ms);
}

test "block_processor_metrics rejects invalid latency" {
    var metrics = BlockProcessorMetrics{};
    try std.testing.expectError(error.InvalidLatency, metrics.recordFrame(80, -0.1));
}

test "block_processor_metrics ring buffer overwrite index regression" {
    var metrics = BlockProcessorMetrics{};
    var i: usize = 0;
    while (i < LATENCY_CAPACITY) : (i += 1) {
        try metrics.recordFrame(1, @as(f32, @floatFromInt(i + 1)));
    }
    try metrics.recordFrame(1, 999.0);

    // 修复后首次溢出应回写到槽位 0。
    try std.testing.expectEqual(@as(f32, 999.0), metrics.latencies[0]);
}
