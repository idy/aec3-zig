const std = @import("std");
const FftCore = @import("../fft/fft_core.zig").FftCore;
const common = @import("ns_common.zig");
const NumericMode = @import("../numeric_mode.zig").NumericMode;
const profileFor = @import("../numeric_profile.zig").profileFor;

const FixedProfile = profileFor(.fixed_mcu_q15);
const Q15 = FixedProfile.Sample;
const FFT_FIXED = FftCore(Q15, common.FFT_SIZE);

// DFT reference path for float32 oracle mode.
// 与 AEC3RS golden 生成器保持一致，确保逐样本 golden 对齐可复核。
fn dftForwardReal(time_data: *const [common.FFT_SIZE]f32, real: *[common.FFT_SIZE]f32, imag: *[common.FFT_SIZE]f32) void {
    for (0..common.FFT_SIZE) |i| {
        real[i] = 0.0;
        imag[i] = 0.0;
    }

    const bins = common.FFT_SIZE_BY_2_PLUS_1;
    const n_f = @as(f32, @floatFromInt(common.FFT_SIZE));
    for (0..bins) |k| {
        var re: f32 = 0.0;
        var im: f32 = 0.0;
        const kf = @as(f32, @floatFromInt(k));

        for (0..common.FFT_SIZE) |n| {
            const nf = @as(f32, @floatFromInt(n));
            const angle = 2.0 * std.math.pi * kf * nf / n_f;
            const x = time_data[n];
            re += x * @cos(angle);
            im -= x * @sin(angle);
        }

        real[k] = re;
        imag[k] = if (k == 0 or k == bins - 1) 0.0 else im;
    }
}

fn dftInverseReal(real: []const f32, imag: []const f32, time_data: []f32) void {
    const bins = common.FFT_SIZE_BY_2_PLUS_1;
    const n_f = @as(f32, @floatFromInt(common.FFT_SIZE));

    for (0..common.FFT_SIZE) |n| {
        var sum: f32 = 0.0;
        const nf = @as(f32, @floatFromInt(n));

        // DC component (k=0)
        sum += real[0];

        // Middle frequencies (k=1 to bins-2)
        for (1..(bins - 1)) |k| {
            const kf = @as(f32, @floatFromInt(k));
            const angle = 2.0 * std.math.pi * kf * nf / n_f;
            const cosv = @cos(angle);
            const sinv = @sin(angle);

            // X[k] * e^(j*angle) + X[N-k] * e^(-j*angle)
            // For real input, X[N-k] = conj(X[k])
            // So: 2 * (real[k]*cos - imag[k]*sin)
            sum += 2.0 * (real[k] * cosv - imag[k] * sinv);
        }

        // Nyquist component (k=bins-1)
        if (bins > 1) {
            sum += real[bins - 1] * @cos(std.math.pi * nf); // (-1)^n
        }

        // Match aec3-rs ns_fft scaling convention: 2 / N.
        time_data[n] = (2.0 * sum) / n_f;
    }
}

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
        if (self.mode == .fixed_mcu_q15) {
            var fixed_in: [common.FFT_SIZE]Q15 = undefined;
            for (0..common.FFT_SIZE) |i| fixed_in[i] = Q15.fromFloatRuntime(time_data[i]);
            const spec_fixed = FFT_FIXED.forwardReal(&fixed_in);

            imag[0] = 0.0;
            real[0] = spec_fixed.re[0].toFloat();
            imag[common.FFT_SIZE_BY_2_PLUS_1 - 1] = 0.0;
            real[common.FFT_SIZE_BY_2_PLUS_1 - 1] = spec_fixed.re[common.FFT_SIZE / 2].toFloat();
            for (1..(common.FFT_SIZE_BY_2_PLUS_1 - 1)) |i| {
                real[i] = spec_fixed.re[i].toFloat();
                imag[i] = spec_fixed.im[i].toFloat();
            }
        } else {
            dftForwardReal(time_data, real, imag);
        }
    }

    /// Inverse FFT with explicit error handling for insufficient buffer sizes.
    ///
    /// # Scaling Convention Note
    /// - fixed_mcu_q15 路径：输出乘以 2.0（与 Rust/Ooura 路径一致）；
    /// - float32 DFT 路径：输出按 `2 / N` 归一化，与 aec3-rs `ns_fft.rs` 对齐。
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
            dftInverseReal(real, imag, time_data);
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
