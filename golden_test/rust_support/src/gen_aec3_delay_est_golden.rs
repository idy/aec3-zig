//! Generates strict AEC3 delay-estimation golden vectors with the official aec3-rs pipeline.
//!
//! Usage:
//!   cargo run --manifest-path golden_test/rust_support/Cargo.toml --release --bin gen-aec3-delay-est-golden > golden_test/vectors/rust_aec3_delay_est_golden_vectors.txt

use aec3::api::config::EchoCanceller3Config;
use aec3::audio_processing::aec3::aec3_common::{
    detect_optimization, num_bands_for_rate, BLOCK_SIZE,
    MATCHED_FILTER_ALIGNMENT_SHIFT_SIZE_SUB_BLOCKS, MATCHED_FILTER_WINDOW_SIZE_SUB_BLOCKS,
};
use aec3::audio_processing::aec3::decimator::Decimator;
use aec3::audio_processing::aec3::delay_estimate::DelayEstimateQuality;
use aec3::audio_processing::aec3::echo_path_delay_estimator::EchoPathDelayEstimator;
use aec3::audio_processing::aec3::matched_filter::{LagEstimate, MatchedFilter};
use aec3::audio_processing::aec3::matched_filter_lag_aggregator::MatchedFilterLagAggregator;
use aec3::audio_processing::aec3::render_delay_buffer::RenderDelayBuffer;
use aec3::audio_processing::aec3::render_signal_analyzer::RenderSignalAnalyzer;
use aec3::audio_processing::logging::apm_data_dumper::ApmDataDumper;

const SAMPLE_RATE_HZ: i32 = 48_000;
const NUM_RENDER_CHANNELS: usize = 1;
const NUM_CAPTURE_CHANNELS: usize = 1;
const FIXED_DELAY_SAMPLES: usize = 20 * BLOCK_SIZE;
const JUMP_DELAY_A_SAMPLES: usize = 10 * BLOCK_SIZE;
const JUMP_DELAY_B_SAMPLES: usize = 35 * BLOCK_SIZE;
const FIXED_CASE_FRAMES: usize = 700;
const SILENCE_CASE_FRAMES: usize = 220;
const LOW_ENERGY_CASE_FRAMES: usize = 240;
const JUMP_CASE_FRAMES: usize = 2500;
const JUMP_AT_FRAME: usize = 500;

struct DelayLine {
    buffer: Vec<f32>,
    write: usize,
    delay: usize,
}

impl DelayLine {
    fn new(max_delay: usize, initial_delay: usize) -> Self {
        let capacity = max_delay + BLOCK_SIZE * 4;
        Self {
            buffer: vec![0.0; capacity],
            write: 0,
            delay: initial_delay,
        }
    }

    fn set_delay(&mut self, delay: usize) {
        self.delay = delay;
    }

    fn process_block(&mut self, input: &[f32], output: &mut [f32]) {
        assert_eq!(input.len(), BLOCK_SIZE);
        assert_eq!(output.len(), BLOCK_SIZE);
        let len = self.buffer.len();
        for i in 0..BLOCK_SIZE {
            self.buffer[self.write] = input[i];
            let read = (self.write + len - (self.delay % len)) % len;
            output[i] = self.buffer[read];
            self.write = (self.write + 1) % len;
        }
    }
}

fn print_vector_f32(name: &str, data: &[f32]) {
    println!("BEGIN {} {}", name, data.len());
    for (i, v) in data.iter().enumerate() {
        println!("{}[{}]={:.9}", name, i, v);
    }
    println!("END {}", name);
}

fn print_vector_i32(name: &str, data: &[i32]) {
    println!("BEGIN {} {}", name, data.len());
    for (i, v) in data.iter().enumerate() {
        println!("{}[{}]={}", name, i, v);
    }
    println!("END {}", name);
}

fn print_vector_usize(name: &str, data: &[usize]) {
    println!("BEGIN {} {}", name, data.len());
    for (i, v) in data.iter().enumerate() {
        println!("{}[{}]={}", name, i, v);
    }
    println!("END {}", name);
}

fn frame_signal(frame_idx: usize, sample_idx: usize, amplitude: f32) -> f32 {
    let n = (frame_idx * BLOCK_SIZE + sample_idx) as u32;
    let mut x = n.wrapping_mul(747_796_405).wrapping_add(2_891_336_453);
    x ^= x >> 16;
    x = x.wrapping_mul(224_682_2519);
    x ^= x >> 13;
    x = x.wrapping_mul(3_266_489_917);
    x ^= x >> 16;

    let white = (x as f32 / u32::MAX as f32) * 2.0 - 1.0;
    let tonal = ((n as f32) * 0.021_31).sin() + 0.37 * ((n as f32) * 0.053_27).cos();
    amplitude * (0.85 * white + 0.15 * tonal)
}

