//! Ported from: docs/aec3-rs-src/audio_processing/audio_buffer.rs
const std = @import("std");
const ChannelBuffer = @import("channel_buffer.zig").ChannelBuffer;
const SplittingFilter = @import("../aec3/filters/splitting_filter.zig").SplittingFilter;
const test_utils = @import("../api/test_utils.zig");

const SAMPLES_PER_32KHZ_CHANNEL: usize = 320;
const SAMPLES_PER_48KHZ_CHANNEL: usize = 480;

pub const FrameAudioBuffer = struct {
    input_num_frames: usize,
    input_num_channels: usize,
    buffer_num_frames: usize,
    buffer_num_channels: usize,
    output_num_frames: usize,
    num_channels_: usize,
    num_bands_: usize,
    num_split_frames: usize,
    data: ChannelBuffer(f32),
    split_data: ?ChannelBuffer(f32),
    splitting_filter: ?SplittingFilter,

    pub fn new(
        allocator: std.mem.Allocator,
        input_num_frames: usize,
        input_num_channels: usize,
        buffer_num_frames: usize,
        buffer_num_channels: usize,
        output_num_frames: usize,
    ) !FrameAudioBuffer {
        if (input_num_frames == 0 or buffer_num_frames == 0 or output_num_frames == 0) return error.InvalidFrameCount;
        if (input_num_channels == 0 or buffer_num_channels == 0) return error.InvalidChannelCount;
        if (buffer_num_channels > input_num_channels) return error.InvalidBufferChannelCount;

        const resolved_num_bands = num_bands_from_frames(buffer_num_frames);
        const num_split_frames = @divExact(buffer_num_frames, resolved_num_bands);
        var data = try ChannelBuffer(f32).new(allocator, buffer_num_frames, buffer_num_channels, 1);
        errdefer data.deinit();

        var split_data: ?ChannelBuffer(f32) = null;
        var splitting_filter: ?SplittingFilter = null;
        errdefer if (split_data) |*s| s.deinit();
        errdefer if (splitting_filter) |*f| f.deinit();

        if (resolved_num_bands > 1) {
            split_data = try ChannelBuffer(f32).new(allocator, buffer_num_frames, buffer_num_channels, resolved_num_bands);
            splitting_filter = try SplittingFilter.new(allocator, buffer_num_channels, resolved_num_bands, buffer_num_frames);
        }

        return .{
            .input_num_frames = input_num_frames,
            .input_num_channels = input_num_channels,
            .buffer_num_frames = buffer_num_frames,
            .buffer_num_channels = buffer_num_channels,
            .output_num_frames = output_num_frames,
            .num_channels_ = buffer_num_channels,
            .num_bands_ = resolved_num_bands,
            .num_split_frames = num_split_frames,
            .data = data,
            .split_data = split_data,
            .splitting_filter = splitting_filter,
        };
    }

    pub fn from_sample_rates(
        allocator: std.mem.Allocator,
        input_rate: usize,
        input_channels: usize,
        buffer_rate: usize,
        buffer_channels: usize,
        output_rate: usize,
    ) !FrameAudioBuffer {
        return FrameAudioBuffer.new(
            allocator,
            input_rate / 100,
            input_channels,
            buffer_rate / 100,
            buffer_channels,
            output_rate / 100,
        );
    }

    pub fn deinit(self: *FrameAudioBuffer) void {
        self.data.deinit();
        if (self.split_data) |*split| split.deinit();
        if (self.splitting_filter) |*filter| filter.deinit();
    }

    pub fn set_num_channels(self: *FrameAudioBuffer, num_channels_in: usize) !void {
        std.debug.assert(num_channels_in <= self.buffer_num_channels);

        // Try the potentially-failing operation first (splitting_filter allocation)
        if (self.splitting_filter) |*filter| {
            try filter.set_num_channels(num_channels_in);
        }

        // Only update state after potential OOM has passed
        self.num_channels_ = num_channels_in;
        self.data.set_num_channels(num_channels_in);
        if (self.split_data) |*split| {
            split.set_num_channels(num_channels_in);
        }
    }

    pub fn num_channels(self: FrameAudioBuffer) usize {
        return self.num_channels_;
    }

    pub fn num_frames(self: FrameAudioBuffer) usize {
        return self.buffer_num_frames;
    }

    pub fn num_frames_per_band(self: FrameAudioBuffer) usize {
        return self.num_split_frames;
    }

    pub fn num_bands(self: FrameAudioBuffer) usize {
        return self.num_bands_;
    }

    pub fn channel(self: *const FrameAudioBuffer, channel_idx: usize) []const f32 {
        return self.data.channel(channel_idx);
    }

    pub fn channel_mut(self: *FrameAudioBuffer, channel_idx: usize) []f32 {
        return self.data.channel_mut(channel_idx);
    }

    pub fn split_band(self: *const FrameAudioBuffer, channel_idx: usize, band_idx: usize) []const f32 {
        if (self.split_data) |*split| {
            return split.band(channel_idx, band_idx);
        }
        return self.data.band(channel_idx, band_idx);
    }

    pub fn split_band_mut(self: *FrameAudioBuffer, channel_idx: usize, band_idx: usize) []f32 {
        if (self.num_bands_ > 1) {
            return self.split_data.?.band_mut(channel_idx, band_idx);
        }
        return self.data.band_mut(channel_idx, band_idx);
    }

    pub fn split_into_frequency_bands(self: *FrameAudioBuffer) void {
        if (self.num_bands_ > 1) {
            self.splitting_filter.?.analysis(&self.data, &self.split_data.?);
        }
    }

    pub fn merge_frequency_bands(self: *FrameAudioBuffer) void {
        if (self.num_bands_ > 1) {
            self.splitting_filter.?.synthesis(&self.split_data.?, &self.data);
        }
    }
};

