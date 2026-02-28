//! Ported from: docs/aec3-rs-src/audio_processing/aec3/spectrum_buffer.rs
//! Circular buffer for per-channel power spectra with read/write indices.
const std = @import("std");
const common = @import("../common/aec3_common.zig");

const FFT_LENGTH_BY_2_PLUS_1 = common.FFT_LENGTH_BY_2_PLUS_1;

/// A single spectrum array for one channel at one time slot.
pub const Spectrum = [FFT_LENGTH_BY_2_PLUS_1]f32;
pub const SpectrumQ30 = [FFT_LENGTH_BY_2_PLUS_1]i64;

/// Circular buffer holding per-channel spectra at each time slot.
pub const SpectrumRingBuffer = struct {
    const Self = @This();

    /// buffer[slot][channel] = spectrum array
    buffer: [][]Spectrum,
    /// Current write position in the ring.
    write: usize,
    /// Current read position in the ring.
    read: usize,
    /// Number of slots in the ring.
    size: usize,
    /// Backing allocator used for cleanup.
    allocator: std.mem.Allocator,

    /// Creates a new SpectrumBuffer with `size` slots and `num_channels` per slot.
    pub fn init(allocator: std.mem.Allocator, size: usize, num_channels: usize) !Self {
        std.debug.assert(size > 0);
        std.debug.assert(num_channels > 0);

        const buffer = try allocator.alloc([]Spectrum, size);
        errdefer allocator.free(buffer);

        var initialized: usize = 0;
        errdefer {
            for (buffer[0..initialized]) |slot| {
                allocator.free(slot);
            }
        }

        for (buffer) |*slot| {
            slot.* = try allocator.alloc(Spectrum, num_channels);
            for (slot.*) |*ch| {
                ch.* = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
            }
            initialized += 1;
        }

        return .{
            .buffer = buffer,
            .write = 0,
            .read = 0,
            .size = size,
            .allocator = allocator,
        };
    }

    /// Releases all allocated memory.
    pub fn deinit(self: *Self) void {
        for (self.buffer) |slot| {
            self.allocator.free(slot);
        }
        self.allocator.free(self.buffer);
        self.* = undefined;
    }

    /// Returns the ring size.
    pub fn getSize(self: Self) usize {
        return self.size;
    }

    /// Increments an index by one, wrapping around.
    pub fn inc_index(self: Self, index: usize) usize {
        return if (index + 1 < self.size) index + 1 else 0;
    }

    /// Decrements an index by one, wrapping around.
    pub fn dec_index(self: Self, index: usize) usize {
        return if (index > 0) index - 1 else self.size - 1;
    }

    /// Offsets an index by a signed amount, wrapping around.
    pub fn offset_index(self: Self, index: usize, offset: isize) usize {
        std.debug.assert(self.size > 0);
        const abs_offset = if (offset < 0) @as(usize, @intCast(-offset)) else @as(usize, @intCast(offset));
        std.debug.assert(abs_offset <= self.size);
        const size_i: isize = @intCast(self.size);
        var value: isize = @as(isize, @intCast(index)) + offset;
        value = @mod(value, size_i);
        return @intCast(value);
    }

    /// Moves the write index forward by `offset`.
    pub fn update_write_index(self: *Self, offset: isize) void {
        self.write = self.offset_index(self.write, offset);
    }

    /// Increments the write index by one.
    pub fn inc_write_index(self: *Self) void {
        self.write = self.inc_index(self.write);
    }

    /// Decrements the write index by one.
    pub fn dec_write_index(self: *Self) void {
        self.write = self.dec_index(self.write);
    }

    /// Moves the read index forward by `offset`.
    pub fn update_read_index(self: *Self, offset: isize) void {
        self.read = self.offset_index(self.read, offset);
    }

    /// Increments the read index by one.
    pub fn inc_read_index(self: *Self) void {
        self.read = self.inc_index(self.read);
    }

    /// Decrements the read index by one.
    pub fn dec_read_index(self: *Self) void {
        self.read = self.dec_index(self.read);
    }
};

