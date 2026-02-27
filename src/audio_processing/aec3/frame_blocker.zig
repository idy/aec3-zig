const std = @import("std");
const common = @import("aec3_common.zig");

const BLOCK_SIZE = common.BLOCK_SIZE;
const SUB_FRAME_LENGTH = common.SUB_FRAME_LENGTH;

pub const FrameBlocker = struct {
    const Self = @This();

    num_bands: usize,
    num_channels: usize,
    buffer: [][][]f32,
    buffered_len: [][]usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, num_bands: usize, num_channels: usize) !Self {
        if (num_bands == 0) return error.InvalidBandCount;
        if (num_channels == 0) return error.InvalidChannelCount;

        const buffer = try allocator.alloc([][]f32, num_bands);
        errdefer allocator.free(buffer);
        const lengths = try allocator.alloc([]usize, num_bands);
        errdefer allocator.free(lengths);

        var bands_done: usize = 0;
        errdefer {
            for (0..bands_done) |b| {
                for (buffer[b]) |channel| allocator.free(channel);
                allocator.free(buffer[b]);
                allocator.free(lengths[b]);
            }
        }

        for (0..num_bands) |b| {
            buffer[b] = try allocator.alloc([]f32, num_channels);
            lengths[b] = try allocator.alloc(usize, num_channels);
            for (0..num_channels) |c| {
                buffer[b][c] = try allocator.alloc(f32, BLOCK_SIZE);
                lengths[b][c] = 0;
            }
            bands_done += 1;
        }

        return .{
            .num_bands = num_bands,
            .num_channels = num_channels,
            .buffer = buffer,
            .buffered_len = lengths,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        for (0..self.num_bands) |b| {
            for (0..self.num_channels) |c| self.allocator.free(self.buffer[b][c]);
            self.allocator.free(self.buffer[b]);
            self.allocator.free(self.buffered_len[b]);
        }
        self.allocator.free(self.buffer);
        self.allocator.free(self.buffered_len);
        self.* = undefined;
    }

    pub fn insert_sub_frame_and_extract_block(
        self: *Self,
        sub_frame: []const []const []const f32,
        block: [][][]f32,
    ) void {
        std.debug.assert(sub_frame.len == self.num_bands);
        std.debug.assert(block.len == self.num_bands);

        for (0..self.num_bands) |b| {
            std.debug.assert(sub_frame[b].len == self.num_channels);
            std.debug.assert(block[b].len == self.num_channels);
            for (0..self.num_channels) |c| {
                std.debug.assert(sub_frame[b][c].len == SUB_FRAME_LENGTH);
                std.debug.assert(block[b][c].len == BLOCK_SIZE);

                const buffered = self.buffered_len[b][c];
                std.debug.assert(buffered <= BLOCK_SIZE - (SUB_FRAME_LENGTH - BLOCK_SIZE));
                const need = BLOCK_SIZE - buffered;

                @memcpy(block[b][c][0..buffered], self.buffer[b][c][0..buffered]);
                @memcpy(block[b][c][buffered..BLOCK_SIZE], sub_frame[b][c][0..need]);

                const remain = SUB_FRAME_LENGTH - need;
                @memcpy(self.buffer[b][c][0..remain], sub_frame[b][c][need..SUB_FRAME_LENGTH]);
                self.buffered_len[b][c] = remain;
            }
        }
    }

    pub fn is_block_available(self: Self) bool {
        return self.buffered_len[0][0] == BLOCK_SIZE;
    }

    pub fn extract_block(self: *Self, block: [][][]f32) void {
        std.debug.assert(self.is_block_available());
        std.debug.assert(block.len == self.num_bands);
        for (0..self.num_bands) |b| {
            std.debug.assert(block[b].len == self.num_channels);
            for (0..self.num_channels) |c| {
                std.debug.assert(block[b][c].len == BLOCK_SIZE);
                std.debug.assert(self.buffered_len[b][c] == BLOCK_SIZE);
                @memcpy(block[b][c], self.buffer[b][c]);
                self.buffered_len[b][c] = 0;
            }
        }
    }
};

fn alloc_tensor(allocator: std.mem.Allocator, bands: usize, channels: usize, len: usize) ![][][]f32 {
    const out = try allocator.alloc([][]f32, bands);
    var bands_done: usize = 0;
    errdefer {
        for (0..bands_done) |b| {
            for (out[b]) |ch| allocator.free(ch);
            allocator.free(out[b]);
        }
        allocator.free(out);
    }
    for (0..bands) |b| {
        out[b] = try allocator.alloc([]f32, channels);
        for (0..channels) |c| {
            out[b][c] = try allocator.alloc(f32, len);
            @memset(out[b][c], 0.0);
        }
        bands_done += 1;
    }
    return out;
}

fn free_tensor(allocator: std.mem.Allocator, tensor: [][][]f32) void {
    for (tensor) |band| {
        for (band) |channel| allocator.free(channel);
        allocator.free(band);
    }
    allocator.free(tensor);
}

test "frame_blocker basic continuity" {
    const allocator = std.testing.allocator;
    var blocker = try FrameBlocker.init(allocator, 1, 1);
    defer blocker.deinit();

    const sub = try alloc_tensor(allocator, 1, 1, SUB_FRAME_LENGTH);
    defer free_tensor(allocator, sub);
    const blk = try alloc_tensor(allocator, 1, 1, BLOCK_SIZE);
    defer free_tensor(allocator, blk);

    for (0..SUB_FRAME_LENGTH) |i| sub[0][0][i] = @floatFromInt(i);
    blocker.insert_sub_frame_and_extract_block(sub, blk);
    try std.testing.expectEqual(@as(f32, 0.0), blk[0][0][0]);
    try std.testing.expectEqual(@as(f32, 63.0), blk[0][0][63]);
}
