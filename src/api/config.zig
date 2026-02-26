//! Ported from: docs/aec3-rs-src/api/config.rs
const std = @import("std");

/// Main configuration structure for the Echo Canceller 3.
pub const EchoCanceller3Config = struct {
    buffering: Buffering = Buffering.default(),
    delay: Delay = Delay.default(),
    filter: Filter = Filter.default(),
    erle: Erle = Erle.default(),
    ep_strength: EpStrength = EpStrength.default(),
    echo_audibility: EchoAudibility = EchoAudibility.default(),
    render_levels: RenderLevels = RenderLevels.default(),
    echo_removal_control: EchoRemovalControl = EchoRemovalControl.default(),
    transparent_mode: TransparentModeConfig = TransparentModeConfig.default(),
    echo_model: EchoModel = EchoModel.default(),
    suppressor: Suppressor = Suppressor.default(),

    /// Returns the default configuration.
    pub fn default() EchoCanceller3Config {
        return .{};
    }

    /// Validates and corrects configuration values. Returns false if any corrections were made.
    pub fn validate(self: *EchoCanceller3Config) bool {
        var res = true;

        if (self.delay.down_sampling_factor != 4 and self.delay.down_sampling_factor != 8) {
            self.delay.down_sampling_factor = 4;
            res = false;
        }

        res = limit_usize(&self.delay.default_delay, 0, 5000) and res;
        res = limit_usize(&self.delay.num_filters, 0, 5000) and res;
        res = limit_usize(&self.delay.delay_headroom_samples, 0, 5000) and res;
        res = limit_usize(&self.delay.hysteresis_limit_blocks, 0, 5000) and res;
        res = limit_usize(&self.delay.fixed_capture_delay_samples, 0, 5000) and res;
        res = limit_f32(&self.delay.delay_estimate_smoothing, 0.0, 1.0) and res;
        res = limit_f32(&self.delay.delay_candidate_detection_threshold, 0.0, 1.0) and res;
        res = limit_i32(&self.delay.delay_selection_thresholds.initial, 1, 250) and res;
        res = limit_i32(&self.delay.delay_selection_thresholds.converged, 1, 250) and res;

        res = floor_limit_usize(&self.filter.main.length_blocks, 1) and res;
        res = limit_f32(&self.filter.main.leakage_converged, 0.0, 1000.0) and res;
        res = limit_f32(&self.filter.main.leakage_diverged, 0.0, 1000.0) and res;
        res = limit_f32(&self.filter.main.error_floor, 0.0, 1000.0) and res;
        res = limit_f32(&self.filter.main.error_ceil, 0.0, 100_000_000.0) and res;
        res = limit_f32(&self.filter.main.noise_gate, 0.0, 100_000_000.0) and res;

        res = floor_limit_usize(&self.filter.main_initial.length_blocks, 1) and res;
        res = limit_f32(&self.filter.main_initial.leakage_converged, 0.0, 1000.0) and res;
        res = limit_f32(&self.filter.main_initial.leakage_diverged, 0.0, 1000.0) and res;
        res = limit_f32(&self.filter.main_initial.error_floor, 0.0, 1000.0) and res;
        res = limit_f32(&self.filter.main_initial.error_ceil, 0.0, 100_000_000.0) and res;
        res = limit_f32(&self.filter.main_initial.noise_gate, 0.0, 100_000_000.0) and res;

        if (self.filter.main.length_blocks < self.filter.main_initial.length_blocks) {
            self.filter.main_initial.length_blocks = self.filter.main.length_blocks;
            res = false;
        }

        res = floor_limit_usize(&self.filter.shadow.length_blocks, 1) and res;
        res = limit_f32(&self.filter.shadow.rate, 0.0, 1.0) and res;
        res = limit_f32(&self.filter.shadow.noise_gate, 0.0, 100_000_000.0) and res;

        res = floor_limit_usize(&self.filter.shadow_initial.length_blocks, 1) and res;
        res = limit_f32(&self.filter.shadow_initial.rate, 0.0, 1.0) and res;
        res = limit_f32(&self.filter.shadow_initial.noise_gate, 0.0, 100_000_000.0) and res;

        if (self.filter.shadow.length_blocks < self.filter.shadow_initial.length_blocks) {
            self.filter.shadow_initial.length_blocks = self.filter.shadow.length_blocks;
            res = false;
        }

        res = limit_usize(&self.filter.config_change_duration_blocks, 0, 100_000) and res;
        res = limit_f32(&self.filter.initial_state_seconds, 0.0, 100.0) and res;
        res = limit_usize(&self.filter.shadow_reset_hangover_blocks, 0, 250_000) and res;

        res = limit_f32(&self.erle.min, 1.0, 100_000.0) and res;
        res = limit_f32(&self.erle.max_l, 1.0, 100_000.0) and res;
        res = limit_f32(&self.erle.max_h, 1.0, 100_000.0) and res;
        if (self.erle.min > self.erle.max_l or self.erle.min > self.erle.max_h) {
            self.erle.min = @min(self.erle.max_l, self.erle.max_h);
            res = false;
        }
        res = limit_usize(&self.erle.num_sections, 1, self.filter.main.length_blocks) and res;

        res = limit_f32(&self.ep_strength.default_gain, 0.0, 1_000_000.0) and res;
        res = limit_f32(&self.ep_strength.default_len, -1.0, 1.0) and res;

        const max_power: f32 = 32_768.0 * 32_768.0;
        res = limit_f32(&self.echo_audibility.low_render_limit, 0.0, max_power) and res;
        res = limit_f32(&self.echo_audibility.normal_render_limit, 0.0, max_power) and res;
        res = limit_f32(&self.echo_audibility.floor_power, 0.0, max_power) and res;
        res = limit_f32(&self.echo_audibility.audibility_threshold_lf, 0.0, max_power) and res;
        res = limit_f32(&self.echo_audibility.audibility_threshold_mf, 0.0, max_power) and res;
        res = limit_f32(&self.echo_audibility.audibility_threshold_hf, 0.0, max_power) and res;

        res = limit_f32(&self.render_levels.active_render_limit, 0.0, max_power) and res;
        res = limit_f32(&self.render_levels.poor_excitation_render_limit, 0.0, max_power) and res;
        res = limit_f32(&self.render_levels.poor_excitation_render_limit_ds8, 0.0, max_power) and res;

        res = limit_usize(&self.echo_model.noise_floor_hold, 0, 1000) and res;
        res = limit_f32(&self.echo_model.min_noise_floor_power, 0.0, 2_000_000.0) and res;
        res = limit_f32(&self.echo_model.stationary_gate_slope, 0.0, 1_000_000.0) and res;
        res = limit_f32(&self.echo_model.noise_gate_power, 0.0, 1_000_000.0) and res;
        res = limit_f32(&self.echo_model.noise_gate_slope, 0.0, 1_000_000.0) and res;
        res = limit_usize(&self.echo_model.render_pre_window_size, 0, 100) and res;
        res = limit_usize(&self.echo_model.render_post_window_size, 0, 100) and res;

        res = limit_usize(&self.suppressor.nearend_average_blocks, 1, 5000) and res;
        res = limit_f32(&self.suppressor.normal_tuning.mask_lf.enr_transparent, 0.0, 100.0) and res;
        res = limit_f32(&self.suppressor.normal_tuning.mask_lf.enr_suppress, 0.0, 100.0) and res;
        res = limit_f32(&self.suppressor.normal_tuning.mask_lf.emr_transparent, 0.0, 100.0) and res;
        res = limit_f32(&self.suppressor.normal_tuning.mask_hf.enr_transparent, 0.0, 100.0) and res;
        res = limit_f32(&self.suppressor.normal_tuning.mask_hf.enr_suppress, 0.0, 100.0) and res;
        res = limit_f32(&self.suppressor.normal_tuning.mask_hf.emr_transparent, 0.0, 100.0) and res;
        res = limit_f32(&self.suppressor.normal_tuning.max_inc_factor, 0.0, 100.0) and res;
        res = limit_f32(&self.suppressor.normal_tuning.max_dec_factor_lf, 0.0, 100.0) and res;

        res = limit_f32(&self.suppressor.nearend_tuning.mask_lf.enr_transparent, 0.0, 100.0) and res;
        res = limit_f32(&self.suppressor.nearend_tuning.mask_lf.enr_suppress, 0.0, 100.0) and res;
        res = limit_f32(&self.suppressor.nearend_tuning.mask_lf.emr_transparent, 0.0, 100.0) and res;
        res = limit_f32(&self.suppressor.nearend_tuning.mask_hf.enr_transparent, 0.0, 100.0) and res;
        res = limit_f32(&self.suppressor.nearend_tuning.mask_hf.enr_suppress, 0.0, 100.0) and res;
        res = limit_f32(&self.suppressor.nearend_tuning.mask_hf.emr_transparent, 0.0, 100.0) and res;
        res = limit_f32(&self.suppressor.nearend_tuning.max_inc_factor, 0.0, 100.0) and res;
        res = limit_f32(&self.suppressor.nearend_tuning.max_dec_factor_lf, 0.0, 100.0) and res;

        res = limit_f32(&self.suppressor.dominant_nearend_detection.enr_threshold, 0.0, 1_000_000.0) and res;
        res = limit_f32(&self.suppressor.dominant_nearend_detection.snr_threshold, 0.0, 1_000_000.0) and res;
        res = limit_usize(&self.suppressor.dominant_nearend_detection.hold_duration, 0, 10_000) and res;
        res = limit_usize(&self.suppressor.dominant_nearend_detection.trigger_threshold, 0, 10_000) and res;

        res = limit_usize(&self.suppressor.subband_nearend_detection.nearend_average_blocks, 1, 1024) and res;
        res = limit_usize(&self.suppressor.subband_nearend_detection.subband1.low, 0, 65) and res;
        res = limit_usize(
            &self.suppressor.subband_nearend_detection.subband1.high,
            self.suppressor.subband_nearend_detection.subband1.low,
            65,
        ) and res;
        res = limit_usize(&self.suppressor.subband_nearend_detection.subband2.low, 0, 65) and res;
        res = limit_usize(
            &self.suppressor.subband_nearend_detection.subband2.high,
            self.suppressor.subband_nearend_detection.subband2.low,
            65,
        ) and res;
        res = limit_f32(&self.suppressor.subband_nearend_detection.nearend_threshold, 0.0, 1.0e24) and res;
        res = limit_f32(&self.suppressor.subband_nearend_detection.snr_threshold, 0.0, 1.0e24) and res;

        res = limit_f32(&self.suppressor.high_bands_suppression.enr_threshold, 0.0, 1_000_000.0) and res;
        res = limit_f32(&self.suppressor.high_bands_suppression.max_gain_during_echo, 0.0, 1.0) and res;
        res = limit_f32(&self.suppressor.high_bands_suppression.anti_howling_activation_threshold, 0.0, max_power) and res;
        res = limit_f32(&self.suppressor.high_bands_suppression.anti_howling_gain, 0.0, 1.0) and res;

        res = limit_f32(&self.suppressor.floor_first_increase, 0.0, 1_000_000.0) and res;
        return res;
    }
};

