//! Ported from: docs/aec3-rs-src/audio_processing/aec3/stationarity_estimator.rs
//! Estimates render signal stationarity for each frequency bin.
const std = @import("std");
const common = @import("../common/aec3_common.zig");
const spectrum_buffer_mod = @import("../buffer/spectrum_ring_buffer.zig");
const apm = @import("../../log/apm_data_dumper.zig");

const FFT_LENGTH_BY_2_PLUS_1 = common.FFT_LENGTH_BY_2_PLUS_1;
const NUM_BLOCKS_PER_SECOND = common.NUM_BLOCKS_PER_SECOND;
const SpectrumBuffer = spectrum_buffer_mod.SpectrumRingBuffer;
const ApmDataDumper = apm.ApmDataDumper;

const WINDOW_LENGTH: usize = 13;
const MIN_NOISE_POWER: f32 = 10.0;
const HANGOVER_BLOCKS: i32 = @as(i32, @intCast(NUM_BLOCKS_PER_SECOND / 20));
const BLOCKS_AVERAGE_INIT_PHASE: usize = 20;
const BLOCKS_INITIAL_PHASE: usize = 2 * NUM_BLOCKS_PER_SECOND;
const STATIONARITY_THRESHOLD: f32 = 10.0;

/// Internal noise spectrum estimator.
const NoiseSpectrum = struct {
    const Self = @This();

    noise_spectrum: [FFT_LENGTH_BY_2_PLUS_1]f32,
    block_counter: usize,

    fn init() Self {
        var ns = Self{ .noise_spectrum = undefined, .block_counter = 0 };
        ns.reset();
        return ns;
    }

    fn reset(self: *Self) void {
        self.block_counter = 0;
        self.noise_spectrum = [_]f32{MIN_NOISE_POWER} ** FFT_LENGTH_BY_2_PLUS_1;
    }

    fn spectrum(self: *const Self) []const f32 {
        return &self.noise_spectrum;
    }

    fn power(self: *const Self, band: usize) f32 {
        return self.noise_spectrum[band];
    }

    fn update(self: *Self, spectra: []const [FFT_LENGTH_BY_2_PLUS_1]f32) void {
        const num_channels = spectra.len;
        // Compute average across channels.
        var avg: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;
        if (num_channels == 1) {
            avg = spectra[0];
        } else {
            avg = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
            for (spectra) |ch| {
                for (&avg, ch) |*a, v| a.* += v;
            }
            const inv: f32 = 1.0 / @as(f32, @floatFromInt(num_channels));
            for (&avg) |*v| v.* *= inv;
        }

        self.block_counter += 1;
        const alpha = self.get_alpha();
        for (0..FFT_LENGTH_BY_2_PLUS_1) |k| {
            if (self.block_counter <= BLOCKS_AVERAGE_INIT_PHASE) {
                self.noise_spectrum[k] += avg[k] / @as(f32, @floatFromInt(BLOCKS_AVERAGE_INIT_PHASE));
            } else {
                self.noise_spectrum[k] = self.update_band_by_smoothing(avg[k], self.noise_spectrum[k], alpha);
            }
        }
    }

    fn get_alpha(self: *const Self) f32 {
        const ALPHA: f32 = 0.004;
        const ALPHA_INIT: f32 = 0.04;
        const TILT: f32 = (ALPHA_INIT - ALPHA) / @as(f32, @floatFromInt(BLOCKS_INITIAL_PHASE));
        if (self.block_counter > BLOCKS_INITIAL_PHASE + BLOCKS_AVERAGE_INIT_PHASE) {
            return ALPHA;
        }
        return ALPHA_INIT - TILT * (@as(f32, @floatFromInt(self.block_counter)) - @as(f32, @floatFromInt(BLOCKS_AVERAGE_INIT_PHASE)));
    }

    fn update_band_by_smoothing(self: *const Self, power_band: f32, noise_band_in: f32, alpha: f32) f32 {
        var noise_band = noise_band_in;
        if (noise_band < power_band) {
            if (power_band > 0.0) {
                var alpha_inc = alpha * (noise_band / power_band);
                if (self.block_counter > BLOCKS_INITIAL_PHASE and 10.0 * noise_band < power_band) {
                    alpha_inc *= 0.1;
                }
                noise_band += alpha_inc * (power_band - noise_band);
            }
        } else {
            noise_band += alpha * (power_band - noise_band);
            noise_band = @max(noise_band, MIN_NOISE_POWER);
        }
        return noise_band;
    }
};

