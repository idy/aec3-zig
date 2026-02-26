const std = @import("std");
const NumericMode = @import("../../numeric_mode.zig").NumericMode;

pub const SuppressionLevel = enum {
    low,
    moderate,
    high,
    very_high,
};

pub const NsConfig = struct {
    level: SuppressionLevel = .moderate,
    numeric_mode: NumericMode = .fixed_mcu_q15,
    min_noise_floor: f32 = 1e-4,
    max_gain: f32 = 1.0,
    prior_snr_smoothing: f32 = 0.85,

    pub fn validate(self: NsConfig) !void {
        if (!(self.min_noise_floor > 0.0 and std.math.isFinite(self.min_noise_floor))) {
            return error.InvalidNoiseFloor;
        }
        if (!(self.max_gain > 0.0 and self.max_gain <= 1.0 and std.math.isFinite(self.max_gain))) {
            return error.InvalidMaxGain;
        }
        if (!(self.prior_snr_smoothing >= 0.0 and self.prior_snr_smoothing <= 1.0 and std.math.isFinite(self.prior_snr_smoothing))) {
            return error.InvalidPriorSnrSmoothing;
        }
    }

    pub fn withDefaultsOnInvalid(self: NsConfig) NsConfig {
        self.validate() catch return .{};
        return self;
    }
};

test "NsConfig validates legal values" {
    var cfg = NsConfig{};
    try cfg.validate();
}

test "NsConfig rejects invalid values" {
    var cfg = NsConfig{ .max_gain = 1.2 };
    try std.testing.expectError(error.InvalidMaxGain, cfg.validate());
}
