const std = @import("std");
const FftCore = @import("../../fft/fft_core.zig").FftCore;
const common = @import("../common/aec3_common.zig");
const FftDataFixed = @import("fft_data.zig").FftDataFixed;
const profileFor = @import("../../numeric_profile.zig").profileFor;

const FixedProfile = profileFor(.fixed_mcu_q15);
const Q15 = FixedProfile.Sample;
const FFT_FIXED = FftCore(Q15, common.FFT_LENGTH);

pub const Aec3FftFixed = struct {
    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    /// Fixed-point FFT path without runtime float conversions.
    pub fn fftFixedQ15(_: *const Self, input: *const [common.FFT_LENGTH]Q15) FftDataFixed {
        const spec = FFT_FIXED.forwardReal(input);
        var out = FftDataFixed.new();
        out.re_q15 = spec.re;
        out.im_q15 = spec.im;
        out.im_q15[0] = Q15.zero();
        out.im_q15[common.FFT_LENGTH_BY_2] = Q15.zero();
        return out;
    }

    /// Fixed-point IFFT path without runtime float conversions.
    pub fn ifftFixedQ15(_: *const Self, spec_data: *const FftDataFixed) [common.FFT_LENGTH]Q15 {
        var spec: FFT_FIXED.Spectrum = .{
            .re = spec_data.re_q15,
            .im = spec_data.im_q15,
        };
        spec.im[0] = Q15.zero();
        spec.im[common.FFT_LENGTH_BY_2] = Q15.zero();
        return FFT_FIXED.inverseReal(&spec);
    }
};

test "aec3_fft_fixed fixed q15 roundtrip remains bounded" {
    var fft = Aec3FftFixed.init();
    var in: [common.FFT_LENGTH]Q15 = [_]Q15{Q15.zero()} ** common.FFT_LENGTH;
    for (0..common.FFT_LENGTH) |i| {
        const phase = 2.0 * std.math.pi * (@as(f32, @floatFromInt(i * 8)) / @as(f32, @floatFromInt(common.FFT_LENGTH)));
        in[i] = Q15.fromFloatRuntime(@sin(phase) * 0.6);
    }

    const spec = fft.fftFixedQ15(&in);
    const out = fft.ifftFixedQ15(&spec);

    var max_err: i32 = 0;
    for (0..common.FFT_LENGTH) |i| {
        const diff = @abs(out[i].raw - in[i].raw);
        if (diff > max_err) max_err = diff;
    }
    try std.testing.expect(max_err <= 128);
}
