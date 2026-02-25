//! Ported from: docs/aec3-rs-src/audio_processing/channel_buffer.rs
const std = @import("std");
const audio_util = @import("audio_util.zig");

/// Generic multi-channel multi-band buffer.
pub fn ChannelBuffer(comptime T: type) type {
    return struct {
        const Self = @This();

        data_: []T,
        num_frames_: usize,
        num_frames_per_band_: usize,
        num_allocated_channels_: usize,
        num_channels_: usize,
        num_bands_: usize,
        allocator: std.mem.Allocator,

        /// Creates a new ChannelBuffer with the specified dimensions.
        pub fn new(allocator: std.mem.Allocator, frames: usize, channels: usize, bands: usize) !Self {
            if (frames == 0) return error.InvalidFrameCount;
            if (channels == 0) return error.InvalidChannelCount;
            if (bands == 0) return error.InvalidBandCount;
            if (frames % bands != 0) return error.FrameCountNotDivisibleByBandCount;

            return .{
                .data_ = try allocator.alloc(T, frames * channels),
                .num_frames_ = frames,
                .num_frames_per_band_ = frames / bands,
                .num_allocated_channels_ = channels,
                .num_channels_ = channels,
                .num_bands_ = bands,
                .allocator = allocator,
            };
        }

        /// Frees the allocated memory.
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.data_);
        }

        /// Returns the total number of frames.
        pub fn num_frames(self: Self) usize {
            return self.num_frames_;
        }

        /// Returns the number of frames per band.
        pub fn num_frames_per_band(self: Self) usize {
            return self.num_frames_per_band_;
        }

        /// Returns the number of channels.
        pub fn num_channels(self: Self) usize {
            return self.num_channels_;
        }

        /// Returns the number of bands.
        pub fn num_bands(self: Self) usize {
            return self.num_bands_;
        }

        /// Sets the number of active channels.
        pub fn set_num_channels(self: *Self, channels: usize) void {
            std.debug.assert(channels <= self.num_allocated_channels_);
            self.num_channels_ = channels;
        }

        /// Returns read-only access to a channel.
        pub fn channel(self: Self, channel_index: usize) []const T {
            std.debug.assert(channel_index < self.num_channels_);
            const start = channel_index * self.num_frames_;
            return self.data_[start .. start + self.num_frames_];
        }

        /// Returns mutable access to a channel.
        pub fn channel_mut(self: *Self, channel_index: usize) []T {
            std.debug.assert(channel_index < self.num_channels_);
            const start = channel_index * self.num_frames_;
            return self.data_[start .. start + self.num_frames_];
        }

        /// Returns read-only access to a band.
        pub fn band(self: Self, channel_index: usize, band_index: usize) []const T {
            std.debug.assert(channel_index < self.num_channels_);
            std.debug.assert(band_index < self.num_bands_);
            const start = channel_index * self.num_frames_ + band_index * self.num_frames_per_band_;
            return self.data_[start .. start + self.num_frames_per_band_];
        }

        /// Returns mutable access to a band.
        pub fn band_mut(self: *Self, channel_index: usize, band_index: usize) []T {
            std.debug.assert(channel_index < self.num_channels_);
            std.debug.assert(band_index < self.num_bands_);
            const start = channel_index * self.num_frames_ + band_index * self.num_frames_per_band_;
            return self.data_[start .. start + self.num_frames_per_band_];
        }

        /// Returns read-only access to all data.
        pub fn data(self: Self) []const T {
            return self.data_;
        }

        /// Returns mutable access to all data.
        pub fn data_mut(self: *Self) []T {
            return self.data_;
        }
    };
}

