const std = @import("std");
const FftCore = @import("../fft_core.zig").FftCore;
const common = @import("ns_common.zig");

const FFT = FftCore(f32, common.FFT_SIZE);

pub const NrFft = struct {
    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    pub fn fft(self: *const Self, time_data: *const [common.FFT_SIZE]f32, real: *[common.FFT_SIZE]f32, imag: *[common.FFT_SIZE]f32) void {
        _ = self;
        const spec = FFT.forwardReal(time_data);

        imag[0] = 0.0;
        real[0] = spec.re[0];

        imag[common.FFT_SIZE_BY_2_PLUS_1 - 1] = 0.0;
        real[common.FFT_SIZE_BY_2_PLUS_1 - 1] = spec.re[common.FFT_SIZE / 2];

        for (1..(common.FFT_SIZE_BY_2_PLUS_1 - 1)) |i| {
            real[i] = spec.re[i];
            imag[i] = spec.im[i];
        }
    }

    pub fn ifft(self: *const Self, real: []const f32, imag: []const f32, time_data: []f32) void {
        _ = self;
        std.debug.assert(real.len >= common.FFT_SIZE_BY_2_PLUS_1);
        std.debug.assert(imag.len >= common.FFT_SIZE_BY_2_PLUS_1);
        std.debug.assert(time_data.len >= common.FFT_SIZE);

        var spec: FFT.Spectrum = .{
            .re = [_]f32{0.0} ** (common.FFT_SIZE / 2 + 1),
            .im = [_]f32{0.0} ** (common.FFT_SIZE / 2 + 1),
        };
        spec.re[0] = real[0];
        spec.im[0] = 0.0;
        spec.re[common.FFT_SIZE / 2] = real[common.FFT_SIZE_BY_2_PLUS_1 - 1];
        spec.im[common.FFT_SIZE / 2] = 0.0;
        for (1..(common.FFT_SIZE_BY_2_PLUS_1 - 1)) |i| {
            spec.re[i] = real[i];
            spec.im[i] = imag[i];
        }

        const reconstructed = FFT.inverseReal(&spec);
        const scaling: f32 = 2.0 / @as(f32, @floatFromInt(common.FFT_SIZE));
        for (0..common.FFT_SIZE) |i| {
            time_data[i] = reconstructed[i] * scaling * @as(f32, @floatFromInt(common.FFT_SIZE));
        }
    }
};