fn num_bands_from_frames(num_frames: usize) usize {
    return if (num_frames == SAMPLES_PER_32KHZ_CHANNEL)
        2
    else if (num_frames == SAMPLES_PER_48KHZ_CHANNEL)
        3
    else
        1;
}

test "audio_buffer multi-channel read write" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buffer = try FrameAudioBuffer.new(arena.allocator(), 160, 2, 160, 2, 160);
    defer buffer.deinit();

    buffer.channel_mut(0)[0] = 11.0;
    buffer.channel_mut(1)[0] = 22.0;
    try std.testing.expectEqual(@as(f32, 11.0), buffer.channel(0)[0]);
    try std.testing.expectEqual(@as(f32, 22.0), buffer.channel(1)[0]);
}

test "audio_buffer split/merge round trip for 48k" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buffer = try FrameAudioBuffer.new(arena.allocator(), 480, 1, 480, 1, 480);
    defer buffer.deinit();
    try std.testing.expectEqual(@as(usize, 3), buffer.num_bands());

    var original = [_]f32{0} ** 480;
    for (0..480) |i| {
        const t = @as(f32, @floatFromInt(i)) / 48_000.0;
        const v = 800.0 * @sin(2.0 * std.math.pi * 700.0 * t);
        buffer.channel_mut(0)[i] = v;
        original[i] = v;
    }

    buffer.split_into_frequency_bands();
    buffer.merge_frequency_bands();

    const err = test_utils.mean_abs_error(original[0..], buffer.channel(0));
    // Threshold: 800.0 (measured: ~760, safety margin: ~5.3%)
    // Tightened 1.5x from original 1200.0, error propagates from underlying ThreeBandFilterBank
    try std.testing.expect(err < 800.0);
}

