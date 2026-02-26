//! Ported from: docs/aec3-rs-src/audio_processing/aec3/fft_data.rs
const std = @import("std");
const common = @import("aec3_common.zig");

const FFT_LENGTH = common.FFT_LENGTH;
const FFT_LENGTH_BY_2 = common.FFT_LENGTH_BY_2;
const FFT_LENGTH_BY_2_PLUS_1 = common.FFT_LENGTH_BY_2_PLUS_1;

/// FFT data structure holding real and imaginary components.
pub const FftData = struct {
    const Self = @This();

    re: [FFT_LENGTH_BY_2_PLUS_1]f32 = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1,
    im: [FFT_LENGTH_BY_2_PLUS_1]f32 = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1,

    /// Creates a new FftData with all zeros.
    pub fn new() FftData {
        return .{
            .re = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1,
            .im = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1,
        };
    }

    /// Copies data from source to self.
    pub fn assign(self: *FftData, src: *const FftData) void {
        self.re = src.re;
        self.im = src.im;
        self.im[0] = 0.0;
        self.im[FFT_LENGTH_BY_2] = 0.0;
    }

    /// Clears all data to zero.
    pub fn clear(self: *Self) void {
        self.re = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
        self.im = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    }

    /// Computes the power spectrum: re[k]^2 + im[k]^2 for each bin.
    pub fn spectrum(self: FftData, optimization: common.Aec3Optimization, power_spectrum: []f32) void {
        _ = optimization;
        std.debug.assert(power_spectrum.len == FFT_LENGTH_BY_2_PLUS_1);
        var k: usize = 0;
        while (k < FFT_LENGTH_BY_2_PLUS_1) : (k += 1) {
            power_spectrum[k] = self.re[k] * self.re[k] + self.im[k] * self.im[k];
        }
    }

    /// Copies data from a packed array (interleaved format).
    pub fn copyFromPackedArray(self: *Self, packed_data: *const [FFT_LENGTH]f32) void {
        self.re[0] = packed_data[0];
        self.im[0] = 0.0;
        self.re[FFT_LENGTH_BY_2] = packed_data[1];
        self.im[FFT_LENGTH_BY_2] = 0.0;
        var idx: usize = 2;
        for (1..FFT_LENGTH_BY_2) |k| {
            self.re[k] = packed_data[idx];
            self.im[k] = packed_data[idx + 1];
            idx += 2;
        }
    }

    /// Copies data from a packed array (snake_case alias).
    pub fn copy_from_packed_array(self: *Self, packed_array: *const [FFT_LENGTH]f32) void {
        self.copyFromPackedArray(packed_array);
    }

    /// Copies data to a packed array (interleaved format).
    pub fn copyToPackedArray(self: *const Self, packed_data: *[FFT_LENGTH]f32) void {
        packed_data[0] = self.re[0];
        packed_data[1] = self.re[FFT_LENGTH_BY_2];
        var idx: usize = 2;
        for (1..FFT_LENGTH_BY_2) |k| {
            packed_data[idx] = self.re[k];
            packed_data[idx + 1] = self.im[k];
            idx += 2;
        }
    }

    /// Copies data to a packed array (snake_case alias).
    pub fn copy_to_packed_array(self: FftData, packed_array: *[FFT_LENGTH]f32) void {
        const self_ptr: *const Self = &self;
        self_ptr.copyToPackedArray(packed_array);
    }
};

test "test_new_is_zero" {
    const d = FftData.new();
    for (d.re) |v| try std.testing.expectEqual(@as(f32, 0.0), v);
    for (d.im) |v| try std.testing.expectEqual(@as(f32, 0.0), v);
}

test "test_assign_copies" {
    var src = FftData.new();
    src.re[1] = 3.0;
    src.im[1] = 4.0;
    var dst = FftData.new();
    dst.assign(&src);
    try std.testing.expectEqual(src.re[1], dst.re[1]);
    try std.testing.expectEqual(src.im[1], dst.im[1]);
    try std.testing.expectEqual(@as(f32, 0.0), dst.im[0]);
    try std.testing.expectEqual(@as(f32, 0.0), dst.im[FFT_LENGTH_BY_2]);
}

test "test_clear" {
    var d = FftData.new();
    d.re[2] = 1.0;
    d.im[3] = 2.0;
    d.clear();
    for (d.re) |v| try std.testing.expectEqual(@as(f32, 0.0), v);
    for (d.im) |v| try std.testing.expectEqual(@as(f32, 0.0), v);
}

test "test_spectrum" {
    var d = FftData.new();
    d.re[0] = 3.0;
    d.im[0] = 4.0;
    var p: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;
    d.spectrum(.none, &p);
    try std.testing.expectEqual(@as(f32, 25.0), p[0]);
}

test "test_packed_array_roundtrip" {
    var packed_array: [FFT_LENGTH]f32 = undefined;
    for (&packed_array, 0..) |*v, i| v.* = @floatFromInt(i);

    var d = FftData.new();
    d.copy_from_packed_array(&packed_array);

    var out: [FFT_LENGTH]f32 = [_]f32{0} ** FFT_LENGTH;
    d.copy_to_packed_array(&out);

    try std.testing.expectEqual(packed_array[0], out[0]);
    try std.testing.expectEqual(packed_array[1], out[1]);
    var i: usize = 2;
    while (i < FFT_LENGTH) : (i += 1) {
        try std.testing.expectEqual(packed_array[i], out[i]);
    }
}
