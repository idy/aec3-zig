const ns_config = @import("ns_config.zig");

/// Suppression parameter mapping from NS suppression level (matches aec3-rs)
pub const SuppressionParams = struct {
    over_subtraction_factor: f32,
    minimum_attenuating_gain: f32,
    use_attenuation_adjustment: bool,

    pub fn fromConfig(config: ns_config.NsConfig) SuppressionParams {
        return switch (config.level) {
            .low => .{
                .over_subtraction_factor = 1.0,
                .minimum_attenuating_gain = 0.5,
                .use_attenuation_adjustment = false,
            },
            .moderate => .{
                .over_subtraction_factor = 1.0,
                .minimum_attenuating_gain = 0.25,
                .use_attenuation_adjustment = true,
            },
            .high => .{
                .over_subtraction_factor = 1.1,
                .minimum_attenuating_gain = 0.125,
                .use_attenuation_adjustment = true,
            },
            .very_high => .{
                .over_subtraction_factor = 1.25,
                .minimum_attenuating_gain = 0.09,
                .use_attenuation_adjustment = true,
            },
        };
    }
};