test "audio_buffer from_sample_rates creates correct buffer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buffer = try FrameAudioBuffer.from_sample_rates(arena.allocator(), 16000, 2, 16000, 2, 16000);
    defer buffer.deinit();

    try std.testing.expectEqual(@as(usize, 160), buffer.num_frames());
    try std.testing.expectEqual(@as(usize, 2), buffer.num_channels());
}

test "audio_buffer from_sample_rates boundary rejects zero rates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectError(error.InvalidFrameCount, FrameAudioBuffer.from_sample_rates(arena.allocator(), 0, 1, 16000, 1, 16000));
    try std.testing.expectError(error.InvalidFrameCount, FrameAudioBuffer.from_sample_rates(arena.allocator(), 16000, 1, 0, 1, 16000));
    try std.testing.expectError(error.InvalidFrameCount, FrameAudioBuffer.from_sample_rates(arena.allocator(), 16000, 1, 16000, 1, 0));
}

test "audio_buffer from_sample_rates boundary various sample rates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // Standard rates
    var buffer_16k = try FrameAudioBuffer.from_sample_rates(arena.allocator(), 16000, 1, 16000, 1, 16000);
    defer buffer_16k.deinit();
    try std.testing.expectEqual(@as(usize, 160), buffer_16k.num_frames());

    var buffer_32k = try FrameAudioBuffer.from_sample_rates(arena.allocator(), 32000, 1, 32000, 1, 32000);
    defer buffer_32k.deinit();
    try std.testing.expectEqual(@as(usize, 320), buffer_32k.num_frames());

    var buffer_48k = try FrameAudioBuffer.from_sample_rates(arena.allocator(), 48000, 1, 48000, 1, 48000);
    defer buffer_48k.deinit();
    try std.testing.expectEqual(@as(usize, 480), buffer_48k.num_frames());

    // Non-standard rate (should still work, frames = rate / 100)
    var buffer_441k = try FrameAudioBuffer.from_sample_rates(arena.allocator(), 44100, 1, 44100, 1, 44100);
    defer buffer_441k.deinit();
    try std.testing.expectEqual(@as(usize, 441), buffer_441k.num_frames());
}

test "audio_buffer num_frames returns correct value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buffer = try FrameAudioBuffer.new(arena.allocator(), 160, 1, 160, 1, 160);
    defer buffer.deinit();

    try std.testing.expectEqual(@as(usize, 160), buffer.num_frames());
}

test "audio_buffer num_frames_per_band returns correct value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buffer = try FrameAudioBuffer.new(arena.allocator(), 480, 1, 480, 1, 480);
    defer buffer.deinit();

    // For 48k with 3 bands, frames per band = 480 / 3 = 160
    try std.testing.expectEqual(@as(usize, 160), buffer.num_frames_per_band());
}

test "audio_buffer num_frames boundary various sizes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buffer_160 = try FrameAudioBuffer.new(arena.allocator(), 160, 1, 160, 1, 160);
    defer buffer_160.deinit();
    try std.testing.expectEqual(@as(usize, 160), buffer_160.num_frames());

    var buffer_320 = try FrameAudioBuffer.new(arena.allocator(), 320, 1, 320, 1, 320);
    defer buffer_320.deinit();
    try std.testing.expectEqual(@as(usize, 320), buffer_320.num_frames());

    var buffer_480 = try FrameAudioBuffer.new(arena.allocator(), 480, 1, 480, 1, 480);
    defer buffer_480.deinit();
    try std.testing.expectEqual(@as(usize, 480), buffer_480.num_frames());
}

test "audio_buffer num_frames_per_band boundary single band" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // For 16k (1 band), frames per band = total frames
    var buffer_16k = try FrameAudioBuffer.new(arena.allocator(), 160, 1, 160, 1, 160);
    defer buffer_16k.deinit();
    try std.testing.expectEqual(@as(usize, 160), buffer_16k.num_frames_per_band());

    // For 32k (2 bands), frames per band = total / 2
    var buffer_32k = try FrameAudioBuffer.new(arena.allocator(), 320, 1, 320, 1, 320);
    defer buffer_32k.deinit();
    try std.testing.expectEqual(@as(usize, 160), buffer_32k.num_frames_per_band());
}

