//! Ported from: docs/aec3-rs-src/audio_processing/audio_frame.rs
const std = @import("std");
const ChannelLayout = @import("channel_layout.zig").ChannelLayout;

/// Voice Activity Detection state.
pub const VadActivity = enum {
    active,
    passive,
    unknown,
};

/// Speech type classification.
pub const SpeechType = enum {
    normal_speech,
    plc,
    cng,
    plc_cng,
    codec_plc,
    undefined,
};

/// Maximum number of samples in an AudioFrame.
pub const MAX_DATA_SIZE_SAMPLES: usize = 7680;
/// Maximum size in bytes.
pub const MAX_DATA_SIZE_BYTES: usize = MAX_DATA_SIZE_SAMPLES * @sizeOf(i16);

const ZERO_SAMPLES = [_]i16{0} ** MAX_DATA_SIZE_SAMPLES;

/// Audio frame containing raw PCM data and metadata.
pub const AudioFrame = struct {
    data_: [MAX_DATA_SIZE_SAMPLES]i16,
    muted_: bool,
    profile_timestamp_ms: i64,
    timestamp: u32,
    elapsed_time_ms: i64,
    ntp_time_ms: i64,
    samples_per_channel: usize,
    sample_rate_hz: i32,
    num_channels: usize,
    channel_layout: ChannelLayout,
    speech_type: SpeechType,
    vad_activity: VadActivity,

    /// Creates a new AudioFrame with default values.
    pub fn new() AudioFrame {
        return .{
            .data_ = [_]i16{0} ** MAX_DATA_SIZE_SAMPLES,
            .muted_ = true,
            .profile_timestamp_ms = -1,
            .timestamp = 0,
            .elapsed_time_ms = -1,
            .ntp_time_ms = -1,
            .samples_per_channel = 0,
            .sample_rate_hz = 0,
            .num_channels = 0,
            .channel_layout = .none,
            .speech_type = .undefined,
            .vad_activity = .unknown,
        };
    }

    /// Resets the frame to default values.
    pub fn reset(self: *AudioFrame) void {
        self.* = AudioFrame.new();
    }

    /// Resets the frame while preserving the muted state.
    pub fn reset_without_muting(self: *AudioFrame) void {
        const muted_state = self.muted_;
        self.reset();
        self.muted_ = muted_state;
    }

    /// Updates the frame with new data.
    pub fn update_frame(
        self: *AudioFrame,
        timestamp: u32,
        input_data: []const i16,
        samples_per_channel: usize,
        sample_rate_hz: i32,
        speech_type: SpeechType,
        vad_activity: VadActivity,
        num_channels: usize,
    ) !void {
        if (samples_per_channel * num_channels > MAX_DATA_SIZE_SAMPLES) {
            return error.TooManySamples;
        }
        const len = samples_per_channel * num_channels;
        if (input_data.len < len) {
            return error.InsufficientInputData;
        }

        self.timestamp = timestamp;
        self.samples_per_channel = samples_per_channel;
        self.sample_rate_hz = sample_rate_hz;
        self.speech_type = speech_type;
        self.vad_activity = vad_activity;
        self.num_channels = num_channels;
        self.channel_layout = ChannelLayout.guess_from_channel_count(num_channels);
        self.muted_ = false;
        @memcpy(self.data_[0..len], input_data[0..len]);
    }

    /// Copies data from another frame.
    pub fn copy_from(self: *AudioFrame, other: *const AudioFrame) void {
        const len = other.data_len();
        self.timestamp = other.timestamp;
        self.elapsed_time_ms = other.elapsed_time_ms;
        self.ntp_time_ms = other.ntp_time_ms;
        self.samples_per_channel = other.samples_per_channel;
        self.sample_rate_hz = other.sample_rate_hz;
        self.num_channels = other.num_channels;
        self.channel_layout = other.channel_layout;
        self.speech_type = other.speech_type;
        self.vad_activity = other.vad_activity;
        self.muted_ = other.muted_;
        self.profile_timestamp_ms = other.profile_timestamp_ms;
        @memcpy(self.data_[0..len], other.data_[0..len]);
    }

    /// Updates the profile timestamp to current time.
    pub fn update_profile_timestamp(self: *AudioFrame) void {
        self.profile_timestamp_ms = std.time.milliTimestamp();
    }

    /// Returns elapsed time since profile timestamp was set.
    pub fn elapsed_profile_time_ms(self: *const AudioFrame) i64 {
        if (self.profile_timestamp_ms < 0) return -1;
        return std.time.milliTimestamp() - self.profile_timestamp_ms;
    }

    /// Returns the audio data (returns zeros if muted).
    pub fn data(self: *const AudioFrame) []const i16 {
        const len = self.data_len();
        if (self.muted_) return ZERO_SAMPLES[0..len];
        return self.data_[0..len];
    }

    /// Returns mutable access to audio data (unmutes if necessary).
    pub fn mutable_data(self: *AudioFrame) []i16 {
        const len = self.data_len();
        if (self.muted_) {
            @memset(self.data_[0..len], 0);
            self.muted_ = false;
        }
        return self.data_[0..len];
    }

    /// Mutes the frame.
    pub fn mute(self: *AudioFrame) void {
        self.muted_ = true;
    }

    /// Returns true if the frame is muted.
    pub fn muted(self: *const AudioFrame) bool {
        return self.muted_;
    }

    fn data_len(self: *const AudioFrame) usize {
        return self.samples_per_channel * self.num_channels;
    }
};

test "test_new_default_values" {
    const frame = AudioFrame.new();
    try std.testing.expect(frame.muted());
    try std.testing.expectEqual(@as(usize, 0), frame.samples_per_channel);
}

test "test_mute_and_data" {
    var frame = AudioFrame.new();
    const raw = [_]i16{ 1, 2, 3, 4 };
    try frame.update_frame(1, &raw, 2, 16_000, .normal_speech, .active, 2);
    frame.mute();
    const out = frame.data();
    for (out) |v| try std.testing.expectEqual(@as(i16, 0), v);
}

test "test_update_frame" {
    var frame = AudioFrame.new();
    const raw = [_]i16{ 1, 2, 3, 4 };
    try frame.update_frame(123, &raw, 2, 16_000, .normal_speech, .active, 2);
    try std.testing.expectEqual(@as(u32, 123), frame.timestamp);
    try std.testing.expectEqual(@as(usize, 2), frame.samples_per_channel);
    try std.testing.expectEqual(@as(i32, 16_000), frame.sample_rate_hz);
    try std.testing.expectEqual(ChannelLayout.stereo, frame.channel_layout);
    try std.testing.expect(!frame.muted());
}

test "test_update_frame_rejects_invalid_sizes" {
    var frame = AudioFrame.new();
    const short = [_]i16{ 1, 2, 3 };
    try std.testing.expectError(error.InsufficientInputData, frame.update_frame(1, &short, 2, 16_000, .normal_speech, .active, 2));

    const tiny = [_]i16{0};
    try std.testing.expectError(error.TooManySamples, frame.update_frame(1, &tiny, MAX_DATA_SIZE_SAMPLES + 1, 16_000, .normal_speech, .active, 1));
}
