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

/// Errors that can occur during FFT operations
pub const FftError = error{
    /// Input real buffer too small (must be >= FFT_SIZE_BY_2_PLUS_1)
    InsufficientRealBuffer,
    /// Input imaginary buffer too small (must be >= FFT_SIZE_BY_2_PLUS_1)
    InsufficientImagBuffer,
    /// Output time buffer too small (must be >= FFT_SIZE)
    InsufficientTimeBuffer,
};

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

    /// Inverse FFT with explicit error handling for insufficient buffer sizes.
    ///
    /// # Scaling Convention Note
    /// The output is multiplied by 2.0 to compensate for the normalization in forward FFT.
    /// The caller (e.g., NoiseSuppressor.process) typically applies a matching 0.5 scale
    /// to get the correct amplitude. This two-step scaling keeps the FFT core normalized
    /// while allowing the suppressor to control final output gain.
    ///
    /// # Errors
    /// Returns FftError.InsufficientRealBuffer if real.len < FFT_SIZE_BY_2_PLUS_1
    /// Returns FftError.InsufficientImagBuffer if imag.len < FFT_SIZE_BY_2_PLUS_1
    /// Returns FftError.InsufficientTimeBuffer if time_data.len < FFT_SIZE
    pub fn ifft(self: *const Self, real: []const f32, imag: []const f32, time_data: []f32) FftError!void {
        if (real.len < common.FFT_SIZE_BY_2_PLUS_1) return FftError.InsufficientRealBuffer;
        if (imag.len < common.FFT_SIZE_BY_2_PLUS_1) return FftError.InsufficientImagBuffer;
        if (time_data.len < common.FFT_SIZE) return FftError.InsufficientTimeBuffer;

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
            // Scale by 2.0 to compensate FFT normalization (see Scaling Convention Note above)
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
            // Scale by 2.0 to compensate FFT normalization (see Scaling Convention Note above)
            for (0..common.FFT_SIZE) |i| {
                time_data[i] = reconstructed[i] * 2.0;
            }
        }
    }
};

// ═══════════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════════

test "ifft returns error for insufficient real buffer" {
    const fft = NrFft.initOracle();
    var real: [common.FFT_SIZE_BY_2_PLUS_1 - 1]f32 = undefined;
    var imag: [common.FFT_SIZE_BY_2_PLUS_1]f32 = undefined;
    var time: [common.FFT_SIZE]f32 = undefined;

    const result = fft.ifft(&real, &imag, &time);
    try std.testing.expectError(FftError.InsufficientRealBuffer, result);
}

test "ifft returns error for insufficient imag buffer" {
    const fft = NrFft.initOracle();
    var real: [common.FFT_SIZE_BY_2_PLUS_1]f32 = undefined;
    var imag: [common.FFT_SIZE_BY_2_PLUS_1 - 1]f32 = undefined;
    var time: [common.FFT_SIZE]f32 = undefined;

    const result = fft.ifft(&real, &imag, &time);
    try std.testing.expectError(FftError.InsufficientImagBuffer, result);
}

test "ifft returns error for insufficient time buffer" {
    const fft = NrFft.initOracle();
    var real: [common.FFT_SIZE_BY_2_PLUS_1]f32 = undefined;
    var imag: [common.FFT_SIZE_BY_2_PLUS_1]f32 = undefined;
    var time: [common.FFT_SIZE - 1]f32 = undefined;

    const result = fft.ifft(&real, &imag, &time);
    try std.testing.expectError(FftError.InsufficientTimeBuffer, result);
}

test "ifft succeeds with correct buffer sizes" {
    const fft = NrFft.initOracle();
    var real: [common.FFT_SIZE_BY_2_PLUS_1]f32 = undefined;
    var imag: [common.FFT_SIZE_BY_2_PLUS_1]f32 = undefined;
    var time: [common.FFT_SIZE]f32 = undefined;

    // Initialize with some data
    for (&real) |*r| r.* = 0.0;
    for (&imag) |*i| i.* = 0.0;
    real[0] = 1.0; // DC component

    try fft.ifft(&real, &imag, &time);

    // After IFFT with DC=1, we should get a constant signal scaled by 2.0
    for (time) |t| {
        try std.testing.expect(std.math.isFinite(t));
    }
}