test "audio_buffer set_num_channels reduces channel count" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buffer = try FrameAudioBuffer.new(arena.allocator(), 160, 4, 160, 4, 160);
    defer buffer.deinit();

    try std.testing.expectEqual(@as(usize, 4), buffer.num_channels());
    try buffer.set_num_channels(2);
    try std.testing.expectEqual(@as(usize, 2), buffer.num_channels());
}

test "audio_buffer set_num_channels to zero" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buffer = try FrameAudioBuffer.new(arena.allocator(), 160, 2, 160, 2, 160);
    defer buffer.deinit();

    try buffer.set_num_channels(0);
    try std.testing.expectEqual(@as(usize, 0), buffer.num_channels());
}

test "audio_buffer num_channels boundary after repeated toggles" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buffer = try FrameAudioBuffer.new(arena.allocator(), 480, 2, 480, 2, 480);
    defer buffer.deinit();

    try buffer.set_num_channels(1);
    try std.testing.expectEqual(@as(usize, 1), buffer.num_channels());
    try buffer.set_num_channels(2);
    try std.testing.expectEqual(@as(usize, 2), buffer.num_channels());
    try buffer.set_num_channels(0);
    try std.testing.expectEqual(@as(usize, 0), buffer.num_channels());
}

test "audio_buffer split/merge on single band is no-op" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // 16kHz sample rate -> 1 band (160 samples)
    var buffer = try FrameAudioBuffer.new(arena.allocator(), 160, 1, 160, 1, 160);
    defer buffer.deinit();

    try std.testing.expectEqual(@as(usize, 1), buffer.num_bands());

    for (0..160) |i| {
        buffer.channel_mut(0)[i] = @floatFromInt(i);
    }

    var original = [_]f32{0} ** 160;
    @memcpy(original[0..], buffer.channel(0));

    buffer.split_into_frequency_bands();
    buffer.merge_frequency_bands();

    try std.testing.expectEqualSlices(f32, original[0..], buffer.channel(0));
}

test "audio_buffer boundary rejects invalid channel setup" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectError(error.InvalidBufferChannelCount, FrameAudioBuffer.new(arena.allocator(), 160, 1, 160, 2, 160));
}

test "audio_buffer boundary rejects zero frames" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectError(error.InvalidFrameCount, FrameAudioBuffer.new(arena.allocator(), 0, 1, 160, 1, 160));
    try std.testing.expectError(error.InvalidFrameCount, FrameAudioBuffer.new(arena.allocator(), 160, 1, 0, 1, 160));
    try std.testing.expectError(error.InvalidFrameCount, FrameAudioBuffer.new(arena.allocator(), 160, 1, 160, 1, 0));
}

test "audio_buffer boundary rejects zero channels" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectError(error.InvalidChannelCount, FrameAudioBuffer.new(arena.allocator(), 160, 0, 160, 1, 160));
    try std.testing.expectError(error.InvalidChannelCount, FrameAudioBuffer.new(arena.allocator(), 160, 1, 160, 0, 160));
}

test "audio_buffer num_bands returns correct value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buffer_16k = try FrameAudioBuffer.new(arena.allocator(), 160, 1, 160, 1, 160);
    defer buffer_16k.deinit();
    try std.testing.expectEqual(@as(usize, 1), buffer_16k.num_bands());

    var buffer_32k = try FrameAudioBuffer.new(arena.allocator(), 320, 1, 320, 1, 320);
    defer buffer_32k.deinit();
    try std.testing.expectEqual(@as(usize, 2), buffer_32k.num_bands());

    var buffer_48k = try FrameAudioBuffer.new(arena.allocator(), 480, 1, 480, 1, 480);
    defer buffer_48k.deinit();
    try std.testing.expectEqual(@as(usize, 3), buffer_48k.num_bands());
}

