//! Ported from: docs/aec3-rs-src/audio_processing/audio_util.rs
const std = @import("std");

/// Converts i16 to normalized f32 (-1.0 to 1.0).
pub fn s16_to_float(v: i16) f32 {
    return @as(f32, @floatFromInt(v)) * (1.0 / 32768.0);
}

/// Converts f32 (S16 scale) to i16 with clamping and rounding.
pub fn float_s16_to_s16(v: f32) i16 {
    var clamped = @min(@as(f32, 32767.0), @max(@as(f32, -32768.0), v));
    clamped += std.math.sign(clamped) * 0.5;
    return @as(i16, @intFromFloat(clamped));
}

/// Converts normalized f32 to i16.
pub fn float_to_s16(v: f32) i16 {
    return float_s16_to_s16(v * 32768.0);
}

/// Converts normalized f32 to f32 S16 scale (-32768 to 32767).
pub fn float_to_float_s16(v: f32) f32 {
    const clamped = @min(@as(f32, 1.0), @max(@as(f32, -1.0), v));
    return clamped * 32768.0;
}

/// Converts f32 S16 scale to normalized f32.
pub fn float_s16_to_float(v: f32) f32 {
    const clamped = @min(@as(f32, 32768.0), @max(@as(f32, -32768.0), v));
    return clamped * (1.0 / 32768.0);
}

/// Converts slice of i16 to f32 S16 scale.
pub fn s16_slice_to_float_s16(src: []const i16, dest: []f32) void {
    std.debug.assert(src.len == dest.len);
    for (src, dest) |s, *d| d.* = @floatFromInt(s);
}

/// Converts slice of f32 S16 scale to i16.
pub fn float_s16_slice_to_s16(src: []const f32, dest: []i16) void {
    std.debug.assert(src.len == dest.len);
    for (src, dest) |s, *d| d.* = float_s16_to_s16(s);
}

/// Converts slice of normalized f32 to f32 S16 scale.
pub fn float_slice_to_float_s16(src: []const f32, dest: []f32) void {
    std.debug.assert(src.len == dest.len);
    for (src, dest) |s, *d| d.* = float_to_float_s16(s);
}

/// Converts slice of normalized f32 to f32 S16 scale in-place.
pub fn float_slice_to_float_s16_in_place(data: []f32) void {
    for (data) |*v| v.* = float_to_float_s16(v.*);
}

/// Converts slice of f32 S16 scale to normalized f32.
pub fn float_s16_slice_to_float(src: []const f32, dest: []f32) void {
    std.debug.assert(src.len == dest.len);
    for (src, dest) |s, *d| d.* = float_s16_to_float(s);
}

/// Converts slice of f32 S16 scale to normalized f32 in-place.
pub fn float_s16_slice_to_float_in_place(data: []f32) void {
    for (data) |*v| v.* = float_s16_to_float(v.*);
}

/// Copies audio data if source and destination pointers differ.
pub fn copy_audio_if_needed(comptime T: type, src: []const []const T, num_frames: usize, dest: []const []T) void {
    std.debug.assert(src.len == dest.len);
    for (src, dest) |s, d| {
        if (@intFromPtr(s.ptr) != @intFromPtr(d.ptr)) {
            @memcpy(d[0..num_frames], s[0..num_frames]);
        }
    }
}

/// Deinterleaves audio data from interleaved to planar format.
pub fn deinterleave(comptime T: type, interleaved: []const T, samples_per_channel: usize, num_channels: usize, deinterleaved: []const []T) void {
    var ch: usize = 0;
    while (ch < num_channels) : (ch += 1) {
        const output = deinterleaved[ch][0..samples_per_channel];
        var idx = ch;
        for (output) |*sample| {
            sample.* = interleaved[idx];
            idx += num_channels;
        }
    }
}