/// Buffering configuration.
pub const Buffering = struct {
    excess_render_detection_interval_blocks: usize,
    max_allowed_excess_render_blocks: usize,

    /// Returns the default buffering configuration.
    pub fn default() Buffering {
        return .{ .excess_render_detection_interval_blocks = 250, .max_allowed_excess_render_blocks = 8 };
    }
};

/// Delay estimation configuration.
pub const Delay = struct {
    default_delay: usize,
    down_sampling_factor: usize,
    num_filters: usize,
    delay_headroom_samples: usize,
    hysteresis_limit_blocks: usize,
    fixed_capture_delay_samples: usize,
    delay_estimate_smoothing: f32,
    delay_candidate_detection_threshold: f32,
    delay_selection_thresholds: DelaySelectionThresholds,
    use_external_delay_estimator: bool,
    log_warning_on_delay_changes: bool,
    render_alignment_mixing: AlignmentMixing,
    capture_alignment_mixing: AlignmentMixing,

    /// Returns the default delay configuration.
    pub fn default() Delay {
        return .{
            .default_delay = 5,
            .down_sampling_factor = 4,
            .num_filters = 5,
            .delay_headroom_samples = 32,
            .hysteresis_limit_blocks = 1,
            .fixed_capture_delay_samples = 0,
            .delay_estimate_smoothing = 0.7,
            .delay_candidate_detection_threshold = 0.2,
            .delay_selection_thresholds = .{ .initial = 5, .converged = 20 },
            .use_external_delay_estimator = false,
            .log_warning_on_delay_changes = false,
            .render_alignment_mixing = .{
                .downmix = false,
                .adaptive_selection = true,
                .activity_power_threshold = 10_000.0,
                .prefer_first_two_channels = true,
            },
            .capture_alignment_mixing = .{
                .downmix = false,
                .adaptive_selection = true,
                .activity_power_threshold = 10_000.0,
                .prefer_first_two_channels = false,
            },
        };
    }
};