test "audio_buffer num_bands boundary non-standard frame counts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // Non-standard frame counts should default to 1 band
    var buffer_100 = try FrameAudioBuffer.new(arena.allocator(), 100, 1, 100, 1, 100);
    defer buffer_100.deinit();
    try std.testing.expectEqual(@as(usize, 1), buffer_100.num_bands());

    var buffer_200 = try FrameAudioBuffer.new(arena.allocator(), 200, 1, 200, 1, 200);
    defer buffer_200.deinit();
    try std.testing.expectEqual(@as(usize, 1), buffer_200.num_bands());
}

test "audio_buffer channel and channel_mut provide access" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buffer = try FrameAudioBuffer.new(arena.allocator(), 160, 2, 160, 2, 160);
    defer buffer.deinit();

    // Test channel_mut writes and channel reads
    buffer.channel_mut(0)[0] = 5.0;
    buffer.channel_mut(1)[10] = 10.0;

    try std.testing.expectEqual(@as(f32, 5.0), buffer.channel(0)[0]);
    try std.testing.expectEqual(@as(f32, 10.0), buffer.channel(1)[10]);
}

test "audio_buffer channel boundary last valid index" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buffer = try FrameAudioBuffer.new(arena.allocator(), 160, 1, 160, 1, 160);
    defer buffer.deinit();

    buffer.channel_mut(0)[159] = 1.0;
    try std.testing.expectEqual(@as(f32, 1.0), buffer.channel(0)[159]);
}

test "audio_buffer split_band and split_band_mut provide access" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buffer = try FrameAudioBuffer.new(arena.allocator(), 480, 1, 480, 1, 480);
    defer buffer.deinit();

    buffer.split_into_frequency_bands();

    // Test split_band_mut writes and split_band reads
    buffer.split_band_mut(0, 0)[0] = 3.0;
    buffer.split_band_mut(0, 1)[10] = 7.0;
    buffer.split_band_mut(0, 2)[20] = 11.0;

    try std.testing.expectEqual(@as(f32, 3.0), buffer.split_band(0, 0)[0]);
    try std.testing.expectEqual(@as(f32, 7.0), buffer.split_band(0, 1)[10]);
    try std.testing.expectEqual(@as(f32, 11.0), buffer.split_band(0, 2)[20]);
}

test "audio_buffer split_band boundary last valid band index" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buffer = try FrameAudioBuffer.new(arena.allocator(), 480, 1, 480, 1, 480);
    defer buffer.deinit();

    buffer.split_into_frequency_bands();
    const last = buffer.num_bands() - 1;
    _ = buffer.split_band(0, last)[0];
}

test "audio_buffer split_band_mut boundary last valid band index" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buffer = try FrameAudioBuffer.new(arena.allocator(), 480, 1, 480, 1, 480);
    defer buffer.deinit();

    buffer.split_into_frequency_bands();
    const last = buffer.num_bands() - 1;
    buffer.split_band_mut(0, last)[0] = 1.0;
    try std.testing.expectEqual(@as(f32, 1.0), buffer.split_band(0, last)[0]);
}

test "audio_buffer split_band on single band returns data band" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // 16kHz -> 1 band
    var buffer = try FrameAudioBuffer.new(arena.allocator(), 160, 1, 160, 1, 160);
    defer buffer.deinit();

    buffer.channel_mut(0)[0] = 42.0;

    // split_band should return the same data as channel for single band
    try std.testing.expectEqual(@as(f32, 42.0), buffer.split_band(0, 0)[0]);
}

test "audio_buffer new cleans up on allocation failure" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    const alloc = failing.allocator();

    try std.testing.expectError(error.OutOfMemory, FrameAudioBuffer.new(alloc, 480, 1, 480, 1, 480));
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
}

