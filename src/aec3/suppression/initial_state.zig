const std = @import("std");
const aec3_common = @import("../common/aec3_common.zig");

const NUM_BLOCKS_PER_SECOND = aec3_common.NUM_BLOCKS_PER_SECOND;
const FFT_LENGTH_BY_2_PLUS_1 = aec3_common.FFT_LENGTH_BY_2_PLUS_1;

/// Manages the initial-state phase of the AEC.
///
/// During the initial phase, conservative gains are applied until enough
/// "strong render" blocks have been observed.  Once the threshold is reached
/// the system deactivates the initial phase and signals a one-shot transition.
pub const InitialState = struct {
    active: bool,
    transition_triggered: bool,
    strong_render_blocks: usize,
    threshold_blocks: usize,

    pub fn init(initial_state_seconds: f32) !InitialState {
        if (initial_state_seconds < 0.0) return error.InvalidDuration;
        const threshold: usize = @intFromFloat(initial_state_seconds * @as(f32, @floatFromInt(NUM_BLOCKS_PER_SECOND)));
        return .{
            .active = true,
            .transition_triggered = false,
            .strong_render_blocks = 0,
            .threshold_blocks = threshold,
        };
    }

    /// Advances the initial-state counter.
    ///
    /// While active and the capture is not saturated, each `active_render`
    /// block increments the counter.  When the counter reaches
    /// `threshold_blocks` the phase is deactivated and
    /// `transition_triggered` is set for exactly one call.
    pub fn update(self: *InitialState, active_render: bool, saturated_capture: bool) void {
        // Clear the one-shot flag from any previous call.
        self.transition_triggered = false;

        if (!self.active) return;
        if (saturated_capture) return;

        if (active_render) {
            self.strong_render_blocks += 1;
        }

        if (self.strong_render_blocks >= self.threshold_blocks) {
            self.active = false;
            self.transition_triggered = true;
        }
    }

    pub fn is_active(self: *const InitialState) bool {
        return self.active;
    }

    pub fn was_transition_triggered(self: *const InitialState) bool {
        return self.transition_triggered;
    }

    pub fn reset(self: *InitialState) void {
        self.active = true;
        self.transition_triggered = false;
        self.strong_render_blocks = 0;
    }

    /// Fills `gains` with a linear ramp from 0.5 to approximately 1.0.
    ///
    /// gains[i] = 0.5 + (i / FFT_LENGTH_BY_2_PLUS_1) * 0.5
    ///
    /// This matches the golden vector expectation for the initial-state
    /// conservative gain curve.
    pub fn compute_initial_gains(gains: []f32) !void {
        if (gains.len != FFT_LENGTH_BY_2_PLUS_1) return error.LengthMismatch;
        const len_f: f32 = @floatFromInt(FFT_LENGTH_BY_2_PLUS_1);
        for (0..FFT_LENGTH_BY_2_PLUS_1) |i| {
            const t: f32 = @as(f32, @floatFromInt(i)) / len_f;
            gains[i] = 0.5 + t * 0.5;
        }
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "initial_state ramp pattern" {
    var gains: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;
    try InitialState.compute_initial_gains(&gains);

    // First bin should be exactly 0.5.
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), gains[0], 1e-6);

    // Gains must be monotonically non-decreasing and in [0.5, 1.0).
    for (gains, 0..) |g, i| {
        try std.testing.expect(g >= 0.5 and g < 1.0);
        if (i > 0) {
            try std.testing.expect(g >= gains[i - 1]);
        }
    }
}

test "initial_state ramp golden formula" {
    var gains: [FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;
    try InitialState.compute_initial_gains(&gains);

    const len_f: f32 = @floatFromInt(FFT_LENGTH_BY_2_PLUS_1);
    for (0..FFT_LENGTH_BY_2_PLUS_1) |i| {
        const expected = 0.5 + @as(f32, @floatFromInt(i)) / len_f * 0.5;
        try std.testing.expectApproxEqAbs(expected, gains[i], 1e-6);
    }
}

test "initial_state transition after threshold" {
    var state = try InitialState.init(0.04); // 0.04 * 250 = 10 blocks
    try std.testing.expect(state.is_active());

    for (0..9) |_| {
        state.update(true, false);
    }
    try std.testing.expect(state.is_active());
    try std.testing.expect(!state.was_transition_triggered());

    // Block 10 triggers the transition.
    state.update(true, false);
    try std.testing.expect(!state.is_active());
    try std.testing.expect(state.was_transition_triggered());

    // One-shot: next call clears transition_triggered.
    state.update(true, false);
    try std.testing.expect(!state.was_transition_triggered());
}

test "initial_state saturated capture pauses counting" {
    var state = try InitialState.init(0.008); // 2 blocks
    state.update(true, true); // saturated – should not count
    try std.testing.expect(state.is_active());
    state.update(true, false);
    try std.testing.expect(state.is_active());
    state.update(true, false);
    try std.testing.expect(!state.is_active());
}

test "initial_state reset behavior" {
    var state = try InitialState.init(0.004); // 1 block
    state.update(true, false);
    try std.testing.expect(!state.is_active());

    state.reset();
    try std.testing.expect(state.is_active());
    try std.testing.expect(!state.was_transition_triggered());
    try std.testing.expectEqual(@as(usize, 0), state.strong_render_blocks);
}

test "initial_state invalid duration" {
    try std.testing.expectError(error.InvalidDuration, InitialState.init(-1.0));
}

test "initial_state length mismatch on gains" {
    var short: [10]f32 = undefined;
    try std.testing.expectError(error.LengthMismatch, InitialState.compute_initial_gains(&short));
}