/// Delay selection threshold configuration.
pub const DelaySelectionThresholds = struct {
    initial: i32,
    converged: i32,
};

/// Alignment mixing configuration.
pub const AlignmentMixing = struct {
    downmix: bool,
    adaptive_selection: bool,
    activity_power_threshold: f32,
    prefer_first_two_channels: bool,
};

/// Filter configuration.
pub const Filter = struct {
    main: MainConfiguration,
    shadow: ShadowConfiguration,
    main_initial: MainConfiguration,
    shadow_initial: ShadowConfiguration,
    config_change_duration_blocks: usize,
    initial_state_seconds: f32,
    shadow_reset_hangover_blocks: usize,
    use_shadow_reset_hangover: bool,
    conservative_initial_phase: bool,
    enable_shadow_filter_output_usage: bool,
    use_linear_filter: bool,
    export_linear_aec_output: bool,

    /// Returns the default filter configuration.
    pub fn default() Filter {
        return .{
            .main = .{
                .length_blocks = 13,
                .leakage_converged = 0.00005,
                .leakage_diverged = 0.05,
                .error_floor = 0.001,
                .error_ceil = 2.0,
                .noise_gate = 20_075_344.0,
            },
            .shadow = .{ .length_blocks = 13, .rate = 0.7, .noise_gate = 20_075_344.0 },
            .main_initial = .{
                .length_blocks = 12,
                .leakage_converged = 0.005,
                .leakage_diverged = 0.5,
                .error_floor = 0.001,
                .error_ceil = 2.0,
                .noise_gate = 20_075_344.0,
            },
            .shadow_initial = .{ .length_blocks = 12, .rate = 0.9, .noise_gate = 20_075_344.0 },
            .config_change_duration_blocks = 250,
            .initial_state_seconds = 2.5,
            .shadow_reset_hangover_blocks = 0,
            .use_shadow_reset_hangover = true,
            .conservative_initial_phase = false,
            .enable_shadow_filter_output_usage = true,
            .use_linear_filter = true,
            .export_linear_aec_output = false,
        };
    }
};

