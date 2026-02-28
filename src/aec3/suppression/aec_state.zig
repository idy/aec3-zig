const std = @import("std");
const aec3_common = @import("../common/aec3_common.zig");

const InitialState = @import("initial_state.zig").InitialState;
const FilterDelay = @import("filter_delay.zig").FilterDelay;
const TransparentMode = @import("transparent_mode.zig").TransparentMode;
const FilteringQualityAnalyzer = @import("filtering_quality_analyzer.zig").FilteringQualityAnalyzer;
const SaturationDetector = @import("saturation_detector.zig").SaturationDetector;

const NUM_BLOCKS_PER_SECOND = aec3_common.NUM_BLOCKS_PER_SECOND;

/// High-level phase of the AEC.
pub const AecPhase = enum {
    initial,
    converging,
    converged,
};

/// Configuration for `AecState`.
pub const AecStateConfig = struct {
    initial_state_seconds: f32 = 2.0,
    erle_threshold: f32 = 6.0,
    convergence_time_ms: f32 = 500.0,
    saturation_threshold: f32 = 32000.0,
};

/// Main AEC state machine coordinating all sub-state components.
pub const AecState = struct {
    initial_state: InitialState,
    filter_delay: FilterDelay,
    transparent_mode: TransparentMode,
    filtering_quality: FilteringQualityAnalyzer,
    saturation_detector: SaturationDetector,
    phase: AecPhase,
    erle_threshold: f32,
    convergence_time_blocks: usize,
    blocks_with_active_render: usize,
    capture_saturation: bool,

    pub fn init(config: AecStateConfig) !AecState {
        const convergence_blocks: usize = @intFromFloat(
            config.convergence_time_ms / 1000.0 * @as(f32, @floatFromInt(NUM_BLOCKS_PER_SECOND)),
        );
        return .{
            .initial_state = try InitialState.init(config.initial_state_seconds),
            .filter_delay = FilterDelay.init(),
            .transparent_mode = TransparentMode.init(true),
            .filtering_quality = FilteringQualityAnalyzer.init(),
            .saturation_detector = try SaturationDetector.init(config.saturation_threshold),
            .phase = .initial,
            .erle_threshold = config.erle_threshold,
            .convergence_time_blocks = convergence_blocks,
            .blocks_with_active_render = 0,
            .capture_saturation = false,
        };
    }

    /// Orchestrates one block of sub-state updates and manages phase
    /// transitions.
    pub fn update(
        self: *AecState,
        active_render: bool,
        saturated_capture: bool,
        filter_converged: bool,
        erle: f32,
        external_delay: ?i32,
    ) void {
        self.capture_saturation = saturated_capture;

        if (active_render) {
            self.blocks_with_active_render +|= 1;
        }

        // Sub-state updates.
        self.initial_state.update(active_render, saturated_capture);
        self.transparent_mode.update(active_render, filter_converged);
        self.filtering_quality.update(
            active_render,
            self.transparent_mode.is_active(),
            saturated_capture,
            self.filter_delay.is_external_delay_reported(),
            filter_converged,
        );

        if (external_delay) |d| {
            self.filter_delay.report_external_delay(d);
        }

        // Phase transitions.
        switch (self.phase) {
            .initial => {
                if (!self.initial_state.is_active()) {
                    self.phase = .converging;
                }
            },
            .converging => {
                if (filter_converged and erle >= self.erle_threshold and
                    self.blocks_with_active_render >= self.convergence_time_blocks)
                {
                    self.phase = .converged;
                }
            },
            .converged => {},
        }
    }

    pub fn get_phase(self: *const AecState) AecPhase {
        return self.phase;
    }

    pub fn is_transparent_mode(self: *const AecState) bool {
        return self.transparent_mode.is_active();
    }

    pub fn is_saturated_echo(self: *const AecState) bool {
        return self.saturation_detector.is_saturated_echo();
    }

    /// The linear estimate is usable when the system has converged past
    /// the initial phase and the filtering-quality analyzer agrees.
    pub fn usable_linear_estimate(self: *const AecState) bool {
        return self.phase != .initial and
            self.filtering_quality.is_linear_filter_usable() and
            !self.transparent_mode.is_active();
    }

    pub fn has_active_render(self: *const AecState) bool {
        return self.blocks_with_active_render > 0;
    }

    /// Signals an echo-path change by resetting convergence-sensitive
    /// sub-states while keeping the overall phase.
    pub fn handle_echo_path_change(self: *AecState) void {
        self.filtering_quality.reset();
        self.transparent_mode.reset();
        self.blocks_with_active_render = 0;
    }

    pub fn reset(self: *AecState) void {
        self.initial_state.reset();
        self.filter_delay = FilterDelay.init();
        self.transparent_mode.reset();
        self.filtering_quality = FilteringQualityAnalyzer.init();
        self.saturation_detector.reset();
        self.phase = .initial;
        self.blocks_with_active_render = 0;
        self.capture_saturation = false;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "aec_state initial phase transitions to converging" {
    var state = try AecState.init(.{ .initial_state_seconds = 0.04 }); // 10 blocks
    try std.testing.expectEqual(AecPhase.initial, state.get_phase());

    for (0..10) |_| {
        state.update(true, false, false, 0.0, null);
    }
    try std.testing.expectEqual(AecPhase.converging, state.get_phase());
}

test "aec_state converging transitions to converged" {
    var state = try AecState.init(.{
        .initial_state_seconds = 0.004, // 1 block
        .erle_threshold = 5.0,
        .convergence_time_ms = 20.0, // 5 blocks
    });

    // Exit initial phase.
    state.update(true, false, false, 0.0, null);
    try std.testing.expectEqual(AecPhase.converging, state.get_phase());

    // Accumulate active-render blocks and provide converged + high ERLE.
    for (0..10) |_| {
        state.update(true, false, true, 10.0, null);
    }
    try std.testing.expectEqual(AecPhase.converged, state.get_phase());
}

test "aec_state stays converging with low erle" {
    var state = try AecState.init(.{
        .initial_state_seconds = 0.004,
        .erle_threshold = 10.0,
        .convergence_time_ms = 4.0, // 1 block
    });

    state.update(true, false, false, 0.0, null);
    try std.testing.expectEqual(AecPhase.converging, state.get_phase());

    // Converged filter but ERLE too low.
    for (0..20) |_| {
        state.update(true, false, true, 5.0, null);
    }
    try std.testing.expectEqual(AecPhase.converging, state.get_phase());
}

test "aec_state reset returns to initial" {
    var state = try AecState.init(.{ .initial_state_seconds = 0.004 });
    state.update(true, false, false, 0.0, null);
    try std.testing.expectEqual(AecPhase.converging, state.get_phase());

    state.reset();
    try std.testing.expectEqual(AecPhase.initial, state.get_phase());
    try std.testing.expect(!state.has_active_render());
}

test "aec_state external delay reported" {
    var state = try AecState.init(.{});
    try std.testing.expect(!state.filter_delay.is_external_delay_reported());
    state.update(true, false, false, 0.0, @as(i32, 5));
    try std.testing.expect(state.filter_delay.is_external_delay_reported());
}

test "aec_state handle_echo_path_change" {
    var state = try AecState.init(.{ .initial_state_seconds = 0.004 });
    // Exit initial.
    state.update(true, false, false, 0.0, null);
    for (0..120) |_| {
        state.update(true, false, true, 10.0, @as(i32, 3));
    }
    try std.testing.expect(state.filtering_quality.is_linear_filter_usable());

    state.handle_echo_path_change();
    try std.testing.expect(!state.filtering_quality.is_linear_filter_usable());
    try std.testing.expectEqual(@as(usize, 0), state.blocks_with_active_render);
}

test "aec_state usable_linear_estimate requires conditions" {
    var state = try AecState.init(.{ .initial_state_seconds = 0.004 });
    // In initial phase – not usable.
    try std.testing.expect(!state.usable_linear_estimate());

    // Exit initial.
    state.update(true, false, false, 0.0, null);
    // Not enough blocks yet.
    try std.testing.expect(!state.usable_linear_estimate());
}

test "aec_state invalid config" {
    try std.testing.expectError(error.InvalidDuration, AecState.init(.{
        .initial_state_seconds = -1.0,
    }));
    try std.testing.expectError(error.InvalidThreshold, AecState.init(.{
        .saturation_threshold = 0.0,
    }));
}

test "aec_state saturation_detector accessible" {
    var state = try AecState.init(.{ .saturation_threshold = 0.5 });
    try std.testing.expect(!state.is_saturated_echo());
    state.saturation_detector.update_echo_saturation(&[_]f32{1.0});
    try std.testing.expect(state.is_saturated_echo());
}
