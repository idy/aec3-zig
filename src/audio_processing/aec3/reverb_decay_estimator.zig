//! Ported from: docs/aec3-rs-src/audio_processing/aec3/reverb_decay_estimator.rs
//! Estimates the exponential decay rate of the late reverberation tail.
const std = @import("std");
const common = @import("aec3_common.zig");
const config_mod = @import("../../api/config.zig");

const FFT_LENGTH_BY_2 = common.FFT_LENGTH_BY_2;
const FFT_LENGTH_BY_2_LOG2 = common.FFT_LENGTH_BY_2_LOG2;
const fast_approx_log2f = common.fast_approx_log2f;
const get_time_domain_length = common.get_time_domain_length;
const EchoCanceller3Config = config_mod.EchoCanceller3Config;

const EARLY_REVERB_MIN_SIZE_BLOCKS: usize = 3;
const BLOCKS_PER_SECTION: usize = 6;
const EARLY_REVERB_FIRST_POINT_AT_LINEAR_REGRESSORS: f32 =
    -0.5 * @as(f32, @floatFromInt(BLOCKS_PER_SECTION * FFT_LENGTH_BY_2)) + 0.5;

fn symmetric_arithmetic_sum(n: usize) f32 {
    const n_f: f32 = @floatFromInt(n);
    return n_f * (n_f * n_f - 1.0) / 12.0;
}

fn block_energy_peak(filter: []const f32, block_index: usize) f32 {
    const start = block_index * FFT_LENGTH_BY_2;
    const end = start + FFT_LENGTH_BY_2;
    var peak: f32 = 0.0;
    for (filter[start..end]) |v| {
        const e = v * v;
        if (e > peak) peak = e;
    }
    return peak;
}

fn block_energy_average(filter: []const f32, block_index: usize) f32 {
    const start = block_index * FFT_LENGTH_BY_2;
    const end = start + FFT_LENGTH_BY_2;
    var sum: f32 = 0.0;
    for (filter[start..end]) |v| sum += v * v;
    return sum / @as(f32, FFT_LENGTH_BY_2);
}

fn analyze_block_gain(block: []const f32, floor_gain: f32, previous_gain: *f32) struct { adapting: bool, above_noise_floor: bool } {
    var sum: f32 = 0.0;
    for (block) |v| sum += v;
    var gain = sum / @as(f32, FFT_LENGTH_BY_2);
    gain = @max(gain, 1e-32);
    const block_adapting = previous_gain.* > 1.1 * gain or previous_gain.* < 0.9 * gain;
    const decaying_gain = gain > floor_gain;
    previous_gain.* = gain;
    return .{ .adapting = block_adapting, .above_noise_floor = decaying_gain };
}

/// Linear regressor for estimating late reverb decay slope.
const LateReverbLinearRegressor = struct {
    const Self = @This();

    nz: f32,
    nn: f32,
    count: f32,
    total_points: usize,
    accumulated_points: usize,

    fn init() Self {
        return .{ .nz = 0.0, .nn = 0.0, .count = 0.0, .total_points = 0, .accumulated_points = 0 };
    }

    fn reset(self: *Self, num_data_points: usize) void {
        self.total_points = num_data_points;
        self.accumulated_points = 0;
        self.nz = 0.0;
        if (num_data_points == 0) {
            self.nn = 0.0;
            self.count = 0.0;
        } else {
            self.nn = symmetric_arithmetic_sum(num_data_points);
            self.count = -@as(f32, @floatFromInt(num_data_points)) * 0.5 + 0.5;
        }
    }

    fn accumulate(self: *Self, z: f32) void {
        self.nz += self.count * z;
        self.count += 1.0;
        self.accumulated_points += 1;
    }

    fn estimate_available(self: *const Self) bool {
        return self.total_points != 0 and self.accumulated_points == self.total_points;
    }

    fn estimate(self: *const Self) f32 {
        return if (self.nn == 0.0) 0.0 else self.nz / self.nn;
    }
};

