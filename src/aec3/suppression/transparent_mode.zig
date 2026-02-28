const std = @import("std");

/// Transparent-mode state machine for the AEC.
///
/// When transparent mode activates, the AEC effectively passes audio through
/// without suppression.  The decision is driven by an HMM-style probability:
/// convergence drives the probability down while extended lack of convergence
/// drives it up.
pub const TransparentMode = struct {
    enabled: bool,
    active: bool,
    prob_transparent: f32,
    active_render_blocks: usize,
    convergence_seen: bool,

    /// Activation threshold – once exceeded, transparent mode turns on.
    const ACTIVATE_THRESHOLD: f32 = 0.95;
    /// Deactivation threshold – once the probability drops below this value
    /// transparent mode turns off.
    const DEACTIVATE_THRESHOLD: f32 = 0.5;
    /// Number of render blocks without convergence before the probability
    /// starts ramping up noticeably.
    const NO_CONVERGENCE_WINDOW: usize = 500;
    /// Per-block increment when convergence is absent.
    const PROB_INCREMENT: f32 = 0.002;
    /// Per-block decrement when convergence is observed.
    const PROB_DECREMENT: f32 = 0.01;

    pub fn init(enabled: bool) TransparentMode {
        return .{
            .enabled = enabled,
            .active = false,
            .prob_transparent = 0.0,
            .active_render_blocks = 0,
            .convergence_seen = false,
        };
    }

    /// Advances the transparent-mode state machine by one block.
    pub fn update(self: *TransparentMode, active_render: bool, filter_converged: bool) void {
        if (!self.enabled) {
            self.active = false;
            return;
        }

        if (active_render) {
            self.active_render_blocks +|= 1;
        }

        if (filter_converged) {
            self.convergence_seen = true;
            self.prob_transparent = @max(self.prob_transparent - PROB_DECREMENT, 0.0);
        } else if (self.active_render_blocks > NO_CONVERGENCE_WINDOW) {
            self.prob_transparent = @min(self.prob_transparent + PROB_INCREMENT, 1.0);
        }

        if (self.prob_transparent > ACTIVATE_THRESHOLD) {
            self.active = true;
        } else if (self.prob_transparent < DEACTIVATE_THRESHOLD) {
            self.active = false;
        }
    }

    pub fn is_active(self: *const TransparentMode) bool {
        return self.active;
    }

    pub fn reset(self: *TransparentMode) void {
        self.active = false;
        self.prob_transparent = 0.0;
        self.active_render_blocks = 0;
        self.convergence_seen = false;
    }

    /// Fills `gains` with the appropriate gain values.
    ///
    /// In transparent mode every bin is set to 0.95 (near-unity pass-through).
    /// Otherwise `base_gain` is used, clamped to [0, 1].
    pub fn compute_gains(self: *const TransparentMode, base_gain: f32, gains: []f32) void {
        const g = if (self.active) @as(f32, 0.95) else std.math.clamp(base_gain, 0.0, 1.0);
        for (gains) |*slot| {
            slot.* = g;
        }
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "transparent_mode normal mode gains" {
    const tm = TransparentMode.init(false);
    var gains: [8]f32 = undefined;
    tm.compute_gains(0.6, &gains);
    for (gains) |g| {
        try std.testing.expectApproxEqAbs(@as(f32, 0.6), g, 1e-9);
    }
}

test "transparent_mode transparent gains" {
    var tm = TransparentMode.init(true);
    // Force active state by driving prob above threshold.
    tm.prob_transparent = 0.96;
    tm.active = true;
    var gains: [8]f32 = undefined;
    tm.compute_gains(0.3, &gains);
    for (gains) |g| {
        try std.testing.expectApproxEqAbs(@as(f32, 0.95), g, 1e-9);
    }
}

test "transparent_mode gain clamping" {
    const tm = TransparentMode.init(false);
    var gains: [4]f32 = undefined;
    tm.compute_gains(1.5, &gains);
    for (gains) |g| {
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), g, 1e-9);
    }
    tm.compute_gains(-0.5, &gains);
    for (gains) |g| {
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), g, 1e-9);
    }
}

test "transparent_mode disabled stays inactive" {
    var tm = TransparentMode.init(false);
    for (0..1000) |_| {
        tm.update(true, false);
    }
    try std.testing.expect(!tm.is_active());
}

test "transparent_mode enabled activates without convergence" {
    var tm = TransparentMode.init(true);
    // Drive past the no-convergence window then accumulate probability.
    for (0..1500) |_| {
        tm.update(true, false);
    }
    try std.testing.expect(tm.is_active());
}

test "transparent_mode convergence suppresses activation" {
    var tm = TransparentMode.init(true);
    for (0..1500) |_| {
        tm.update(true, true);
    }
    try std.testing.expect(!tm.is_active());
}

test "transparent_mode reset clears state" {
    var tm = TransparentMode.init(true);
    tm.prob_transparent = 0.99;
    tm.active = true;
    tm.active_render_blocks = 999;
    tm.convergence_seen = true;

    tm.reset();
    try std.testing.expect(!tm.is_active());
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), tm.prob_transparent, 1e-9);
    try std.testing.expectEqual(@as(usize, 0), tm.active_render_blocks);
    try std.testing.expect(!tm.convergence_seen);
}

test "transparent_mode transition back on convergence" {
    var tm = TransparentMode.init(true);
    // First activate.
    tm.prob_transparent = 0.96;
    tm.active = true;
    tm.active_render_blocks = 600;

    // Sustained convergence should bring it back below deactivation threshold.
    for (0..100) |_| {
        tm.update(true, true);
    }
    try std.testing.expect(!tm.is_active());
}
