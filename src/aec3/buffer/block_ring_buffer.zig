const std = @import("std");
const profileFor = @import("../../numeric_profile.zig").profileFor;
pub const Q15 = profileFor(.fixed_mcu_q15).Sample;

pub const BlockRingBuffer = struct {
    const Self = @This();

    buffer: [][][][]f32,
    write: usize,
    read: usize,
    size: usize,
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        size: usize,
        num_bands: usize,
        num_channels: usize,
        frame_length: usize,
    ) !Self {
        std.debug.assert(size > 0);
        std.debug.assert(num_bands > 0);
        std.debug.assert(num_channels > 0);
        std.debug.assert(frame_length > 0);

        const buffer = try allocator.alloc([][][]f32, size);
        errdefer allocator.free(buffer);
        var slots_initialized: usize = 0;
        errdefer {
            for (buffer[0..slots_initialized]) |slot| {
                for (slot) |band| {
                    for (band) |channel| allocator.free(channel);
                    allocator.free(band);
                }
                allocator.free(slot);
            }
        }

        for (buffer) |*slot| {
            slot.* = try allocator.alloc([][]f32, num_bands);
            for (slot.*) |*band| {
                band.* = try allocator.alloc([]f32, num_channels);
                for (band.*) |*channel| {
                    channel.* = try allocator.alloc(f32, frame_length);
                    @memset(channel.*, 0.0);
                }
            }
            slots_initialized += 1;
        }

        return .{ .buffer = buffer, .write = 0, .read = 0, .size = size, .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        for (self.buffer) |slot| {
            for (slot) |band| {
                for (band) |channel| self.allocator.free(channel);
                self.allocator.free(band);
            }
            self.allocator.free(slot);
        }
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

pub const BlockRingBufferFixed = struct {
    const Self = @This();

    buffer: [][][][]Q15,
    write: usize,
    read: usize,
    size: usize,
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        size: usize,
        num_bands: usize,
        num_channels: usize,
        frame_length: usize,
    ) !Self {
        std.debug.assert(size > 0);
        std.debug.assert(num_bands > 0);
        std.debug.assert(num_channels > 0);
        std.debug.assert(frame_length > 0);

        const buffer = try allocator.alloc([][][]Q15, size);
        errdefer allocator.free(buffer);
        var slots_initialized: usize = 0;
        errdefer {
            for (buffer[0..slots_initialized]) |slot| {
                for (slot) |band| {
                    for (band) |channel| allocator.free(channel);
                    allocator.free(band);
                }
                allocator.free(slot);
            }
        }

        for (buffer) |*slot| {
            slot.* = try allocator.alloc([][]Q15, num_bands);
            for (slot.*) |*band| {
                band.* = try allocator.alloc([]Q15, num_channels);
                for (band.*) |*channel| {
                    channel.* = try allocator.alloc(Q15, frame_length);
                    @memset(channel.*, Q15.zero());
                }
            }
            slots_initialized += 1;
        }

        return .{ .buffer = buffer, .write = 0, .read = 0, .size = size, .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        for (self.buffer) |slot| {
            for (slot) |band| {
                for (band) |channel| self.allocator.free(channel);
                self.allocator.free(band);
            }
            self.allocator.free(slot);
        }
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

test "block_buffer ring semantics basic" {
    var bb = try BlockRingBuffer.init(std.testing.allocator, 2, 1, 1, 4);
    defer bb.deinit();

    bb.buffer[0][0][0][0] = 1.0;
    bb.inc_write_index();
    bb.buffer[1][0][0][0] = 2.0;
    bb.inc_write_index(); // wrap
    bb.buffer[0][0][0][0] = 3.0; // overwrite oldest slot

    try std.testing.expectEqual(@as(f32, 3.0), bb.buffer[0][0][0][0]);
    try std.testing.expectEqual(@as(f32, 2.0), bb.buffer[1][0][0][0]);
}

test "block_buffer index helpers cover wrap and offset" {
    var bb = try BlockRingBuffer.init(std.testing.allocator, 4, 1, 1, 2);
    defer bb.deinit();

    try std.testing.expectEqual(@as(usize, 1), bb.inc_index(0));
    try std.testing.expectEqual(@as(usize, 0), bb.inc_index(3));
    try std.testing.expectEqual(@as(usize, 3), bb.dec_index(0));
    try std.testing.expectEqual(@as(usize, 2), bb.dec_index(3));
    try std.testing.expectEqual(@as(usize, 3), bb.offset_index(0, -1));
    try std.testing.expectEqual(@as(usize, 2), bb.offset_index(1, 1));

    bb.update_write_index(2);
    try std.testing.expectEqual(@as(usize, 2), bb.write);
    bb.dec_write_index();
    try std.testing.expectEqual(@as(usize, 1), bb.write);
    bb.inc_read_index();
    try std.testing.expectEqual(@as(usize, 1), bb.read);
    bb.update_read_index(-1);
    try std.testing.expectEqual(@as(usize, 0), bb.read);
}

test "block_buffer init rolls back on allocation failure" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const alloc = failing.allocator();

    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, BlockRingBuffer.init(alloc, 3, 2, 2, 8));
}

test "block_buffer_fixed ring semantics basic" {
    var bb = try BlockRingBufferFixed.init(std.testing.allocator, 2, 1, 1, 4);
    defer bb.deinit();

    bb.buffer[0][0][0][0] = Q15.fromInt(1);
    bb.inc_write_index();
    bb.buffer[1][0][0][0] = Q15.fromInt(2);
    bb.inc_write_index();
    bb.buffer[0][0][0][0] = Q15.fromInt(3);

    try std.testing.expectEqual(@as(i32, Q15.fromInt(3).raw), bb.buffer[0][0][0][0].raw);
    try std.testing.expectEqual(@as(i32, Q15.fromInt(2).raw), bb.buffer[1][0][0][0].raw);
}
