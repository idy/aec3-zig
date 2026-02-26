const std = @import("std");
const aec3 = @import("aec3");
const test_utils = @import("test_utils.zig");

const golden_text = @embedFile("../vectors/rust_aec3_delay_est_golden_vectors.txt");

test "golden_delay_vector_metadata_is_stable" {
    const fixed_first = test_utils.parseNamedI32(golden_text, "DELAY_FIXED_FIRST_MATCH_FRAME", 1);
    const jump_first = test_utils.parseNamedI32(golden_text, "DELAY_JUMP_FIRST_MATCH_NEW_FRAME", 1);
    const peak = test_utils.parseNamedI32(golden_text, "RENDER_SIGNAL_ANALYZER_NARROW_PEAK", 1);
    const poor = test_utils.parseNamedI32(golden_text, "RENDER_SIGNAL_ANALYZER_POOR_EXCITATION", 1);

    try std.testing.expectEqual(@as(i32, 61), fixed_first[0]);
    try std.testing.expectEqual(@as(i32, 688), jump_first[0]);
    try std.testing.expectEqual(@as(i32, 2), peak[0]);
    try std.testing.expectEqual(@as(i32, 1), poor[0]);
}

test "golden_lag_aggregator_transition_matches_reference" {
    const expected_delay = test_utils.parseNamedI32(golden_text, "LAG_AGGREGATOR_DELAY_TRAJECTORY", 140);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var agg = try aec3.MatchedFilterLagAggregator.init(arena.allocator(), 512, .{ .initial = 5, .converged = 20 });
    var actual = [_]i32{-1} ** 140;

    for (0..140) |frame| {
        const lag: usize = if (frame < 70) 80 else 140;
        const lag_estimates = [_]aec3.LagEstimate{
            aec3.LagEstimate.new(0.95, true, lag, true),
            aec3.LagEstimate.new(0.2, true, lag + 9, true),
            aec3.LagEstimate.new(0.1, false, lag + 20, true),
        };

        if (agg.aggregate(lag_estimates[0..])) |de| {
            actual[frame] = @intCast(de.delay);
        }
    }

    try std.testing.expectEqualSlices(i32, expected_delay[0..], actual[0..]);
}

test "golden_delay_fixed_sequence_remains_locked_after_first_match" {
    const true_delay = test_utils.parseNamedI32(golden_text, "DELAY_FIXED_TRUE_DELAY_SAMPLES", 700);
    const est_delay = test_utils.parseNamedI32(golden_text, "DELAY_FIXED_ESTIMATED_DELAY_SAMPLES", 700);
    const first_match = test_utils.parseNamedI32(golden_text, "DELAY_FIXED_FIRST_MATCH_FRAME", 1);

    const begin: usize = @intCast(first_match[0]);
    var valid_count: usize = 0;
    for (begin..700) |i| {
        if (est_delay[i] >= 0) {
            valid_count += 1;
            try std.testing.expect(@abs(est_delay[i] - true_delay[i]) <= 4);
        }
    }
    try std.testing.expect(valid_count >= 500);
}

test "golden_delay_jump_sequence_tracks_new_delay_after_switch" {
    const true_delay = test_utils.parseNamedI32(golden_text, "DELAY_JUMP_TRUE_DELAY_SAMPLES", 2500);
    const est_delay = test_utils.parseNamedI32(golden_text, "DELAY_JUMP_ESTIMATED_DELAY_SAMPLES", 2500);
    const switch_frame = test_utils.parseNamedI32(golden_text, "DELAY_JUMP_SWITCH_FRAME", 1);
    const first_new = test_utils.parseNamedI32(golden_text, "DELAY_JUMP_FIRST_MATCH_NEW_FRAME", 1);

    const sw: usize = @intCast(switch_frame[0]);
    const begin_new: usize = @intCast(first_new[0]);

    // 切换前估计应围绕旧延迟。
    for (sw..@min(sw + 120, est_delay.len)) |i| {
        if (est_delay[i] >= 0) {
            try std.testing.expect(@abs(est_delay[i] - true_delay[sw - 1]) <= 4);
        }
    }

    // 命中新延迟后，尾段应稳定围绕新延迟。
    for (begin_new..est_delay.len) |i| {
        if (est_delay[i] >= 0) {
            try std.testing.expect(@abs(est_delay[i] - true_delay[i]) <= 4);
        }
    }
}
