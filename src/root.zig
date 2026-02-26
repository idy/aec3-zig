//! AEC3 - Acoustic Echo Canceller 3 (Zig port)
//! Fixed-point-first implementation

// 数值模式与配置
pub const NumericMode = @import("numeric_mode.zig").NumericMode;
pub const profileFor = @import("numeric_profile.zig").profileFor;
pub const DEFAULT_NUMERIC_MODE = @import("numeric_profile.zig").DEFAULT_NUMERIC_MODE;
pub const DefaultNumericProfile = @import("numeric_profile.zig").DefaultProfile;

// 核心数值类型
pub const SampleOps = @import("sample_ops.zig").SampleOps;
pub const FixedPoint = @import("fixed_point.zig").FixedPoint;
pub const Complex = @import("complex.zig").Complex;

// FFT 子系统
pub const FftCore = @import("audio_processing/fft_core.zig").FftCore;
pub const isPowerOfTwo = @import("audio_processing/fft_core.zig").isPowerOfTwo;
pub const Aec3Fft = @import("audio_processing/aec3/aec3_fft.zig").Aec3Fft;
pub const Aec3Window = @import("audio_processing/aec3/aec3_fft.zig").Window;
pub const Aec3FftData = @import("audio_processing/aec3/fft_data.zig").FftData;
pub const NrFft = @import("audio_processing/ns/ns_fft.zig").NrFft;
pub const NsConfig = @import("audio_processing/ns/ns_config.zig").NsConfig;
pub const SuppressionLevel = @import("audio_processing/ns/ns_config.zig").SuppressionLevel;
pub const NoiseSuppressor = @import("audio_processing/ns/noise_suppressor.zig").NoiseSuppressor;

// Foundation 模块
pub const Aec3Common = @import("audio_processing/aec3/aec3_common.zig");
pub const DelayEstimate = @import("audio_processing/aec3/delay_estimate.zig");
pub const EchoPathVariability = @import("audio_processing/aec3/echo_path_variability.zig");
pub const FftData = @import("audio_processing/aec3/fft_data.zig");
pub const ChannelLayout = @import("audio_processing/channel_layout.zig").ChannelLayout;
pub const StreamConfig = @import("audio_processing/stream_config.zig").StreamConfig;
pub const AudioUtil = @import("audio_processing/audio_util.zig");
pub const AudioFrame = @import("audio_processing/audio_frame.zig").AudioFrame;
pub const ChannelBuffer = @import("audio_processing/channel_buffer.zig").ChannelBuffer;
pub const IFChannelBuffer = @import("audio_processing/channel_buffer.zig").IFChannelBuffer;
pub const Config = @import("api/config.zig");
pub const Control = @import("api/control.zig");
pub const ApmDataDumper = @import("audio_processing/logging/apm_data_dumper.zig").ApmDataDumper;

// 测试入口（仅测试时编译）
test {
    _ = @import("numeric_mode.zig");
    _ = @import("numeric_profile.zig");
    _ = @import("sample_ops.zig");
    _ = @import("fixed_point.zig");
    _ = @import("complex.zig");
    _ = @import("audio_processing/aec3/aec3_common.zig");
    _ = @import("audio_processing/aec3/delay_estimate.zig");
    _ = @import("audio_processing/aec3/echo_path_variability.zig");
    _ = @import("audio_processing/aec3/fft_data.zig");
    _ = @import("audio_processing/channel_layout.zig");
    _ = @import("audio_processing/stream_config.zig");
    _ = @import("audio_processing/audio_util.zig");
    _ = @import("audio_processing/audio_frame.zig");
    _ = @import("audio_processing/channel_buffer.zig");
    _ = @import("api/config.zig");
    _ = @import("api/control.zig");
    _ = @import("audio_processing/logging/apm_data_dumper.zig");
    _ = @import("audio_processing/ns/ns_common.zig");
    _ = @import("audio_processing/ns/ns_config.zig");
    _ = @import("audio_processing/ns/ns_fft.zig");
    _ = @import("audio_processing/ns/fast_math.zig");
    _ = @import("audio_processing/ns/suppression_params.zig");
    _ = @import("audio_processing/ns/prior_signal_model.zig");
    _ = @import("audio_processing/ns/signal_model.zig");
    _ = @import("audio_processing/ns/histograms.zig");
    _ = @import("audio_processing/ns/quantile_noise_estimator.zig");
    _ = @import("audio_processing/ns/prior_signal_model_estimator.zig");
    _ = @import("audio_processing/ns/noise_estimator.zig");
    _ = @import("audio_processing/ns/signal_model_estimator.zig");
    _ = @import("audio_processing/ns/speech_probability_estimator.zig");
    _ = @import("audio_processing/ns/wiener_filter.zig");
    _ = @import("audio_processing/ns/noise_suppressor.zig");
    _ = @import("test.zig");
    _ = @import("fft_test.zig");
    _ = @import("foundation_extra_test.zig");
    _ = @import("foundation_fixed_float_test.zig");
    _ = @import("test_golden_foundation.zig");
    _ = @import("test_support/smoke_fir.zig");
}