/// Main filter configuration.
pub const MainConfiguration = struct {
    length_blocks: usize,
    leakage_converged: f32,
    leakage_diverged: f32,
    error_floor: f32,
    error_ceil: f32,
    noise_gate: f32,
};

/// Shadow filter configuration.
pub const ShadowConfiguration = struct {
    length_blocks: usize,
    rate: f32,
    noise_gate: f32,
};

/// Echo Return Loss Enhancement configuration.
pub const Erle = struct {
    min: f32,
    max_l: f32,
    max_h: f32,
    onset_detection: bool,
    num_sections: usize,
    clamp_quality_estimate_to_zero: bool,
    clamp_quality_estimate_to_one: bool,

    /// Returns the default ERLE configuration.
    pub fn default() Erle {
        return .{
            .min = 1.0,
            .max_l = 4.0,
            .max_h = 1.5,
            .onset_detection = true,
            .num_sections = 1,
            .clamp_quality_estimate_to_zero = true,
            .clamp_quality_estimate_to_one = true,
        };
    }
};

/// Echo path strength configuration.
pub const EpStrength = struct {
    default_gain: f32,
    default_len: f32,
    echo_can_saturate: bool,
    bounded_erl: bool,

    /// Returns the default EP strength configuration.
    pub fn default() EpStrength {
        return .{ .default_gain = 1.0, .default_len = 0.83, .echo_can_saturate = true, .bounded_erl = false };
    }
};

/// Echo audibility configuration.
pub const EchoAudibility = struct {
    low_render_limit: f32,
    normal_render_limit: f32,
    floor_power: f32,
    audibility_threshold_lf: f32,
    audibility_threshold_mf: f32,
    audibility_threshold_hf: f32,
    use_stationarity_properties: bool,
    use_stationarity_properties_at_init: bool,

    /// Returns the default echo audibility configuration.
    pub fn default() EchoAudibility {
        return .{
            .low_render_limit = 4.0 * 64.0,
            .normal_render_limit = 64.0,
            .floor_power = 2.0 * 64.0,
            .audibility_threshold_lf = 10.0,
            .audibility_threshold_mf = 10.0,
            .audibility_threshold_hf = 10.0,
            .use_stationarity_properties = false,
            .use_stationarity_properties_at_init = false,
        };
    }
};

