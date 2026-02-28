//! Ported from: docs/aec3-rs-src/audio_processing/aec3/echo_path_variability.rs
const std = @import("std");

/// Type of delay adjustment that occurred.
pub const DelayAdjustment = enum {
    none,
    buffer_readjustment,
    buffer_flush,
    delay_reset,
    new_detected_delay,
};

/// Tracks echo path variability including gain changes, delay changes, and clock drift.
pub const EchoPathVariability = struct {
    gain_change: bool,
    delay_change: DelayAdjustment,
    clock_drift: bool,

    /// Creates a new EchoPathVariability instance.
    pub fn new(gain_change: bool, delay_change: DelayAdjustment, clock_drift: bool) EchoPathVariability {
        return .{
            .gain_change = gain_change,
            .delay_change = delay_change,
            .clock_drift = clock_drift,
        };
    }

    /// Returns true if the audio path has changed (gain or delay change detected).
    pub fn audio_path_changed(self: EchoPathVariability) bool {
        return self.gain_change or self.delay_change != .none;
    }
};

test "test_audio_path_changed" {
    try std.testing.expect(!EchoPathVariability.new(false, .none, false).audio_path_changed());
    try std.testing.expect(EchoPathVariability.new(true, .none, false).audio_path_changed());
    try std.testing.expect(EchoPathVariability.new(false, .buffer_flush, false).audio_path_changed());
}
