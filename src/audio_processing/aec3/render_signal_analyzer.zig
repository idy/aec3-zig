const std = @import("std");
const config = @import("../../api/config.zig");
const aec3_common = @import("aec3_common.zig");
const FixedPoint = @import("../../fixed_point.zig").FixedPoint;

const COUNTER_THRESHOLD: usize = 5;
const Q15 = FixedPoint(15);

fn q15_from_float(x: f32) i32 {
    return Q15.fromFloatRuntime(x / 32_000.0).raw;
}

pub const RenderSignalAnalyzer = struct {
    strong_peak_freeze_duration: usize,
    narrow_band_counters: [aec3_common.FFT_LENGTH_BY_2 - 1]usize,
    narrow_peak_band_state: ?usize,
    narrow_peak_counter: usize,

    pub fn init(cfg: *const config.EchoCanceller3Config) RenderSignalAnalyzer {
        return .{
            .strong_peak_freeze_duration = cfg.filter.main.length_blocks,
            .narrow_band_counters = [_]usize{0} ** (aec3_common.FFT_LENGTH_BY_2 - 1),
            .narrow_peak_band_state = null,
            .narrow_peak_counter = 0,
        };
    }

    pub fn update_from_spectrum(
        self: *RenderSignalAnalyzer,
        latest_time_block: []const f32,
        spectrum: []const f32,
        delay_known: bool,
    ) void {
        if (spectrum.len != aec3_common.FFT_LENGTH_BY_2_PLUS_1) return;
        if (!delay_known) {
            self.narrow_band_counters = [_]usize{0} ** (aec3_common.FFT_LENGTH_BY_2 - 1);
        } else {
            for (1..aec3_common.FFT_LENGTH_BY_2) |k| {
                const center = q15_from_float(spectrum[k]);
                const neigh = @max(q15_from_float(spectrum[k - 1]), q15_from_float(spectrum[k + 1]));
                if (center > 3 * neigh) {
                    self.narrow_band_counters[k - 1] += 1;
                } else {
                    self.narrow_band_counters[k - 1] = 0;
                }
            }
        }

        if (self.narrow_peak_band_state != null) {
            self.narrow_peak_counter += 1;
            if (self.narrow_peak_counter > self.strong_peak_freeze_duration) {
                self.narrow_peak_band_state = null;
            }
        }

        var peak_bin: usize = 0;
        var peak_val: f32 = spectrum[0];
        for (spectrum, 0..) |v, k| {
            if (v > peak_val) {
                peak_val = v;
                peak_bin = k;
            }
        }

        var non_peak_power: f32 = 0.0;
        const left_start = peak_bin -| 14;
        const left_end = peak_bin -| 4;
        if (left_start < left_end) {
            for (left_start..left_end) |k| non_peak_power = @max(non_peak_power, spectrum[k]);
        }
        const right_start = peak_bin + 5;
        const right_end = @min(peak_bin + 15, aec3_common.FFT_LENGTH_BY_2_PLUS_1);
        if (right_start < right_end) {
            for (right_start..right_end) |k| non_peak_power = @max(non_peak_power, spectrum[k]);
        }

        var max_abs_q15: i32 = 0;
        for (latest_time_block) |x| max_abs_q15 = @max(max_abs_q15, @abs(q15_from_float(x)));

        if (peak_bin > 0 and
            max_abs_q15 > q15_from_float(100.0) and
            q15_from_float(peak_val) > 100 * q15_from_float(non_peak_power))
        {
            self.narrow_peak_band_state = peak_bin;
            self.narrow_peak_counter = 0;
        }
    }

    pub fn poor_signal_excitation(self: *const RenderSignalAnalyzer) bool {
        for (self.narrow_band_counters) |counter| {
            if (counter > 10) return true;
        }
        return false;
    }

    pub fn mask_regions_around_narrow_bands(self: *const RenderSignalAnalyzer, mask: *[aec3_common.FFT_LENGTH_BY_2_PLUS_1]f32) void {
        if (self.narrow_band_counters[0] > COUNTER_THRESHOLD) {
            mask[0] = 0.0;
            mask[1] = 0.0;
        }
        for (2..aec3_common.FFT_LENGTH_BY_2 - 1) |k| {
            if (self.narrow_band_counters[k - 1] > COUNTER_THRESHOLD) {
                mask[k - 2] = 0.0;
                mask[k - 1] = 0.0;
                mask[k] = 0.0;
                mask[k + 1] = 0.0;
                mask[k + 2] = 0.0;
            }
        }
        if (self.narrow_band_counters[aec3_common.FFT_LENGTH_BY_2 - 2] > COUNTER_THRESHOLD) {
            mask[aec3_common.FFT_LENGTH_BY_2 - 1] = 0.0;
            mask[aec3_common.FFT_LENGTH_BY_2] = 0.0;
        }
    }

    pub fn narrow_peak_band(self: *const RenderSignalAnalyzer) ?usize {
        return self.narrow_peak_band_state;
    }
};

test "render_signal_analyzer detects narrow peak and masks region" {
    var cfg = config.EchoCanceller3Config.default();
    var analyzer = RenderSignalAnalyzer.init(&cfg);

    var block = [_]f32{120.0} ** aec3_common.BLOCK_SIZE;
    var spectrum = [_]f32{1.0} ** aec3_common.FFT_LENGTH_BY_2_PLUS_1;
    spectrum[32] = 10_000.0;

    for (0..16) |_| analyzer.update_from_spectrum(block[0..], spectrum[0..], true);

    try std.testing.expect(analyzer.poor_signal_excitation());
    try std.testing.expectEqual(@as(?usize, 32), analyzer.narrow_peak_band());

    var mask = [_]f32{1.0} ** aec3_common.FFT_LENGTH_BY_2_PLUS_1;
    analyzer.mask_regions_around_narrow_bands(&mask);
    try std.testing.expectEqual(@as(f32, 0.0), mask[32]);
}

test "render_signal_analyzer clears counters when delay unknown" {
    var cfg = config.EchoCanceller3Config.default();
    var analyzer = RenderSignalAnalyzer.init(&cfg);

    var block = [_]f32{120.0} ** aec3_common.BLOCK_SIZE;
    var spectrum = [_]f32{1.0} ** aec3_common.FFT_LENGTH_BY_2_PLUS_1;
    spectrum[20] = 1000.0;
    for (0..8) |_| analyzer.update_from_spectrum(block[0..], spectrum[0..], true);
    analyzer.update_from_spectrum(block[0..], spectrum[0..], false);

    var mask = [_]f32{1.0} ** aec3_common.FFT_LENGTH_BY_2_PLUS_1;
    analyzer.mask_regions_around_narrow_bands(&mask);
    for (mask) |m| try std.testing.expectEqual(@as(f32, 1.0), m);
}