/// Render levels configuration.
pub const RenderLevels = struct {
    active_render_limit: f32,
    poor_excitation_render_limit: f32,
    poor_excitation_render_limit_ds8: f32,
    render_power_gain_db: f32,

    /// Returns the default render levels configuration.
    pub fn default() RenderLevels {
        return .{ .active_render_limit = 100.0, .poor_excitation_render_limit = 150.0, .poor_excitation_render_limit_ds8 = 20.0, .render_power_gain_db = 0.0 };
    }
};

/// Echo removal control configuration.
pub const EchoRemovalControl = struct {
    has_clock_drift: bool,
    linear_and_stable_echo_path: bool,

    /// Returns the default echo removal control configuration.
    pub fn default() EchoRemovalControl {
        return .{ .has_clock_drift = false, .linear_and_stable_echo_path = false };
    }
};

/// Transparent mode configuration.
pub const TransparentModeConfig = struct {
    enabled: bool,
    use_hmm: bool,

    /// Returns the default transparent mode configuration.
    pub fn default() TransparentModeConfig {
        return .{ .enabled = true, .use_hmm = false };
    }
};

/// Echo model configuration.
pub const EchoModel = struct {
    noise_floor_hold: usize,
    min_noise_floor_power: f32,
    stationary_gate_slope: f32,
    noise_gate_power: f32,
    noise_gate_slope: f32,
    render_pre_window_size: usize,
    render_post_window_size: usize,

    /// Returns the default echo model configuration.
    pub fn default() EchoModel {
        return .{
            .noise_floor_hold = 50,
            .min_noise_floor_power = 1_638_400.0,
            .stationary_gate_slope = 10.0,
            .noise_gate_power = 27_509.42,
            .noise_gate_slope = 0.3,
            .render_pre_window_size = 1,
            .render_post_window_size = 1,
        };
    }
};

/// Echo suppressor configuration.
pub const Suppressor = struct {
    nearend_average_blocks: usize,
    normal_tuning: Tuning,
    nearend_tuning: Tuning,
    dominant_nearend_detection: DominantNearendDetection,
    subband_nearend_detection: SubbandNearendDetection,
    use_subband_nearend_detection: bool,
    high_bands_suppression: HighBandsSuppression,
    floor_first_increase: f32,

    /// Returns the default suppressor configuration.
    pub fn default() Suppressor {
        return .{
            .nearend_average_blocks = 4,
            .normal_tuning = Tuning.init(
                MaskingThresholds.init(0.3, 0.4, 0.3),
                MaskingThresholds.init(0.07, 0.1, 0.3),
                2.0,
                0.25,
            ),
            .nearend_tuning = Tuning.init(
                MaskingThresholds.init(1.09, 1.1, 0.3),
                MaskingThresholds.init(0.1, 0.3, 0.3),
                2.0,
                0.25,
            ),
            .dominant_nearend_detection = .{
                .enr_threshold = 0.25,
                .enr_exit_threshold = 10.0,
                .snr_threshold = 30.0,
                .hold_duration = 50,
                .trigger_threshold = 12,
                .use_during_initial_phase = true,
            },
            .subband_nearend_detection = .{
                .nearend_average_blocks = 1,
                .subband1 = .{ .low = 1, .high = 1 },
                .subband2 = .{ .low = 1, .high = 1 },
                .nearend_threshold = 1.0,
                .snr_threshold = 1.0,
            },
            .use_subband_nearend_detection = false,
            .high_bands_suppression = .{
                .enr_threshold = 1.0,
                .max_gain_during_echo = 1.0,
                .anti_howling_activation_threshold = 25.0,
                .anti_howling_gain = 0.01,
            },
            .floor_first_increase = 0.00001,
        };
    }
};

/// Masking thresholds for echo suppression.
pub const MaskingThresholds = struct {
    enr_transparent: f32,
    enr_suppress: f32,
    emr_transparent: f32,

    /// Creates a new MaskingThresholds instance.
    pub fn init(enr_transparent: f32, enr_suppress: f32, emr_transparent: f32) MaskingThresholds {
        return .{ .enr_transparent = enr_transparent, .enr_suppress = enr_suppress, .emr_transparent = emr_transparent };
    }
};