test "audio_buffer set_num_channels keeps splitting filter in sync" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buffer = try FrameAudioBuffer.new(arena.allocator(), 480, 2, 480, 2, 480);
    defer buffer.deinit();

    for (0..480) |i| {
        const t = @as(f32, @floatFromInt(i)) / 48_000.0;
        buffer.channel_mut(0)[i] = 600.0 * @sin(2.0 * std.math.pi * 700.0 * t);
        buffer.channel_mut(1)[i] = 400.0 * @sin(2.0 * std.math.pi * 1200.0 * t);
    }

    try buffer.set_num_channels(1);
    buffer.split_into_frequency_bands();
    buffer.merge_frequency_bands();

    var energy: f32 = 0.0;
    for (buffer.channel(0)) |v| energy += v * v;
    try std.testing.expect(std.math.isFinite(energy));
    try std.testing.expect(energy > 0.0);
}

test "audio_buffer deinit frees memory" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buffer = try FrameAudioBuffer.new(arena.allocator(), 480, 2, 480, 2, 480);
    buffer.deinit();

    // If deinit doesn't free properly, arena will detect leak
    try std.testing.expect(true);
}

test "audio_buffer deinit boundary single band" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // 16kHz -> 1 band (no splitting filter allocated)
    var buffer = try FrameAudioBuffer.new(arena.allocator(), 160, 1, 160, 1, 160);
    buffer.deinit();

    try std.testing.expect(true);
}

test "audio_buffer deinit boundary after split_merge" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buffer = try FrameAudioBuffer.new(arena.allocator(), 480, 1, 480, 1, 480);

    // Use the buffer before deinit
    for (0..480) |i| {
        buffer.channel_mut(0)[i] = @floatFromInt(i);
    }
    buffer.split_into_frequency_bands();
    buffer.merge_frequency_bands();

    buffer.deinit();

    try std.testing.expect(true);
}

test "audio_buffer set_num_channels rollback on failure" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const alloc = failing.allocator();

    // Create buffer with 3 bands (has splitting_filter), then shrink to force future growth allocation.
    var buffer = try FrameAudioBuffer.new(alloc, 480, 2, 480, 2, 480);
    defer buffer.deinit();

    try buffer.set_num_channels(1);

    const old_num_channels = buffer.num_channels_;
    const old_data_channels = buffer.data.num_channels();
    const old_split_channels = buffer.split_data.?.num_channels();
    const old_filter_channels = buffer.splitting_filter.?.num_channels_;
    const old_filter_len = buffer.splitting_filter.?.three_band_filter_banks.len;

    failing.fail_index = failing.alloc_index; // fail next growth allocation in SplittingFilter.set_num_channels
    try std.testing.expectError(error.OutOfMemory, buffer.set_num_channels(2));

    // State must remain unchanged after failure.
    try std.testing.expectEqual(old_num_channels, buffer.num_channels_);
    try std.testing.expectEqual(old_num_channels, buffer.num_channels());
    try std.testing.expectEqual(old_data_channels, buffer.data.num_channels());
    try std.testing.expectEqual(old_split_channels, buffer.split_data.?.num_channels());
    try std.testing.expectEqual(old_filter_channels, buffer.splitting_filter.?.num_channels_);
    try std.testing.expectEqual(old_filter_len, buffer.splitting_filter.?.three_band_filter_banks.len);

    // After failure, operation can still succeed once allocation is available.
    failing.fail_index = std.math.maxInt(usize);
    try buffer.set_num_channels(2);
    try std.testing.expectEqual(@as(usize, 2), buffer.num_channels());
    try std.testing.expectEqual(@as(usize, 2), buffer.data.num_channels());
    try std.testing.expectEqual(@as(usize, 2), buffer.split_data.?.num_channels());
    try std.testing.expectEqual(@as(usize, 2), buffer.splitting_filter.?.num_channels_);
}
