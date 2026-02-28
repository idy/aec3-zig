//! Ported from: docs/aec3-rs-src/audio_processing/resampler/push_sinc_resampler.rs
const std = @import("std");
const audio_util = @import("../api/audio_util.zig");
const sinc = @import("sinc_resampler.zig");

const SincResampler = sinc.SincResampler;
pub const KERNEL_SIZE = sinc.KERNEL_SIZE;

pub const PushSincResampler = struct {
    resampler: SincResampler,
    destination_frames: usize,
    needs_prime: bool,
    scratch: []f32,
    allocator: std.mem.Allocator,

    pub fn new(allocator: std.mem.Allocator, source_frames: usize, destination_frames: usize) !PushSincResampler {
        if (source_frames == 0) return error.InvalidSourceFrames;
        if (destination_frames == 0) return error.InvalidDestinationFrames;
        const io_ratio = @as(f64, @floatFromInt(source_frames)) / @as(f64, @floatFromInt(destination_frames));
        var resampler = try SincResampler.new(allocator, io_ratio, source_frames);
        errdefer resampler.deinit();

        const required = @max(destination_frames, resampler.chunk_size());
        const scratch = try allocator.alloc(f32, required);
        @memset(scratch, 0.0);

        return .{
            .resampler = resampler,
            .destination_frames = destination_frames,
            .needs_prime = true,
            .scratch = scratch,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PushSincResampler) void {
        self.resampler.deinit();
        if (self.scratch.len > 0) self.allocator.free(self.scratch);
    }

    pub fn resample_f32(self: *PushSincResampler, source: []const f32, destination: []f32) usize {
        std.debug.assert(source.len == self.resampler.request_frames());
        std.debug.assert(destination.len >= self.destination_frames);
        self.ensure_prime();

        var ctx = F32SourceCtx{ .source = source };
        self.resampler.resample(self.destination_frames, destination[0..self.destination_frames], &ctx, F32SourceCtx.fill);
        std.debug.assert(ctx.consumed == source.len);
        return self.destination_frames;
    }

    pub fn resample_i16(self: *PushSincResampler, source: []const i16, destination: []i16) !usize {
        std.debug.assert(source.len == self.resampler.request_frames());
        std.debug.assert(destination.len >= self.destination_frames);
        const required = @max(self.destination_frames, self.resampler.chunk_size());
        try self.ensure_scratch(required);
        self.ensure_prime();

        var ctx = I16SourceCtx{ .source = source };
        self.resampler.resample(self.destination_frames, self.scratch[0..self.destination_frames], &ctx, I16SourceCtx.fill);
        std.debug.assert(ctx.consumed == source.len);
        audio_util.float_s16_slice_to_s16(self.scratch[0..self.destination_frames], destination[0..self.destination_frames]);
        return self.destination_frames;
    }

    pub fn algorithmic_delay_seconds(source_rate_hz: i32) f32 {
        if (source_rate_hz <= 0) return 0.0;
        return (1.0 / @as(f32, @floatFromInt(source_rate_hz))) * (@as(f32, @floatFromInt(KERNEL_SIZE)) / 2.0);
    }

    fn ensure_prime(self: *PushSincResampler) void {
        if (!self.needs_prime) return;
        const chunk = self.resampler.chunk_size();
        if (chunk > 0) {
            std.debug.assert(self.scratch.len >= chunk);

            var ctx = ZeroCtx{};
            self.resampler.resample(chunk, self.scratch[0..chunk], &ctx, ZeroCtx.fill);
        }
        self.needs_prime = false;
    }

    fn ensure_scratch(self: *PushSincResampler, required: usize) !void {
        if (self.scratch.len >= required) return;
        const new_scratch = try self.allocator.alloc(f32, required);
        @memset(new_scratch, 0.0);
        if (self.scratch.len > 0) self.allocator.free(self.scratch);
        self.scratch = new_scratch;
    }
};

const F32SourceCtx = struct {
    source: []const f32,
    consumed: usize = 0,

    fn fill(ctx: *anyopaque, dest: []f32) void {
        const self: *F32SourceCtx = @ptrCast(@alignCast(ctx));
        @memcpy(dest, self.source[self.consumed .. self.consumed + dest.len]);
        self.consumed += dest.len;
    }
};

const I16SourceCtx = struct {
    source: []const i16,
    consumed: usize = 0,

    fn fill(ctx: *anyopaque, dest: []f32) void {
        const self: *I16SourceCtx = @ptrCast(@alignCast(ctx));
        audio_util.s16_slice_to_float_s16(self.source[self.consumed .. self.consumed + dest.len], dest);
        self.consumed += dest.len;
    }
};

const ZeroCtx = struct {
    fn fill(_: *anyopaque, dest: []f32) void {
        @memset(dest, 0.0);
    }
};

test "push_sinc_resampler f32 resample returns destination length" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var rs = try PushSincResampler.new(arena.allocator(), 160, 480);
    defer rs.deinit();

    var src = [_]f32{0} ** 160;
    for (0..src.len) |i| src[i] = @sin(2.0 * std.math.pi * 440.0 * (@as(f32, @floatFromInt(i)) / 16_000.0));
    var dst = [_]f32{0} ** 480;
    const n = rs.resample_f32(src[0..], dst[0..]);
    try std.testing.expectEqual(@as(usize, 480), n);
}

