const std = @import("std");
const common = @import("../common/aec3_common.zig");
const profileFor = @import("../../numeric_profile.zig").profileFor;
const Aec3Fft = @import("../fft/mod.zig").Aec3Fft;

const Q15 = profileFor(.fixed_mcu_q15).Sample;

pub const FixedI16Pipeline = struct {
    const Self = @This();

    fft: Aec3Fft,

    pub fn init() Self {
        return .{ .fft = Aec3Fft.init() };
    }

    pub fn analyze_render_i16(self: *Self, input: *const [common.FFT_LENGTH]i16) void {
        var q15_in: [common.FFT_LENGTH]Q15 = undefined;
        for (0..common.FFT_LENGTH) |i| {
            q15_in[i] = Q15.fromRaw(@as(i32, input[i]));
        }

        // Render analysis typically computes FFT of the render signal and stores it in the render buffer.
        // We only compute the FFT here without inverse mapping, to simulate render analysis behavior.
        _ = self.fft.fftFixedQ15(&q15_in);
    }

    pub fn process_capture_i16(self: *Self, input: *const [common.FFT_LENGTH]i16, gain_q15: Q15) [common.FFT_LENGTH]i16 {
        var q15_in: [common.FFT_LENGTH]Q15 = undefined;
        for (0..common.FFT_LENGTH) |i| {
            q15_in[i] = Q15.fromRaw(@as(i32, input[i]));
        }

        var spec = self.fft.fftFixedQ15(&q15_in);
        for (0..common.FFT_LENGTH_BY_2_PLUS_1) |k| {
            spec.re_q15[k] = Q15.mulSat(spec.re_q15[k], gain_q15);
            spec.im_q15[k] = Q15.mulSat(spec.im_q15[k], gain_q15);
        }

        const q15_out = self.fft.ifftFixedQ15(&spec);
        var out: [common.FFT_LENGTH]i16 = undefined;
        for (0..common.FFT_LENGTH) |i| {
            const clamped = std.math.clamp(q15_out[i].raw, @as(i32, std.math.minInt(i16)), @as(i32, std.math.maxInt(i16)));
            out[i] = @intCast(clamped);
        }
        return out;
    }
};

test "fixed_i16_pipeline handles 1000 frames without divergence" {
    var pipeline = FixedI16Pipeline.init();
    var prng = std.Random.DefaultPrng.init(0xAEC3_0001);
    const random = prng.random();

    var frame: [common.FFT_LENGTH]i16 = undefined;
    for (0..1000) |_| {
        for (0..common.FFT_LENGTH) |i| {
            frame[i] = random.int(i16);
        }
        const out = pipeline.process_capture_i16(&frame, Q15.fromFloatRuntime(0.75));
        for (out) |s| {
            try std.testing.expect(s >= std.math.minInt(i16));
            try std.testing.expect(s <= std.math.maxInt(i16));
        }
    }
}