/// Interleaved float/int channel buffer for format conversion.
pub const IFChannelBuffer = struct {
    ivalid: bool,
    ibuf_: ChannelBuffer(i16),
    fvalid: bool,
    fbuf_: ChannelBuffer(f32),

    /// Creates a new IFChannelBuffer with the specified dimensions.
    pub fn new(allocator: std.mem.Allocator, num_frames: usize, num_channels: usize, num_bands: usize) !IFChannelBuffer {
        var ibuf_buf = try ChannelBuffer(i16).new(allocator, num_frames, num_channels, num_bands);
        errdefer ibuf_buf.deinit();

        const fbuf_buf = try ChannelBuffer(f32).new(allocator, num_frames, num_channels, num_bands);
        return .{
            .ivalid = true,
            .ibuf_ = ibuf_buf,
            .fvalid = true,
            .fbuf_ = fbuf_buf,
        };
    }

    /// Frees the allocated memory for both buffers.
    pub fn deinit(self: *IFChannelBuffer) void {
        self.ibuf_.deinit();
        self.fbuf_.deinit();
    }

    /// Returns mutable access to the i16 buffer (refreshes from f32 if needed).
    pub fn ibuf(self: *IFChannelBuffer) *ChannelBuffer(i16) {
        self.refresh_i();
        self.fvalid = false;
        return &self.ibuf_;
    }

    /// Returns mutable access to the f32 buffer (refreshes from i16 if needed).
    pub fn fbuf(self: *IFChannelBuffer) *ChannelBuffer(f32) {
        self.refresh_f();
        self.ivalid = false;
        return &self.fbuf_;
    }

    /// Returns const access to the i16 buffer (refreshes from f32 if needed).
    pub fn ibuf_const(self: *IFChannelBuffer) *const ChannelBuffer(i16) {
        self.refresh_i();
        return &self.ibuf_;
    }

    /// Returns const access to the f32 buffer (refreshes from i16 if needed).
    pub fn fbuf_const(self: *IFChannelBuffer) *const ChannelBuffer(f32) {
        self.refresh_f();
        return &self.fbuf_;
    }

    /// Sets the number of active channels for both buffers.
    pub fn set_num_channels(self: *IFChannelBuffer, num_channels: usize) void {
        self.ibuf_.set_num_channels(num_channels);
        self.fbuf_.set_num_channels(num_channels);
    }

    fn refresh_f(self: *IFChannelBuffer) void {
        if (!self.fvalid) {
            std.debug.assert(self.ivalid);
            var ch: usize = 0;
            while (ch < self.ibuf_.num_channels()) : (ch += 1) {
                const src = self.ibuf_.channel(ch);
                const dst = self.fbuf_.channel_mut(ch);
                for (src, dst) |s, *d| d.* = @floatFromInt(s);
            }
            self.fbuf_.set_num_channels(self.ibuf_.num_channels());
            self.fvalid = true;
        }
    }

    fn refresh_i(self: *IFChannelBuffer) void {
        if (!self.ivalid) {
            std.debug.assert(self.fvalid);
            var ch: usize = 0;
            while (ch < self.fbuf_.num_channels()) : (ch += 1) {
                const src = self.fbuf_.channel(ch);
                const dst = self.ibuf_.channel_mut(ch);
                audio_util.float_s16_slice_to_s16(src, dst);
            }
            self.ibuf_.set_num_channels(self.fbuf_.num_channels());
            self.ivalid = true;
        }
    }
};

test "test_single_channel_read_write" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buf = try ChannelBuffer(f32).new(arena.allocator(), 4, 1, 1);
    defer buf.deinit();

    const ch = buf.channel_mut(0);
    ch[0] = 1.0;
    ch[1] = 2.0;
    try std.testing.expectEqual(@as(f32, 1.0), buf.channel(0)[0]);
    try std.testing.expectEqual(@as(f32, 2.0), buf.channel(0)[1]);
}

test "test_multi_channel" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buf = try ChannelBuffer(i16).new(arena.allocator(), 4, 2, 1);
    defer buf.deinit();

    buf.channel_mut(0)[0] = 11;
    buf.channel_mut(1)[0] = 22;
    try std.testing.expectEqual(@as(i16, 11), buf.channel(0)[0]);
    try std.testing.expectEqual(@as(i16, 22), buf.channel(1)[0]);
}

test "test_multi_band" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buf = try ChannelBuffer(f32).new(arena.allocator(), 8, 1, 2);
    defer buf.deinit();

    buf.band_mut(0, 0)[0] = 1.0;
    buf.band_mut(0, 1)[0] = 2.0;
    try std.testing.expectEqual(@as(f32, 1.0), buf.band(0, 0)[0]);
    try std.testing.expectEqual(@as(f32, 2.0), buf.band(0, 1)[0]);
}

test "test_new_rejects_invalid_dimensions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectError(error.InvalidFrameCount, ChannelBuffer(f32).new(arena.allocator(), 0, 1, 1));
    try std.testing.expectError(error.InvalidChannelCount, ChannelBuffer(f32).new(arena.allocator(), 8, 0, 1));
    try std.testing.expectError(error.InvalidBandCount, ChannelBuffer(f32).new(arena.allocator(), 8, 1, 0));
    try std.testing.expectError(error.FrameCountNotDivisibleByBandCount, ChannelBuffer(f32).new(arena.allocator(), 7, 1, 2));
}

test "test_if_channel_buffer_new_cleans_up_on_second_allocation_failure" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    const alloc = failing.allocator();

    try std.testing.expectError(error.OutOfMemory, IFChannelBuffer.new(alloc, 8, 1, 1));
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
}
