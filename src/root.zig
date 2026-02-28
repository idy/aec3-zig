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
pub const FftCore = @import("fft/fft_core.zig").FftCore;
pub const isPowerOfTwo = @import("fft/fft_core.zig").isPowerOfTwo;
pub const AudioBuffers = @import("buffer/mod.zig");
pub const Aec3Fft = @import("aec3/fft/mod.zig").Aec3Fft;
pub const Aec3Window = @import("aec3/fft/mod.zig").Window;
pub const Aec3FftData = @import("aec3/fft/fft_data.zig").FftData;
pub const Aec3FftDataFixed = @import("aec3/fft/fft_data.zig").FftDataFixed;
pub const NrFft = @import("ns/ns_fft.zig").NrFft;
pub const NsCommon = @import("ns/ns_common.zig");
pub const NsConfig = @import("ns/ns_config.zig").NsConfig;
pub const SuppressionLevel = @import("ns/ns_config.zig").SuppressionLevel;
pub const NoiseSuppressor = @import("ns/noise_suppressor.zig").NoiseSuppressor;
pub const SpeechProbabilityEstimator = @import("ns/speech_probability_estimator.zig").SpeechProbabilityEstimator;
pub const WienerFilter = @import("ns/wiener_filter.zig").WienerFilter;
pub const SuppressionParams = @import("ns/suppression_params.zig").SuppressionParams;

// Foundation 模块
pub const Aec3Common = @import("aec3/common/aec3_common.zig");
pub const DelayEstimate = @import("aec3/delay/delay_estimate.zig");
pub const Aec3Buffers = @import("aec3/buffer/mod.zig");
pub const BlockRingBuffer = @import("aec3/buffer/block_ring_buffer.zig").BlockRingBuffer;
pub const BlockRingBufferFixed = @import("aec3/buffer/block_ring_buffer.zig").BlockRingBufferFixed;
pub const FftRingBuffer = @import("aec3/buffer/fft_ring_buffer.zig").FftRingBuffer;
pub const FftRingBufferFixed = @import("aec3/buffer/fft_ring_buffer.zig").FftRingBufferFixed;
pub const RenderRingView = @import("aec3/buffer/render_ring_view.zig").RenderRingView;
pub const RenderRingViewFixed = @import("aec3/buffer/render_ring_view.zig").RenderRingViewFixed;
pub const DownsampledRenderBuffer = @import("aec3/state/downsampled_render_buffer.zig").DownsampledRenderBuffer;
pub const BlockDelayBuffer = @import("aec3/state/block_delay_buffer.zig").BlockDelayBuffer;
pub const MovingAverage = @import("aec3/state/moving_average.zig").MovingAverage;
pub const Decimator = @import("aec3/state/decimator.zig").Decimator;
pub const MixingVariant = @import("aec3/delay/alignment_mixer.zig").MixingVariant;
pub const AlignmentMixer = @import("aec3/delay/alignment_mixer.zig").AlignmentMixer;
pub const BlockFramer = @import("aec3/state/block_framer.zig").BlockFramer;
pub const FrameBlocker = @import("aec3/state/frame_blocker.zig").FrameBlocker;
pub const ClockDriftLevel = @import("aec3/state/clockdrift_detector.zig").ClockDriftLevel;
pub const ClockDriftDetector = @import("aec3/state/clockdrift_detector.zig").ClockDriftDetector;
pub const AdaptiveFirFilter = @import("aec3/filters/adaptive_fir_filter.zig").AdaptiveFirFilter;
pub const AdaptiveFirFilterErl = @import("aec3/filters/adaptive_fir_filter_erl.zig").AdaptiveFirFilterErl;
pub const MatchedFilter = @import("aec3/filters/matched_filter.zig").MatchedFilter;
pub const LagEstimate = @import("aec3/filters/matched_filter.zig").LagEstimate;
pub const MatchedFilterLagAggregator = @import("aec3/filters/matched_filter_lag_aggregator.zig").MatchedFilterLagAggregator;
pub const EchoPathDelayEstimator = @import("aec3/delay/echo_path_delay_estimator.zig").EchoPathDelayEstimator;
pub const RenderSignalAnalyzer = @import("aec3/state/render_signal_analyzer.zig").RenderSignalAnalyzer;
pub const FilterAnalyzer = @import("aec3/filters/filter_analyzer.zig").FilterAnalyzer;
pub const EchoPathVariability = @import("aec3/state/echo_path_variability.zig");
pub const FftData = @import("aec3/fft/fft_data.zig");
pub const Aec3Core = @import("aec3/core/mod.zig");
pub const ChannelLayout = @import("api/channel_layout.zig").ChannelLayout;
pub const StreamConfig = @import("api/stream_config.zig").StreamConfig;
pub const AudioUtil = @import("api/audio_util.zig");
pub const AudioFrame = @import("buffer/audio_frame.zig").AudioFrame;
pub const ChannelBuffer = @import("buffer/channel_buffer.zig").ChannelBuffer;
pub const IFChannelBuffer = @import("buffer/channel_buffer.zig").IFChannelBuffer;
pub const SparseFIRFilter = @import("aec3/filters/sparse_fir_filter.zig").SparseFIRFilter;
pub const SincResampler = @import("resampler/sinc_resampler.zig").SincResampler;
pub const PushSincResampler = @import("resampler/push_sinc_resampler.zig").PushSincResampler;
pub const CascadedBiQuadFilter = @import("aec3/filters/cascaded_biquad_filter.zig").CascadedBiQuadFilter;
pub const BiQuadCoefficients = @import("aec3/filters/cascaded_biquad_filter.zig").BiQuadCoefficients;
pub const HighPassFilter = @import("aec3/filters/high_pass_filter.zig").HighPassFilter;
pub const ThreeBandFilterBank = @import("aec3/filters/three_band_filter_bank.zig").ThreeBandFilterBank;
pub const SplittingFilter = @import("aec3/filters/splitting_filter.zig").SplittingFilter;
pub const FrameAudioBuffer = @import("buffer/frame_audio_buffer.zig").FrameAudioBuffer;
pub const Config = @import("api/config.zig");
pub const Control = @import("api/control.zig");
pub const ApmDataDumper = @import("log/apm_data_dumper.zig").ApmDataDumper;

