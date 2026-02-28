const std = @import("std");

/// A reusable state and index manager for ring buffers.
pub const RingBufferState = struct {
    write: usize,
    read: usize,
    size: usize,

    pub fn init(size: usize) @This() {
        std.debug.assert(size > 0);
        return .{
            .write = 0,
            .read = 0,
            .size = size,
        };
    }

    pub fn inc_index(self: @This(), index: usize) usize {
        return if (index + 1 < self.size) index + 1 else 0;
    }

    pub fn dec_index(self: @This(), index: usize) usize {
        return if (index > 0) index - 1 else self.size - 1;
    }

    pub fn offset_index(self: @This(), index: usize, offset: isize) usize {
        std.debug.assert(self.size > 0);
        const size_i: isize = @intCast(self.size);
        var v: isize = @as(isize, @intCast(index)) + offset;
        v = @mod(v, size_i);
        return @intCast(v);
    }

    pub fn update_write_index(self: *@This(), offset: isize) void {
        self.write = self.offset_index(self.write, offset);
    }

    pub fn inc_write_index(self: *@This()) void {
        self.write = self.inc_index(self.write);
    }

    pub fn dec_write_index(self: *@This()) void {
        self.write = self.dec_index(self.write);
    }

    pub fn update_read_index(self: *@This(), offset: isize) void {
        self.read = self.offset_index(self.read, offset);
    }

    pub fn inc_read_index(self: *@This()) void {
        self.read = self.inc_index(self.read);
    }

    pub fn dec_read_index(self: *@This()) void {
        self.read = self.dec_index(self.read);
    }
};