/// Tuning parameters for echo suppression.
pub const Tuning = struct {
    mask_lf: MaskingThresholds,
    mask_hf: MaskingThresholds,
    max_inc_factor: f32,
    max_dec_factor_lf: f32,

    /// Creates a new Tuning instance.
    pub fn init(mask_lf: MaskingThresholds, mask_hf: MaskingThresholds, max_inc_factor: f32, max_dec_factor_lf: f32) Tuning {
        return .{ .mask_lf = mask_lf, .mask_hf = mask_hf, .max_inc_factor = max_inc_factor, .max_dec_factor_lf = max_dec_factor_lf };
    }
};

/// Dominant nearend detection configuration.
pub const DominantNearendDetection = struct {
    enr_threshold: f32,
    enr_exit_threshold: f32,
    snr_threshold: f32,
    hold_duration: usize,
    trigger_threshold: usize,
    use_during_initial_phase: bool,
};

/// Subband nearend detection configuration.
pub const SubbandNearendDetection = struct {
    nearend_average_blocks: usize,
    subband1: SubbandRegion,
    subband2: SubbandRegion,
    nearend_threshold: f32,
    snr_threshold: f32,
};

/// Subband frequency region.
pub const SubbandRegion = struct {
    low: usize,
    high: usize,
};

/// High bands suppression configuration.
pub const HighBandsSuppression = struct {
    enr_threshold: f32,
    max_gain_during_echo: f32,
    anti_howling_activation_threshold: f32,
    anti_howling_gain: f32,
};

fn limit_f32(value: *f32, min_value: f32, max_value: f32) bool {
    var clamped = @min(max_value, @max(min_value, value.*));
    if (!std.math.isFinite(clamped)) {
        clamped = min_value;
    }
    const unchanged = value.* == clamped;
    value.* = clamped;
    return unchanged;
}

fn limit_usize(value: *usize, min_value: usize, max_value: usize) bool {
    const clamped = @min(max_value, @max(min_value, value.*));
    const unchanged = value.* == clamped;
    value.* = clamped;
    return unchanged;
}

fn floor_limit_usize(value: *usize, min_value: usize) bool {
    if (value.* < min_value) {
        value.* = min_value;
        return false;
    }
    return true;
}

fn limit_i32(value: *i32, min_value: i32, max_value: i32) bool {
    const clamped = @min(max_value, @max(min_value, value.*));
    const unchanged = value.* == clamped;
    value.* = clamped;
    return unchanged;
}

test "test_default_values" {
    const cfg = EchoCanceller3Config.default();
    try std.testing.expectEqual(@as(usize, 4), cfg.delay.down_sampling_factor);
    try std.testing.expectEqual(@as(usize, 13), cfg.filter.main.length_blocks);
    try std.testing.expectEqual(@as(f32, 1.0), cfg.erle.min);
}

test "test_validate_default_passes" {
    var cfg = EchoCanceller3Config.default();
    try std.testing.expect(cfg.validate());
}

test "test_validate_catches_invalid" {
    var cfg = EchoCanceller3Config.default();
    cfg.delay.down_sampling_factor = 3;
    const ok = cfg.validate();
    try std.testing.expect(!ok);
    try std.testing.expectEqual(@as(usize, 4), cfg.delay.down_sampling_factor);
}

