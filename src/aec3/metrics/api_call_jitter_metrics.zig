const std = @import("std");

pub const JitterSnapshot = struct {
    samples: u64,
    mean: f64,
    variance: f64,
    min_delta: i64,
    max_delta: i64,
    negative_deltas: u64,
};

pub const ApiCallJitterMetrics = struct {
    last_timestamp_us: ?i64 = null,
    sample_count: u64 = 0,
    negative_deltas: u64 = 0,
    sum_delta: f64 = 0.0,
    sum_delta_sq: f64 = 0.0,
    min_delta: i64 = std.math.maxInt(i64),
    max_delta: i64 = std.math.minInt(i64),

    pub fn recordCall(self: *ApiCallJitterMetrics, timestamp_us: i64) void {
        if (self.last_timestamp_us) |prev| {
            const delta = timestamp_us - prev;
            if (delta < 0) {
                self.negative_deltas += 1;
                self.last_timestamp_us = timestamp_us;
                return;
            }

            const delta_f = @as(f64, @floatFromInt(delta));
            self.sample_count += 1;
            self.sum_delta += delta_f;
            self.sum_delta_sq += delta_f * delta_f;
            self.min_delta = @min(self.min_delta, delta);
            self.max_delta = @max(self.max_delta, delta);
        }
        self.last_timestamp_us = timestamp_us;
    }

    pub fn snapshot(self: *const ApiCallJitterMetrics) JitterSnapshot {
        if (self.sample_count == 0) {
            return .{
                .samples = 0,
                .mean = 0.0,
                .variance = 0.0,
                .min_delta = 0,
                .max_delta = 0,
                .negative_deltas = self.negative_deltas,
            };
        }

        const n = @as(f64, @floatFromInt(self.sample_count));
        const mean = self.sum_delta / n;
        return .{
            .samples = self.sample_count,
            .mean = mean,
            .variance = @max(0.0, self.sum_delta_sq / n - mean * mean),
            .min_delta = self.min_delta,
            .max_delta = self.max_delta,
            .negative_deltas = self.negative_deltas,
        };
    }
};

test "api_call_jitter_metrics normal accumulation" {
    var metrics = ApiCallJitterMetrics{};
    metrics.recordCall(0);
    metrics.recordCall(10_000);
    metrics.recordCall(20_000);
    metrics.recordCall(30_000);

    const s = metrics.snapshot();
    try std.testing.expectEqual(@as(u64, 3), s.samples);
    try std.testing.expectApproxEqAbs(@as(f64, 10_000.0), s.mean, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), s.variance, 1e-9);
}

test "api_call_jitter_metrics single call boundary" {
    var metrics = ApiCallJitterMetrics{};
    metrics.recordCall(123_456);
    const s = metrics.snapshot();
    try std.testing.expectEqual(@as(u64, 0), s.samples);
    try std.testing.expectEqual(@as(i64, 0), s.min_delta);
    try std.testing.expectEqual(@as(i64, 0), s.max_delta);
}

test "api_call_jitter_metrics extreme jitter" {
    var metrics = ApiCallJitterMetrics{};
    metrics.recordCall(0);
    metrics.recordCall(1);
    metrics.recordCall(1_000_000);

    const s = metrics.snapshot();
    try std.testing.expectEqual(@as(i64, 1), s.min_delta);
    try std.testing.expectEqual(@as(i64, 999_999), s.max_delta);
}

test "api_call_jitter_metrics negative delta handling" {
    var metrics = ApiCallJitterMetrics{};
    metrics.recordCall(1000);
    metrics.recordCall(900);
    metrics.recordCall(1100);
    const s = metrics.snapshot();
    try std.testing.expectEqual(@as(u64, 1), s.samples);
    try std.testing.expectEqual(@as(u64, 1), s.negative_deltas);
    try std.testing.expectEqual(@as(i64, 200), s.min_delta);
}
