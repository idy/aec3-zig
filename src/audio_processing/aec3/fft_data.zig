const common = @import("aec3_common.zig");
const FFT_LENGTH = common.FFT_LENGTH;
const FFT_LENGTH_BY_2 = common.FFT_LENGTH_BY_2;
const FFT_LENGTH_BY_2_PLUS_1 = common.FFT_LENGTH_BY_2_PLUS_1;

pub const FftData = struct {
    const Self = @This();

    re: [FFT_LENGTH_BY_2_PLUS_1]f32 = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1,
    im: [FFT_LENGTH_BY_2_PLUS_1]f32 = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1,

    pub fn clear(self: *Self) void {
        self.re = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
        self.im = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    }

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
};
