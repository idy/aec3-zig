const std = @import("std");
const common = @import("aec3_common.zig");
const block_buffer = @import("block_buffer.zig");
const fft_buffer = @import("fft_buffer.zig");
const spectrum_buffer = @import("spectrum_buffer.zig");

const FFT_LENGTH_BY_2_PLUS_1 = common.FFT_LENGTH_BY_2_PLUS_1;

pub const RenderBuffer = struct {
    const Self = @This();

    block_buffer_ref: *const block_buffer.BlockBuffer,
    spectrum_buffer_ref: *const spectrum_buffer.SpectrumBuffer,
    fft_buffer_ref: *const fft_buffer.FftBuffer,
    render_activity: bool,

    pub fn init(
        bb: *const block_buffer.BlockBuffer,
        sb: *const spectrum_buffer.SpectrumBuffer,
        fb: *const fft_buffer.FftBuffer,
        render_activity: bool,
    ) Self {
        std.debug.assert(bb.getSize() == sb.getSize());
        std.debug.assert(sb.getSize() == fb.getSize());
        std.debug.assert(sb.read == fb.read);
        std.debug.assert(sb.write == fb.write);
        return .{
            .block_buffer_ref = bb,
            .spectrum_buffer_ref = sb,
            .fft_buffer_ref = fb,
            .render_activity = render_activity,
        };
    }

    pub fn block(self: Self, buffer_offset_blocks: isize) [][][]f32 {
        const pos = self.block_buffer_ref.offset_index(self.block_buffer_ref.read, buffer_offset_blocks);
        return self.block_buffer_ref.buffer[pos];
    }

    pub fn spectrum(self: Self, buffer_offset_ffts: isize) []spectrum_buffer.Spectrum {
        const pos = self.spectrum_buffer_ref.offset_index(self.spectrum_buffer_ref.read, buffer_offset_ffts);
        return self.spectrum_buffer_ref.buffer[pos];
    }

    pub fn position(self: Self) usize {
        std.debug.assert(self.spectrum_buffer_ref.read == self.fft_buffer_ref.read);
        std.debug.assert(self.spectrum_buffer_ref.write == self.fft_buffer_ref.write);
        return self.fft_buffer_ref.read;
    }

    pub fn spectral_sum(self: Self, num_spectra: usize, x2: *[FFT_LENGTH_BY_2_PLUS_1]f32) void {
        @memset(x2, 0.0);
        var pos_idx = self.spectrum_buffer_ref.read;
        for (0..num_spectra) |_| {
            for (self.spectrum_buffer_ref.buffer[pos_idx]) |channel_spectrum| {
                for (channel_spectrum, 0..) |v, bin| x2[bin] += v;
            }
            pos_idx = self.spectrum_buffer_ref.inc_index(pos_idx);
        }
    }

    pub fn set_render_activity(self: *Self, activity: bool) void {
        self.render_activity = activity;
    }

    pub fn get_render_activity(self: Self) bool {
        return self.render_activity;
    }

    pub fn headroom(self: Self) usize {
        const write = self.fft_buffer_ref.write;
        const read = self.fft_buffer_ref.read;
        if (write < read) return read - write;
        return self.fft_buffer_ref.getSize() - write + read;
    }
};

test "render_buffer spectral_sum accumulates channels" {
    var bb = try block_buffer.BlockBuffer.init(std.testing.allocator, 4, 1, 2, common.BLOCK_SIZE);
    defer bb.deinit();
    var sb = try spectrum_buffer.SpectrumBuffer.init(std.testing.allocator, 4, 2);
    defer sb.deinit();
    var fb = try fft_buffer.FftBuffer.init(std.testing.allocator, 4, 2);
    defer fb.deinit();

    sb.buffer[0][0][1] = 1.0;
    sb.buffer[0][1][1] = 2.0;
    var rb = RenderBuffer.init(&bb, &sb, &fb, false);
    var sum: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;
    rb.spectral_sum(1, &sum);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), sum[1], 1e-6);
    rb.set_render_activity(true);
    try std.testing.expect(rb.get_render_activity());
}

test "render_buffer block spectrum position and headroom" {
    var bb = try block_buffer.BlockBuffer.init(std.testing.allocator, 4, 1, 1, common.BLOCK_SIZE);
    defer bb.deinit();
    var sb = try spectrum_buffer.SpectrumBuffer.init(std.testing.allocator, 4, 1);
    defer sb.deinit();
    var fb = try fft_buffer.FftBuffer.init(std.testing.allocator, 4, 1);
    defer fb.deinit();

    bb.buffer[2][0][0][0] = 9.0;
    bb.read = 2;
    sb.read = 1;
    sb.write = 3;
    fb.read = 1;
    fb.write = 3;
    sb.buffer[1][0][0] = 7.0;

    const rb = RenderBuffer.init(&bb, &sb, &fb, true);
    try std.testing.expectEqual(@as(f32, 9.0), rb.block(0)[0][0][0]);
    try std.testing.expectEqual(@as(f32, 7.0), rb.spectrum(0)[0][0]);
    try std.testing.expectEqual(@as(usize, 1), rb.position());
    try std.testing.expectEqual(@as(usize, 2), rb.headroom());
    try std.testing.expect(rb.get_render_activity());
}

test "render_buffer spectral_sum with zero spectra yields zeros" {
    var bb = try block_buffer.BlockBuffer.init(std.testing.allocator, 2, 1, 1, common.BLOCK_SIZE);
    defer bb.deinit();
    var sb = try spectrum_buffer.SpectrumBuffer.init(std.testing.allocator, 2, 1);
    defer sb.deinit();
    var fb = try fft_buffer.FftBuffer.init(std.testing.allocator, 2, 1);
    defer fb.deinit();

    const rb = RenderBuffer.init(&bb, &sb, &fb, false);
    var sum: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;
    rb.spectral_sum(0, &sum);
    for (sum) |v| try std.testing.expectEqual(@as(f32, 0.0), v);
}
