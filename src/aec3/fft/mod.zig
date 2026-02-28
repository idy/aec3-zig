pub const aec3_fft_fixed = @import("aec3_fft_fixed.zig");
pub const aec3_fft_float = @import("aec3_fft_float.zig");
pub const fft_data = @import("fft_data.zig");

// Provide a legacy dispatch facade
pub const Window = aec3_fft_float.Window;

const NumericMode = @import("../../numeric_mode.zig").NumericMode;

pub const Aec3Fft = struct {
    const Self = @This();

    mode: NumericMode = .fixed_mcu_q15,
    fixed_impl: aec3_fft_fixed.Aec3FftFixed,
    float_impl: aec3_fft_float.Aec3FftFloat,

    pub fn init() Self {
        return .{
            .mode = .fixed_mcu_q15,
            .fixed_impl = aec3_fft_fixed.Aec3FftFixed.init(),
            .float_impl = aec3_fft_float.Aec3FftFloat.init(),
        };
    }

    pub fn initOracle() Self {
        return .{
            .mode = .float32,
            .fixed_impl = aec3_fft_fixed.Aec3FftFixed.init(),
            .float_impl = aec3_fft_float.Aec3FftFloat.init(),
        };
    }

    pub fn fft(self: *const Self, x: []const f32) fft_data.FftData {
        if (self.mode == .fixed_mcu_q15) {
            // Need a bridge function for backwards compat tests
            const common = @import("../common/aec3_common.zig");
            const Q15 = @import("../../numeric_profile.zig").profileFor(.fixed_mcu_q15).Sample;
            var input: [common.FFT_LENGTH]Q15 = undefined;
            for (0..common.FFT_LENGTH) |i| {
                input[i] = Q15.fromFloatRuntime(x[i]);
            }
            const spec = self.fixed_impl.fftFixedQ15(&input);
            var out = fft_data.FftData{};
            out.re[0] = spec.re_q15[0].toFloat();
            out.im[0] = 0.0;
            out.re[common.FFT_LENGTH_BY_2] = spec.re_q15[common.FFT_LENGTH_BY_2].toFloat();
            out.im[common.FFT_LENGTH_BY_2] = 0.0;
            for (1..common.FFT_LENGTH_BY_2) |k| {
                out.re[k] = spec.re_q15[k].toFloat();
                out.im[k] = spec.im_q15[k].toFloat();
            }
            return out;
        } else {
            return self.float_impl.fft(x);
        }
    }

    pub fn ifft(self: *const Self, X: fft_data.FftData) [128]f32 {
        const common = @import("../common/aec3_common.zig");
        var out: [common.FFT_LENGTH]f32 = undefined;
        if (self.mode == .fixed_mcu_q15) {
            const Q15 = @import("../../numeric_profile.zig").profileFor(.fixed_mcu_q15).Sample;
            var spec = fft_data.FftDataFixed.new();
            for (0..common.FFT_LENGTH_BY_2_PLUS_1) |k| {
                spec.re_q15[k] = Q15.fromFloatRuntime(X.re[k]);
                spec.im_q15[k] = if (k == 0 or k == common.FFT_LENGTH_BY_2) Q15.zero() else Q15.fromFloatRuntime(X.im[k]);
            }
            const fixed_out = self.fixed_impl.ifftFixedQ15(&spec);
            const scaling = @as(f32, @floatFromInt(common.FFT_LENGTH / 2));
            for (0..common.FFT_LENGTH) |i| {
                out[i] = fixed_out[i].toFloat() * scaling;
            }
        } else {
            return self.float_impl.ifft(X);
        }
        return out;
    }

    pub fn fftFixedQ15(self: *const Self, input: *const [128]@import("../../numeric_profile.zig").profileFor(.fixed_mcu_q15).Sample) fft_data.FftDataFixed {
        return self.fixed_impl.fftFixedQ15(input);
    }

    pub fn ifftFixedQ15(self: *const Self, spec_data: *const fft_data.FftDataFixed) [128]@import("../../numeric_profile.zig").profileFor(.fixed_mcu_q15).Sample {
        return self.fixed_impl.ifftFixedQ15(spec_data);
    }

    pub fn zero_padded_fft(self: *const Self, input: []const f32, window: Window) !fft_data.FftData {
        const common = @import("../common/aec3_common.zig");
        if (input.len != common.FFT_LENGTH_BY_2) return error.InvalidLength;
        var data = [_]f32{0.0} ** common.FFT_LENGTH;
        switch (window) {
            .rectangular => {
                @import("std").mem.copyForwards(f32, data[common.FFT_LENGTH_BY_2..], input);
            },
            .hanning => {
                for (0..common.FFT_LENGTH_BY_2) |i| {
                    data[common.FFT_LENGTH_BY_2 + i] = input[i] * aec3_fft_float.HANNING_64[i];
                }
            },
            .sqrt_hanning => return error.UnsupportedWindow,
        }
        return self.fft(data[0..]);
    }

    pub fn padded_fft(self: *const Self, x: []const f32, x_old: []const f32, window: Window) !fft_data.FftData {
        const common = @import("../common/aec3_common.zig");
        if (x.len != common.FFT_LENGTH_BY_2 or x_old.len != common.FFT_LENGTH_BY_2) return error.InvalidLength;
        var data = [_]f32{0.0} ** common.FFT_LENGTH;
        switch (window) {
            .rectangular => {
                @import("std").mem.copyForwards(f32, data[0..common.FFT_LENGTH_BY_2], x_old);
                @import("std").mem.copyForwards(f32, data[common.FFT_LENGTH_BY_2..], x);
            },
            .hanning => return error.UnsupportedWindow,
            .sqrt_hanning => {
                for (0..common.FFT_LENGTH_BY_2) |i| {
                    data[i] = x_old[i] * aec3_fft_float.SQRT_HANNING_128[i];
                    data[common.FFT_LENGTH_BY_2 + i] = x[i] * aec3_fft_float.SQRT_HANNING_128[common.FFT_LENGTH_BY_2 + i];
                }
            },
        }
        return self.fft(data[0..]);
    }

    pub fn hanning() []const f32 {
        return aec3_fft_float.Aec3FftFloat.hanning();
    }

    pub fn sqrt_hanning() []const f32 {
        return aec3_fft_float.Aec3FftFloat.sqrt_hanning();
    }
};
