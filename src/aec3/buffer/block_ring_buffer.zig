const std = @import("std");
const RingBufferState = @import("ring_buffer_state.zig").RingBufferState;
const profileFor = @import("../../numeric_profile.zig").profileFor;
pub const Q15 = profileFor(.fixed_mcu_q15).Sample;

pub const BlockRingBuffer = struct {
    const Self = @This();

    buffer: [][][][]f32,
    state: RingBufferState,
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
        var bands_initialized: usize = 0;
        var channels_initialized: usize = 0;

        errdefer {
            for (0..slots_initialized) |i| {
                for (0..num_bands) |j| {
                    for (0..num_channels) |k| allocator.free(buffer[i][j][k]);
                    allocator.free(buffer[i][j]);
                }
                allocator.free(buffer[i]);
            }
            if (slots_initialized < size) {
                for (0..bands_initialized) |j| {
                    for (0..num_channels) |k| allocator.free(buffer[slots_initialized][j][k]);
                    allocator.free(buffer[slots_initialized][j]);
                }
                if (bands_initialized < num_bands) {
                    for (0..channels_initialized) |k| allocator.free(buffer[slots_initialized][bands_initialized][k]);
                }
                // we check if we allocated the slot itself before trying to free it
                // Since bands_initialized means slot was allocated:
                allocator.free(buffer[slots_initialized]);
            }
        }

        for (0..size) |i| {
            bands_initialized = 0;
            buffer[i] = try allocator.alloc([][]f32, num_bands);
            for (0..num_bands) |j| {
                channels_initialized = 0;
                buffer[i][j] = try allocator.alloc([]f32, num_channels);
                for (0..num_channels) |k| {
                    buffer[i][j][k] = try allocator.alloc(f32, frame_length);
                    @memset(buffer[i][j][k], 0.0);
                    channels_initialized += 1;
                }
                bands_initialized += 1;
            }
            slots_initialized += 1;
        }

        return .{ .buffer = buffer, .state = RingBufferState.init(size), .allocator = allocator };
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
};

pub const BlockRingBufferFixed = struct {
    const Self = @This();

    buffer: [][][][]Q15,
    state: RingBufferState,
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
        var bands_initialized: usize = 0;
        var channels_initialized: usize = 0;

        errdefer {
            for (0..slots_initialized) |i| {
                for (0..num_bands) |j| {
                    for (0..num_channels) |k| allocator.free(buffer[i][j][k]);
                    allocator.free(buffer[i][j]);
                }
                allocator.free(buffer[i]);
            }
            if (slots_initialized < size) {
                for (0..bands_initialized) |j| {
                    for (0..num_channels) |k| allocator.free(buffer[slots_initialized][j][k]);
                    allocator.free(buffer[slots_initialized][j]);
                }
                if (bands_initialized < num_bands) {
                    for (0..channels_initialized) |k| allocator.free(buffer[slots_initialized][bands_initialized][k]);
                }
                allocator.free(buffer[slots_initialized]);
            }
        }

        for (0..size) |i| {
            bands_initialized = 0;
            buffer[i] = try allocator.alloc([][]Q15, num_bands);
            for (0..num_bands) |j| {
                channels_initialized = 0;
                buffer[i][j] = try allocator.alloc([]Q15, num_channels);
                for (0..num_channels) |k| {
                    buffer[i][j][k] = try allocator.alloc(Q15, frame_length);
                    @memset(buffer[i][j][k], Q15.zero());
                    channels_initialized += 1;
                }
                bands_initialized += 1;
            }
            slots_initialized += 1;
        }

        return .{ .buffer = buffer, .state = RingBufferState.init(size), .allocator = allocator };
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
};

test "block_buffer ring semantics basic" {
    var bb = try BlockRingBuffer.init(std.testing.allocator, 2, 1, 1, 4);
    defer bb.deinit();

    bb.buffer[0][0][0][0] = 1.0;
    bb.state.inc_write_index();
    bb.buffer[1][0][0][0] = 2.0;
    bb.state.inc_write_index(); // wrap
    bb.buffer[0][0][0][0] = 3.0; // overwrite oldest slot

    try std.testing.expectEqual(@as(f32, 3.0), bb.buffer[0][0][0][0]);
    try std.testing.expectEqual(@as(f32, 2.0), bb.buffer[1][0][0][0]);
}

test "block_buffer index helpers cover wrap and offset" {
    var bb = try BlockRingBuffer.init(std.testing.allocator, 4, 1, 1, 2);
    defer bb.deinit();

    try std.testing.expectEqual(@as(usize, 1), bb.state.inc_index(0));
    try std.testing.expectEqual(@as(usize, 0), bb.state.inc_index(3));
    try std.testing.expectEqual(@as(usize, 3), bb.state.dec_index(0));
    try std.testing.expectEqual(@as(usize, 2), bb.state.dec_index(3));
    try std.testing.expectEqual(@as(usize, 3), bb.state.offset_index(0, -1));
    try std.testing.expectEqual(@as(usize, 2), bb.state.offset_index(1, 1));

    bb.state.update_write_index(2);
    try std.testing.expectEqual(@as(usize, 2), bb.state.write);
    bb.state.dec_write_index();
    try std.testing.expectEqual(@as(usize, 1), bb.state.write);
    bb.state.inc_read_index();
    try std.testing.expectEqual(@as(usize, 1), bb.state.read);
    bb.state.update_read_index(-1);
    try std.testing.expectEqual(@as(usize, 0), bb.state.read);
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
    bb.state.inc_write_index();
    bb.buffer[1][0][0][0] = Q15.fromInt(2);
    bb.state.inc_write_index();
    bb.buffer[0][0][0][0] = Q15.fromInt(3);

    try std.testing.expectEqual(@as(i32, Q15.fromInt(3).raw), bb.buffer[0][0][0][0].raw);
    try std.testing.expectEqual(@as(i32, Q15.fromInt(2).raw), bb.buffer[1][0][0][0].raw);
}
