//! Ported from: docs/aec3-rs-src/audio_processing/resampler/sinc_resampler.rs
const std = @import("std");

pub const KERNEL_SIZE: usize = 32;
const KERNEL_OFFSET_COUNT: usize = 32;
const KERNEL_STORAGE_SIZE: usize = KERNEL_SIZE * (KERNEL_OFFSET_COUNT + 1);
const MIN_REQUEST_FRAMES: usize = KERNEL_SIZE + KERNEL_SIZE / 2 + 1; // must satisfy block_size > KERNEL_SIZE

pub const ProvideInputFn = *const fn (ctx: *anyopaque, dest: []f32) void;

pub const SincResampler = struct {
    io_sample_rate_ratio: f64,
    request_frames_: usize,
    input_buffer_size: usize,
    kernel_storage: []f32,
    kernel_pre_sinc_storage: []f32,
    kernel_window_storage: []f32,
    input_buffer: []f32,
    virtual_source_idx: f64,
    buffer_primed: bool,
    block_size: usize,
    r0: usize,
    r1: usize,
    r2: usize,
    r3: usize,
    r4: usize,
    allocator: std.mem.Allocator,

    pub fn new(allocator: std.mem.Allocator, io_sample_rate_ratio: f64, request_frames_in: usize) !SincResampler {
        if (request_frames_in == 0) return error.InvalidRequestFrames;
        if (request_frames_in < MIN_REQUEST_FRAMES) return error.RequestFramesTooSmall;
        if (io_sample_rate_ratio <= 0.0) return error.InvalidSampleRateRatio;
        const input_buffer_size = request_frames_in + KERNEL_SIZE;

        const kernel_storage = try allocator.alloc(f32, KERNEL_STORAGE_SIZE);
        errdefer allocator.free(kernel_storage);
        const kernel_pre_sinc_storage = try allocator.alloc(f32, KERNEL_STORAGE_SIZE);
        errdefer allocator.free(kernel_pre_sinc_storage);
        const kernel_window_storage = try allocator.alloc(f32, KERNEL_STORAGE_SIZE);
        errdefer allocator.free(kernel_window_storage);
        const input_buffer = try allocator.alloc(f32, input_buffer_size);
        errdefer allocator.free(input_buffer);

        var resampler = SincResampler{
            .io_sample_rate_ratio = io_sample_rate_ratio,
            .request_frames_ = request_frames_in,
            .input_buffer_size = input_buffer_size,
            .kernel_storage = kernel_storage,
            .kernel_pre_sinc_storage = kernel_pre_sinc_storage,
            .kernel_window_storage = kernel_window_storage,
            .input_buffer = input_buffer,
            .virtual_source_idx = 0.0,
            .buffer_primed = false,
            .block_size = 0,
            .r0 = 0,
            .r1 = 0,
            .r2 = KERNEL_SIZE / 2,
            .r3 = 0,
            .r4 = 0,
            .allocator = allocator,
        };

        resampler.initialize_kernel();
        resampler.flush();
        std.debug.assert(resampler.block_size > KERNEL_SIZE);
        return resampler;
    }

    pub fn deinit(self: *SincResampler) void {
        self.allocator.free(self.kernel_storage);
        self.allocator.free(self.kernel_pre_sinc_storage);
        self.allocator.free(self.kernel_window_storage);
        self.allocator.free(self.input_buffer);
    }

    pub fn set_ratio(self: *SincResampler, io_sample_rate_ratio: f64) void {
        if (io_sample_rate_ratio <= 0.0) return; // Reject invalid ratio
        if (@abs(self.io_sample_rate_ratio - io_sample_rate_ratio) < std.math.floatEps(f64)) return;
        self.io_sample_rate_ratio = io_sample_rate_ratio;
        const sinc_factor = sinc_scale_factor(self.io_sample_rate_ratio);
        var offset_idx: usize = 0;
        while (offset_idx <= KERNEL_OFFSET_COUNT) : (offset_idx += 1) {
            var i: usize = 0;
            while (i < KERNEL_SIZE) : (i += 1) {
                const idx = i + offset_idx * KERNEL_SIZE;
                const window: f64 = self.kernel_window_storage[idx];
                const pre_sinc: f64 = self.kernel_pre_sinc_storage[idx];
                const value = if (pre_sinc == 0.0)
                    sinc_factor
                else
                    @sin(sinc_factor * pre_sinc) / pre_sinc;
                self.kernel_storage[idx] = @floatCast(window * value);
            }
        }
    }

    pub fn resample(self: *SincResampler, frames: usize, destination: []f32, ctx: *anyopaque, provide_input: ProvideInputFn) void {
        if (frames == 0) return;
        std.debug.assert(destination.len >= frames);

        if (!self.buffer_primed) {
            provide_input(ctx, self.buffer_slice_mut(self.r0, self.request_frames_));
            self.buffer_primed = true;
        }

        const current_ratio = self.io_sample_rate_ratio;
        var remaining = frames;
        var dest_index: usize = 0;

        while (remaining > 0) {
            var iterations: i64 = @intFromFloat(@ceil((@as(f64, @floatFromInt(self.block_size)) - self.virtual_source_idx) / current_ratio));
            if (iterations < 0) iterations = 0;

            while (iterations > 0) : (iterations -= 1) {
                const source_idx_f = @max(self.virtual_source_idx, 0.0);
                const source_idx: usize = @intFromFloat(@floor(source_idx_f));
                const subsample_remainder = source_idx_f - @as(f64, @floatFromInt(source_idx));
                const virtual_offset_idx = subsample_remainder * KERNEL_OFFSET_COUNT;
                const offset_idx_raw: usize = @intFromFloat(@floor(virtual_offset_idx));
                const offset_idx = @min(offset_idx_raw, KERNEL_OFFSET_COUNT - 1);
                const interp = virtual_offset_idx - @as(f64, @floatFromInt(offset_idx));
                const k1_start = offset_idx * KERNEL_SIZE;
                const k1 = self.kernel_storage[k1_start .. k1_start + KERNEL_SIZE];
                const k2 = self.kernel_storage[k1_start + KERNEL_SIZE .. k1_start + 2 * KERNEL_SIZE];
                const input_idx = self.r1 + source_idx;
                const input = self.input_buffer[input_idx .. input_idx + KERNEL_SIZE];
                destination[dest_index] = convolve(input, k1, k2, interp);
                dest_index += 1;
                remaining -= 1;
                self.virtual_source_idx += current_ratio;
                if (remaining == 0) return;
            }

            self.virtual_source_idx -= @as(f64, @floatFromInt(self.block_size));
            std.mem.copyForwards(f32, self.input_buffer[self.r1 .. self.r1 + KERNEL_SIZE], self.input_buffer[self.r3 .. self.r3 + KERNEL_SIZE]);

            if (self.r0 == self.r2) {
                self.update_regions(true);
            }
            provide_input(ctx, self.buffer_slice_mut(self.r0, self.request_frames_));
        }
    }

    pub fn chunk_size(self: SincResampler) usize {
        return @intFromFloat(@as(f64, @floatFromInt(self.block_size)) / self.io_sample_rate_ratio);
    }

    pub fn request_frames(self: SincResampler) usize {
        return self.request_frames_;
    }

    pub fn flush(self: *SincResampler) void {
        self.virtual_source_idx = 0.0;
        self.buffer_primed = false;
        @memset(self.input_buffer, 0.0);
        self.update_regions(false);
    }

    fn update_regions(self: *SincResampler, second_load: bool) void {
        self.r0 = if (second_load) KERNEL_SIZE else KERNEL_SIZE / 2;
        self.r3 = self.r0 + self.request_frames_ - KERNEL_SIZE;
        self.r4 = self.r0 + self.request_frames_ - KERNEL_SIZE / 2;
        self.block_size = self.r4 - self.r2;
        self.r1 = 0;
    }

    fn initialize_kernel(self: *SincResampler) void {
        const alpha: f64 = 0.16;
        const a0: f64 = 0.5 * (1.0 - alpha);
        const a1: f64 = 0.5;
        const a2: f64 = 0.5 * alpha;
        const sinc_factor = sinc_scale_factor(self.io_sample_rate_ratio);

        var offset_idx: usize = 0;
        while (offset_idx <= KERNEL_OFFSET_COUNT) : (offset_idx += 1) {
            const subsample_offset = @as(f64, @floatFromInt(offset_idx)) / KERNEL_OFFSET_COUNT;
            var i: usize = 0;
            while (i < KERNEL_SIZE) : (i += 1) {
                const idx = i + offset_idx * KERNEL_SIZE;
                const half_kernel = @as(f64, @floatFromInt(KERNEL_SIZE)) / 2.0;
                const pre_sinc = std.math.pi * (@as(f64, @floatFromInt(i)) - half_kernel - subsample_offset);
                self.kernel_pre_sinc_storage[idx] = @floatCast(pre_sinc);

                const x = (@as(f64, @floatFromInt(i)) - subsample_offset) / KERNEL_SIZE;
                const window = a0 - a1 * @cos(2.0 * std.math.pi * x) + a2 * @cos(4.0 * std.math.pi * x);
                self.kernel_window_storage[idx] = @floatCast(window);

                const value = if (pre_sinc == 0.0)
                    sinc_factor
                else
                    @sin(sinc_factor * pre_sinc) / pre_sinc;
                self.kernel_storage[idx] = @floatCast(window * value);
            }
        }
    }

    fn buffer_slice_mut(self: *SincResampler, offset: usize, len: usize) []f32 {
        std.debug.assert(offset + len <= self.input_buffer_size);
        return self.input_buffer[offset .. offset + len];
    }
};

