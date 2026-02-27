//! Ported from: docs/aec3-rs-src/audio_processing/aec3/fullband_erle_estimator.rs
//! Fullband ERLE estimator operating in log2 domain.
const std = @import("std");
const common = @import("aec3_common.zig");
const config_mod = @import("../../api/config.zig");

const FFT_LENGTH_BY_2_PLUS_1 = common.FFT_LENGTH_BY_2_PLUS_1;
const fast_approx_log2f = common.fast_approx_log2f;
const Erle = config_mod.Erle;

const EPSILON: f32 = 1e-3;
const X2_BAND_ENERGY_THRESHOLD: f32 = 44_015_068.0;
const BLOCKS_TO_HOLD_ERLE: i32 = 100;
const POINTS_TO_ACCUMULATE: i32 = 6;

/// Tracks instantaneous ERLE and quality estimates for one capture channel.
const ErleInstantaneous = struct {
    const Self = @This();

    clamp_quality_to_zero: bool,
    clamp_quality_to_one: bool,
    erle_log2: ?f32,
    inst_quality_estimate: f32,
    max_erle_log2: f32,
    min_erle_log2: f32,
    y2_accum: f32,
    e2_accum: f32,
    num_points: i32,

    fn init(cfg: *const Erle) Self {
        var inst = Self{
            .clamp_quality_to_zero = cfg.clamp_quality_estimate_to_zero,
            .clamp_quality_to_one = cfg.clamp_quality_estimate_to_one,
            .erle_log2 = null,
            .inst_quality_estimate = 0.0,
            .max_erle_log2 = -10.0,
            .min_erle_log2 = 33.0,
            .y2_accum = 0.0,
            .e2_accum = 0.0,
            .num_points = 0,
        };
        inst.reset();
        return inst;
    }

    fn reset(self: *Self) void {
        self.reset_accumulators();
        self.max_erle_log2 = -10.0;
        self.min_erle_log2 = 33.0;
        self.inst_quality_estimate = 0.0;
    }

    fn reset_accumulators(self: *Self) void {
        self.erle_log2 = null;
        self.inst_quality_estimate = 0.0;
        self.num_points = 0;
        self.e2_accum = 0.0;
        self.y2_accum = 0.0;
    }

    /// Accumulates one frame's energy sums. Returns true when a new estimate is ready.
    fn update(self: *Self, y2_sum: f32, e2_sum: f32) bool {
        self.e2_accum += e2_sum;
        self.y2_accum += y2_sum;
        self.num_points += 1;
        var updated = false;
        if (self.num_points == POINTS_TO_ACCUMULATE) {
            if (self.e2_accum > 0.0) {
                self.erle_log2 = fast_approx_log2f(self.y2_accum / self.e2_accum + EPSILON);
                updated = true;
            }
            self.num_points = 0;
            self.e2_accum = 0.0;
            self.y2_accum = 0.0;
        }
        if (updated) {
            self.update_max_min();
            self.update_quality_estimate();
        }
        return updated;
    }

    fn inst_erle_log2_value(self: *const Self) ?f32 {
        return self.erle_log2;
    }

    fn quality_estimate(self: *const Self) ?f32 {
        if (self.erle_log2 == null) return null;
        var value = self.inst_quality_estimate;
        if (self.clamp_quality_to_zero) value = @max(value, 0.0);
        if (self.clamp_quality_to_one) value = @min(value, 1.0);
        return value;
    }

    fn update_max_min(self: *Self) void {
        const value = self.erle_log2 orelse return;
        if (value > self.max_erle_log2) {
            self.max_erle_log2 = value;
        } else {
            self.max_erle_log2 -= 0.0004;
        }
        if (value < self.min_erle_log2) {
            self.min_erle_log2 = value;
        } else {
            self.min_erle_log2 += 0.0004;
        }
    }

    fn update_quality_estimate(self: *Self) void {
        const value = self.erle_log2 orelse return;
        var quality: f32 = 0.0;
        if (self.max_erle_log2 > self.min_erle_log2) {
            quality = (value - self.min_erle_log2) / (self.max_erle_log2 - self.min_erle_log2);
        }
        if (quality > self.inst_quality_estimate) {
            self.inst_quality_estimate = quality;
        } else {
            self.inst_quality_estimate += 0.07 * (quality - self.inst_quality_estimate);
        }
    }
};