/// Estimates render stationarity for each frequency bin.
pub const StationarityEstimator = struct {
    const Self = @This();

    data_dumper: ApmDataDumper,
    noise: NoiseSpectrum,
    hangovers: [FFT_LENGTH_BY_2_PLUS_1]i32,
    stationarity_flags: [FFT_LENGTH_BY_2_PLUS_1]bool,

    pub fn init() Self {
        var est = Self{
            .data_dumper = ApmDataDumper.new_unique(),
            .noise = NoiseSpectrum.init(),
            .hangovers = [_]i32{0} ** FFT_LENGTH_BY_2_PLUS_1,
            .stationarity_flags = [_]bool{false} ** FFT_LENGTH_BY_2_PLUS_1,
        };
        est.reset();
        return est;
    }

    pub fn reset(self: *Self) void {
        self.noise.reset();
        self.hangovers = [_]i32{0} ** FFT_LENGTH_BY_2_PLUS_1;
        self.stationarity_flags = [_]bool{false} ** FFT_LENGTH_BY_2_PLUS_1;
    }

    pub fn update_noise_estimator(self: *Self, spectra: []const [FFT_LENGTH_BY_2_PLUS_1]f32) void {
        if (spectra.len == 0) return;
        self.noise.update(spectra);
    }

    pub fn update_stationarity_flags(
        self: *Self,
        spectrum_buffer: *const SpectrumBuffer,
        average_reverb: []const f32,
        idx_current: usize,
        num_lookahead: i32,
    ) void {
        std.debug.assert(average_reverb.len == FFT_LENGTH_BY_2_PLUS_1);

        var indexes: [WINDOW_LENGTH]usize = undefined;
        const num_lookahead_bounded = std.math.clamp(num_lookahead, 0, @as(i32, WINDOW_LENGTH - 1));
        var idx = idx_current;
        if (num_lookahead_bounded < @as(i32, WINDOW_LENGTH - 1)) {
            const num_lookback = @as(i32, WINDOW_LENGTH - 1) - num_lookahead_bounded;
            idx = spectrum_buffer.offset_index(idx_current, @as(isize, num_lookback));
        }
        indexes[0] = idx;
        for (1..WINDOW_LENGTH) |k| {
            indexes[k] = spectrum_buffer.dec_index(indexes[k - 1]);
        }

        for (0..FFT_LENGTH_BY_2_PLUS_1) |band| {
            self.stationarity_flags[band] =
                self.estimate_band_stationarity(spectrum_buffer, average_reverb, &indexes, band);
        }
        self.update_hangover();
        self.smooth_stationary_per_freq();
    }

    pub fn is_band_stationary(self: *const Self, band: usize) bool {
        return self.stationarity_flags[band] and self.hangovers[band] == 0;
    }

    pub fn is_block_stationary(self: *const Self) bool {
        var stationary_bins: usize = 0;
        for (0..FFT_LENGTH_BY_2_PLUS_1) |band| {
            if (self.is_band_stationary(band)) stationary_bins += 1;
        }
        return @as(f32, @floatFromInt(stationary_bins)) / @as(f32, FFT_LENGTH_BY_2_PLUS_1) > 0.75;
    }

    // ── Private ──

    fn estimate_band_stationarity(
        self: *const Self,
        spectrum_buffer: *const SpectrumBuffer,
        average_reverb: []const f32,
        indexes: *const [WINDOW_LENGTH]usize,
        band: usize,
    ) bool {
        const num_render_channels = spectrum_buffer.buffer[0].len;
        const inv_channels: f32 = 1.0 / @as(f32, @floatFromInt(num_render_channels));
        var accumulated_power: f32 = 0.0;
        for (indexes) |idx| {
            for (0..num_render_channels) |ch| {
                accumulated_power += spectrum_buffer.buffer[idx][ch][band] * inv_channels;
            }
        }
        accumulated_power += average_reverb[band];
        const noise = @as(f32, WINDOW_LENGTH) * self.noise.power(band);
        std.debug.assert(noise > 0.0);
        return accumulated_power < STATIONARITY_THRESHOLD * noise;
    }

    fn update_hangover(self: *Self) void {
        var all_stationary = true;
        for (self.stationarity_flags) |flag| {
            if (!flag) {
                all_stationary = false;
                break;
            }
        }
        for (self.stationarity_flags, 0..) |flag, k| {
            if (!flag) {
                self.hangovers[k] = HANGOVER_BLOCKS;
            } else if (all_stationary) {
                self.hangovers[k] = @max(self.hangovers[k] - 1, 0);
            }
        }
    }

    fn smooth_stationary_per_freq(self: *Self) void {
        if (FFT_LENGTH_BY_2_PLUS_1 <= 2) return;
        var smoothed = [_]bool{false} ** FFT_LENGTH_BY_2_PLUS_1;
        for (1..FFT_LENGTH_BY_2_PLUS_1 - 1) |k| {
            smoothed[k] = self.stationarity_flags[k - 1] and
                self.stationarity_flags[k] and
                self.stationarity_flags[k + 1];
        }
        smoothed[0] = smoothed[1];
        smoothed[FFT_LENGTH_BY_2_PLUS_1 - 1] = smoothed[FFT_LENGTH_BY_2_PLUS_1 - 2];
        self.stationarity_flags = smoothed;
    }
};

