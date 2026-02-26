const std = @import("std");
const ns_common = @import("ns_common.zig");
const fast_math = @import("fast_math.zig");

/// Simultaneous quantile estimators
const SIMULT: usize = 3;

/// Long startup phase blocks (from aec3-rs ns_common)
const LONG_STARTUP_PHASE_BLOCKS: i32 = 200;

/// Quantile-based noise floor estimator (matches aec3-rs implementation)
pub const QuantileNoiseEstimator = struct {
    density: [SIMULT * ns_common.FFT_SIZE_BY_2_PLUS_1]f32,
    log_quantile: [SIMULT * ns_common.FFT_SIZE_BY_2_PLUS_1]f32,
    quantile: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32,
    counter: [SIMULT]i32,
    num_updates: i32,

    pub fn init() QuantileNoiseEstimator {
        var counter: [SIMULT]i32 = undefined;
        const one_by_simult: f32 = 1.0 / @as(f32, SIMULT);
        for (0..SIMULT) |i| {
            counter[i] = @intFromFloat(@floor(@as(f32, LONG_STARTUP_PHASE_BLOCKS) * (@as(f32, @floatFromInt(i)) + 1.0) * one_by_simult));
        }

        return QuantileNoiseEstimator{
            .density = [_]f32{0.3} ** (SIMULT * ns_common.FFT_SIZE_BY_2_PLUS_1),
            .log_quantile = [_]f32{8.0} ** (SIMULT * ns_common.FFT_SIZE_BY_2_PLUS_1),
            .quantile = [_]f32{0.0} ** ns_common.FFT_SIZE_BY_2_PLUS_1,
            .counter = counter,
            .num_updates = 1,
        };
    }

    pub fn estimate(
        self: *QuantileNoiseEstimator,
        signal_spectrum: []const f32,
        noise_spectrum: []f32,
    ) void {
        std.debug.assert(signal_spectrum.len >= ns_common.FFT_SIZE_BY_2_PLUS_1);
        std.debug.assert(noise_spectrum.len >= ns_common.FFT_SIZE_BY_2_PLUS_1);

        var log_spectrum: [ns_common.FFT_SIZE_BY_2_PLUS_1]f32 = undefined;
        fast_math.logApproximationSlice(signal_spectrum[0..ns_common.FFT_SIZE_BY_2_PLUS_1], &log_spectrum);

        var quantile_index_to_return: ?usize = null;

        for (0..SIMULT) |s| {
            const k = s * ns_common.FFT_SIZE_BY_2_PLUS_1;
            const one_by_counter_plus_1: f32 = 1.0 / (@as(f32, @floatFromInt(self.counter[s])) + 1.0);

            for (0..ns_common.FFT_SIZE_BY_2_PLUS_1) |i| {
                const j = k + i;
                const delta: f32 = if (self.density[j] > 1.0)
                    40.0 / self.density[j]
                else
                    40.0;

                const multiplier = delta * one_by_counter_plus_1;
                if (log_spectrum[i] > self.log_quantile[j]) {
                    self.log_quantile[j] += 0.25 * multiplier;
                } else {
                    self.log_quantile[j] -= 0.75 * multiplier;
                }

                const WIDTH: f32 = 0.01;
                const ONE_BY_WIDTH_PLUS_2: f32 = 1.0 / (2.0 * WIDTH);
                if (@abs(log_spectrum[i] - self.log_quantile[j]) < WIDTH) {
                    self.density[j] = (@as(f32, @floatFromInt(self.counter[s])) * self.density[j] + ONE_BY_WIDTH_PLUS_2) * one_by_counter_plus_1;
                }
            }

            if (self.counter[s] >= LONG_STARTUP_PHASE_BLOCKS) {
                self.counter[s] = 0;
                if (self.num_updates >= LONG_STARTUP_PHASE_BLOCKS) {
                    quantile_index_to_return = k;
                }
            }

            self.counter[s] += 1;
        }

        if (self.num_updates < LONG_STARTUP_PHASE_BLOCKS) {
            quantile_index_to_return = ns_common.FFT_SIZE_BY_2_PLUS_1 * (SIMULT - 1);
            self.num_updates += 1;
        }

        if (quantile_index_to_return) |k| {
            fast_math.expApproximationSlice(
                self.log_quantile[k .. k + ns_common.FFT_SIZE_BY_2_PLUS_1],
                &self.quantile,
            );
        }

        @memcpy(noise_spectrum[0..ns_common.FFT_SIZE_BY_2_PLUS_1], &self.quantile);
    }
};
