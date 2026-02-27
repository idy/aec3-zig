//! Golden parity tests for Metrics & Leafs modules.

const std = @import("std");
const testing = std.testing;
const aec3 = @import("aec3");
const test_utils = @import("test_utils.zig");

const golden_text = @embedFile("../vectors/rust_metrics_leafs_golden_vectors.txt");

test "golden_metrics_leafs_api_call_jitter" {
    const expected_samples = test_utils.parseScalarF32(golden_text, "APICALL_SAMPLES");
    const expected_mean = test_utils.parseScalarF32(golden_text, "APICALL_MEAN");
    const expected_variance = test_utils.parseScalarF32(golden_text, "APICALL_VARIANCE");
    const expected_min = test_utils.parseScalarF32(golden_text, "APICALL_MIN_DELTA");
    const expected_max = test_utils.parseScalarF32(golden_text, "APICALL_MAX_DELTA");
    const expected_negative = test_utils.parseScalarF32(golden_text, "APICALL_NEGATIVE_DELTAS");

    var m = aec3.ApiCallJitterMetrics{};
    const ts = [_]i64{ 0, 10_000, 20_000, 15_000, 30_000 };
    for (ts) |t| m.recordCall(t);
    const s = m.snapshot();

    try testing.expectApproxEqAbs(expected_samples, @as(f32, @floatFromInt(s.samples)), 1e-6);
    try testing.expectApproxEqAbs(expected_mean, @as(f32, @floatCast(s.mean)), 1e-6);
    try testing.expectApproxEqAbs(expected_variance, @as(f32, @floatCast(s.variance)), 1e-6);
    try testing.expectApproxEqAbs(expected_min, @as(f32, @floatFromInt(s.min_delta)), 1e-6);
    try testing.expectApproxEqAbs(expected_max, @as(f32, @floatFromInt(s.max_delta)), 1e-6);
    try testing.expectApproxEqAbs(expected_negative, @as(f32, @floatFromInt(s.negative_deltas)), 1e-6);
}

test "golden_metrics_leafs_block_processor" {
    const expected_frames = test_utils.parseScalarF32(golden_text, "BLOCKPROC_FRAMES");
    const expected_samples = test_utils.parseScalarF32(golden_text, "BLOCKPROC_SAMPLES");
    const expected_mean = test_utils.parseScalarF32(golden_text, "BLOCKPROC_MEAN_LATENCY");
    const expected_min = test_utils.parseScalarF32(golden_text, "BLOCKPROC_MIN_LATENCY");
    const expected_max = test_utils.parseScalarF32(golden_text, "BLOCKPROC_MAX_LATENCY");
    const expected_p90 = test_utils.parseScalarF32(golden_text, "BLOCKPROC_P90");
    const expected_slot0 = test_utils.parseScalarF32(golden_text, "BLOCKPROC_SLOT0");

    var m = aec3.BlockProcessorMetrics{};
    for (0..70) |i| {
        try m.recordFrame(80, @as(f32, @floatFromInt(i + 1)));
    }
    const s = m.snapshot();

    try testing.expectApproxEqAbs(expected_frames, @as(f32, @floatFromInt(s.frames_processed)), 1e-6);
    try testing.expectApproxEqAbs(expected_samples, @as(f32, @floatFromInt(s.samples_processed)), 1e-6);
    try testing.expectApproxEqAbs(expected_mean, s.mean_latency_ms, 1e-6);
    try testing.expectApproxEqAbs(expected_min, s.min_latency_ms, 1e-6);
    try testing.expectApproxEqAbs(expected_max, s.max_latency_ms, 1e-6);
    try testing.expectApproxEqAbs(expected_p90, s.p90_latency_ms, 1e-6);
    try testing.expectApproxEqAbs(expected_slot0, m.latencies[0], 1e-6);
}

test "golden_metrics_leafs_render_delay" {
    const expected_samples = test_utils.parseScalarF32(golden_text, "RENDER_DELAY_SAMPLES");
    const expected_mean = test_utils.parseScalarF32(golden_text, "RENDER_DELAY_MEAN");
    const expected_variance = test_utils.parseScalarF32(golden_text, "RENDER_DELAY_VARIANCE");
    const expected_jumps = test_utils.parseScalarF32(golden_text, "RENDER_DELAY_JUMPS");

    var m = try aec3.RenderDelayControllerMetrics.init(20);
    const seq = [_]i32{ 50, 51, 50, 80, 79 };
    for (seq) |d| try m.updateDelay(d);
    const s = m.snapshot();

    try testing.expectApproxEqAbs(expected_samples, @as(f32, @floatFromInt(s.samples)), 1e-6);
    try testing.expectApproxEqAbs(expected_mean, s.mean_delay, 1e-6);
    try testing.expectApproxEqAbs(expected_variance, s.variance, 1e-5);
    try testing.expectApproxEqAbs(expected_jumps, @as(f32, @floatFromInt(s.jump_count)), 1e-6);
}

