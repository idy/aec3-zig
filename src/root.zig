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
pub const BlockBuffer = @import("audio_processing/aec3/block_buffer.zig").BlockBuffer;
pub const FftBuffer = @import("audio_processing/aec3/fft_buffer.zig").FftBuffer;
pub const RenderBuffer = @import("audio_processing/aec3/render_buffer.zig").RenderBuffer;
pub const DownsampledRenderBuffer = @import("audio_processing/aec3/downsampled_render_buffer.zig").DownsampledRenderBuffer;
pub const BlockDelayBuffer = @import("audio_processing/aec3/block_delay_buffer.zig").BlockDelayBuffer;
pub const MovingAverage = @import("audio_processing/aec3/moving_average.zig").MovingAverage;
pub const Decimator = @import("audio_processing/aec3/decimator.zig").Decimator;
pub const MixingVariant = @import("audio_processing/aec3/alignment_mixer.zig").MixingVariant;
pub const AlignmentMixer = @import("audio_processing/aec3/alignment_mixer.zig").AlignmentMixer;
pub const BlockFramer = @import("audio_processing/aec3/block_framer.zig").BlockFramer;
pub const FrameBlocker = @import("audio_processing/aec3/frame_blocker.zig").FrameBlocker;
pub const ClockDriftLevel = @import("audio_processing/aec3/clockdrift_detector.zig").ClockDriftLevel;
pub const ClockDriftDetector = @import("audio_processing/aec3/clockdrift_detector.zig").ClockDriftDetector;
pub const AdaptiveFirFilter = @import("audio_processing/aec3/adaptive_fir_filter.zig").AdaptiveFirFilter;
pub const AdaptiveFirFilterErl = @import("audio_processing/aec3/adaptive_fir_filter_erl.zig").AdaptiveFirFilterErl;
pub const MatchedFilter = @import("audio_processing/aec3/matched_filter.zig").MatchedFilter;
pub const LagEstimate = @import("audio_processing/aec3/matched_filter.zig").LagEstimate;
pub const MatchedFilterLagAggregator = @import("audio_processing/aec3/matched_filter_lag_aggregator.zig").MatchedFilterLagAggregator;
pub const EchoPathDelayEstimator = @import("audio_processing/aec3/echo_path_delay_estimator.zig").EchoPathDelayEstimator;
pub const RenderSignalAnalyzer = @import("audio_processing/aec3/render_signal_analyzer.zig").RenderSignalAnalyzer;
pub const FilterAnalyzer = @import("audio_processing/aec3/filter_analyzer.zig").FilterAnalyzer;
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

// ERLE & Reverb estimation modules
pub const SpectrumBuffer = @import("audio_processing/aec3/spectrum_buffer.zig").SpectrumBuffer;
pub const ErlEstimator = @import("audio_processing/aec3/erl_estimator.zig").ErlEstimator;
pub const ReverbModel = @import("audio_processing/aec3/reverb_model.zig").ReverbModel;
pub const ReverbFrequencyResponse = @import("audio_processing/aec3/reverb_frequency_response.zig").ReverbFrequencyResponse;
pub const FullBandErleEstimator = @import("audio_processing/aec3/fullband_erle_estimator.zig").FullBandErleEstimator;
pub const SubbandErleEstimator = @import("audio_processing/aec3/subband_erle_estimator.zig").SubbandErleEstimator;
pub const StationarityEstimator = @import("audio_processing/aec3/stationarity_estimator.zig").StationarityEstimator;
pub const ReverbDecayEstimator = @import("audio_processing/aec3/reverb_decay_estimator.zig").ReverbDecayEstimator;
pub const SignalDependentErleEstimator = @import("audio_processing/aec3/signal_dependent_erle_estimator.zig").SignalDependentErleEstimator;
pub const ErleEstimator = @import("audio_processing/aec3/erle_estimator.zig").ErleEstimator;
pub const ReverbModelEstimator = @import("audio_processing/aec3/reverb_model_estimator.zig").ReverbModelEstimator;

// Metrics & leaf modules
pub const ApiCallJitterMetrics = @import("audio_processing/aec3/api_call_jitter_metrics.zig").ApiCallJitterMetrics;
pub const BlockProcessorMetrics = @import("audio_processing/aec3/block_processor_metrics.zig").BlockProcessorMetrics;
pub const RenderDelayControllerMetrics = @import("audio_processing/aec3/render_delay_controller_metrics.zig").RenderDelayControllerMetrics;
pub const EchoRemoverMetrics = @import("audio_processing/aec3/echo_remover_metrics.zig").EchoRemoverMetrics;
pub const SubtractorOutput = @import("audio_processing/aec3/subtractor_output.zig").SubtractorOutput;
pub const SubtractorOutputAnalyzer = @import("audio_processing/aec3/subtractor_output_analyzer.zig").SubtractorOutputAnalyzer;
pub const NearendDetector = @import("audio_processing/aec3/nearend_detector.zig").NearendDetector;
pub const DominantNearendDetector = @import("audio_processing/aec3/dominant_nearend_detector.zig").DominantNearendDetector;
pub const SubbandNearendDetector = @import("audio_processing/aec3/subband_nearend_detector.zig").SubbandNearendDetector;
pub const EchoAudibility = @import("audio_processing/aec3/echo_audibility.zig").EchoAudibility;
pub const ComfortNoiseGenerator = @import("audio_processing/aec3/comfort_noise_generator.zig").ComfortNoiseGenerator;
pub const MainFilterUpdateGain = @import("audio_processing/aec3/main_filter_update_gain.zig").MainFilterUpdateGain;
pub const ShadowFilterUpdateGain = @import("audio_processing/aec3/shadow_filter_update_gain.zig").ShadowFilterUpdateGain;
pub const SuppressionFilter = @import("audio_processing/aec3/suppression_filter.zig").SuppressionFilter;
pub const SuppressionGain = @import("audio_processing/aec3/suppression_gain.zig").SuppressionGain;
pub const ResidualEchoEstimator = @import("audio_processing/aec3/residual_echo_estimator.zig").ResidualEchoEstimator;

// AEC3 state management modules
pub const AvgRenderReverb = @import("audio_processing/aec3/avg_render_reverb.zig").AvgRenderReverb;
pub const FilterDelay = @import("audio_processing/aec3/filter_delay.zig").FilterDelay;
pub const FilteringQualityAnalyzer = @import("audio_processing/aec3/filtering_quality_analyzer.zig").FilteringQualityAnalyzer;
pub const InitialState = @import("audio_processing/aec3/initial_state.zig").InitialState;
pub const SaturationDetector = @import("audio_processing/aec3/saturation_detector.zig").SaturationDetector;
pub const TransparentMode = @import("audio_processing/aec3/transparent_mode.zig").TransparentMode;
pub const AecPhase = @import("audio_processing/aec3/aec_state.zig").AecPhase;
pub const AecStateConfig = @import("audio_processing/aec3/aec_state.zig").AecStateConfig;
pub const AecState = @import("audio_processing/aec3/aec_state.zig").AecState;
pub const Subtractor = @import("audio_processing/aec3/subtractor.zig").Subtractor;