/// Interleaves audio data from planar to interleaved format.
pub fn interleave(comptime T: type, deinterleaved: []const []const T, samples_per_channel: usize, num_channels: usize, interleaved: []T) void {
    var ch: usize = 0;
    while (ch < num_channels) : (ch += 1) {
        const input = deinterleaved[ch][0..samples_per_channel];
        var idx = ch;
        for (input) |sample| {
            interleaved[idx] = sample;
            idx += num_channels;
        }
    }
}

/// Downmixes multi-channel f32 audio to mono.
pub fn downmix_to_mono_f32(input_channels: []const []const f32, num_frames: usize, out: []f32) void {
    var i: usize = 0;
    while (i < num_frames) : (i += 1) {
        var value = input_channels[0][i];
        var ch: usize = 1;
        while (ch < input_channels.len) : (ch += 1) {
            value += input_channels[ch][i];
        }
        out[i] = value / @as(f32, @floatFromInt(input_channels.len));
    }
}

/// Downmixes multi-channel i16 audio to mono.
pub fn downmix_to_mono_i16(input_channels: []const []const i16, num_frames: usize, out: []i16) void {
    var i: usize = 0;
    while (i < num_frames) : (i += 1) {
        var sum: i32 = input_channels[0][i];
        var ch: usize = 1;
        while (ch < input_channels.len) : (ch += 1) {
            sum += input_channels[ch][i];
        }
        sum = @divTrunc(sum, @as(i32, @intCast(input_channels.len)));
        out[i] = @intCast(@min(@as(i32, std.math.maxInt(i16)), @max(@as(i32, std.math.minInt(i16)), sum)));
    }
}

/// Downmixes interleaved multi-channel i16 audio to mono.
pub fn downmix_interleaved_to_mono_i16(interleaved: []const i16, num_frames: usize, num_channels: usize, out: []i16) void {
    std.debug.assert(num_channels > 0);
    var frame: usize = 0;
    while (frame < num_frames) : (frame += 1) {
        var sum: i32 = 0;
        var ch: usize = 0;
        while (ch < num_channels) : (ch += 1) {
            sum += interleaved[frame * num_channels + ch];
        }
        sum = @divTrunc(sum, @as(i32, @intCast(num_channels)));
        out[frame] = @intCast(@min(@as(i32, std.math.maxInt(i16)), @max(@as(i32, std.math.minInt(i16)), sum)));
    }
}

test "test_s16_to_float_roundtrip" {
    const values = [_]i16{ 0, 1, -1, 32767, -32768 };
    for (values) |v| {
        try std.testing.expectEqual(v, float_to_s16(s16_to_float(v)));
    }
}

test "test_float_s16_roundtrip" {
    const values = [_]f32{ -1.0, -0.5, 0.0, 0.25, 1.0 };
    for (values) |v| {
        const round = float_s16_to_float(float_to_float_s16(v));
        try std.testing.expectApproxEqAbs(v, round, 1e-6);
    }
}

test "test_interleave_deinterleave" {
    var inter = [_]f32{ 1, 3, 2, 4, 5, 7, 6, 8 };
    var ch0 = [_]f32{0} ** 4;
    var ch1 = [_]f32{0} ** 4;
    const out_ch = [_][]f32{ ch0[0..], ch1[0..] };
    deinterleave(f32, &inter, 4, 2, &out_ch);

    var back = [_]f32{0} ** 8;
    const in_ch = [_][]const f32{ ch0[0..], ch1[0..] };
    interleave(f32, &in_ch, 4, 2, &back);

    for (inter, back) |a, b| try std.testing.expectEqual(a, b);
}

test "test_downmix_to_mono" {
    const c0 = [_]f32{ 1.0, 1.0 };
    const c1 = [_]f32{ 3.0, 3.0 };
    const channels = [_][]const f32{ c0[0..], c1[0..] };
    var out = [_]f32{0} ** 2;
    downmix_to_mono_f32(&channels, 2, &out);
    try std.testing.expectEqual(@as(f32, 2.0), out[0]);
    try std.testing.expectEqual(@as(f32, 2.0), out[1]);
}