fn fill_render_block(frame_idx: usize, amplitude: f32, render_block: &mut [Vec<Vec<f32>>]) {
    for sample_idx in 0..BLOCK_SIZE {
        render_block[0][0][sample_idx] = frame_signal(frame_idx, sample_idx, amplitude);
    }
    for band in render_block.iter_mut().skip(1) {
        for channel in band.iter_mut() {
            channel.fill(0.0);
        }
    }
}

fn run_delay_estimator_case(
    config: &EchoCanceller3Config,
    num_frames: usize,
    amplitude: f32,
    initial_delay_samples: usize,
    jump_frame: Option<usize>,
    jump_delay_samples: usize,
) -> (Vec<i32>, Vec<i32>, Vec<i32>) {
    let num_bands = num_bands_for_rate(SAMPLE_RATE_HZ);
    let mut render_delay_buffer =
        RenderDelayBuffer::new(config.clone(), SAMPLE_RATE_HZ, NUM_RENDER_CHANNELS);
    let mut estimator = EchoPathDelayEstimator::new(config, NUM_CAPTURE_CHANNELS);
    let max_delay = initial_delay_samples.max(jump_delay_samples);
    let mut delay_line = DelayLine::new(max_delay, initial_delay_samples);

    let mut render_block = vec![vec![vec![0.0f32; BLOCK_SIZE]; NUM_RENDER_CHANNELS]; num_bands];
    let mut capture_block = vec![vec![0.0f32; BLOCK_SIZE]; NUM_CAPTURE_CHANNELS];

    let mut estimated_delay = vec![-1; num_frames];
    let mut estimated_quality = vec![-1; num_frames];
    let mut used_delay = vec![initial_delay_samples as i32; num_frames];

    for frame in 0..num_frames {
        if let Some(sw) = jump_frame {
            if frame == sw {
                delay_line.set_delay(jump_delay_samples);
            }
        }
        used_delay[frame] = delay_line.delay as i32;

        fill_render_block(frame, amplitude, &mut render_block);
        delay_line.process_block(&render_block[0][0], &mut capture_block[0]);

        render_delay_buffer.insert(&render_block);
        if frame == 0 {
            render_delay_buffer.reset();
        }
        render_delay_buffer.prepare_capture_processing();

        if let Some(estimate) = estimator.estimate_delay(
            render_delay_buffer.downsampled_render_buffer(),
            &capture_block,
        ) {
            estimated_delay[frame] = estimate.delay as i32;
            estimated_quality[frame] = match estimate.quality {
                DelayEstimateQuality::Coarse => 0,
                DelayEstimateQuality::Refined => 1,
            };
        }
    }

    (used_delay, estimated_delay, estimated_quality)
}

fn run_matched_filter_case(
    config: &EchoCanceller3Config,
) -> (Vec<usize>, Vec<i32>, Vec<f32>, Vec<i32>) {
    let num_bands = num_bands_for_rate(SAMPLE_RATE_HZ);
    let down_sampling_factor = config.delay.down_sampling_factor;
    let sub_block_size = BLOCK_SIZE / down_sampling_factor;

    let mut render_delay_buffer =
        RenderDelayBuffer::new(config.clone(), SAMPLE_RATE_HZ, NUM_RENDER_CHANNELS);
    let mut decimator = Decimator::new(down_sampling_factor);
    let mut matched_filter = MatchedFilter::new(
        ApmDataDumper::new_unique(),
        detect_optimization(),
        sub_block_size,
        MATCHED_FILTER_WINDOW_SIZE_SUB_BLOCKS,
        config.delay.num_filters,
        MATCHED_FILTER_ALIGNMENT_SHIFT_SIZE_SUB_BLOCKS,
        config.render_levels.poor_excitation_render_limit,
        config.delay.delay_estimate_smoothing,
        config.delay.delay_candidate_detection_threshold,
    );

    let mut render_block = vec![vec![vec![0.0f32; BLOCK_SIZE]; NUM_RENDER_CHANNELS]; num_bands];
    let mut capture_block = vec![0.0f32; BLOCK_SIZE];
    let mut capture_ds = vec![0.0f32; sub_block_size];
    let mut delay_line = DelayLine::new(FIXED_DELAY_SAMPLES, FIXED_DELAY_SAMPLES);

    for frame in 0..650 {
        fill_render_block(frame, 22_000.0, &mut render_block);
        delay_line.process_block(&render_block[0][0], &mut capture_block);

        render_delay_buffer.insert(&render_block);
        if frame == 0 {
            render_delay_buffer.reset();
        }
        render_delay_buffer.prepare_capture_processing();

        decimator.decimate(&capture_block, &mut capture_ds);
        matched_filter.update(render_delay_buffer.downsampled_render_buffer(), &capture_ds);
    }

    let lags = matched_filter.lag_estimates();
    let lag_values: Vec<usize> = lags.iter().map(|x| x.lag).collect();
    let reliable_values: Vec<i32> = lags
        .iter()
        .map(|x| if x.reliable { 1 } else { 0 })
        .collect();
    let accuracy_values: Vec<f32> = lags.iter().map(|x| x.accuracy).collect();
    let updated_values: Vec<i32> = lags.iter().map(|x| if x.updated { 1 } else { 0 }).collect();

    (lag_values, reliable_values, accuracy_values, updated_values)
}

