const std = @import("std");
const NumericMode = @import("../numeric_mode.zig").NumericMode;

pub const SuppressionLevel = enum {
    low,
    moderate,
    high,
    very_high,
};

pub const NsConfig = struct {
    level: SuppressionLevel = .moderate,
    numeric_mode: NumericMode = .fixed_mcu_q15,

    pub fn validate(self: NsConfig) !void {
        _ = self;
    }
};

test "NsConfig validates legal values" {
    var cfg = NsConfig{};
    try cfg.validate();
}