/// Circular buffer for fixed-point Q30 power spectra.
pub const SpectrumRingBufferFixed = struct {
    const Self = @This();

    buffer: [][]SpectrumQ30,
    write: usize,
    read: usize,
    size: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, size: usize, num_channels: usize) !Self {
        std.debug.assert(size > 0);
        std.debug.assert(num_channels > 0);

        const buffer = try allocator.alloc([]SpectrumQ30, size);
        errdefer allocator.free(buffer);

        var initialized: usize = 0;
        errdefer {
            for (buffer[0..initialized]) |slot| {
                allocator.free(slot);
            }
        }

        for (buffer) |*slot| {
            slot.* = try allocator.alloc(SpectrumQ30, num_channels);
            for (slot.*) |*ch| {
                ch.* = [_]i64{0} ** FFT_LENGTH_BY_2_PLUS_1;
            }
            initialized += 1;
        }

        return .{ .buffer = buffer, .write = 0, .read = 0, .size = size, .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        for (self.buffer) |slot| {
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
        std.debug.assert(self.size > 0);
        const size_i: isize = @intCast(self.size);
        var value: isize = @as(isize, @intCast(index)) + offset;
        value = @mod(value, size_i);
        return @intCast(value);
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

// ---------------------------------------------------------------------------
// Inline tests
// ---------------------------------------------------------------------------

test "spectrum_buffer init and deinit" {
    const allocator = std.testing.allocator;
    var sb = try SpectrumRingBuffer.init(allocator, 4, 2);
    defer sb.deinit();

    try std.testing.expectEqual(@as(usize, 4), sb.getSize());
    try std.testing.expectEqual(@as(usize, 0), sb.write);
    try std.testing.expectEqual(@as(usize, 0), sb.read);

    // All buffers should be zero-initialized.
    for (sb.buffer) |slot| {
        try std.testing.expectEqual(@as(usize, 2), slot.len);
        for (slot) |ch| {
            for (ch) |v| {
                try std.testing.expectEqual(@as(f32, 0.0), v);
            }
        }
    }
}

test "spectrum_buffer inc and dec index wrap" {
    const allocator = std.testing.allocator;
    var sb = try SpectrumRingBuffer.init(allocator, 4, 1);
    defer sb.deinit();

    try std.testing.expectEqual(@as(usize, 1), sb.inc_index(0));
    try std.testing.expectEqual(@as(usize, 2), sb.inc_index(1));
    try std.testing.expectEqual(@as(usize, 0), sb.inc_index(3)); // wrap

    try std.testing.expectEqual(@as(usize, 3), sb.dec_index(0)); // wrap
    try std.testing.expectEqual(@as(usize, 0), sb.dec_index(1));
    try std.testing.expectEqual(@as(usize, 2), sb.dec_index(3));
}

test "spectrum_buffer offset_index positive and negative" {
    const allocator = std.testing.allocator;
    var sb = try SpectrumRingBuffer.init(allocator, 4, 1);
    defer sb.deinit();

    try std.testing.expectEqual(@as(usize, 2), sb.offset_index(0, 2));
    try std.testing.expectEqual(@as(usize, 0), sb.offset_index(2, 2)); // wrap
    try std.testing.expectEqual(@as(usize, 3), sb.offset_index(1, -2)); // negative wrap
    try std.testing.expectEqual(@as(usize, 0), sb.offset_index(0, 0)); // no-op
}

test "spectrum_buffer write and read index mutations" {
    const allocator = std.testing.allocator;
    var sb = try SpectrumRingBuffer.init(allocator, 4, 1);
    defer sb.deinit();

    sb.inc_write_index();
    try std.testing.expectEqual(@as(usize, 1), sb.write);
    sb.inc_write_index();
    sb.inc_write_index();
    sb.inc_write_index();
    try std.testing.expectEqual(@as(usize, 0), sb.write); // wrapped

    sb.dec_write_index();
    try std.testing.expectEqual(@as(usize, 3), sb.write);

    sb.inc_read_index();
    try std.testing.expectEqual(@as(usize, 1), sb.read);
    sb.dec_read_index();
    try std.testing.expectEqual(@as(usize, 0), sb.read);

    sb.update_write_index(2);
    try std.testing.expectEqual(@as(usize, 1), sb.write); // 3+2 mod 4 = 1
    sb.update_read_index(-1);
    try std.testing.expectEqual(@as(usize, 3), sb.read); // 0-1 mod 4 = 3
}

test "spectrum_buffer data access" {
    const allocator = std.testing.allocator;
    var sb = try SpectrumRingBuffer.init(allocator, 4, 2);
    defer sb.deinit();

    // Write known values.
    sb.buffer[0][0][0] = 1.0;
    sb.buffer[0][1][0] = 2.0;
    sb.buffer[1][0][0] = 3.0;

    try std.testing.expectEqual(@as(f32, 1.0), sb.buffer[0][0][0]);
    try std.testing.expectEqual(@as(f32, 2.0), sb.buffer[0][1][0]);
    try std.testing.expectEqual(@as(f32, 3.0), sb.buffer[1][0][0]);
}

test "spectrum_buffer_fixed data access and wrap" {
    var sb = try SpectrumRingBufferFixed.init(std.testing.allocator, 4, 2);
    defer sb.deinit();

    sb.buffer[0][0][0] = 11;
    sb.buffer[0][1][0] = 22;
    sb.inc_write_index();
    sb.dec_write_index();

    try std.testing.expectEqual(@as(i64, 11), sb.buffer[0][0][0]);
    try std.testing.expectEqual(@as(i64, 22), sb.buffer[0][1][0]);
}