/// Fullband ERLE estimator across capture channels, operating in log2 domain.
pub const FullBandErleEstimator = struct {
    const Self = @This();

    min_erle_log2: f32,
    max_erle_lf_log2: f32,
    hold_counters_time_domain: []i32,
    erle_time_domain_log2: []f32,
    instantaneous_erle: []ErleInstantaneous,
    linear_filters_qualities: []?f32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, cfg: *const Erle, num_capture_channels: usize) !Self {
        const min_erle_log2 = fast_approx_log2f(cfg.min + EPSILON);
        const max_erle_lf_log2 = fast_approx_log2f(cfg.max_l + EPSILON);

        const hold = try allocator.alloc(i32, num_capture_channels);
        errdefer allocator.free(hold);
        const erle_td = try allocator.alloc(f32, num_capture_channels);
        errdefer allocator.free(erle_td);
        const inst = try allocator.alloc(ErleInstantaneous, num_capture_channels);
        errdefer allocator.free(inst);
        const quals = try allocator.alloc(?f32, num_capture_channels);
        errdefer allocator.free(quals);

        for (inst) |*e| e.* = ErleInstantaneous.init(cfg);
        for (erle_td) |*v| v.* = min_erle_log2;
        @memset(hold, 0);
        @memset(quals, null);

        var estimator = Self{
            .min_erle_log2 = min_erle_log2,
            .max_erle_lf_log2 = max_erle_lf_log2,
            .hold_counters_time_domain = hold,
            .erle_time_domain_log2 = erle_td,
            .instantaneous_erle = inst,
            .linear_filters_qualities = quals,
            .allocator = allocator,
        };
        estimator.reset();
        return estimator;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.hold_counters_time_domain);
        self.allocator.free(self.erle_time_domain_log2);
        self.allocator.free(self.instantaneous_erle);
        self.allocator.free(self.linear_filters_qualities);
        self.* = undefined;
    }

    pub fn reset(self: *Self) void {
        for (self.instantaneous_erle) |*inst| inst.reset();
        self.update_quality_estimates();
        for (self.erle_time_domain_log2) |*v| v.* = self.min_erle_log2;
        @memset(self.hold_counters_time_domain, 0);
    }

    pub fn update(
        self: *Self,
        x2: *const [FFT_LENGTH_BY_2_PLUS_1]f32,
        y2: []const [FFT_LENGTH_BY_2_PLUS_1]f32,
        e2: []const [FFT_LENGTH_BY_2_PLUS_1]f32,
        converged_filters: []const bool,
    ) void {
        std.debug.assert(y2.len == e2.len);
        std.debug.assert(y2.len == converged_filters.len);

        var x2_sum: f32 = 0.0;
        for (x2) |v| x2_sum += v;

        for (converged_filters, 0..) |converged, ch| {
            if (converged) {
                if (x2_sum > X2_BAND_ENERGY_THRESHOLD * @as(f32, @floatFromInt(x2.len))) {
                    var y2_sum: f32 = 0.0;
                    for (y2[ch]) |v| y2_sum += v;
                    var e2_sum: f32 = 0.0;
                    for (e2[ch]) |v| e2_sum += v;
                    if (self.instantaneous_erle[ch].update(y2_sum, e2_sum)) {
                        self.hold_counters_time_domain[ch] = BLOCKS_TO_HOLD_ERLE;
                        if (self.instantaneous_erle[ch].inst_erle_log2_value()) |inst_erle| {
                            self.erle_time_domain_log2[ch] +=
                                0.1 * (inst_erle - self.erle_time_domain_log2[ch]);
                            self.erle_time_domain_log2[ch] = std.math.clamp(
                                self.erle_time_domain_log2[ch],
                                self.min_erle_log2,
                                self.max_erle_lf_log2,
                            );
                        }
                    }
                }
            }

            self.hold_counters_time_domain[ch] -= 1;
            if (self.hold_counters_time_domain[ch] <= 0) {
                self.erle_time_domain_log2[ch] =
                    @max(self.erle_time_domain_log2[ch] - 0.044, self.min_erle_log2);
            }
            if (self.hold_counters_time_domain[ch] == 0) {
                self.instantaneous_erle[ch].reset_accumulators();
            }
        }

        self.update_quality_estimates();
    }

    /// Returns the minimum fullband ERLE in log2 across all channels.
    pub fn fullband_erle_log2(self: *const Self) f32 {
        var result: f32 = self.min_erle_log2;
        var first = true;
        for (self.erle_time_domain_log2) |v| {
            if (first) {
                result = v;
                first = false;
            } else {
                result = @min(result, v);
            }
        }
        return result;
    }

    pub fn get_linear_quality_estimates(self: *const Self) []const ?f32 {
        return self.linear_filters_qualities;
    }

    fn update_quality_estimates(self: *Self) void {
        for (self.linear_filters_qualities, self.instantaneous_erle) |*quality, *inst| {
            quality.* = inst.quality_estimate();
        }
    }
};

