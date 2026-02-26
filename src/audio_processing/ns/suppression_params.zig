const ns_config = @import("ns_config.zig");

pub const SuppressionParams = struct {
    floor_gain: f32,
    max_gain: f32,
    prior_snr_smoothing: f32,
    noise_update_rate: f32,

    pub fn fromConfig(config: ns_config.NsConfig) SuppressionParams {
        return switch (config.level) {
            .low => .{
                .floor_gain = 0.20,
                .max_gain = config.max_gain,
                .prior_snr_smoothing = config.prior_snr_smoothing,
                .noise_update_rate = 0.97,
            },
            .moderate => .{
                .floor_gain = 0.12,
                .max_gain = config.max_gain,
                .prior_snr_smoothing = config.prior_snr_smoothing,
                .noise_update_rate = 0.98,
            },
            .high => .{
                .floor_gain = 0.08,
                .max_gain = config.max_gain,
                .prior_snr_smoothing = config.prior_snr_smoothing,
                .noise_update_rate = 0.985,
            },
            .very_high => .{
                .floor_gain = 0.04,
                .max_gain = config.max_gain,
                .prior_snr_smoothing = config.prior_snr_smoothing,
                .noise_update_rate = 0.99,
            },
        };
    }
};
