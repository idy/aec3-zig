const std = @import("std");

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

test "histogram quantile returns expected trend" {
    var h = Histogram.init(0.0, 10.0);
    h.observe(1.0);
    h.observe(2.0);
    h.observe(9.0);
    try std.testing.expect(h.quantile(0.1) <= h.quantile(0.9));
}