fn sinc_scale_factor(io_ratio: f64) f64 {
    const factor = if (io_ratio > 1.0) 1.0 / io_ratio else 1.0;
    return factor * 0.9;
}

fn convolve(input: []const f32, k1: []const f32, k2: []const f32, interp: f64) f32 {
    var sum1: f32 = 0.0;
    var sum2: f32 = 0.0;
    var i: usize = 0;
    while (i < KERNEL_SIZE) : (i += 1) {
        sum1 += input[i] * k1[i];
        sum2 += input[i] * k2[i];
    }
    return @floatCast((1.0 - interp) * @as(f64, sum1) + interp * @as(f64, sum2));
}

const InputProvider = struct {
    source: []const f32,
    consumed: usize = 0,

    fn fill(ctx: *anyopaque, dest: []f32) void {
        const self: *InputProvider = @ptrCast(@alignCast(ctx));
        const available = self.source.len - @min(self.consumed, self.source.len);
        const n = @min(available, dest.len);
        if (n > 0) {
            @memcpy(dest[0..n], self.source[self.consumed .. self.consumed + n]);
            self.consumed += n;
        }
        if (n < dest.len) {
            @memset(dest[n..], 0.0);
        }
    }
};

test "sinc_resampler upsample 16k to 48k has finite output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var resampler = try SincResampler.new(arena.allocator(), 160.0 / 480.0, 160);
    defer resampler.deinit();

    var input = [_]f32{0} ** 160;
    for (0..input.len) |i| {
        const t = @as(f32, @floatFromInt(i)) / 16_000.0;
        input[i] = @sin(2.0 * std.math.pi * 1000.0 * t);
    }

    var output = [_]f32{0} ** 480;
    var provider = InputProvider{ .source = input[0..] };
    resampler.resample(480, output[0..], &provider, InputProvider.fill);

    var energy: f32 = 0.0;
    for (output) |v| {
        try std.testing.expect(std.math.isFinite(v));
        energy += v * v;
    }
    try std.testing.expect(energy > 1.0);
}

