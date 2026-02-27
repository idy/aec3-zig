//! Generates ERLE and Reverb golden vectors in text format for Zig cross-validation.
//!
//! This generator creates test vectors for 10 AEC3 modules:
//! - ERL Estimator
//! - ERLE Estimator (main)
//! - Subband ERLE Estimator
//! - Fullband ERLE Estimator
//! - Signal Dependent ERLE Estimator
//! - Stationarity Estimator
//! - Reverb Decay Estimator
//! - Reverb Frequency Response
//! - Reverb Model
//! - Reverb Model Estimator
//!
//! Usage: cargo run --release --bin erle-reverb-golden-generator > ../vectors/rust_erle_reverb_golden_vectors.txt

use aec3::api::config::EchoCanceller3Config;
use aec3::audio_processing::aec3::{
    aec3_common::{BLOCK_SIZE, FFT_LENGTH_BY_2, FFT_LENGTH_BY_2_PLUS_1},
    erl_estimator::ErlEstimator,
    erle_estimator::ErleEstimator,
    fullband_erle_estimator::FullBandErleEstimator,
    reverb_decay_estimator::ReverbDecayEstimator,
    reverb_frequency_response::ReverbFrequencyResponse,
    reverb_model::ReverbModel,
    reverb_model_estimator::ReverbModelEstimator,
    signal_dependent_erle_estimator::SignalDependentErleEstimator,
    stationarity_estimator::StationarityEstimator,
    subband_erle_estimator::SubbandErleEstimator,
};

fn print_vector_f32(name: &str, data: &[f32]) {
    println!("BEGIN {} {}", name, data.len());
    for (i, v) in data.iter().enumerate() {
        println!("{}[{}]={:.9}", name, i, v);
    }
    println!("END {}", name);
}

