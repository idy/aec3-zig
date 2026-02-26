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
pub const NsCommon = @import("audio_processing/ns/ns_common.zig");
pub const NsConfig = @import("audio_processing/ns/ns_config.zig").NsConfig;
pub const SuppressionLevel = @import("audio_processing/ns/ns_config.zig").SuppressionLevel;
pub const NoiseSuppressor = @import("audio_processing/ns/noise_suppressor.zig").NoiseSuppressor;
pub const SpeechProbabilityEstimator = @import("audio_processing/ns/speech_probability_estimator.zig").SpeechProbabilityEstimator;
pub const WienerFilter = @import("audio_processing/ns/wiener_filter.zig").WienerFilter;
pub const SuppressionParams = @import("audio_processing/ns/suppression_params.zig").SuppressionParams;

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
pub const SparseFIRFilter = @import("audio_processing/sparse_fir_filter.zig").SparseFIRFilter;
pub const SincResampler = @import("audio_processing/sinc_resampler.zig").SincResampler;
pub const PushSincResampler = @import("audio_processing/push_sinc_resampler.zig").PushSincResampler;
pub const CascadedBiQuadFilter = @import("audio_processing/cascaded_biquad_filter.zig").CascadedBiQuadFilter;
pub const BiQuadCoefficients = @import("audio_processing/cascaded_biquad_filter.zig").BiQuadCoefficients;
pub const HighPassFilter = @import("audio_processing/high_pass_filter.zig").HighPassFilter;
pub const ThreeBandFilterBank = @import("audio_processing/three_band_filter_bank.zig").ThreeBandFilterBank;
pub const SplittingFilter = @import("audio_processing/splitting_filter.zig").SplittingFilter;
pub const AudioBuffer = @import("audio_processing/audio_buffer.zig").AudioBuffer;
pub const Config = @import("api/config.zig");
pub const Control = @import("api/control.zig");
pub const ApmDataDumper = @import("audio_processing/logging/apm_data_dumper.zig").ApmDataDumper;
