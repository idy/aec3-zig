const std = @import("std");
const FftCore = @import("../fft_core.zig").FftCore;
const common = @import("aec3_common.zig");
const FftData = @import("fft_data.zig").FftData;

const FFT = FftCore(f32, common.FFT_LENGTH);

pub const Window = enum {
    rectangular,
    hanning,
    sqrt_hanning,
};

pub const Aec3Fft = struct {
    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    pub fn fft(self: *const Self, x: []const f32) FftData {
        _ = self;
        std.debug.assert(x.len == common.FFT_LENGTH);
        var input: [common.FFT_LENGTH]f32 = undefined;
        @memcpy(input[0..], x);

        const spec = FFT.forwardReal(&input);
        var out = FftData{};
        out.re[0] = spec.re[0];
        out.im[0] = 0.0;
        out.re[common.FFT_LENGTH_BY_2] = spec.re[common.FFT_LENGTH_BY_2];
        out.im[common.FFT_LENGTH_BY_2] = 0.0;
        for (1..common.FFT_LENGTH_BY_2) |k| {
            out.re[k] = spec.re[k];
            out.im[k] = spec.im[k];
        }
        return out;
    }

    pub fn ifft(self: *const Self, X: FftData) [common.FFT_LENGTH]f32 {
        _ = self;
        var spec: FFT.Spectrum = .{
            .re = [_]f32{0.0} ** common.FFT_LENGTH_BY_2_PLUS_1,
            .im = [_]f32{0.0} ** common.FFT_LENGTH_BY_2_PLUS_1,
        };
        for (0..common.FFT_LENGTH_BY_2_PLUS_1) |k| {
            spec.re[k] = X.re[k];
            spec.im[k] = if (k == 0 or k == common.FFT_LENGTH_BY_2) 0.0 else X.im[k];
        }
        var out = FFT.inverseReal(&spec);
        for (0..common.FFT_LENGTH) |i| {
            out[i] *= @as(f32, @floatFromInt(common.FFT_LENGTH / 2));
        }
        return out;
    }

    pub fn zero_padded_fft(self: *const Self, input: []const f32, window: Window) FftData {
        std.debug.assert(input.len == common.FFT_LENGTH_BY_2);
        var data = [_]f32{0.0} ** common.FFT_LENGTH;
        switch (window) {
            .rectangular => {
                @memcpy(data[common.FFT_LENGTH_BY_2..], input);
            },
            .hanning => {
                for (0..common.FFT_LENGTH_BY_2) |i| {
                    data[common.FFT_LENGTH_BY_2 + i] = input[i] * HANNING_64[i];
                }
            },
            .sqrt_hanning => @panic("Window::sqrt_hanning is not supported for zero_padded_fft"),
        }
        return self.fft(data[0..]);
    }

    pub fn padded_fft(self: *const Self, x: []const f32, x_old: []const f32, window: Window) FftData {
        std.debug.assert(x.len == common.FFT_LENGTH_BY_2);
        std.debug.assert(x_old.len == common.FFT_LENGTH_BY_2);
        var data = [_]f32{0.0} ** common.FFT_LENGTH;
        switch (window) {
            .rectangular => {
                @memcpy(data[0..common.FFT_LENGTH_BY_2], x_old);
                @memcpy(data[common.FFT_LENGTH_BY_2..], x);
            },
            .hanning => @panic("Window::hanning is not supported for padded_fft"),
            .sqrt_hanning => {
                for (0..common.FFT_LENGTH_BY_2) |i| {
                    data[i] = x_old[i] * SQRT_HANNING_128[i];
                    data[common.FFT_LENGTH_BY_2 + i] = x[i] * SQRT_HANNING_128[common.FFT_LENGTH_BY_2 + i];
                }
            },
        }
        return self.fft(data[0..]);
    }

    pub fn hanning() []const f32 {
        return HANNING_64[0..];
    }

    pub fn sqrt_hanning() []const f32 {
        return SQRT_HANNING_128[0..];
    }
};

pub const HANNING_64: [common.FFT_LENGTH_BY_2]f32 = .{
    0.0,        0.00248461, 0.00991376, 0.0222136,  0.03926189, 0.06088921, 0.08688061, 0.11697778,
    0.15088159, 0.1882551,  0.22872687, 0.27189467, 0.31732949, 0.36457977, 0.41317591, 0.46263495,
    0.51246535, 0.56217185, 0.61126047, 0.65924333, 0.70564355, 0.75,       0.79187184, 0.83084292,
    0.86652594, 0.89856625, 0.92664544, 0.95048443, 0.96984631, 0.98453864, 0.99441541, 0.99937846,
    0.99937846, 0.99441541, 0.98453864, 0.96984631, 0.95048443, 0.92664544, 0.89856625, 0.86652594,
    0.83084292, 0.79187184, 0.75,       0.70564355, 0.65924333, 0.61126047, 0.56217185, 0.51246535,
    0.46263495, 0.41317591, 0.36457977, 0.31732949, 0.27189467, 0.22872687, 0.1882551,  0.15088159,
    0.11697778, 0.08688061, 0.06088921, 0.03926189, 0.0222136,  0.00991376, 0.00248461, 0.0,
};

pub const SQRT_HANNING_128: [common.FFT_LENGTH]f32 = .{
    0.0,        0.024541229, 0.049067676, 0.07356456, 0.09801714, 0.12241068, 0.14673048,  0.17096189,
    0.19509032, 0.21910124,  0.24298018,  0.26671276, 0.29028466, 0.31368175, 0.33688986,  0.35989505,
    0.38268343, 0.4052413,   0.4275551,   0.44961134, 0.47139674, 0.4928982,  0.51410276,  0.53499764,
    0.55557024, 0.57580817,  0.5956993,   0.6152316,  0.6343933,  0.65317285, 0.6715589,   0.68954057,
    0.70710677, 0.7242471,   0.7409511,   0.7572088,  0.77301043, 0.7883464,  0.8032075,   0.8175848,
    0.8314696,  0.8448536,   0.8577286,   0.87008697, 0.8819213,  0.8932243,  0.9039893,   0.9142098,
    0.92387956, 0.9329928,   0.94154406,  0.94952816, 0.95694035, 0.96377605, 0.97003126,  0.9757021,
    0.98078525, 0.98527765,  0.9891765,   0.99247956, 0.9951847,  0.99729043, 0.99879545,  0.9996988,
    1.0,        0.9996988,   0.99879545,  0.99729043, 0.9951847,  0.99247956, 0.9891765,   0.98527765,
    0.98078525, 0.9757021,   0.97003126,  0.96377605, 0.95694035, 0.94952816, 0.94154406,  0.9329928,
    0.92387956, 0.9142098,   0.9039893,   0.8932243,  0.8819213,  0.87008697, 0.8577286,   0.8448536,
    0.8314696,  0.8175848,   0.8032075,   0.7883464,  0.77301043, 0.7572088,  0.7409511,   0.7242471,
    0.70710677, 0.68954057,  0.6715589,   0.65317285, 0.6343933,  0.6152316,  0.5956993,   0.57580817,
    0.55557024, 0.53499764,  0.51410276,  0.4928982,  0.47139674, 0.44961134, 0.4275551,   0.4052413,
    0.38268343, 0.35989505,  0.33688986,  0.31368175, 0.29028466, 0.26671276, 0.24298018,  0.21910124,
    0.19509032, 0.17096189,  0.14673048,  0.12241068, 0.09801714, 0.07356456, 0.049067676, 0.024541229,
};