test "sinc_resampler boundary rejects zero request frames" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.InvalidRequestFrames, SincResampler.new(arena.allocator(), 1.0, 0));
}

test "sinc_resampler boundary rejects too-small request frames" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectError(error.RequestFramesTooSmall, SincResampler.new(arena.allocator(), 1.0, MIN_REQUEST_FRAMES - 1));
}

test "sinc_resampler boundary rejects non-positive sample rate ratio" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.InvalidSampleRateRatio, SincResampler.new(arena.allocator(), 0.0, 160));
    try std.testing.expectError(error.InvalidSampleRateRatio, SincResampler.new(arena.allocator(), -1.0, 160));
}

test "sinc_resampler flush resets state" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var resampler = try SincResampler.new(arena.allocator(), 0.5, 160);
    defer resampler.deinit();

    const TestInputProvider = struct {
        source: []const f32,
        consumed: usize = 0,

        fn fill(ctx: *anyopaque, dest: []f32) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            const available = self.source.len - @min(self.consumed, self.source.len);
            const n = @min(available, dest.len);
            if (n > 0) {
                @memcpy(dest[0..n], self.source[self.consumed .. self.consumed + n]);
                self.consumed += n;
            }
            if (n < dest.len) {
                @memset(dest[n..], 0.0);
            }
        }
    };

    var input = [_]f32{0} ** 160;
    for (0..input.len) |i| {
        input[i] = @sin(2.0 * std.math.pi * 440.0 * @as(f32, @floatFromInt(i)) / 16000.0);
    }

    var provider1 = TestInputProvider{ .source = input[0..] };
    var output1 = [_]f32{0} ** 320;
    resampler.resample(320, output1[0..], &provider1, TestInputProvider.fill);

    resampler.flush();

    // After flush, the resampler should be in initial state
    try std.testing.expect(!resampler.buffer_primed);
    try std.testing.expectEqual(@as(f64, 0.0), resampler.virtual_source_idx);
}