test "golden_metrics_leafs_echo_remover" {
    const expected_samples = test_utils.parseScalarF32(golden_text, "ECHO_REMOVER_SAMPLES");
    const expected_mean = test_utils.parseScalarF32(golden_text, "ECHO_REMOVER_MEAN_ERLE");
    const expected_peak = test_utils.parseScalarF32(golden_text, "ECHO_REMOVER_PEAK_ERLE");
    const expected_toggles = test_utils.parseScalarF32(golden_text, "ECHO_REMOVER_TOGGLES");
    const expected_state = test_utils.parseScalarF32(golden_text, "ECHO_REMOVER_LAST_PRESENT");

    var m = aec3.EchoRemoverMetrics{};
    try m.update(3.0, true);
    try m.update(6.0, true);
    try m.update(0.0, false);
    try m.update(8.0, true);
    const s = m.snapshot();

    try testing.expectApproxEqAbs(expected_samples, @as(f32, @floatFromInt(s.samples)), 1e-6);
    try testing.expectApproxEqAbs(expected_mean, s.mean_erle, 1e-6);
    try testing.expectApproxEqAbs(expected_peak, s.peak_erle, 1e-6);
    try testing.expectApproxEqAbs(expected_toggles, @as(f32, @floatFromInt(s.echo_toggle_count)), 1e-6);
    const actual_state: f32 = if (s.echo_present) 1.0 else 0.0;
    try testing.expectApproxEqAbs(expected_state, actual_state, 1e-6);
}

test "golden_metrics_leafs_nearend_sequence" {
    const expected = test_utils.parseNamedF32(golden_text, "NEAREND_SEQUENCE", 4);

    var d = try aec3.NearendDetector.init(2.0, 1.5);
    const near = [_]f32{ 1.0, 10.0, 6.0, 1.0 };
    const echo = [_]f32{ 3.0, 3.0, 3.0, 3.0 };
    const noise = [_]f32{ 1.0, 1.0, 1.0, 1.0 };

    for (0..expected.len) |i| {
        const actual = d.detect(near[i], echo[i], noise[i]);
        try testing.expectEqual(expected[i] > 0.5, actual);
    }
}

test "golden_metrics_leafs_dominant_nearend_sequence" {
    const expected = test_utils.parseNamedF32(golden_text, "DOMINANT_NEAREND_SEQUENCE", 4);

    var d = try aec3.DominantNearendDetector.init(2.0, 1.5);
    const near = [_]f32{ 1.0, 5.0, 6.0, 1.0 };
    const echo = [_]f32{ 3.0, 2.0, 2.0, 3.0 };

    for (0..expected.len) |i| {
        const actual = d.detect(near[i], echo[i]);
        try testing.expectEqual(expected[i] > 0.5, actual);
    }
}

test "golden_metrics_leafs_echo_audibility_sequence" {
    const expected = test_utils.parseNamedF32(golden_text, "ECHO_AUDIBILITY_SEQUENCE", 3);

    var a = try aec3.EchoAudibility.init(0.8);
    const echo = [_]f32{ 1.0, 10.0, 0.1 };
    const noise = [_]f32{ 1.0, 1.0, 1.0 };
    for (0..expected.len) |i| {
        const actual = try a.update(echo[i], noise[i]);
        try testing.expectApproxEqAbs(expected[i], actual, 1e-6);
    }
}

test "golden_metrics_leafs_main_filter_gain_sequence" {
    const expected = test_utils.parseNamedF32(golden_text, "MAIN_FILTER_GAIN_SEQUENCE", 4);

    var g = try aec3.MainFilterUpdateGain.init(0.9);
    const erle = [_]f32{ 1.0, 0.0, 10.0, 2.0 };
    const present = [_]bool{ true, true, true, false };

    for (0..expected.len) |i| {
        const actual = try g.compute(erle[i], present[i]);
        try testing.expectApproxEqAbs(expected[i], actual, 1e-6);
    }
}

test "golden_metrics_leafs_subtractor_output_energy" {
    const expected_init = test_utils.parseScalarF32(golden_text, "SUBTRACTOR_OUTPUT_ENERGY_INIT");
    const expected_updated = test_utils.parseScalarF32(golden_text, "SUBTRACTOR_OUTPUT_ENERGY_UPDATED");

    const input = [_]f32{ 1.0, -1.0, 0.5 };
    const update_values = [_]f32{ 2.0, 0.0, 1.0 };
    var out = try aec3.SubtractorOutput.fromSlice(testing.allocator, input[0..]);
    defer out.deinit();

    try testing.expectApproxEqAbs(expected_init, out.residual_energy, 1e-6);
    try out.update(update_values[0..]);
    try testing.expectApproxEqAbs(expected_updated, out.residual_energy, 1e-6);
}

test "golden_metrics_leafs_subtractor_output_analyzer" {
    const expected_power = test_utils.parseScalarF32(golden_text, "SUBTRACTOR_ANALYZER_POWER");
    const expected_likelihood = test_utils.parseScalarF32(golden_text, "SUBTRACTOR_ANALYZER_LIKELIHOOD");

    const analyzer = try aec3.SubtractorOutputAnalyzer.init(0.1, 1.0);
    const input = [_]f32{ 0.5, 0.5, 0.5, 0.5 };
    const actual = try analyzer.analyze(input[0..]);

    try testing.expectApproxEqAbs(expected_power, actual.residual_power, 1e-6);
    try testing.expectApproxEqAbs(expected_likelihood, actual.residual_echo_likelihood, 1e-6);
}