// ---------------------------------------------------------------------------
// Inline tests
// ---------------------------------------------------------------------------

test "stationarity_estimator init and reset" {
    var est = StationarityEstimator.init();
    try std.testing.expect(!est.is_block_stationary());
    est.reset();
    try std.testing.expect(!est.is_block_stationary());
}

test "stationarity_estimator empty spectra noop" {
    var est = StationarityEstimator.init();
    const empty: []const [FFT_LENGTH_BY_2_PLUS_1]f32 = &.{};
    est.update_noise_estimator(empty);
    // Should not crash.
}

test "stationarity_estimator noise update with constant signal" {
    var est = StationarityEstimator.init();
    const spectra = [_][FFT_LENGTH_BY_2_PLUS_1]f32{[_]f32{100.0} ** FFT_LENGTH_BY_2_PLUS_1};
    for (0..50) |_| {
        est.update_noise_estimator(&spectra);
    }
    // Noise estimate should be close to 100.
    try std.testing.expect(est.noise.power(0) > 50.0);
    try std.testing.expect(est.noise.power(0) < 200.0);
}

test "stationarity_estimator stationary detection with constant input" {
    const allocator = std.testing.allocator;
    // Create a spectrum buffer with constant data across slots.
    var sb = try SpectrumBuffer.init(allocator, WINDOW_LENGTH + 5, 1);
    defer sb.deinit();

    // Fill all slots with constant power.
    for (sb.buffer) |slot| {
        for (slot) |*ch| {
            ch.* = [_]f32{100.0} ** FFT_LENGTH_BY_2_PLUS_1;
        }
    }

    var est = StationarityEstimator.init();
    // Train noise estimator on same constant.
    const spectra = [_][FFT_LENGTH_BY_2_PLUS_1]f32{[_]f32{100.0} ** FFT_LENGTH_BY_2_PLUS_1};
    for (0..50) |_| {
        est.update_noise_estimator(&spectra);
    }

    const avg_reverb = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    est.update_stationarity_flags(&sb, &avg_reverb, 0, 0);
    // With constant input matching noise, all bands should be stationary.
    try std.testing.expect(est.is_block_stationary());
}
