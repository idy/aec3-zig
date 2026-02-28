const std = @import("std");
const RingBufferState = @import("ring_buffer_state.zig").RingBufferState;
const fft_data = @import("../fft/fft_data.zig");

pub const FftRingBuffer = struct {
    const Self = @This();

    buffer: [][]fft_data.FftData,
    state: RingBufferState,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, size: usize, num_channels: usize) !Self {
        std.debug.assert(size > 0);
        std.debug.assert(num_channels > 0);

        const buffer = try allocator.alloc([]fft_data.FftData, size);
        errdefer allocator.free(buffer);

        var initialized: usize = 0;
        errdefer {
            for (0..initialized) |i| allocator.free(buffer[i]);
            allocator.free(buffer);
        }

        for (0..size) |i| {
            buffer[i] = try allocator.alloc(fft_data.FftData, num_channels);
            for (0..num_channels) |j| buffer[i][j] = fft_data.FftData.new();
            initialized += 1;
        }

        return .{ .buffer = buffer, .state = RingBufferState.init(size), .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        for (self.buffer) |slot| self.allocator.free(slot);
        self.allocator.free(self.buffer);
        self.* = undefined;
    }
};

pub const FftRingBufferFixed = struct {
    const Self = @This();

    buffer: [][]fft_data.FftDataFixed,
    state: RingBufferState,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, size: usize, num_channels: usize) !Self {
        std.debug.assert(size > 0);
        std.debug.assert(num_channels > 0);

        const buffer = try allocator.alloc([]fft_data.FftDataFixed, size);
        errdefer allocator.free(buffer);

        var initialized: usize = 0;
        errdefer {
            for (0..initialized) |i| allocator.free(buffer[i]);
            allocator.free(buffer);
        }

        for (0..size) |i| {
            buffer[i] = try allocator.alloc(fft_data.FftDataFixed, num_channels);
            for (0..num_channels) |j| buffer[i][j] = fft_data.FftDataFixed.new();
            initialized += 1;
        }

        return .{ .buffer = buffer, .state = RingBufferState.init(size), .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        for (self.buffer) |slot| self.allocator.free(slot);
        self.allocator.free(self.buffer);
        self.* = undefined;
    }
};

test "fft_buffer init and index wrap" {
    var fb = try FftRingBuffer.init(std.testing.allocator, 3, 2);
    defer fb.deinit();

    try std.testing.expectEqual(@as(usize, 3), fb.getSize());
    fb.write = 2;
    fb.inc_write_index();
    try std.testing.expectEqual(@as(usize, 0), fb.write);
    fb.read = 0;
    fb.dec_read_index();
    try std.testing.expectEqual(@as(usize, 2), fb.read);
}

test "fft_buffer index and update operations" {
    var fb = try FftRingBuffer.init(std.testing.allocator, 4, 1);
    defer fb.deinit();

    try std.testing.expectEqual(@as(usize, 3), fb.offset_index(0, -1));
    try std.testing.expectEqual(@as(usize, 1), fb.offset_index(0, 1));

    fb.update_write_index(3);
    try std.testing.expectEqual(@as(usize, 3), fb.write);
    fb.inc_write_index();
    try std.testing.expectEqual(@as(usize, 0), fb.write);
    fb.dec_write_index();
    try std.testing.expectEqual(@as(usize, 3), fb.write);

    fb.update_read_index(2);
    try std.testing.expectEqual(@as(usize, 2), fb.read);
    fb.dec_read_index();
    try std.testing.expectEqual(@as(usize, 1), fb.read);
}

test "fft_buffer init rolls back on allocation failure" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const alloc = failing.allocator();
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, FftRingBuffer.init(alloc, 4, 2));
}

test "fft_buffer_fixed init and index wrap" {
    var fb = try FftRingBufferFixed.init(std.testing.allocator, 3, 2);
    defer fb.deinit();

    try std.testing.expectEqual(@as(usize, 3), fb.state.getSize());
    fb.state.write = 2;
    fb.state.inc_write_index();
    try std.testing.expectEqual(@as(usize, 0), fb.state.write);
    fb.state.read = 0;
    fb.state.dec_read_index();
    try std.testing.expectEqual(@as(usize, 2), fb.state.read);
}
