//! Ported from: docs/aec3-rs-src/audio_processing/stream_config.rs
const std = @import("std");

const CHUNK_SIZE_MS: usize = 10;

/// Audio stream configuration.
pub const StreamConfig = struct {
    sample_rate_hz_: usize,
    num_channels_: usize,
    has_keyboard_: bool,
    num_frames_: usize,

    /// Creates a new StreamConfig with computed num_frames.
    pub fn new(rate_hz: usize, channels: usize, has_keyboard_value: bool) StreamConfig {
        return .{
            .sample_rate_hz_ = rate_hz,
            .num_channels_ = channels,
            .has_keyboard_ = has_keyboard_value,
            .num_frames_ = frames_from_rate(rate_hz),
        };
    }

    /// Returns the sample rate in Hz.
    pub fn sample_rate_hz(self: StreamConfig) usize {
        return self.sample_rate_hz_;
    }

    /// Sets the sample rate and updates num_frames.
    pub fn set_sample_rate_hz(self: *StreamConfig, rate: usize) void {
        self.sample_rate_hz_ = rate;
        self.num_frames_ = frames_from_rate(rate);
    }

    /// Returns the number of channels.
    pub fn num_channels(self: StreamConfig) usize {
        return self.num_channels_;
    }

    /// Sets the number of channels.
    pub fn set_num_channels(self: *StreamConfig, channels: usize) void {
        self.num_channels_ = channels;
    }

    /// Returns true if the stream has a keyboard channel.
    pub fn has_keyboard(self: StreamConfig) bool {
        return self.has_keyboard_;
    }

    /// Sets the keyboard channel flag.
    pub fn set_has_keyboard(self: *StreamConfig, has_keyboard_value: bool) void {
        self.has_keyboard_ = has_keyboard_value;
    }

    /// Returns the number of frames per 10ms chunk.
    pub fn num_frames(self: StreamConfig) usize {
        return self.num_frames_;
    }

    /// Returns the total number of samples (frames * channels).
    pub fn num_samples(self: StreamConfig) usize {
        return self.num_frames_ * self.num_channels_;
    }
};

fn frames_from_rate(rate: usize) usize {
    if (rate == 0) return 0;
    return (CHUNK_SIZE_MS * rate) / 1000;
}

test "test_new_computes_frames" {
    const cfg = StreamConfig.new(16_000, 1, false);
    try std.testing.expectEqual(@as(usize, 160), cfg.num_frames());
}

test "test_num_samples" {
    const cfg = StreamConfig.new(48_000, 2, false);
    try std.testing.expectEqual(@as(usize, 960), cfg.num_samples());
}

test "test_setters" {
    var cfg = StreamConfig.new(16_000, 1, false);
    cfg.set_sample_rate_hz(32_000);
    try std.testing.expectEqual(@as(usize, 320), cfg.num_frames());
    cfg.set_num_channels(2);
    try std.testing.expectEqual(@as(usize, 2), cfg.num_channels());
    cfg.set_has_keyboard(true);
    try std.testing.expect(cfg.has_keyboard());
}