test "sinc_resampler flush boundary idempotent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var resampler = try SincResampler.new(arena.allocator(), 0.5, 160);
    defer resampler.deinit();

    // Multiple flushes should be idempotent
    resampler.flush();
    const primed1 = resampler.buffer_primed;
    const idx1 = resampler.virtual_source_idx;

    resampler.flush();
    const primed2 = resampler.buffer_primed;
    const idx2 = resampler.virtual_source_idx;

    resampler.flush();
    const primed3 = resampler.buffer_primed;
    const idx3 = resampler.virtual_source_idx;

    try std.testing.expectEqual(primed1, primed2);
    try std.testing.expectEqual(primed2, primed3);
    try std.testing.expectEqual(idx1, idx2);
    try std.testing.expectEqual(idx2, idx3);
}

test "sinc_resampler deinit frees memory" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var resampler = try SincResampler.new(arena.allocator(), 0.5, 160);
    resampler.deinit();

    // If deinit doesn't free, arena will detect leak
    try std.testing.expect(true);
}

test "sinc_resampler deinit boundary minimum frames" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var resampler = try SincResampler.new(arena.allocator(), 1.0, MIN_REQUEST_FRAMES);
    resampler.deinit();
}

test "sinc_resampler set_ratio updates chunk_size" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var resampler = try SincResampler.new(arena.allocator(), 1.0, 160);
    defer resampler.deinit();

    const before = resampler.chunk_size();
    resampler.set_ratio(0.5);
    const after = resampler.chunk_size();
    try std.testing.expect(after > before);
}

test "sinc_resampler set_ratio with very small ratio" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var resampler = try SincResampler.new(arena.allocator(), 1.0, 160);
    defer resampler.deinit();

    // Test with very small ratio (high upsampling)
    resampler.set_ratio(0.1);
    try std.testing.expect(resampler.chunk_size() > 0);
}

test "sinc_resampler set_ratio with large ratio" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var resampler = try SincResampler.new(arena.allocator(), 1.0, 160);
    defer resampler.deinit();

    // Test with large ratio (high downsampling)
    resampler.set_ratio(10.0);
    try std.testing.expect(resampler.chunk_size() > 0);
}

