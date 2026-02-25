const std = @import("std");
const FftCore = @import("../fft_core.zig").FftCore;
const common = @import("ns_common.zig");
const NumericMode = @import("../../numeric_mode.zig").NumericMode;
const profileFor = @import("../../numeric_profile.zig").profileFor;

const FixedProfile = profileFor(.fixed_mcu_q15);
const OracleProfile = profileFor(.float32);
const Q15 = FixedProfile.Sample;
const FFT_FIXED = FftCore(Q15, common.FFT_SIZE);
const FFT_ORACLE = FftCore(OracleProfile.Sample, common.FFT_SIZE);

pub const NrFft = struct {
    const Self = @This();

    mode: NumericMode = .fixed_mcu_q15,

    pub fn init() Self {
        return .{ .mode = .fixed_mcu_q15 };
    }

    pub fn initOracle() Self {
        return .{ .mode = .float32 };
    }

    pub fn fft(self: *const Self, time_data: *const [common.FFT_SIZE]f32, real: *[common.FFT_SIZE]f32, imag: *[common.FFT_SIZE]f32) void {
        const spec_fixed = blk: {
            if (self.mode == .fixed_mcu_q15) {
                var fixed_in: [common.FFT_SIZE]Q15 = undefined;
                for (0..common.FFT_SIZE) |i| fixed_in[i] = Q15.fromFloatRuntime(time_data[i]);
                break :blk FFT_FIXED.forwardReal(&fixed_in);
            }
            break :blk undefined;
        };

        imag[0] = 0.0;
        real[0] = if (self.mode == .fixed_mcu_q15) spec_fixed.re[0].toFloat() else FFT_ORACLE.forwardReal(time_data).re[0];

        imag[common.FFT_SIZE_BY_2_PLUS_1 - 1] = 0.0;
        if (self.mode == .fixed_mcu_q15) {
            real[common.FFT_SIZE_BY_2_PLUS_1 - 1] = spec_fixed.re[common.FFT_SIZE / 2].toFloat();
            for (1..(common.FFT_SIZE_BY_2_PLUS_1 - 1)) |i| {
                real[i] = spec_fixed.re[i].toFloat();
                imag[i] = spec_fixed.im[i].toFloat();
            }
        } else {
            const spec = FFT_ORACLE.forwardReal(time_data);
            real[common.FFT_SIZE_BY_2_PLUS_1 - 1] = spec.re[common.FFT_SIZE / 2];
            for (1..(common.FFT_SIZE_BY_2_PLUS_1 - 1)) |i| {
                real[i] = spec.re[i];
                imag[i] = spec.im[i];
            }
        }
    }

    pub fn ifft(self: *const Self, real: []const f32, imag: []const f32, time_data: []f32) void {
        std.debug.assert(real.len >= common.FFT_SIZE_BY_2_PLUS_1);
        std.debug.assert(imag.len >= common.FFT_SIZE_BY_2_PLUS_1);
        std.debug.assert(time_data.len >= common.FFT_SIZE);

        if (self.mode == .fixed_mcu_q15) {
            var spec: FFT_FIXED.Spectrum = .{
                .re = [_]Q15{Q15.zero()} ** (common.FFT_SIZE / 2 + 1),
                .im = [_]Q15{Q15.zero()} ** (common.FFT_SIZE / 2 + 1),
            };
            spec.re[0] = Q15.fromFloatRuntime(real[0]);
            spec.im[0] = Q15.zero();
            spec.re[common.FFT_SIZE / 2] = Q15.fromFloatRuntime(real[common.FFT_SIZE_BY_2_PLUS_1 - 1]);
            spec.im[common.FFT_SIZE / 2] = Q15.zero();
            for (1..(common.FFT_SIZE_BY_2_PLUS_1 - 1)) |i| {
                spec.re[i] = Q15.fromFloatRuntime(real[i]);
                spec.im[i] = Q15.fromFloatRuntime(imag[i]);
            }

            const reconstructed = FFT_FIXED.inverseReal(&spec);
            for (0..common.FFT_SIZE) |i| {
                time_data[i] = reconstructed[i].toFloat() * 2.0;
            }
        } else {
            var spec: FFT_ORACLE.Spectrum = .{
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

            const reconstructed = FFT_ORACLE.inverseReal(&spec);
            for (0..common.FFT_SIZE) |i| {
                time_data[i] = reconstructed[i] * 2.0;
            }
        }
    }
};
