//! Ported from: docs/aec3-rs-src/audio_processing/aec3/reverb_model.rs
//! Simple exponential reverberation model applied to render spectra.
const std = @import("std");
const common = @import("aec3_common.zig");

const FFT_LENGTH_BY_2_PLUS_1 = common.FFT_LENGTH_BY_2_PLUS_1;

/// Simple exponential reverberation model applied to render spectra.
pub const ReverbModel = struct {
    const Self = @This();

    reverb_power: [FFT_LENGTH_BY_2_PLUS_1]f32,

    pub fn init() Self {
        var model = Self{ .reverb_power = undefined };
        model.reset();
        return model;
    }

    pub fn reset(self: *Self) void {
        self.reverb_power = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    }

    pub fn reverb(self: *const Self) *const [FFT_LENGTH_BY_2_PLUS_1]f32 {
        return &self.reverb_power;
    }

    /// Updates reverb using a uniform power spectrum scaling factor.
    pub fn update_reverb_no_freq_shaping(
        self: *Self,
        power_spectrum: []const f32,
        power_spectrum_scaling: f32,
        reverb_decay: f32,
    ) void {
        if (reverb_decay <= 0.0) return;
        std.debug.assert(power_spectrum.len == FFT_LENGTH_BY_2_PLUS_1);
        for (&self.reverb_power, power_spectrum) |*dst, src| {
            dst.* = (dst.* + src * power_spectrum_scaling) * reverb_decay;
        }
    }

    /// Updates reverb using per-bin power spectrum scaling.
    pub fn update_reverb(
        self: *Self,
        power_spectrum: []const f32,
        power_spectrum_scaling: []const f32,
        reverb_decay: f32,
    ) void {
        if (reverb_decay <= 0.0) return;
        std.debug.assert(power_spectrum.len == FFT_LENGTH_BY_2_PLUS_1);
        std.debug.assert(power_spectrum_scaling.len == FFT_LENGTH_BY_2_PLUS_1);
        for (&self.reverb_power, power_spectrum, power_spectrum_scaling) |*dst, src, scale| {
            dst.* = (dst.* + src * scale) * reverb_decay;
        }
    }
};

// ---------------------------------------------------------------------------
// Inline tests
// ---------------------------------------------------------------------------

test "reverb_model init is zero" {
    const model = ReverbModel.init();
    for (model.reverb_power) |v| {
        try std.testing.expectEqual(@as(f32, 0.0), v);
    }
}

test "reverb_model reset clears state" {
    var model = ReverbModel.init();
    model.reverb_power[0] = 42.0;
    model.reverb_power[FFT_LENGTH_BY_2_PLUS_1 - 1] = 99.0;
    model.reset();
    for (model.reverb_power) |v| {
        try std.testing.expectEqual(@as(f32, 0.0), v);
    }
}

test "reverb_model zero decay is noop" {
    var model = ReverbModel.init();
    var spectrum = [_]f32{1.0} ** FFT_LENGTH_BY_2_PLUS_1;
    model.update_reverb_no_freq_shaping(&spectrum, 1.0, 0.0);
    for (model.reverb_power) |v| {
        try std.testing.expectEqual(@as(f32, 0.0), v);
    }
}

test "reverb_model negative decay is noop" {
    var model = ReverbModel.init();
    var spectrum = [_]f32{1.0} ** FFT_LENGTH_BY_2_PLUS_1;
    model.update_reverb_no_freq_shaping(&spectrum, 1.0, -0.5);
    for (model.reverb_power) |v| {
        try std.testing.expectEqual(@as(f32, 0.0), v);
    }
}

test "reverb_model no_freq_shaping accumulates" {
    var model = ReverbModel.init();
    var spectrum = [_]f32{100.0} ** FFT_LENGTH_BY_2_PLUS_1;
    const decay: f32 = 0.5;
    const scaling: f32 = 1.0;

    // First update: reverb = (0 + 100*1) * 0.5 = 50
    model.update_reverb_no_freq_shaping(&spectrum, scaling, decay);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), model.reverb_power[0], 1e-6);

    // Second update: reverb = (50 + 100) * 0.5 = 75
    model.update_reverb_no_freq_shaping(&spectrum, scaling, decay);
    try std.testing.expectApproxEqAbs(@as(f32, 75.0), model.reverb_power[0], 1e-6);
}

test "reverb_model per-bin scaling" {
    var model = ReverbModel.init();
    var spectrum = [_]f32{100.0} ** FFT_LENGTH_BY_2_PLUS_1;
    var scaling = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    scaling[0] = 2.0;
    scaling[1] = 0.5;
    const decay: f32 = 0.5;

    model.update_reverb(&spectrum, &scaling, decay);
    // bin 0: (0 + 100*2) * 0.5 = 100
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), model.reverb_power[0], 1e-6);
    // bin 1: (0 + 100*0.5) * 0.5 = 25
    try std.testing.expectApproxEqAbs(@as(f32, 25.0), model.reverb_power[1], 1e-6);
    // bin 2: (0 + 100*0) * 0.5 = 0
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), model.reverb_power[2], 1e-6);
}

test "reverb_model exponential decay converges toward zero" {
    var model = ReverbModel.init();
    var spectrum = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    model.reverb_power[0] = 1000.0;

    // Apply many updates with zero input, decay should converge to 0.
    // 1000 * 0.9^200 ≈ 7e-7, well below 0.01.
    for (0..200) |_| {
        model.update_reverb_no_freq_shaping(&spectrum, 0.0, 0.9);
    }
    try std.testing.expect(model.reverb_power[0] < 0.01);
}
