//! Ported from: docs/aec3-rs-src/audio_processing/aec3/delay_estimate.rs
const std = @import("std");

/// Quality level of a delay estimate.
pub const DelayEstimateQuality = enum {
    coarse,
    refined,
};

/// Delay estimate with quality indicator and tracking counters.
pub const DelayEstimate = struct {
    quality: DelayEstimateQuality,
    delay: usize,
    blocks_since_last_change: usize,
    blocks_since_last_update: usize,

    /// Creates a new DelayEstimate with counters initialized to zero.
    pub fn new(quality: DelayEstimateQuality, delay: usize) DelayEstimate {
        return .{
            .quality = quality,
            .delay = delay,
            .blocks_since_last_change = 0,
            .blocks_since_last_update = 0,
        };
    }
};

test "test_new_initializes_zero_counters" {
    const estimate = DelayEstimate.new(.coarse, 5);
    try std.testing.expectEqual(@as(usize, 0), estimate.blocks_since_last_change);
    try std.testing.expectEqual(@as(usize, 0), estimate.blocks_since_last_update);
}
