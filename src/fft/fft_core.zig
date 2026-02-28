//! 通用 2^N FFT 核心（fixed-point-first）

const std = @import("std");
const Complex = @import("../complex.zig").Complex;
const SampleOps = @import("../sample_ops.zig").SampleOps;

pub fn isPowerOfTwo(v: usize) bool {
    return v != 0 and (v & (v - 1)) == 0;
}

fn bitReverse(comptime bits: usize, x: usize) usize {
    var v = x;
    var r: usize = 0;
    inline for (0..bits) |_| {
        r = (r << 1) | (v & 1);
        v >>= 1;
    }
    return r;
}

pub fn FftCore(comptime T: type, comptime N: usize) type {
    if (!isPowerOfTwo(N)) @compileError("FFT size N must be power of two");
    if (N < 2) @compileError("FFT size N must be >= 2");

    const Ops = SampleOps(T);
    const ComplexT = Complex(T);
    const log2_n = std.math.log2_int(usize, N);

    return struct {
        const TWIDDLE_FORWARD: [N / 2]ComplexT = blk: {
            var twiddles: [N / 2]ComplexT = undefined;
            for (0..N / 2) |k| {
                const angle = -2.0 * std.math.pi * (@as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(N)));
                twiddles[k] = ComplexT.init(Ops.fromFloatComptime(@cos(angle)), Ops.fromFloatComptime(@sin(angle)));
            }
            break :blk twiddles;
        };

        pub const Spectrum = struct {
            re: [N / 2 + 1]T,
            im: [N / 2 + 1]T,
        };

        pub fn forward(input: *[N]ComplexT) void {
            transformGeneric(input, false);
        }

        pub fn inverse(input: *[N]ComplexT) void {
            transformGeneric(input, true);
            const inv_n = Ops.div(Ops.one(), Ops.fromInt(@as(i32, @intCast(N))));
            for (input) |*v| {
                v.* = ComplexT.scale(v.*, inv_n);
            }
        }

        pub fn forwardOracleFloat(input: *const [N]T) [N]Complex(f32) {
            var tmp: [N]Complex(f32) = undefined;
            for (0..N) |i| {
                tmp[i] = Complex(f32).init(Ops.toFloat(input[i]), 0.0);
            }
            transformFloatGeneric(&tmp, false);
            return tmp;
        }

        pub fn inverseOracleFloat(spec: *const [N]Complex(f32)) [N]f32 {
            var tmp = spec.*;
            transformFloatGeneric(&tmp, true);
            const inv_n = 1.0 / @as(f32, @floatFromInt(N));
            var out: [N]f32 = undefined;
            for (0..N) |i| {
                out[i] = tmp[i].re * inv_n;
            }
            return out;
        }

        pub fn forwardReal(input: *const [N]T) Spectrum {
            var tmp: [N]ComplexT = undefined;
            for (0..N) |i| {
                tmp[i] = ComplexT.init(input[i], Ops.zero());
            }
            forward(&tmp);

            var out: Spectrum = .{
                .re = [_]T{Ops.zero()} ** (N / 2 + 1),
                .im = [_]T{Ops.zero()} ** (N / 2 + 1),
            };
            out.re[0] = tmp[0].re;
            out.im[0] = Ops.zero();
            out.re[N / 2] = tmp[N / 2].re;
            out.im[N / 2] = Ops.zero();
            for (1..N / 2) |k| {
                out.re[k] = tmp[k].re;
                out.im[k] = tmp[k].im;
            }
            return out;
        }

        pub fn inverseReal(spec: *const Spectrum) [N]T {
            var tmp: [N]ComplexT = [_]ComplexT{ComplexT.zero()} ** N;
            tmp[0] = ComplexT.init(spec.re[0], Ops.zero());
            tmp[N / 2] = ComplexT.init(spec.re[N / 2], Ops.zero());

            for (1..N / 2) |k| {
                const v = ComplexT.init(spec.re[k], spec.im[k]);
                tmp[k] = v;
                tmp[N - k] = ComplexT.conj(v);
            }

            inverse(&tmp);

            var out: [N]T = [_]T{Ops.zero()} ** N;
            for (0..N) |i| {
                out[i] = tmp[i].re;
            }
            return out;
        }

        fn transformGeneric(data: *[N]ComplexT, inverse_mode: bool) void {
            // Bit-reversal permutation
            for (0..N) |i| {
                const j = bitReverse(log2_n, i);
                if (j > i) {
                    const tmp = data[i];
                    data[i] = data[j];
                    data[j] = tmp;
                }
            }

            var len: usize = 2;
            while (len <= N) : (len <<= 1) {
                const half = len / 2;
                const tw_step = N / len;

                var i: usize = 0;
                while (i < N) : (i += len) {
                    var j: usize = 0;
                    while (j < half) : (j += 1) {
                        const tw_idx = j * tw_step;
                        var w = TWIDDLE_FORWARD[tw_idx];
                        if (inverse_mode) {
                            w.im = Ops.neg(w.im);
                        }

                        const u = data[i + j];
                        const t = ComplexT.mul(w, data[i + j + half]);

                        data[i + j] = ComplexT.add(u, t);
                        data[i + j + half] = ComplexT.sub(u, t);
                    }
                }
            }
        }

        fn transformFloatGeneric(data: *[N]Complex(f32), inverse_mode: bool) void {
            // Bit-reversal permutation
            for (0..N) |i| {
                const j = bitReverse(log2_n, i);
                if (j > i) {
                    const tmp = data[i];
                    data[i] = data[j];
                    data[j] = tmp;
                }
            }

            var len: usize = 2;
            while (len <= N) : (len <<= 1) {
                const half = len / 2;
                const theta_sign: f32 = if (inverse_mode) 1.0 else -1.0;
                const step_angle = theta_sign * (2.0 * std.math.pi / @as(f32, @floatFromInt(len)));

                var i: usize = 0;
                while (i < N) : (i += len) {
                    var j: usize = 0;
                    while (j < half) : (j += 1) {
                        const angle = step_angle * @as(f32, @floatFromInt(j));
                        const w = Complex(f32).init(@cos(angle), @sin(angle));
                        const u = data[i + j];
                        const t = Complex(f32).mul(w, data[i + j + half]);
                        data[i + j] = Complex(f32).add(u, t);
                        data[i + j + half] = Complex(f32).sub(u, t);
                    }
                }
            }
        }
    };
}
