const std = @import("std");
const ns_common = @import("ns_common.zig");
const SignalModel = @import("signal_model.zig").SignalModel;

/// Original Histogram struct (kept for compatibility)
pub const Histogram = struct {
    const kBins: usize = 64;

    counts: [kBins]u32 = [_]u32{0} ** kBins,
    total: u32 = 0,
    min_value: f32 = 0.0,
    max_value: f32 = 1.0,

    pub fn init(min_value: f32, max_value: f32) Histogram {
        std.debug.assert(max_value > min_value);
        return .{
            .min_value = min_value,
            .max_value = max_value,
        };
    }

    pub fn clear(self: *Histogram) void {
        self.counts = [_]u32{0} ** kBins;
        self.total = 0;
    }

    pub fn observe(self: *Histogram, value: f32) void {
        const clamped = std.math.clamp(value, self.min_value, self.max_value);
        const ratio = (clamped - self.min_value) / (self.max_value - self.min_value);
        const idx = std.math.clamp(@as(usize, @intFromFloat(@floor(ratio * @as(f32, @floatFromInt(kBins - 1))))), 0, kBins - 1);
        self.counts[idx] += 1;
        self.total += 1;
    }

    pub fn quantile(self: *const Histogram, p: f32) f32 {
        if (self.total == 0) return self.min_value;
        const q = std.math.clamp(p, 0.0, 1.0);
        const target = @as(u32, @intFromFloat(@floor(q * @as(f32, @floatFromInt(self.total - 1)))));

        var acc: u32 = 0;
        for (0..kBins) |i| {
            acc += self.counts[i];
            if (acc > target) {
                const bin_ratio = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(kBins - 1));
                return self.min_value + bin_ratio * (self.max_value - self.min_value);
            }
        }
        return self.max_value;
    }
};

/// Histograms for NS feature thresholds adaptation (matches aec3-rs)
pub const HISTOGRAM_SIZE: usize = 1000;

// Bin sizes from ns_common
const BIN_SIZE_LRT: f32 = 0.1;
const BIN_SIZE_SPEC_FLAT: f32 = 0.05;
const BIN_SIZE_SPEC_DIFF: f32 = 0.1;

pub const Histograms = struct {
    lrt: [HISTOGRAM_SIZE]i32,
    spectral_flatness: [HISTOGRAM_SIZE]i32,
    spectral_diff: [HISTOGRAM_SIZE]i32,

    pub fn init() Histograms {
        return .{
            .lrt = [_]i32{0} ** HISTOGRAM_SIZE,
            .spectral_flatness = [_]i32{0} ** HISTOGRAM_SIZE,
            .spectral_diff = [_]i32{0} ** HISTOGRAM_SIZE,
        };
    }

    pub fn clear(self: *Histograms) void {
        @memset(&self.lrt, 0);
        @memset(&self.spectral_flatness, 0);
        @memset(&self.spectral_diff, 0);
    }

    pub fn update(self: *Histograms, features: *const SignalModel) void {
        if (features.lrt >= 0.0) {
            const lrt_idx_f = features.lrt / BIN_SIZE_LRT;
            if (lrt_idx_f < @as(f32, @floatFromInt(HISTOGRAM_SIZE))) {
                const lrt_idx = @as(usize, @intFromFloat(lrt_idx_f));
                if (lrt_idx < HISTOGRAM_SIZE) {
                    self.lrt[lrt_idx] += 1;
                }
            }
        }

        if (features.spectral_flatness >= 0.0) {
            const flat_idx_f = features.spectral_flatness / BIN_SIZE_SPEC_FLAT;
            if (flat_idx_f < @as(f32, @floatFromInt(HISTOGRAM_SIZE))) {
                const flat_idx = @as(usize, @intFromFloat(flat_idx_f));
                if (flat_idx < HISTOGRAM_SIZE) {
                    self.spectral_flatness[flat_idx] += 1;
                }
            }
        }

        if (features.spectral_diff >= 0.0) {
            const diff_idx_f = features.spectral_diff / BIN_SIZE_SPEC_DIFF;
            if (diff_idx_f < @as(f32, @floatFromInt(HISTOGRAM_SIZE))) {
                const diff_idx = @as(usize, @intFromFloat(diff_idx_f));
                if (diff_idx < HISTOGRAM_SIZE) {
                    self.spectral_diff[diff_idx] += 1;
                }
            }
        }
    }

    pub fn getLrt(self: *const Histograms) []const i32 {
        return &self.lrt;
    }

    pub fn getSpectralFlatness(self: *const Histograms) []const i32 {
        return &self.spectral_flatness;
    }

    pub fn getSpectralDiff(self: *const Histograms) []const i32 {
        return &self.spectral_diff;
    }
};

test "histogram quantile returns expected trend" {
    var h = Histogram.init(0.0, 10.0);
    h.observe(1.0);
    h.observe(2.0);
    h.observe(9.0);
    try std.testing.expect(h.quantile(0.1) <= h.quantile(0.9));
}