test "push_sinc_resampler i16 path works" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var rs = try PushSincResampler.new(arena.allocator(), 160, 320);
    defer rs.deinit();

    var src = [_]i16{0} ** 160;
    for (0..src.len) |i| {
        const v: i32 = @as(i32, @intCast(i % 40)) * 200 - 4000;
        src[i] = @intCast(v);
    }
    var dst = [_]i16{0} ** 320;
    const n = try rs.resample_i16(src[0..], dst[0..]);
    try std.testing.expectEqual(@as(usize, 320), n);
}

test "push_sinc_resampler algorithmic_delay_seconds returns finite positive value" {
    const delay = PushSincResampler.algorithmic_delay_seconds(16000);
    try std.testing.expect(delay > 0.0);
    try std.testing.expect(std.math.isFinite(delay));
}

test "push_sinc_resampler algorithmic_delay_seconds boundary invalid rates" {
    // Zero or negative sample rates should return 0 (defensive programming)
    const delay_zero = PushSincResampler.algorithmic_delay_seconds(0);
    try std.testing.expectEqual(@as(f32, 0.0), delay_zero);

    const delay_neg = PushSincResampler.algorithmic_delay_seconds(-16000);
    try std.testing.expectEqual(@as(f32, 0.0), delay_neg);

    // Very high sample rate should still return finite value
    const delay_high = PushSincResampler.algorithmic_delay_seconds(192000);
    try std.testing.expect(delay_high > 0.0);
    try std.testing.expect(std.math.isFinite(delay_high));
}

test "push_sinc_resampler boundary rejects zero sizes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectError(error.InvalidSourceFrames, PushSincResampler.new(arena.allocator(), 0, 160));
    try std.testing.expectError(error.InvalidDestinationFrames, PushSincResampler.new(arena.allocator(), 160, 0));
}

test "push_sinc_resampler boundary handles various sample rate ratios" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // Upsampling ratio 1:2 (e.g., 16k -> 32k)
    var rs1 = try PushSincResampler.new(arena.allocator(), 160, 320);
    defer rs1.deinit();
    try std.testing.expectEqual(@as(usize, 320), rs1.destination_frames);

    // Downsampling ratio 2:1 (e.g., 32k -> 16k)
    var rs2 = try PushSincResampler.new(arena.allocator(), 320, 160);
    defer rs2.deinit();
    try std.testing.expectEqual(@as(usize, 160), rs2.destination_frames);

    // 1:1 ratio
    var rs3 = try PushSincResampler.new(arena.allocator(), 160, 160);
    defer rs3.deinit();
    try std.testing.expectEqual(@as(usize, 160), rs3.destination_frames);
}

test "push_sinc_resampler resample_f32 boundary minimum supported frames" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const min_frames = KERNEL_SIZE + KERNEL_SIZE / 2 + 1;
    var rs = try PushSincResampler.new(arena.allocator(), min_frames, min_frames);
    defer rs.deinit();

    var src = [_]f32{0} ** min_frames;
    var dst = [_]f32{0} ** min_frames;
    for (0..src.len) |i| src[i] = @sin(2.0 * std.math.pi * 1000.0 * @as(f32, @floatFromInt(i)) / 16_000.0);

    const n = rs.resample_f32(src[0..], dst[0..]);
    try std.testing.expectEqual(min_frames, n);
}

test "push_sinc_resampler resample_i16 boundary minimum supported frames" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const min_frames = KERNEL_SIZE + KERNEL_SIZE / 2 + 1;
    var rs = try PushSincResampler.new(arena.allocator(), min_frames, min_frames);
    defer rs.deinit();

    var src = [_]i16{0} ** min_frames;
    var dst = [_]i16{0} ** min_frames;
    for (0..src.len) |i| src[i] = @intCast((@as(i32, @intCast(i)) - 24) * 80);

    const n = try rs.resample_i16(src[0..], dst[0..]);
    try std.testing.expectEqual(min_frames, n);
}

test "push_sinc_resampler deinit frees memory" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var rs = try PushSincResampler.new(arena.allocator(), 160, 320);
    rs.deinit();
}

test "push_sinc_resampler deinit boundary minimum frames" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const min_frames = KERNEL_SIZE + KERNEL_SIZE / 2 + 1;
    var rs = try PushSincResampler.new(arena.allocator(), min_frames, min_frames);
    rs.deinit();
}