/// Estimates the early reverb length by analyzing linear regression numerators across sections.
const EarlyReverbLengthEstimator = struct {
    const Self = @This();

    numerators_smooth: []f32,
    numerators: []f32,
    coefficients_counter: usize,
    block_counter: usize,
    n_sections: usize,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator, max_blocks: usize) !Self {
        const size = if (max_blocks > BLOCKS_PER_SECTION) max_blocks - BLOCKS_PER_SECTION else 0;
        const num_smooth = try allocator.alloc(f32, size);
        errdefer allocator.free(num_smooth);
        const num = try allocator.alloc(f32, size);
        errdefer allocator.free(num);
        @memset(num_smooth, 0.0);
        @memset(num, 0.0);
        return .{
            .numerators_smooth = num_smooth,
            .numerators = num,
            .coefficients_counter = 0,
            .block_counter = 0,
            .n_sections = 0,
            .allocator = allocator,
        };
    }

    fn deinit(self: *Self) void {
        self.allocator.free(self.numerators_smooth);
        self.allocator.free(self.numerators);
    }

    fn reset(self: *Self) void {
        self.coefficients_counter = 0;
        self.block_counter = 0;
        self.n_sections = 0;
        @memset(self.numerators, 0.0);
    }

    fn accumulate(self: *Self, value: f32, smoothing: f32) void {
        if (self.numerators.len == 0) {
            self.advance_counters();
            return;
        }
        const first_section_index = if (self.block_counter >= BLOCKS_PER_SECTION - 1)
            self.block_counter - (BLOCKS_PER_SECTION - 1)
        else
            0;
        const last_section_index = @min(self.block_counter, self.numerators.len - 1);
        const x_value = @as(f32, @floatFromInt(self.coefficients_counter)) +
            EARLY_REVERB_FIRST_POINT_AT_LINEAR_REGRESSORS;
        const value_to_inc = @as(f32, FFT_LENGTH_BY_2) * value;
        var value_to_add = x_value * value +
            @as(f32, @floatFromInt(self.block_counter - last_section_index)) * value_to_inc;

        // Iterate in reverse from last_section_index to first_section_index.
        var section_i: isize = @intCast(last_section_index);
        while (section_i >= @as(isize, @intCast(first_section_index))) : (section_i -= 1) {
            const section: usize = @intCast(section_i);
            self.numerators[section] += value_to_add;
            value_to_add += value_to_inc;
        }

        if (self.coefficients_counter + 1 == FFT_LENGTH_BY_2) {
            if (self.block_counter + 1 >= BLOCKS_PER_SECTION) {
                const section = self.block_counter + 1 - BLOCKS_PER_SECTION;
                if (section < self.numerators.len) {
                    self.numerators_smooth[section] +=
                        smoothing * (self.numerators[section] - self.numerators_smooth[section]);
                    self.n_sections = section + 1;
                }
            }
            self.block_counter += 1;
            self.coefficients_counter = 0;
        } else {
            self.coefficients_counter += 1;
        }
    }

    fn estimate(self: *const Self) usize {
        const NUM_SECTIONS_TO_ANALYZE: usize = 9;
        if (self.n_sections < NUM_SECTIONS_TO_ANALYZE or
            self.numerators_smooth.len < NUM_SECTIONS_TO_ANALYZE)
        {
            return 0;
        }
        const n = BLOCKS_PER_SECTION * FFT_LENGTH_BY_2;
        const nn = symmetric_arithmetic_sum(n);
        const NUMERATOR_11: f32 = 0.13750352374993502;
        const NUMERATOR_08: f32 = -0.32192809488736229;
        const numerator_11 = NUMERATOR_11 * nn / @as(f32, FFT_LENGTH_BY_2);
        const numerator_08 = NUMERATOR_08 * nn / @as(f32, FFT_LENGTH_BY_2);

        var min_tail: f32 = std.math.inf(f32);
        for (self.numerators_smooth[NUM_SECTIONS_TO_ANALYZE..self.n_sections]) |v| {
            min_tail = @min(min_tail, v);
        }

        var early_reverb_size_minus1: usize = 0;
        for (0..NUM_SECTIONS_TO_ANALYZE) |k| {
            const v = self.numerators_smooth[k];
            if (v > numerator_11 or (v < numerator_08 and v < 0.9 * min_tail)) {
                early_reverb_size_minus1 = k;
            }
        }
        return if (early_reverb_size_minus1 == 0) 0 else early_reverb_size_minus1 + 1;
    }

    fn advance_counters(self: *Self) void {
        if (self.coefficients_counter + 1 == FFT_LENGTH_BY_2) {
            self.block_counter += 1;
            self.coefficients_counter = 0;
        } else {
            self.coefficients_counter += 1;
        }
    }
};