// ERLE & Reverb estimation modules
pub const SpectrumRingBuffer = @import("aec3/buffer/spectrum_ring_buffer.zig").SpectrumRingBuffer;
pub const SpectrumRingBufferFixed = @import("aec3/buffer/spectrum_ring_buffer.zig").SpectrumRingBufferFixed;
pub const ErlEstimator = @import("aec3/erle/erl_estimator.zig").ErlEstimator;
pub const ReverbModel = @import("aec3/erle/reverb_model.zig").ReverbModel;
pub const ReverbFrequencyResponse = @import("aec3/erle/reverb_frequency_response.zig").ReverbFrequencyResponse;
pub const FullBandErleEstimator = @import("aec3/erle/fullband_erle_estimator.zig").FullBandErleEstimator;
pub const SubbandErleEstimator = @import("aec3/erle/subband_erle_estimator.zig").SubbandErleEstimator;
pub const StationarityEstimator = @import("aec3/state/stationarity_estimator.zig").StationarityEstimator;
pub const ReverbDecayEstimator = @import("aec3/erle/reverb_decay_estimator.zig").ReverbDecayEstimator;
pub const SignalDependentErleEstimator = @import("aec3/erle/signal_dependent_erle_estimator.zig").SignalDependentErleEstimator;
pub const ErleEstimator = @import("aec3/erle/erle_estimator.zig").ErleEstimator;
pub const ReverbModelEstimator = @import("aec3/erle/reverb_model_estimator.zig").ReverbModelEstimator;

// Metrics & leaf modules
pub const ApiCallJitterMetrics = @import("aec3/metrics/api_call_jitter_metrics.zig").ApiCallJitterMetrics;
pub const BlockProcessorMetrics = @import("aec3/metrics/block_processor_metrics.zig").BlockProcessorMetrics;
pub const RenderDelayControllerMetrics = @import("aec3/metrics/render_delay_controller_metrics.zig").RenderDelayControllerMetrics;
pub const EchoRemoverMetrics = @import("aec3/metrics/echo_remover_metrics.zig").EchoRemoverMetrics;
pub const SubtractorOutput = @import("aec3/state/subtractor_output.zig").SubtractorOutput;
pub const SubtractorOutputAnalyzer = @import("aec3/state/subtractor_output_analyzer.zig").SubtractorOutputAnalyzer;
pub const NearendDetector = @import("aec3/state/nearend_detector.zig").NearendDetector;
pub const DominantNearendDetector = @import("aec3/state/dominant_nearend_detector.zig").DominantNearendDetector;
pub const SubbandNearendDetector = @import("aec3/state/subband_nearend_detector.zig").SubbandNearendDetector;
pub const EchoAudibility = @import("aec3/state/echo_audibility.zig").EchoAudibility;
pub const ComfortNoiseGenerator = @import("aec3/state/comfort_noise_generator.zig").ComfortNoiseGenerator;
pub const MainFilterUpdateGain = @import("aec3/state/main_filter_update_gain.zig").MainFilterUpdateGain;