fn print_vector_f32_2d(name: &str, data: &[[f32; FFT_LENGTH_BY_2_PLUS_1]]) {
    let flat_len = data.len() * FFT_LENGTH_BY_2_PLUS_1;
    println!("BEGIN {} {}", name, flat_len);
    for (ch, channel_data) in data.iter().enumerate() {
        for (i, v) in channel_data.iter().enumerate() {
            println!("{}[{}][{}]={:.9}", name, ch, i, v);
        }
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

fn print_vector_bool(name: &str, data: &[bool]) {
    println!("BEGIN {} {}", name, data.len());
    for (i, v) in data.iter().enumerate() {
        println!("{}[{}]={}", name, i, if *v { 1 } else { 0 });
    }
    println!("END {}", name);
}

fn main() {
    // Generate vectors for each module
    gen_erl_estimator_vectors();
    gen_subband_erle_vectors();
    gen_fullband_erle_vectors();
    gen_stationarity_vectors();
    gen_reverb_model_vectors();
    gen_reverb_decay_vectors();
    gen_reverb_frequency_response_vectors();
    gen_reverb_model_estimator_vectors();
}

// ==================== ERL Estimator ====================

fn gen_erl_estimator_vectors() {
    println!("# ERL Estimator Vectors");

    // Test case 1: Basic ERL estimation with strong echo
    {
        let mut estimator = ErlEstimator::new(0);
        let num_render_channels = 1;
        let num_capture_channels = 1;

        // Create render and capture spectra
        let render_power = 500.0 * 1_000_000.0;
        let capture_power = 10.0 * render_power; // ERL = 10

        let render_spectra = vec![[render_power; FFT_LENGTH_BY_2_PLUS_1]; num_render_channels];
        let mut capture_spectra = vec![[0.0f32; FFT_LENGTH_BY_2_PLUS_1]; num_capture_channels];
        capture_spectra[0].fill(capture_power);

        let converged = vec![true; num_capture_channels];

        // Update estimator for 200 blocks
        for _ in 0..200 {
            estimator.update(&converged, &render_spectra, &capture_spectra);
        }

        print_vector_f32("ERL_CASE1_ERL", estimator.erl());
        println!("ERL_CASE1_TIME_DOMAIN={:.9}", estimator.erl_time_domain());
    }

    // Test case 2: Multiple render channels
    {
        let mut estimator = ErlEstimator::new(0);
        let num_render_channels = 2;
        let num_capture_channels = 1;

        let render_power = 500.0 * 1_000_000.0;
        let capture_power = 5.0 * render_power; // ERL = 5

        let render_spectra = vec![[render_power; FFT_LENGTH_BY_2_PLUS_1]; num_render_channels];
        let mut capture_spectra = vec![[0.0f32; FFT_LENGTH_BY_2_PLUS_1]; num_capture_channels];
        capture_spectra[0].fill(capture_power);

        let converged = vec![true; num_capture_channels];

        for _ in 0..200 {
            estimator.update(&converged, &render_spectra, &capture_spectra);
        }

        print_vector_f32("ERL_CASE2_ERL", estimator.erl());
        println!("ERL_CASE2_TIME_DOMAIN={:.9}", estimator.erl_time_domain());
    }

    // Test case 3: No converged filters (startup phase)
    {
        let mut estimator = ErlEstimator::new(10);
        let num_render_channels = 1;
        let num_capture_channels = 1;

        let render_power = 500.0 * 1_000_000.0;
        let capture_power = 10.0 * render_power;

        let render_spectra = vec![[render_power; FFT_LENGTH_BY_2_PLUS_1]; num_render_channels];
        let mut capture_spectra = vec![[0.0f32; FFT_LENGTH_BY_2_PLUS_1]; num_capture_channels];
        capture_spectra[0].fill(capture_power);

        let converged = vec![false; num_capture_channels];

        // During startup phase, should not update
        for _ in 0..5 {
            estimator.update(&converged, &render_spectra, &capture_spectra);
        }

        print_vector_f32("ERL_CASE3_STARTUP_ERL", estimator.erl());

        // Now enable convergence
        let converged = vec![true; num_capture_channels];
        for _ in 0..200 {
            estimator.update(&converged, &render_spectra, &capture_spectra);
        }

        print_vector_f32("ERL_CASE3_AFTER_STARTUP_ERL", estimator.erl());
    }
}

// ==================== Subband ERLE Estimator ====================

fn gen_subband_erle_vectors() {
    println!("\n# Subband ERLE Estimator Vectors");

    let mut config = EchoCanceller3Config::default();
    config.erle.max_l = 20.0;
    config.erle.max_h = 20.0;
    config.erle.min = 1.0;
    config.erle.onset_detection = false;

    // Test case 1: Strong echo with high ERLE
    {
        let mut estimator = SubbandErleEstimator::new(&config, 1);
        let x2 = [100_000_000.0f32; FFT_LENGTH_BY_2_PLUS_1];
        let mut y2 = vec![[0.0f32; FFT_LENGTH_BY_2_PLUS_1]; 1];
        let mut e2 = vec![[0.0f32; FFT_LENGTH_BY_2_PLUS_1]; 1];

        // ERLE = 10: y2 = 10 * e2
        y2[0].fill(1_000_000_000.0);
        e2[0].fill(y2[0][0] / 10.0);

        let converged = vec![true];

        // Run for enough iterations to accumulate and update
        for _ in 0..(6 * 60) {
            // POINTS_TO_ACCUMULATE (6) * 60
            estimator.update(&x2, &y2, &e2, &converged);
        }

        print_vector_f32_2d("SUBBAND_ERLE_CASE1", estimator.erle());
    }

    // Test case 2: Low echo with low ERLE
    {
        let mut estimator = SubbandErleEstimator::new(&config, 1);
        let x2 = [100_000_000.0f32; FFT_LENGTH_BY_2_PLUS_1];
        let mut y2 = vec![[0.0f32; FFT_LENGTH_BY_2_PLUS_1]; 1];
        let mut e2 = vec![[0.0f32; FFT_LENGTH_BY_2_PLUS_1]; 1];

        // ERLE = 2: y2 = 2 * e2
        y2[0].fill(200_000_000.0);
        e2[0].fill(y2[0][0] / 2.0);

        let converged = vec![true];

        for _ in 0..(6 * 60) {
            estimator.update(&x2, &y2, &e2, &converged);
        }

        print_vector_f32_2d("SUBBAND_ERLE_CASE2", estimator.erle());
    }

    // Test case 3: Multiple capture channels
    {
        let num_capture_channels = 2;
        let mut estimator = SubbandErleEstimator::new(&config, num_capture_channels);
        let x2 = [100_000_000.0f32; FFT_LENGTH_BY_2_PLUS_1];
        let mut y2 = vec![[0.0f32; FFT_LENGTH_BY_2_PLUS_1]; num_capture_channels];
        let mut e2 = vec![[0.0f32; FFT_LENGTH_BY_2_PLUS_1]; num_capture_channels];

        for ch in 0..num_capture_channels {
            y2[ch].fill(1_000_000_000.0);
            e2[ch].fill(y2[ch][0] / 10.0);
        }

        let converged = vec![true; num_capture_channels];

        for _ in 0..(6 * 60) {
            estimator.update(&x2, &y2, &e2, &converged);
        }

        print_vector_f32_2d("SUBBAND_ERLE_CASE3_MULTI_CHANNEL", estimator.erle());
    }

    // Test case 4: Onset detection enabled
    {
        let mut config_onset = config.clone();
        config_onset.erle.onset_detection = true;
        let mut estimator = SubbandErleEstimator::new(&config_onset, 1);
        let x2 = [100_000_000.0f32; FFT_LENGTH_BY_2_PLUS_1];
        let mut y2 = vec![[0.0f32; FFT_LENGTH_BY_2_PLUS_1]; 1];
        let mut e2 = vec![[0.0f32; FFT_LENGTH_BY_2_PLUS_1]; 1];

        y2[0].fill(1_000_000_000.0);
        e2[0].fill(y2[0][0] / 10.0);

        let converged = vec![true];

        for _ in 0..(6 * 60) {
            estimator.update(&x2, &y2, &e2, &converged);
        }

        print_vector_f32_2d("SUBBAND_ERLE_CASE4_ONSET_ERLE", estimator.erle());
        print_vector_f32_2d(
            "SUBBAND_ERLE_CASE4_ONSET_ERLE_ONSETS",
            estimator.erle_onsets(),
        );
    }
}

// ==================== Fullband ERLE Estimator ====================

fn gen_fullband_erle_vectors() {
    println!("\n# Fullband ERLE Estimator Vectors");

    let config = EchoCanceller3Config::default();

    // Test case 1: Basic fullband ERLE
    {
        let mut estimator = FullBandErleEstimator::new(&config.erle, 1);
        let x2 = [100_000_000.0f32; FFT_LENGTH_BY_2_PLUS_1];
        let mut y2 = vec![[0.0f32; FFT_LENGTH_BY_2_PLUS_1]; 1];
        let mut e2 = vec![[0.0f32; FFT_LENGTH_BY_2_PLUS_1]; 1];

        // Create a case with ERLE ≈ 10
        y2[0].fill(1_000_000_000.0);
        e2[0].fill(y2[0][0] / 10.0);

        let converged = vec![true];

        // Accumulate enough points (6 points needed)
        for _ in 0..100 {
            estimator.update(&x2, &y2, &e2, &converged);
        }

        println!(
            "FULLBAND_ERLE_CASE1_LOG2={:.9}",
            estimator.fullband_erle_log2()
        );
    }

    // Test case 2: Multiple channels - take minimum
    {
        let num_channels = 2;
        let mut estimator = FullBandErleEstimator::new(&config.erle, num_channels);
        let x2 = [100_000_000.0f32; FFT_LENGTH_BY_2_PLUS_1];
        let mut y2 = vec![[0.0f32; FFT_LENGTH_BY_2_PLUS_1]; num_channels];
        let mut e2 = vec![[0.0f32; FFT_LENGTH_BY_2_PLUS_1]; num_channels];

        // Channel 0: ERLE = 10
        y2[0].fill(1_000_000_000.0);
        e2[0].fill(y2[0][0] / 10.0);

        // Channel 1: ERLE = 5
        y2[1].fill(500_000_000.0);
        e2[1].fill(y2[1][0] / 5.0);

        let converged = vec![true; num_channels];

        for _ in 0..100 {
            estimator.update(&x2, &y2, &e2, &converged);
        }

        println!(
            "FULLBAND_ERLE_CASE2_MULTI_CHANNEL_LOG2={:.9}",
            estimator.fullband_erle_log2()
        );

        // Check linear quality estimates
        let qualities = estimator.get_linear_quality_estimates();
        print_vector_f32(
            "FULLBAND_ERLE_CASE2_QUALITIES",
            &qualities
                .iter()
                .map(|q| q.unwrap_or(0.0))
                .collect::<Vec<_>>(),
        );
    }
}

// ==================== Stationarity Estimator ====================

fn gen_stationarity_vectors() {
    println!("\n# Stationarity Estimator Vectors");

    // Test case 1: Stationary signal
    {
        let mut estimator = StationarityEstimator::new();

        // Create a stationary spectrum
        let stationary_spectrum = [[1_000_000.0f32; FFT_LENGTH_BY_2_PLUS_1]; 1];

        // Update noise estimator first
        for _ in 0..50 {
            estimator.update_noise_estimator(&stationary_spectrum);
        }

        println!(
            "STATIONARITY_CASE1_IS_BLOCK_STATIONARY={}",
            if estimator.is_block_stationary() {
                1
            } else {
                0
            }
        );
    }

    // Test case 2: Non-stationary signal (changing power)
    {
        let mut estimator = StationarityEstimator::new();
        let mut power = 1_000_000.0f32;

        // Initialize with some stationary data
        let stationary_spectrum = [[1_000_000.0f32; FFT_LENGTH_BY_2_PLUS_1]; 1];
        for _ in 0..50 {
            estimator.update_noise_estimator(&stationary_spectrum);
        }

        // Now add non-stationary data
        for i in 0..10 {
            power = 1_000_000.0 * (1.0 + (i as f32) * 0.5);
            let varying_spectrum = [[power; FFT_LENGTH_BY_2_PLUS_1]; 1];
            estimator.update_noise_estimator(&varying_spectrum);
        }

        println!(
            "STATIONARITY_CASE2_IS_BLOCK_STATIONARY={}",
            if estimator.is_block_stationary() {
                1
            } else {
                0
            }
        );
    }
}

// ==================== Reverb Model ====================

fn gen_reverb_model_vectors() {
    println!("\n# Reverb Model Vectors");

    // Test case 1: Update without frequency shaping
    {
        let mut model = ReverbModel::new();
        let power_spectrum = [1_000_000.0f32; FFT_LENGTH_BY_2_PLUS_1];
        let scaling = 0.5f32;
        let decay = 0.9f32;

        // Run multiple updates
        for _ in 0..100 {
            model.update_reverb_no_freq_shaping(&power_spectrum, scaling, decay);
        }

        print_vector_f32("REVERB_MODEL_CASE1_NO_SHAPING", model.reverb());
    }

    // Test case 2: Update with frequency shaping
    {
        let mut model = ReverbModel::new();
        let power_spectrum = [1_000_000.0f32; FFT_LENGTH_BY_2_PLUS_1];
        let scaling: Vec<f32> = (0..FFT_LENGTH_BY_2_PLUS_1)
            .map(|i| 0.3 + 0.4 * (i as f32 / FFT_LENGTH_BY_2_PLUS_1 as f32))
            .collect();
        let decay = 0.85f32;

        for _ in 0..100 {
            model.update_reverb(&power_spectrum, &scaling, decay);
        }

        print_vector_f32("REVERB_MODEL_CASE2_WITH_SHAPING", model.reverb());
    }

    // Test case 3: Reset behavior
    {
        let mut model = ReverbModel::new();
        let power_spectrum = [1_000_000.0f32; FFT_LENGTH_BY_2_PLUS_1];

        // Build up some reverb
        for _ in 0..50 {
            model.update_reverb_no_freq_shaping(&power_spectrum, 0.5, 0.9);
        }

        print_vector_f32("REVERB_MODEL_CASE3_BEFORE_RESET", model.reverb());

        model.reset();

        print_vector_f32("REVERB_MODEL_CASE3_AFTER_RESET", model.reverb());
    }

    // Test case 4: Different decay values
    {
        let decays = [0.5f32, 0.7, 0.9, 0.95];
        let power_spectrum = [1_000_000.0f32; FFT_LENGTH_BY_2_PLUS_1];

        for (i, decay) in decays.iter().enumerate() {
            let mut model = ReverbModel::new();

            for _ in 0..100 {
                model.update_reverb_no_freq_shaping(&power_spectrum, 0.5, *decay);
            }

            print_vector_f32(
                &format!("REVERB_MODEL_CASE4_DECAY_{:.2}", decay),
                model.reverb(),
            );
        }
    }
}

// ==================== Reverb Decay Estimator ====================

fn gen_reverb_decay_vectors() {
    println!("\n# Reverb Decay Estimator Vectors");

    let mut config = EchoCanceller3Config::default();
    config.filter.main.length_blocks = 40;
    config.ep_strength.default_len = -0.9; // Enable adaptive decay estimation

    // Test case 1: Exponential decay filter
    {
        let mut estimator = ReverbDecayEstimator::new(&config);

        // Create an impulse response with exponential decay
        let num_blocks = config.filter.main.length_blocks;
        let filter_len = num_blocks * FFT_LENGTH_BY_2;
        let mut filter = vec![0.0f32; filter_len];

        // Set peak at block 2
        let peak_block = 2;
        let peak_sample = peak_block * FFT_LENGTH_BY_2;
        filter[peak_sample] = 1.0;

        // Apply exponential decay: 0.5 power decay per block
        let true_decay: f32 = 0.5f32;
        let decay_per_sample = true_decay.powf(1.0 / FFT_LENGTH_BY_2 as f32);

        for i in (peak_sample + 1)..filter.len() {
            filter[i] = filter[i - 1] * decay_per_sample;
        }

        // Update estimator multiple times
        let quality = Some(1.0f32);
        let filter_delay = 2i32;
        let usable = true;
        let stationary = false;

        for _ in 0..500 {
            estimator.update(&filter, quality, filter_delay, usable, stationary);
        }

        println!(
            "REVERB_DECAY_CASE1_ESTIMATED_DECAY={:.9}",
            estimator.decay()
        );
        println!("REVERB_DECAY_CASE1_TRUE_DECAY={:.9}", true_decay);
    }

    // Test case 2: Fixed decay (non-adaptive)
    {
        let mut config_fixed = config.clone();
        config_fixed.ep_strength.default_len = 0.8; // Positive = fixed decay

        let mut estimator = ReverbDecayEstimator::new(&config_fixed);

        let num_blocks = config_fixed.filter.main.length_blocks;
        let filter_len = num_blocks * FFT_LENGTH_BY_2;
        let filter = vec![0.0f32; filter_len];

        let quality = Some(1.0f32);
        let filter_delay = 2i32;
        let usable = true;
        let stationary = false;

        for _ in 0..100 {
            estimator.update(&filter, quality, filter_delay, usable, stationary);
        }

        println!("REVERB_DECAY_CASE2_FIXED_DECAY={:.9}", estimator.decay());
    }

    // Test case 3: Stationary block (should not update)
    {
        let mut estimator = ReverbDecayEstimator::new(&config);

        let num_blocks = config.filter.main.length_blocks;
        let filter_len = num_blocks * FFT_LENGTH_BY_2;
        let mut filter = vec![0.0f32; filter_len];

        // Create some filter content
        filter[FFT_LENGTH_BY_2 * 2] = 1.0;

        let quality = Some(1.0f32);
        let filter_delay = 2i32;
        let usable = true;
        let stationary = true; // Stationary - should not update

        for _ in 0..100 {
            estimator.update(&filter, quality, filter_delay, usable, stationary);
        }

        println!(
            "REVERB_DECAY_CASE3_STATIONARY_DECAY={:.9}",
            estimator.decay()
        );
    }
}

// ==================== Reverb Frequency Response ====================

fn gen_reverb_frequency_response_vectors() {
    println!("\n# Reverb Frequency Response Vectors");

    // Test case 1: Basic frequency response update
    {
        let mut freq_response = ReverbFrequencyResponse::new();

        // Create frequency responses for multiple blocks
        let num_blocks = 10;
        let mut responses = vec![[0.0f32; FFT_LENGTH_BY_2_PLUS_1]; num_blocks];

        // Fill with decaying values
        for (block, response) in responses.iter_mut().enumerate() {
            let decay = 0.9f32.powi(block as i32);
            for (k, val) in response.iter_mut().enumerate() {
                *val = decay * (1.0 + 0.5 * (k as f32 / FFT_LENGTH_BY_2_PLUS_1 as f32));
            }
        }

        let quality = Some(1.0f32);
        let filter_delay = 2i32;
        let stationary = false;

        for _ in 0..100 {
            freq_response.update(&responses, filter_delay, quality, stationary);
        }

        print_vector_f32(
            "REVERB_FREQ_RESPONSE_CASE1",
            freq_response.frequency_response(),
        );
    }

    // Test case 2: Empty frequency response
    {
        let mut freq_response = ReverbFrequencyResponse::new();
        let empty_responses: &[[f32; FFT_LENGTH_BY_2_PLUS_1]] = &[];

        let quality = Some(1.0f32);
        let filter_delay = 2i32;
        let stationary = false;

        freq_response.update(empty_responses, filter_delay, quality, stationary);

        print_vector_f32(
            "REVERB_FREQ_RESPONSE_CASE2_EMPTY",
            freq_response.frequency_response(),
        );
    }

    // Test case 3: Stationary block
    {
        let mut freq_response = ReverbFrequencyResponse::new();

        let num_blocks = 10;
        let mut responses = vec![[0.0f32; FFT_LENGTH_BY_2_PLUS_1]; num_blocks];
        for response in responses.iter_mut() {
            response.fill(1.0);
        }

        let quality = Some(1.0f32);
        let filter_delay = 2i32;
        let stationary = true;

        // Should not update during stationary block
        for _ in 0..100 {
            freq_response.update(&responses, filter_delay, quality, stationary);
        }

        print_vector_f32(
            "REVERB_FREQ_RESPONSE_CASE3_STATIONARY",
            freq_response.frequency_response(),
        );
    }
}

// ==================== Reverb Model Estimator ====================

fn gen_reverb_model_estimator_vectors() {
    println!("\n# Reverb Model Estimator Vectors");

    let mut config = EchoCanceller3Config::default();
    config.filter.main.length_blocks = 40;
    config.ep_strength.default_len = -0.9;

    // Test case 1: Full estimator with exponential decay
    {
        let num_capture_channels = 1;
        let mut estimator = ReverbModelEstimator::new(&config, num_capture_channels);

        // Create impulse response
        let num_blocks = config.filter.main.length_blocks;
        let filter_len = num_blocks * FFT_LENGTH_BY_2;
        let mut impulse_responses = vec![vec![0.0f32; filter_len]; num_capture_channels];

        // Create frequency responses
        let mut frequency_responses =
            vec![vec![[0.0f32; FFT_LENGTH_BY_2_PLUS_1]; num_blocks]; num_capture_channels];

        // Set up exponential decay
        let true_decay = 0.5f32;
        let peak_block = 2;
        let peak_sample = peak_block * FFT_LENGTH_BY_2;
        impulse_responses[0][peak_sample] = 1.0;

        let decay_per_sample = true_decay.powf(1.0 / FFT_LENGTH_BY_2 as f32);
        for i in (peak_sample + 1)..impulse_responses[0].len() {
            impulse_responses[0][i] = impulse_responses[0][i - 1] * decay_per_sample;
        }

        // Compute frequency responses (simplified)
        for block in 0..num_blocks {
            let start = block * FFT_LENGTH_BY_2;
            for k in 0..FFT_LENGTH_BY_2_PLUS_1 {
                // Simplified: sum of squares in block
                let sum_sq: f32 = impulse_responses[0]
                    [start..(start + FFT_LENGTH_BY_2).min(impulse_responses[0].len())]
                    .iter()
                    .map(|&v| v * v)
                    .sum();
                frequency_responses[0][block][k] = sum_sq;
            }
        }

        let qualities = vec![Some(1.0f32); num_capture_channels];
        let filter_delays = vec![peak_block as i32; num_capture_channels];
        let usable = vec![true; num_capture_channels];
        let stationary = false;

        for _ in 0..500 {
            estimator.update(
                &impulse_responses,
                &frequency_responses,
                &qualities,
                &filter_delays,
                &usable,
                stationary,
            );
        }

        println!(
            "REVERB_MODEL_ESTIMATOR_CASE1_DECAY={:.9}",
            estimator.reverb_decay()
        );
        print_vector_f32(
            "REVERB_MODEL_ESTIMATOR_CASE1_FREQ_RESPONSE",
            estimator.get_reverb_frequency_response(),
        );
    }

    // Test case 2: Multiple capture channels
    {
        let num_capture_channels = 2;
        let mut estimator = ReverbModelEstimator::new(&config, num_capture_channels);

        let num_blocks = config.filter.main.length_blocks;
        let filter_len = num_blocks * FFT_LENGTH_BY_2;
        let impulse_responses = vec![vec![0.0f32; filter_len]; num_capture_channels];
        let frequency_responses =
            vec![vec![[0.0f32; FFT_LENGTH_BY_2_PLUS_1]; num_blocks]; num_capture_channels];

        let qualities = vec![Some(1.0f32); num_capture_channels];
        let filter_delays = vec![2i32; num_capture_channels];
        let usable = vec![true; num_capture_channels];
        let stationary = false;

        for _ in 0..100 {
            estimator.update(
                &impulse_responses,
                &frequency_responses,
                &qualities,
                &filter_delays,
                &usable,
                stationary,
            );
        }

        println!(
            "REVERB_MODEL_ESTIMATOR_CASE2_MULTI_CHANNEL_DECAY={:.9}",
            estimator.reverb_decay()
        );
    }
}