/// Estimates the exponential decay rate of the late reverberation tail.
pub const ReverbDecayEstimator = struct {
    const Self = @This();

    filter_length_blocks: usize,
    filter_length_coefficients: usize,
    use_adaptive_echo_decay: bool,
    late_reverb_decay_estimator: LateReverbLinearRegressor,
    early_reverb_estimator: EarlyReverbLengthEstimator,
    late_reverb_start: usize,
    late_reverb_end: usize,
    block_to_analyze: usize,
    estimation_region_candidate_size: usize,
    estimation_region_identified: bool,
    previous_gains: []f32,
    decay_value: f32,
    tail_gain: f32,
    smoothing_constant: f32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, cfg: *const EchoCanceller3Config) !Self {
        std.debug.assert(cfg.filter.main.length_blocks > EARLY_REVERB_MIN_SIZE_BLOCKS);
        const filter_length_blocks = cfg.filter.main.length_blocks;
        const prev_gains = try allocator.alloc(f32, filter_length_blocks);
        errdefer allocator.free(prev_gains);
        @memset(prev_gains, 0.0);
        var early = try EarlyReverbLengthEstimator.init(
            allocator,
            filter_length_blocks - EARLY_REVERB_MIN_SIZE_BLOCKS,
        );
        errdefer early.deinit();
        return .{
            .filter_length_blocks = filter_length_blocks,
            .filter_length_coefficients = get_time_domain_length(filter_length_blocks),
            .use_adaptive_echo_decay = cfg.ep_strength.default_len < 0.0,
            .late_reverb_decay_estimator = LateReverbLinearRegressor.init(),
            .early_reverb_estimator = early,
            .late_reverb_start = EARLY_REVERB_MIN_SIZE_BLOCKS,
            .late_reverb_end = EARLY_REVERB_MIN_SIZE_BLOCKS,
            .block_to_analyze = 0,
            .estimation_region_candidate_size = 0,
            .estimation_region_identified = false,
            .previous_gains = prev_gains,
            .decay_value = @abs(cfg.ep_strength.default_len),
            .tail_gain = 0.0,
            .smoothing_constant = 0.0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.early_reverb_estimator.deinit();
        self.allocator.free(self.previous_gains);
        self.* = undefined;
    }

    pub fn update(
        self: *Self,
        filter: []const f32,
        filter_quality: ?f32,
        filter_delay_blocks: i32,
        usable_linear_filter: bool,
        stationary_signal: bool,
    ) void {
        if (stationary_signal) return;

        const filter_size = filter.len;
        const estimation_feasible = filter_delay_blocks > 0 and
            @as(usize, @intCast(filter_delay_blocks)) <=
                self.filter_length_blocks - EARLY_REVERB_MIN_SIZE_BLOCKS - 1 and
            filter_size == self.filter_length_coefficients and
            usable_linear_filter;

        if (!estimation_feasible) {
            self.reset_decay_estimation();
            return;
        }

        if (!self.use_adaptive_echo_decay) return;

        const new_smoothing = (filter_quality orelse 0.0) * 0.2;
        if (new_smoothing > self.smoothing_constant) {
            self.smoothing_constant = new_smoothing;
        }
        if (self.smoothing_constant == 0.0) return;

        if (self.block_to_analyze < self.filter_length_blocks) {
            self.analyze_filter(filter);
            self.block_to_analyze += 1;
        } else {
            self.estimate_decay(filter, @intCast(filter_delay_blocks));
        }
    }

    pub fn decay(self: *const Self) f32 {
        return self.decay_value;
    }

    // ── Private ──

    fn reset_decay_estimation(self: *Self) void {
        self.early_reverb_estimator.reset();
        self.late_reverb_decay_estimator.reset(0);
        self.block_to_analyze = 0;
        self.estimation_region_candidate_size = 0;
        self.estimation_region_identified = false;
        self.smoothing_constant = 0.0;
        self.late_reverb_start = 0;
        self.late_reverb_end = 0;
    }

    fn estimate_decay(self: *Self, filter: []const f32, peak_block: usize) void {
        self.block_to_analyze = @min(
            peak_block + EARLY_REVERB_MIN_SIZE_BLOCKS,
            if (self.filter_length_blocks > 0) self.filter_length_blocks - 1 else 0,
        );

        const first_reverb_gain = block_energy_average(filter, self.block_to_analyze);
        const h_size_blocks = filter.len >> FFT_LENGTH_BY_2_LOG2;
        self.tail_gain = block_energy_average(filter, h_size_blocks - 1);
        const peak_energy = block_energy_peak(filter, peak_block);
        const sufficient_reverb_decay = first_reverb_gain > 4.0 * self.tail_gain;
        const valid_filter = first_reverb_gain > 2.0 * self.tail_gain and peak_energy < 100.0;

        const size_early_reverb = self.early_reverb_estimator.estimate();
        const size_late_reverb = self.estimation_region_candidate_size -| size_early_reverb;

        if (size_late_reverb >= 5) {
            if (valid_filter and self.late_reverb_decay_estimator.estimate_available()) {
                var decay_val = std.math.pow(
                    f32,
                    2.0,
                    self.late_reverb_decay_estimator.estimate() * @as(f32, FFT_LENGTH_BY_2),
                );
                const MAX_DECAY: f32 = 0.95;
                const MIN_DECAY: f32 = 0.02;
                decay_val = @max(decay_val, 0.97 * self.decay_value);
                decay_val = @min(decay_val, MAX_DECAY);
                decay_val = @max(decay_val, MIN_DECAY);
                self.decay_value += self.smoothing_constant * (decay_val - self.decay_value);
            }

            self.late_reverb_decay_estimator.reset(size_late_reverb * FFT_LENGTH_BY_2);
            self.late_reverb_start = @min(
                peak_block + EARLY_REVERB_MIN_SIZE_BLOCKS + size_early_reverb,
                if (self.filter_length_blocks > 0) self.filter_length_blocks - 1 else 0,
            );
            self.late_reverb_end = @min(
                if (self.estimation_region_candidate_size > 0)
                    self.block_to_analyze + self.estimation_region_candidate_size - 1
                else
                    self.block_to_analyze,
                if (self.filter_length_blocks > 0) self.filter_length_blocks - 1 else 0,
            );
        } else {
            self.late_reverb_decay_estimator.reset(0);
            self.late_reverb_start = 0;
            self.late_reverb_end = 0;
        }

        self.estimation_region_identified = !(valid_filter and sufficient_reverb_decay);
        self.estimation_region_candidate_size = 0;
        self.smoothing_constant = 0.0;
        self.early_reverb_estimator.reset();
    }

    fn analyze_filter(self: *Self, filter: []const f32) void {
        if (self.block_to_analyze >= self.filter_length_blocks) return;
        const start = self.block_to_analyze * FFT_LENGTH_BY_2;
        if (start + FFT_LENGTH_BY_2 > filter.len) return;
        const h_block = filter[start .. start + FFT_LENGTH_BY_2];

        var h2: [FFT_LENGTH_BY_2]f32 = undefined;
        for (&h2, h_block) |*dst, v| dst.* = v * v;

        const result = analyze_block_gain(&h2, self.tail_gain, &self.previous_gains[self.block_to_analyze]);
        if (result.adapting or !result.above_noise_floor) {
            self.estimation_region_identified = true;
        } else if (!self.estimation_region_identified) {
            self.estimation_region_candidate_size += 1;
        }

        if (self.block_to_analyze <= self.late_reverb_end) {
            if (self.block_to_analyze >= self.late_reverb_start) {
                for (h2) |h2_k| {
                    const h2_log2 = fast_approx_log2f(h2_k + 1e-10);
                    self.late_reverb_decay_estimator.accumulate(h2_log2);
                    self.early_reverb_estimator.accumulate(h2_log2, self.smoothing_constant);
                }
            } else {
                for (h2) |h2_k| {
                    const h2_log2 = fast_approx_log2f(h2_k + 1e-10);
                    self.early_reverb_estimator.accumulate(h2_log2, self.smoothing_constant);
                }
            }
        }
    }
};