// ---------------------------------------------------------------------------
// Inline tests
// ---------------------------------------------------------------------------

test "fullband_erle_estimator init and deinit" {
    const allocator = std.testing.allocator;
    const cfg = Erle.default();
    var est = try FullBandErleEstimator.init(allocator, &cfg, 2);
    defer est.deinit();

    // Initial ERLE should be at min.
    try std.testing.expect(est.fullband_erle_log2() == est.min_erle_log2);
    // Quality estimates should be null initially.
    for (est.get_linear_quality_estimates()) |q| {
        try std.testing.expectEqual(@as(?f32, null), q);
    }
}

test "fullband_erle_estimator increases with strong echo" {
    const allocator = std.testing.allocator;
    var cfg = Erle.default();
    cfg.max_l = 20.0;
    var est = try FullBandErleEstimator.init(allocator, &cfg, 1);
    defer est.deinit();

    var x2 = [_]f32{100_000_000.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var y2 = [_][FFT_LENGTH_BY_2_PLUS_1]f32{[_]f32{1_000_000_000.0} ** FFT_LENGTH_BY_2_PLUS_1};
    var e2 = [_][FFT_LENGTH_BY_2_PLUS_1]f32{[_]f32{100_000_000.0} ** FFT_LENGTH_BY_2_PLUS_1};
    const converged = [_]bool{true};

    const initial_erle = est.fullband_erle_log2();
    for (0..100) |_| {
        est.update(&x2, &y2, &e2, &converged);
    }
    // ERLE should have increased.
    try std.testing.expect(est.fullband_erle_log2() > initial_erle);
}

test "fullband_erle_estimator unconverged filter no update" {
    const allocator = std.testing.allocator;
    const cfg = Erle.default();
    var est = try FullBandErleEstimator.init(allocator, &cfg, 1);
    defer est.deinit();

    var x2 = [_]f32{100_000_000.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var y2 = [_][FFT_LENGTH_BY_2_PLUS_1]f32{[_]f32{1e9} ** FFT_LENGTH_BY_2_PLUS_1};
    var e2 = [_][FFT_LENGTH_BY_2_PLUS_1]f32{[_]f32{1e8} ** FFT_LENGTH_BY_2_PLUS_1};
    const converged = [_]bool{false};

    for (0..100) |_| {
        est.update(&x2, &y2, &e2, &converged);
    }
    // ERLE should stay at or below min since filter never converged and hold decays.
    try std.testing.expectEqual(est.min_erle_log2, est.fullband_erle_log2());
}

test "fullband_erle_estimator reset" {
    const allocator = std.testing.allocator;
    const cfg = Erle.default();
    var est = try FullBandErleEstimator.init(allocator, &cfg, 2);
    defer est.deinit();

    est.erle_time_domain_log2[0] = 5.0;
    est.reset();
    try std.testing.expectEqual(est.min_erle_log2, est.erle_time_domain_log2[0]);
    try std.testing.expectEqual(est.min_erle_log2, est.erle_time_domain_log2[1]);
}
