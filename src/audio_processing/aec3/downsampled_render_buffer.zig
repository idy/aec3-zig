const std = @import("std");

pub const DownsampledRenderBuffer = struct {
    const Self = @This();

    buffer: []f32,
    write: usize,
    read: usize,
    size: usize,

    pub fn init(storage: []f32) Self {
        std.debug.assert(storage.len > 0);
        return .{ .buffer = storage, .write = 0, .read = 0, .size = storage.len };
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

test "downsampled_render_buffer index wrap" {
    var store = [_]f32{1.0} ** 5;
    var rb = DownsampledRenderBuffer.init(store[0..]);
    try std.testing.expectEqual(@as(usize, 5), rb.getSize());
    rb.write = 4;
    rb.inc_write_index();
    try std.testing.expectEqual(@as(usize, 0), rb.write);
    try std.testing.expectEqual(@as(usize, 4), rb.offset_index(0, -1));
}

test "downsampled_render_buffer init keeps existing storage content" {
    var store = [_]f32{ 3.0, 4.0, 5.0 };
    const rb = DownsampledRenderBuffer.init(store[0..]);
    try std.testing.expectEqual(@as(f32, 3.0), rb.buffer[0]);
    try std.testing.expectEqual(@as(f32, 4.0), rb.buffer[1]);
}

test "downsampled_render_buffer update read/write index operations" {
    var store = [_]f32{ 0.0, 1.0, 2.0, 3.0 };
    var rb = DownsampledRenderBuffer.init(store[0..]);

    rb.update_write_index(2);
    try std.testing.expectEqual(@as(usize, 2), rb.write);
    rb.dec_write_index();
    try std.testing.expectEqual(@as(usize, 1), rb.write);
    rb.inc_write_index();
    try std.testing.expectEqual(@as(usize, 2), rb.write);

    rb.update_read_index(-1);
    try std.testing.expectEqual(@as(usize, 3), rb.read);
    rb.inc_read_index();
    try std.testing.expectEqual(@as(usize, 0), rb.read);
    rb.dec_read_index();
    try std.testing.expectEqual(@as(usize, 3), rb.read);
}