// ---------------------------------------------------------------------------
// Inline tests
// ---------------------------------------------------------------------------

test "reverb_decay_estimator init and deinit" {
    const allocator = std.testing.allocator;
    var cfg = EchoCanceller3Config.default();
    cfg.filter.main.length_blocks = 40;
    var est = try ReverbDecayEstimator.init(allocator, &cfg);
    defer est.deinit();
    try std.testing.expectApproxEqAbs(@as(f32, 0.83), est.decay(), 1e-6);
}

test "reverb_decay_estimator stationary signal noop" {
    const allocator = std.testing.allocator;
    var cfg = EchoCanceller3Config.default();
    cfg.filter.main.length_blocks = 40;
    var est = try ReverbDecayEstimator.init(allocator, &cfg);
    defer est.deinit();
    const initial_decay = est.decay();
    const filter = try allocator.alloc(f32, get_time_domain_length(40));
    defer allocator.free(filter);
    @memset(filter, 0.0);

    est.update(filter, 1.0, 2, true, true); // stationary=true
    try std.testing.expectEqual(initial_decay, est.decay());
}

test "reverb_decay_estimator infeasible estimation resets" {
    const allocator = std.testing.allocator;
    var cfg = EchoCanceller3Config.default();
    cfg.filter.main.length_blocks = 40;
    var est = try ReverbDecayEstimator.init(allocator, &cfg);
    defer est.deinit();

    const filter = try allocator.alloc(f32, get_time_domain_length(40));
    defer allocator.free(filter);
    @memset(filter, 0.0);

    // filter_delay_blocks = 0 is not > 0, so infeasible.
    est.update(filter, 1.0, 0, true, false);
    try std.testing.expectEqual(@as(usize, 0), est.late_reverb_start);
}

