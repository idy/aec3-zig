const std = @import("std");
const audio_buffer = @import("../audio_buffer.zig");

pub const BlockDelayBuffer = struct {
    const Self = @This();

    frame_length: usize,
    delay: usize,
    num_bands: usize,
    num_channels: usize,
    lines: [][]f32,
    heads: []usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, num_bands: usize, frame_length: usize, delay_samples: usize) !Self {
        std.debug.assert(num_bands > 0);
        std.debug.assert(frame_length > 0);

        const empty_lines = try allocator.alloc([]f32, 0);
        errdefer allocator.free(empty_lines);
        const empty_heads = try allocator.alloc(usize, 0);

        return .{
            .frame_length = frame_length,
            .delay = delay_samples,
            .num_bands = num_bands,
            .num_channels = 0,
            .lines = empty_lines,
            .heads = empty_heads,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.lines) |line| self.allocator.free(line);
        self.allocator.free(self.lines);
        self.allocator.free(self.heads);
        self.* = undefined;
    }

    fn ensure_channels(self: *Self, channels: usize) !void {
        if (self.delay == 0) {
            self.num_channels = channels;
            return;
        }
        if (self.num_channels != 0) {
            std.debug.assert(self.num_channels == channels);
            return;
        }

        self.allocator.free(self.lines);
        self.allocator.free(self.heads);

        const n = channels * self.num_bands;
        self.lines = try self.allocator.alloc([]f32, n);
        errdefer self.allocator.free(self.lines);
        self.heads = try self.allocator.alloc(usize, n);
        errdefer self.allocator.free(self.heads);

        var initialized: usize = 0;
        errdefer {
            for (self.lines[0..initialized]) |line| self.allocator.free(line);
        }
        for (0..n) |i| {
            self.lines[i] = try self.allocator.alloc(f32, self.delay);
            @memset(self.lines[i], 0.0);
            self.heads[i] = 0;
            initialized += 1;
        }

        self.num_channels = channels;
    }

    inline fn line_index(self: Self, channel: usize, band: usize) usize {
        return channel * self.num_bands + band;
    }

    pub fn delay_signal(self: *Self, frame: *audio_buffer.AudioBuffer) !void {
        std.debug.assert(frame.num_frames_per_band() == self.frame_length);
        std.debug.assert(frame.num_bands() == self.num_bands);

        const channels = frame.num_channels();
        try self.ensure_channels(channels);

        if (self.delay == 0) return;

        for (0..channels) |channel| {
            for (0..self.num_bands) |band| {
                const idx = self.line_index(channel, band);
                const line = self.lines[idx];
                var head = self.heads[idx];
                const data = frame.split_band_mut(channel, band);
                for (0..self.frame_length) |i| {
                    const input = data[i];
                    const out = line[head];
                    line[head] = input;
                    head += 1;
                    if (head == self.delay) head = 0;
                    data[i] = out;
                }
                self.heads[idx] = head;
            }
        }
    }
};

test "block_delay_buffer zero delay passthrough" {
    var ab = try audio_buffer.AudioBuffer.from_sample_rates(std.testing.allocator, 16_000, 1, 16_000, 1, 16_000);
    defer ab.deinit();

    var db = try BlockDelayBuffer.init(std.testing.allocator, ab.num_bands(), ab.num_frames_per_band(), 0);
    defer db.deinit();

    const band = ab.split_band_mut(0, 0);
    band[0] = 7.0;
    try db.delay_signal(&ab);
    try std.testing.expectEqual(@as(f32, 7.0), ab.split_band(0, 0)[0]);
}

test "block_delay_buffer delays all channels and bands" {
    var ab = try audio_buffer.AudioBuffer.from_sample_rates(std.testing.allocator, 32_000, 2, 32_000, 2, 32_000);
    defer ab.deinit();

    var db = try BlockDelayBuffer.init(std.testing.allocator, ab.num_bands(), ab.num_frames_per_band(), 3);
    defer db.deinit();

    for (0..ab.num_channels()) |ch| {
        for (0..ab.num_bands()) |band| {
            const s = ab.split_band_mut(ch, band);
            for (0..ab.num_frames_per_band()) |i| {
                s[i] = @as(f32, @floatFromInt((ch + 1) * 1000 + band * 100 + i));
            }
        }
    }

    try db.delay_signal(&ab);

    for (0..ab.num_channels()) |ch| {
        for (0..ab.num_bands()) |band| {
            const s = ab.split_band(ch, band);
            try std.testing.expectEqual(@as(f32, 0.0), s[0]);
            try std.testing.expectEqual(@as(f32, 0.0), s[1]);
            try std.testing.expectEqual(@as(f32, 0.0), s[2]);
            try std.testing.expectEqual(
                @as(f32, @floatFromInt((ch + 1) * 1000 + band * 100)),
                s[3],
            );
        }
    }
}

test "block_delay_buffer init rolls back on allocation failure" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const alloc = failing.allocator();
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, BlockDelayBuffer.init(alloc, 1, 64, 3));
}

test "block_delay_buffer delay_signal propagates OOM during lazy line allocation" {
    var ab = try audio_buffer.AudioBuffer.from_sample_rates(std.testing.allocator, 32_000, 2, 32_000, 2, 32_000);
    defer ab.deinit();

    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var db = try BlockDelayBuffer.init(failing.allocator(), ab.num_bands(), ab.num_frames_per_band(), 4);
    defer db.deinit();

    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, db.delay_signal(&ab));
}