fn run_aggregator_transition(config: &EchoCanceller3Config) -> (Vec<i32>, Vec<i32>) {
    let mut aggregator = MatchedFilterLagAggregator::new(
        ApmDataDumper::new_unique(),
        512,
        config.delay.delay_selection_thresholds.clone(),
    );

    let mut estimates_over_time = Vec::with_capacity(140);
    let mut quality_over_time = Vec::with_capacity(140);

    for frame in 0..140 {
        let lag = if frame < 70 { 80 } else { 140 };
        let lag_estimates = vec![
            LagEstimate::new(0.95, true, lag, true),
            LagEstimate::new(0.2, true, lag + 9, true),
            LagEstimate::new(0.1, false, lag + 20, true),
        ];

        if let Some(de) = aggregator.aggregate(&lag_estimates) {
            estimates_over_time.push(de.delay as i32);
            quality_over_time.push(match de.quality {
                DelayEstimateQuality::Coarse => 0,
                DelayEstimateQuality::Refined => 1,
            });
        } else {
            estimates_over_time.push(-1);
            quality_over_time.push(-1);
        }
    }

    (estimates_over_time, quality_over_time)
}

fn run_render_signal_analyzer_case(config: &EchoCanceller3Config) -> (Vec<f32>, i32, i32) {
    let num_bands = num_bands_for_rate(SAMPLE_RATE_HZ);
    let mut analyzer = RenderSignalAnalyzer::new(config);
    let mut render_delay_buffer =
        RenderDelayBuffer::new(config.clone(), SAMPLE_RATE_HZ, NUM_RENDER_CHANNELS);

    let mut render_block = vec![vec![vec![0.0f32; BLOCK_SIZE]; NUM_RENDER_CHANNELS]; num_bands];

    for frame in 0..120 {
        for n in 0..BLOCK_SIZE {
            let t = (frame * BLOCK_SIZE + n) as f32;
            render_block[0][0][n] = 26_000.0 * (t * 0.098_174_77).sin() + 15.0 * (t * 0.023).cos();
        }
        for band in render_block.iter_mut().skip(1) {
            for ch in band {
                ch.fill(0.0);
            }
        }

        render_delay_buffer.insert(&render_block);
        if frame == 0 {
            render_delay_buffer.reset();
        }
        render_delay_buffer.prepare_capture_processing();

        let render_view = render_delay_buffer.render_buffer();
        analyzer.update(&render_view, Some(0));
    }

    let mut mask = [1.0f32; 65];
    analyzer.mask_regions_around_narrow_bands(&mut mask);
    let narrow_peak = analyzer.narrow_peak_band().map(|x| x as i32).unwrap_or(-1);
    let poor_excitation = if analyzer.poor_signal_excitation() {
        1
    } else {
        0
    };
    (mask.to_vec(), narrow_peak, poor_excitation)
}

fn first_frame_with_delay(estimates: &[i32], target: i32, tolerance: i32) -> i32 {
    for (i, &value) in estimates.iter().enumerate() {
        if value >= 0 && (value - target).abs() <= tolerance {
            return i as i32;
        }
    }
    -1
}

fn first_frame_after_jump(estimates: &[i32], start: usize, target: i32, tolerance: i32) -> i32 {
    for (i, &value) in estimates.iter().enumerate().skip(start) {
        if value >= 0 && (value - target).abs() <= tolerance {
            return i as i32;
        }
    }
    -1
}