test "reverb_decay_estimator non-adaptive stays constant" {
    const allocator = std.testing.allocator;
    var cfg = EchoCanceller3Config.default();
    cfg.filter.main.length_blocks = 40;
    cfg.ep_strength.default_len = 0.9; // positive → not adaptive
    var est = try ReverbDecayEstimator.init(allocator, &cfg);
    defer est.deinit();

    const initial_decay = est.decay();
    const filter = try allocator.alloc(f32, get_time_domain_length(40));
    defer allocator.free(filter);
    @memset(filter, 0.0);
    filter[FFT_LENGTH_BY_2 * 2] = 1.0; // peak at block 2

    for (0..100) |_| {
        est.update(filter, 1.0, 2, true, false);
    }
    try std.testing.expectEqual(initial_decay, est.decay());
}

test "symmetric_arithmetic_sum correctness" {
    // n=1: 1*(1-1)/12 = 0
    try std.testing.expectEqual(@as(f32, 0.0), symmetric_arithmetic_sum(1));
    // n=3: 3*(9-1)/12 = 3*8/12 = 2
    try std.testing.expectEqual(@as(f32, 2.0), symmetric_arithmetic_sum(3));
    // n=10: 10*(100-1)/12 = 10*99/12 = 82.5
    try std.testing.expectApproxEqAbs(@as(f32, 82.5), symmetric_arithmetic_sum(10), 1e-4);
}
