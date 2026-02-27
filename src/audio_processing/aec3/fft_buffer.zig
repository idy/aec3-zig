const std = @import("std");
const fft_data = @import("fft_data.zig");

pub const FftBuffer = struct {
    const Self = @This();

    buffer: [][]fft_data.FftData,
    write: usize,
    read: usize,
    size: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, size: usize, num_channels: usize) !Self {
        std.debug.assert(size > 0);
        std.debug.assert(num_channels > 0);

        const buffer = try allocator.alloc([]fft_data.FftData, size);
        errdefer allocator.free(buffer);

        var initialized: usize = 0;
        errdefer {
            for (buffer[0..initialized]) |slot| allocator.free(slot);
        }

        for (buffer) |*slot| {
            slot.* = try allocator.alloc(fft_data.FftData, num_channels);
            for (slot.*) |*channel| channel.* = fft_data.FftData.new();
            initialized += 1;
        }

        return .{ .buffer = buffer, .write = 0, .read = 0, .size = size, .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        for (self.buffer) |slot| self.allocator.free(slot);
        self.allocator.free(self.buffer);
        self.* = undefined;
    }

    pub fn getSize(self: Self) usize {
        return self.size;
    }

    pub fn inc_index(self: Self, index: usize) usize {
        return if (index + 1 < self.size) index + 1 else 0;
    }

    pub fn dec_index(self: Self, index: usize) usize {
        return if (index > 0) index - 1 else self.size - 1;
    }

    pub fn offset_index(self: Self, index: usize, offset: isize) usize {
        const size_i: isize = @intCast(self.size);
        var v: isize = @as(isize, @intCast(index)) + offset;
        v = @mod(v, size_i);
        return @intCast(v);
    }

    pub fn update_write_index(self: *Self, offset: isize) void {
        self.write = self.offset_index(self.write, offset);
    }

    pub fn inc_write_index(self: *Self) void {
        self.write = self.inc_index(self.write);
    }

    pub fn dec_write_index(self: *Self) void {
        self.write = self.dec_index(self.write);
    }

    pub fn update_read_index(self: *Self, offset: isize) void {
        self.read = self.offset_index(self.read, offset);
    }

    pub fn inc_read_index(self: *Self) void {
        self.read = self.inc_index(self.read);
    }

    pub fn dec_read_index(self: *Self) void {
        self.read = self.dec_index(self.read);
    }
};

test "fft_buffer init and index wrap" {
    var fb = try FftBuffer.init(std.testing.allocator, 3, 2);
    defer fb.deinit();

    try std.testing.expectEqual(@as(usize, 3), fb.getSize());
    fb.write = 2;
    fb.inc_write_index();
    try std.testing.expectEqual(@as(usize, 0), fb.write);
    fb.read = 0;
    fb.dec_read_index();
    try std.testing.expectEqual(@as(usize, 2), fb.read);
}
