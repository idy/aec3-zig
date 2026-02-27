const std = @import("std");
const audio_buffer = @import("../audio_buffer.zig");

pub const BlockDelayBuffer = struct {
    const Self = @This();

    frame_length: usize,
    delay: usize,
    bufs: []std.ArrayList(f32),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, num_bands: usize, frame_length: usize, delay_samples: usize) !Self {
        const bufs = try allocator.alloc(std.ArrayList(f32), num_bands);
        errdefer allocator.free(bufs);

        var initialized: usize = 0;
        errdefer {
            for (bufs[0..initialized]) |*buf| buf.deinit(allocator);
        }

        for (bufs) |*buf| {
            buf.* = try std.ArrayList(f32).initCapacity(allocator, delay_samples + frame_length);
            try buf.appendNTimes(allocator, 0.0, delay_samples);
            initialized += 1;
        }

        return .{ .frame_length = frame_length, .delay = delay_samples, .bufs = bufs, .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        for (self.bufs) |*buf| buf.deinit(self.allocator);
        self.allocator.free(self.bufs);
        self.* = undefined;
    }

    pub fn delay_signal(self: *Self, frame: *audio_buffer.AudioBuffer) !void {
        if (self.delay == 0) return;

        std.debug.assert(frame.num_frames_per_band() == self.frame_length);
        const num_bands = frame.num_bands();
        std.debug.assert(num_bands == self.bufs.len);

        for (0..num_bands) |band| {
            const data = frame.split_band_mut(0, band);
            for (0..self.frame_length) |i| {
                const input = data[i];
                const out = if (self.bufs[band].items.len > 0)
                    self.bufs[band].orderedRemove(0)
                else
                    0.0;
                try self.bufs[band].append(self.allocator, input);
                data[i] = out;
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
