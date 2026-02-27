//! Golden-style parity smoke tests for metrics & leaf modules.

const std = @import("std");
const testing = std.testing;
const aec3 = @import("aec3");

test "comfort_noise_generator repeatability parity" {
    var gen_a = aec3.ComfortNoiseGenerator.init(12345);
    var gen_b = aec3.ComfortNoiseGenerator.init(12345);
    var a = [_]f32{0.0} ** 65;
    var b = [_]f32{0.0} ** 65;

    try gen_a.generate(a[0..], 0.03);
    try gen_b.generate(b[0..], 0.03);
    try testing.expectEqualSlices(f32, a[0..], b[0..]);
}

test "echo_audibility monotonic trend parity" {
    var aud = try aec3.EchoAudibility.init(0.0);
    const low = try aud.update(0.1, 1.0);
    const high = try aud.update(10.0, 1.0);
    try testing.expect(low < high);
}

test "nearend_detector dominant energy parity" {
    var det = try aec3.NearendDetector.init(2.0, 1.5);
    try testing.expect(det.detect(10.0, 2.0, 0.5));
    try testing.expect(!det.detect(1.0, 3.0, 0.2));
}

test "subtractor_output keeps residual energy parity" {
    const in = [_]f32{ 0.5, -0.5, 1.0, -1.0 };
    var out = try aec3.SubtractorOutput.fromSlice(testing.allocator, in[0..]);
    defer out.deinit();
    try testing.expectApproxEqAbs(@as(f32, 2.5), out.residual_energy, 1e-6);
}

test "subtractor_output_analyzer quality trend parity" {
    const analyzer = try aec3.SubtractorOutputAnalyzer.init(0.01, 1.0);
    const clean = [_]f32{ 0.01, 0.01, 0.01, 0.01 };
    const noisy = [_]f32{ 1.0, 1.0, 1.0, 1.0 };
    const q_clean = try analyzer.analyze(clean[0..]);
    const q_noisy = try analyzer.analyze(noisy[0..]);
    try testing.expect(q_noisy.residual_echo_likelihood > q_clean.residual_echo_likelihood);
}

test "main_filter_update_gain erle response parity" {
    var gain = try aec3.MainFilterUpdateGain.init(0.0);
    const low_erle = try gain.compute(0.1, true);
    const high_erle = try gain.compute(10.0, true);
    try testing.expect(low_erle > high_erle);
}