fn main() {
    let mut config = EchoCanceller3Config::default();
    config.delay.down_sampling_factor = 4;
    config.delay.num_filters = 10;

    println!("# AEC3 delay-estimation golden vectors");
    println!("# Reference: aec3-rs (matched_filter / lag_aggregator / render_signal_analyzer / echo_path_delay_estimator)");
    println!(
        "# SampleRate={} BlockSize={} DownSamplingFactor={}",
        SAMPLE_RATE_HZ, BLOCK_SIZE, config.delay.down_sampling_factor
    );
    println!();

    // Case 1: fixed-delay convergence (strict trajectory)
    let (fixed_used_delay, fixed_delay, fixed_quality) = run_delay_estimator_case(
        &config,
        FIXED_CASE_FRAMES,
        24_000.0,
        FIXED_DELAY_SAMPLES,
        None,
        FIXED_DELAY_SAMPLES,
    );
    print_vector_i32("DELAY_FIXED_TRUE_DELAY_SAMPLES", &fixed_used_delay);
    print_vector_i32("DELAY_FIXED_ESTIMATED_DELAY_SAMPLES", &fixed_delay);
    print_vector_i32("DELAY_FIXED_ESTIMATED_QUALITY", &fixed_quality);

    let fixed_first_match = first_frame_with_delay(&fixed_delay, FIXED_DELAY_SAMPLES as i32, 4);
    print_vector_i32("DELAY_FIXED_FIRST_MATCH_FRAME", &[fixed_first_match]);

    // Case 2: silence stability
    let (silence_used_delay, silence_delay, silence_quality) = run_delay_estimator_case(
        &config,
        SILENCE_CASE_FRAMES,
        0.0,
        FIXED_DELAY_SAMPLES,
        None,
        FIXED_DELAY_SAMPLES,
    );
    print_vector_i32("DELAY_SILENCE_TRUE_DELAY_SAMPLES", &silence_used_delay);
    print_vector_i32("DELAY_SILENCE_ESTIMATED_DELAY_SAMPLES", &silence_delay);
    print_vector_i32("DELAY_SILENCE_ESTIMATED_QUALITY", &silence_quality);

    // Case 3: low-energy reject behavior
    let (low_used_delay, low_delay, low_quality) = run_delay_estimator_case(
        &config,
        LOW_ENERGY_CASE_FRAMES,
        100.0,
        FIXED_DELAY_SAMPLES,
        None,
        FIXED_DELAY_SAMPLES,
    );
    print_vector_i32("DELAY_LOW_ENERGY_TRUE_DELAY_SAMPLES", &low_used_delay);
    print_vector_i32("DELAY_LOW_ENERGY_ESTIMATED_DELAY_SAMPLES", &low_delay);
    print_vector_i32("DELAY_LOW_ENERGY_ESTIMATED_QUALITY", &low_quality);

    // Case 4: delay jump tracking
    let (jump_used_delay, jump_delay, jump_quality) = run_delay_estimator_case(
        &config,
        JUMP_CASE_FRAMES,
        25_000.0,
        JUMP_DELAY_A_SAMPLES,
        Some(JUMP_AT_FRAME),
        JUMP_DELAY_B_SAMPLES,
    );
    print_vector_i32("DELAY_JUMP_TRUE_DELAY_SAMPLES", &jump_used_delay);
    print_vector_i32("DELAY_JUMP_ESTIMATED_DELAY_SAMPLES", &jump_delay);
    print_vector_i32("DELAY_JUMP_ESTIMATED_QUALITY", &jump_quality);
    print_vector_i32("DELAY_JUMP_SWITCH_FRAME", &[JUMP_AT_FRAME as i32]);

    let jump_first_old = first_frame_with_delay(&jump_delay, JUMP_DELAY_A_SAMPLES as i32, 4);
    let jump_first_new =
        first_frame_after_jump(&jump_delay, JUMP_AT_FRAME, JUMP_DELAY_B_SAMPLES as i32, 4);
    print_vector_i32("DELAY_JUMP_FIRST_MATCH_OLD_FRAME", &[jump_first_old]);
    print_vector_i32("DELAY_JUMP_FIRST_MATCH_NEW_FRAME", &[jump_first_new]);

    // Case 5: matched filter final lag landscape
    let (lags, reliability, accuracy, updated) = run_matched_filter_case(&config);
    print_vector_usize("MATCHED_FILTER_FINAL_LAGS", &lags);
    print_vector_i32("MATCHED_FILTER_FINAL_RELIABLE", &reliability);
    print_vector_f32("MATCHED_FILTER_FINAL_ACCURACY", &accuracy);
    print_vector_i32("MATCHED_FILTER_FINAL_UPDATED", &updated);

    // Case 6: lag-aggregator transition behavior
    let (agg_delay, agg_quality) = run_aggregator_transition(&config);
    print_vector_i32("LAG_AGGREGATOR_DELAY_TRAJECTORY", &agg_delay);
    print_vector_i32("LAG_AGGREGATOR_QUALITY_TRAJECTORY", &agg_quality);

    // Case 7: render-signal-analyzer narrow-band mask behavior
    let (mask, peak, poor_excitation) = run_render_signal_analyzer_case(&config);
    print_vector_f32("RENDER_SIGNAL_ANALYZER_MASK65", &mask);
    print_vector_i32("RENDER_SIGNAL_ANALYZER_NARROW_PEAK", &[peak]);
    print_vector_i32("RENDER_SIGNAL_ANALYZER_POOR_EXCITATION", &[poor_excitation]);
}