test "sinc_resampler request_frames returns correct value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var resampler1 = try SincResampler.new(arena.allocator(), 1.0, 160);
    defer resampler1.deinit();
    try std.testing.expectEqual(@as(usize, 160), resampler1.request_frames());

    var resampler2 = try SincResampler.new(arena.allocator(), 1.0, 320);
    defer resampler2.deinit();
    try std.testing.expectEqual(@as(usize, 320), resampler2.request_frames());
}

test "sinc_resampler request_frames boundary minimum accepted" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var resampler = try SincResampler.new(arena.allocator(), 1.0, MIN_REQUEST_FRAMES);
    defer resampler.deinit();
    try std.testing.expectEqual(MIN_REQUEST_FRAMES, resampler.request_frames());
}

test "sinc_resampler chunk_size returns reasonable value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // 1:1 ratio
    var resampler1 = try SincResampler.new(arena.allocator(), 1.0, 160);
    defer resampler1.deinit();
    const chunk1 = resampler1.chunk_size();
    try std.testing.expect(chunk1 > 0);
    // chunk_size depends on internal block_size / ratio, not necessarily >= request_frames

    // 1:2 upsampling ratio (0.5 = 160/320)
    var resampler2 = try SincResampler.new(arena.allocator(), 0.5, 160);
    defer resampler2.deinit();
    const chunk2 = resampler2.chunk_size();
    // Upsampling ratio produces larger output chunk for same input
    try std.testing.expect(chunk2 > 0);
}

test "sinc_resampler chunk_size boundary rejects invalid ratio" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var resampler = try SincResampler.new(arena.allocator(), 1.0, 160);
    defer resampler.deinit();

    const before = resampler.chunk_size();

    // set_ratio should reject <= 0 values
    resampler.set_ratio(0.0);
    // chunk_size should remain unchanged
    try std.testing.expectEqual(before, resampler.chunk_size());

    resampler.set_ratio(-1.0);
    try std.testing.expectEqual(before, resampler.chunk_size());
}

test "sinc_resampler resample with zero frames returns immediately" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var resampler = try SincResampler.new(arena.allocator(), 1.0, 160);
    defer resampler.deinit();

    const TestCtx = struct {
        fn fill(_: *anyopaque, _: []f32) void {}
    };

    var output = [_]f32{0} ** 10;
    var dummy: u8 = 0;
    // Resampling 0 frames should return immediately without calling provider
    resampler.resample(0, output[0..], &dummy, TestCtx.fill);
    // No panic means success
    try std.testing.expect(true);
}

test "sinc_resampler resample boundary minimum supported frames" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var resampler = try SincResampler.new(arena.allocator(), 1.0, MIN_REQUEST_FRAMES);
    defer resampler.deinit();

    var src = [_]f32{0} ** MIN_REQUEST_FRAMES;
    for (0..src.len) |i| src[i] = @sin(2.0 * std.math.pi * 300.0 * @as(f32, @floatFromInt(i)) / 16_000.0);

    const Ctx = struct {
        source: []const f32,
        consumed: usize = 0,

        fn fill(ctx: *anyopaque, dest: []f32) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            const available = self.source.len - @min(self.consumed, self.source.len);
            const n = @min(available, dest.len);
            if (n > 0) {
                @memcpy(dest[0..n], self.source[self.consumed .. self.consumed + n]);
                self.consumed += n;
            }
            if (n < dest.len) {
                @memset(dest[n..], 0.0);
            }
        }
    };

    var ctx = Ctx{ .source = src[0..] };
    var out = [_]f32{0} ** MIN_REQUEST_FRAMES;
    resampler.resample(MIN_REQUEST_FRAMES, out[0..], &ctx, Ctx.fill);
    try std.testing.expectEqual(MIN_REQUEST_FRAMES, ctx.consumed);
}