test "test_default_and_init_matrix" {
    const buffering = Buffering.default();
    try std.testing.expectEqual(@as(usize, 250), buffering.excess_render_detection_interval_blocks);
    try std.testing.expectEqual(@as(usize, 8), buffering.max_allowed_excess_render_blocks);

    const delay = Delay.default();
    try std.testing.expectEqual(@as(usize, 4), delay.down_sampling_factor);
    try std.testing.expectEqual(@as(usize, 5), delay.default_delay);

    const filter = Filter.default();
    try std.testing.expectEqual(@as(usize, 13), filter.main.length_blocks);
    try std.testing.expectEqual(@as(usize, 12), filter.main_initial.length_blocks);

    const erle = Erle.default();
    try std.testing.expectEqual(@as(f32, 1.0), erle.min);
    const ep = EpStrength.default();
    try std.testing.expectEqual(@as(f32, 0.83), ep.default_len);
    const audibility = EchoAudibility.default();
    try std.testing.expectEqual(@as(f32, 64.0), audibility.normal_render_limit);
    const levels = RenderLevels.default();
    try std.testing.expectEqual(@as(f32, 20.0), levels.poor_excitation_render_limit_ds8);
    const removal = EchoRemovalControl.default();
    try std.testing.expect(!removal.has_clock_drift);
    const transparent = TransparentModeConfig.default();
    try std.testing.expect(transparent.enabled);
    const model = EchoModel.default();
    try std.testing.expectEqual(@as(usize, 50), model.noise_floor_hold);
    const suppressor = Suppressor.default();
    try std.testing.expectEqual(@as(usize, 4), suppressor.nearend_average_blocks);

    const mask = MaskingThresholds.init(-1.0, 101.0, 0.5);
    try std.testing.expectEqual(@as(f32, -1.0), mask.enr_transparent);
    try std.testing.expectEqual(@as(f32, 101.0), mask.enr_suppress);
    const tuning = Tuning.init(mask, mask, 0.0, 100.0);
    try std.testing.expectEqual(@as(f32, 0.0), tuning.max_inc_factor);
    try std.testing.expectEqual(@as(f32, 100.0), tuning.max_dec_factor_lf);
}

test "test_validate_min_max_and_just_outside_bounds" {
    var cfg = EchoCanceller3Config.default();

    cfg.delay.default_delay = 0;
    cfg.delay.num_filters = 5000;
    cfg.delay.delay_headroom_samples = 5001; // just above max
    cfg.delay.delay_estimate_smoothing = -0.01; // just below min
    cfg.delay.delay_candidate_detection_threshold = 1.01; // just above max

    cfg.filter.main.length_blocks = 0; // floor limit
    cfg.filter.main.error_floor = -1.0;
    cfg.filter.main.error_ceil = 100_000_001.0;

    cfg.erle.min = 100_001.0;
    cfg.erle.max_l = 1.0;
    cfg.erle.max_h = 2.0;

    cfg.suppressor.subband_nearend_detection.subband1.low = 66;
    cfg.suppressor.subband_nearend_detection.subband1.high = 0;
    cfg.suppressor.high_bands_suppression.max_gain_during_echo = 2.0;

    const ok = cfg.validate();
    try std.testing.expect(!ok);

    try std.testing.expectEqual(@as(usize, 5000), cfg.delay.delay_headroom_samples);
    try std.testing.expectEqual(@as(f32, 0.0), cfg.delay.delay_estimate_smoothing);
    try std.testing.expectEqual(@as(f32, 1.0), cfg.delay.delay_candidate_detection_threshold);
    try std.testing.expectEqual(@as(usize, 1), cfg.filter.main.length_blocks);
    try std.testing.expectEqual(@as(f32, 0.0), cfg.filter.main.error_floor);
    try std.testing.expectEqual(@as(f32, 100_000_000.0), cfg.filter.main.error_ceil);
    try std.testing.expectEqual(@as(f32, 1.0), cfg.erle.min);
    try std.testing.expectEqual(@as(usize, 65), cfg.suppressor.subband_nearend_detection.subband1.low);
    try std.testing.expectEqual(@as(usize, 65), cfg.suppressor.subband_nearend_detection.subband1.high);
    try std.testing.expectEqual(@as(f32, 1.0), cfg.suppressor.high_bands_suppression.max_gain_during_echo);
}

test "test_validate_sanitizes_nan_and_infinity" {
    var cfg = EchoCanceller3Config.default();
    cfg.delay.delay_estimate_smoothing = std.math.nan(f32);
    cfg.filter.main.leakage_converged = std.math.inf(f32);
    cfg.filter.main.leakage_diverged = -std.math.inf(f32);
    cfg.echo_model.noise_gate_slope = std.math.nan(f32);
    cfg.suppressor.normal_tuning.max_inc_factor = std.math.inf(f32);

    const ok = cfg.validate();
    try std.testing.expect(!ok);

    try std.testing.expectEqual(@as(f32, 0.0), cfg.delay.delay_estimate_smoothing);
    try std.testing.expectEqual(@as(f32, 1000.0), cfg.filter.main.leakage_converged);
    try std.testing.expectEqual(@as(f32, 0.0), cfg.filter.main.leakage_diverged);
    try std.testing.expectEqual(@as(f32, 0.0), cfg.echo_model.noise_gate_slope);
    try std.testing.expectEqual(@as(f32, 100.0), cfg.suppressor.normal_tuning.max_inc_factor);
}
