//! Ported from: docs/aec3-rs-src/audio_processing/channel_layout.rs
const std = @import("std");

/// Audio channel layout enumeration.
pub const ChannelLayout = enum(i32) {
    none = 0,
    unsupported = 1,
    mono = 2,
    stereo = 3,
    layout_2_1 = 4,
    surround = 5,
    layout_4_0 = 6,
    layout_2_2 = 7,
    quad = 8,
    layout_5_0 = 9,
    layout_5_1 = 10,
    layout_5_0_back = 11,
    layout_5_1_back = 12,
    layout_7_0 = 13,
    layout_7_1 = 14,
    layout_7_1_wide = 15,
    stereo_downmix = 16,
    layout_2_point_1 = 17,
    layout_3_1 = 18,
    layout_4_1 = 19,
    layout_6_0 = 20,
    layout_6_0_front = 21,
    hexagonal = 22,
    layout_6_1 = 23,
    layout_6_1_back = 24,
    layout_6_1_front = 25,
    layout_7_0_front = 26,
    layout_7_1_wide_back = 27,
    octagonal = 28,
    discrete = 29,
    stereo_and_keyboard_mic = 30,
    layout_4_1_quad_side = 31,
    bitstream = 32,

    /// Returns the number of channels for this layout.
    pub fn channel_count(self: ChannelLayout) usize {
        return switch (self) {
            .none, .unsupported, .discrete, .bitstream => 0,
            .mono => 1,
            .stereo, .stereo_downmix, .layout_2_point_1, .stereo_and_keyboard_mic, .layout_4_1_quad_side => 2,
            .layout_2_1, .layout_3_1, .layout_2_2 => 3,
            .surround, .layout_4_0, .quad, .layout_4_1, .layout_6_0_front, .hexagonal => 4,
            .layout_5_0, .layout_5_1, .layout_5_0_back, .layout_5_1_back, .layout_6_0, .layout_6_1, .layout_6_1_back, .layout_6_1_front => 6,
            .layout_7_0, .layout_7_1, .layout_7_1_wide, .layout_7_0_front, .layout_7_1_wide_back, .octagonal => 8,
        };
    }

    /// Guesses the channel layout from the number of channels.
    pub fn guess_from_channel_count(channels: usize) ChannelLayout {
        return switch (channels) {
            0 => .none,
            1 => .mono,
            2 => .stereo,
            3 => .layout_2_1,
            4 => .quad,
            5 => .layout_5_0,
            6 => .layout_5_1,
            7 => .layout_7_0,
            else => .layout_7_1,
        };
    }
};

test "test_channel_count" {
    try std.testing.expectEqual(@as(usize, 1), ChannelLayout.mono.channel_count());
    try std.testing.expectEqual(@as(usize, 2), ChannelLayout.stereo.channel_count());
    try std.testing.expectEqual(@as(usize, 4), ChannelLayout.surround.channel_count());
    try std.testing.expectEqual(@as(usize, 6), ChannelLayout.layout_5_1.channel_count());
}

test "test_guess_from_channel_count" {
    try std.testing.expectEqual(ChannelLayout.mono, ChannelLayout.guess_from_channel_count(1));
    try std.testing.expectEqual(ChannelLayout.stereo, ChannelLayout.guess_from_channel_count(2));
}
