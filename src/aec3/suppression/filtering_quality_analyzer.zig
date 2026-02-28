const std = @import("std");

/// Analyzes the quality of the adaptive filtering based on input/output
/// energy ratios and convergence counters.
///
/// The linear filter is considered usable once the system has been running
/// long enough, has passed the post-reset guard interval, and either an
/// external delay has been reported or convergence has been observed.
pub const FilteringQualityAnalyzer = struct {
    blocks_since_reset: usize,
    blocks_since_start: usize,
    convergence_seen: bool,
    linear_filter_usable: bool,

    /// Minimum blocks since start before the linear filter may be used
    /// (approximately 0.4 s at 250 blocks/s).
    const MIN_BLOCKS_SINCE_START: usize = 100;
    /// Minimum blocks since the last reset before the linear filter may be
    /// used (approximately 0.2 s at 250 blocks/s).
    const MIN_BLOCKS_SINCE_RESET: usize = 50;

    pub fn init() FilteringQualityAnalyzer {
        return .{
            .blocks_since_reset = 0,
            .blocks_since_start = 0,
            .convergence_seen = false,
            .linear_filter_usable = false,
        };
    }

    /// Advances internal counters and re-evaluates whether the linear filter
    /// output is trustworthy enough to use.
    pub fn update(
        self: *FilteringQualityAnalyzer,
        active_render: bool,
        transparent_mode: bool,
        saturated_capture: bool,
        external_delay_reported: bool,
        filter_converged: bool,
    ) void {
        _ = active_render;
        _ = saturated_capture;

        self.blocks_since_start +|= 1;
        self.blocks_since_reset +|= 1;

        if (filter_converged) {
            self.convergence_seen = true;
        }

        self.linear_filter_usable =
            self.blocks_since_start > MIN_BLOCKS_SINCE_START and
            self.blocks_since_reset > MIN_BLOCKS_SINCE_RESET and
            (external_delay_reported or self.convergence_seen) and
            !transparent_mode;
    }

    /// Returns the filtering quality as `1 - output_energy / input_energy`,
    /// clamped to [0, 1].  Returns `error.InvalidInputEnergy` when the
    /// denominator is non-positive.
    pub fn compute_quality(input_energy: f32, output_energy: f32) !f32 {
        if (input_energy <= 0.0) return error.InvalidInputEnergy;
        const ratio = output_energy / input_energy;
        return std.math.clamp(1.0 - ratio, 0.0, 1.0);
    }

    pub fn is_linear_filter_usable(self: *const FilteringQualityAnalyzer) bool {
        return self.linear_filter_usable;
    }

    /// Resets the post-reset counter; convergence_seen and blocks_since_start
    /// are *not* cleared so startup history is preserved.
    pub fn reset(self: *FilteringQualityAnalyzer) void {
        self.blocks_since_reset = 0;
        self.linear_filter_usable = false;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "filtering_quality_analyzer good quality" {
    const q = try FilteringQualityAnalyzer.compute_quality(100.0, 5.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.95), q, 1e-6);
}

test "filtering_quality_analyzer poor quality" {
    const q = try FilteringQualityAnalyzer.compute_quality(100.0, 90.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), q, 1e-6);
}

test "filtering_quality_analyzer output exceeds input clamped to zero" {
    const q = try FilteringQualityAnalyzer.compute_quality(50.0, 100.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), q, 1e-9);
}

test "filtering_quality_analyzer zero input error" {
    try std.testing.expectError(error.InvalidInputEnergy, FilteringQualityAnalyzer.compute_quality(0.0, 1.0));
    try std.testing.expectError(error.InvalidInputEnergy, FilteringQualityAnalyzer.compute_quality(-1.0, 1.0));
}

test "filtering_quality_analyzer convergence tracking makes filter usable" {
    var fqa = FilteringQualityAnalyzer.init();

    // Advance past both guard intervals with convergence but no external delay.
    for (0..110) |_| {
        fqa.update(true, false, false, false, true);
    }
    try std.testing.expect(fqa.is_linear_filter_usable());
}

test "filtering_quality_analyzer not usable before start threshold" {
    var fqa = FilteringQualityAnalyzer.init();
    for (0..50) |_| {
        fqa.update(true, false, false, true, true);
    }
    try std.testing.expect(!fqa.is_linear_filter_usable());
}

test "filtering_quality_analyzer not usable in transparent mode" {
    var fqa = FilteringQualityAnalyzer.init();
    for (0..110) |_| {
        fqa.update(true, true, false, true, true);
    }
    try std.testing.expect(!fqa.is_linear_filter_usable());
}

test "filtering_quality_analyzer reset clears usability" {
    var fqa = FilteringQualityAnalyzer.init();
    for (0..110) |_| {
        fqa.update(true, false, false, true, true);
    }
    try std.testing.expect(fqa.is_linear_filter_usable());
    fqa.reset();
    try std.testing.expect(!fqa.is_linear_filter_usable());
    try std.testing.expectEqual(@as(usize, 0), fqa.blocks_since_reset);
}

test "filtering_quality_analyzer external delay alone sufficient" {
    var fqa = FilteringQualityAnalyzer.init();
    for (0..110) |_| {
        fqa.update(true, false, false, true, false);
    }
    try std.testing.expect(fqa.is_linear_filter_usable());
}
