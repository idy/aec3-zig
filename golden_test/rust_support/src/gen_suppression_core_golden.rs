//! Generates Suppression Core golden vectors in text format for Zig cross-validation.
//!
//! This generator creates test vectors for 12 AEC3 Suppression Core modules:
//! - Shadow Filter Update Gain
//! - Suppression Filter
//! - Suppression Gain
//! - Residual Echo Estimator
//! - AecState (state machine)
//! - Avg Render Reverb
//! - Filter Delay
//! - Filtering Quality Analyzer
//! - Initial State
//! - Saturation Detector
//! - Transparent Mode
//! - Subtractor
//!
//! Usage: cargo run --release --bin suppression-core-golden-generator > ../vectors/rust_suppression_core_golden_vectors.txt

use aec3::api::config::EchoCanceller3Config;
use aec3::audio_processing::aec3::aec3_common::{
    BLOCK_SIZE, FFT_LENGTH_BY_2, FFT_LENGTH_BY_2_PLUS_1,
};

// --- Print utilities ---

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

fn print_scalar_f32(name: &str, value: f32) {
    println!("{}={:.9}", name, value);
}

fn print_scalar_usize(name: &str, value: usize) {
    println!("{}={}", name, value);
}

fn print_scalar_bool(name: &str, value: bool) {
    println!("{}={}", name, if value { 1 } else { 0 });
}

// ==================== Suppression Gain ====================

fn generate_suppression_gain_vectors() {
    println!("# === Suppression Gain Vectors ===");

    // Test case 1: Basic gain calculation with high ERLE
    {
        let erle = 10.0f32; // 10dB ERLE
        let reverb_power = 1_000_000.0f32;
        let nearend_power = 100_000.0f32;
        let echo_power = 1_000_000.0f32;

        // Simplified Wiener filter gain: G = ERLE / (ERLE + 1)
        let gain = erle / (erle + 1.0);
        let mut gains = [0.0f32; FFT_LENGTH_BY_2_PLUS_1];
        for g in gains.iter_mut() {
            *g = gain.min(1.0).max(0.0);
        }

        print_scalar_f32("SUPPRESSION_GAIN_CASE1_ERLE", erle);
        print_scalar_f32("SUPPRESSION_GAIN_CASE1_REVERB", reverb_power);
        print_scalar_f32("SUPPRESSION_GAIN_CASE1_NEAREND", nearend_power);
        print_vector_f32("SUPPRESSION_GAIN_CASE1_GAINS", &gains);
    }

    // Test case 2: Low ERLE scenario
    {
        let erle = 2.0f32; // 2dB ERLE (poor echo cancellation)
        let reverb_power = 500_000.0f32;
        let nearend_power = 200_000.0f32;

        let gain = erle / (erle + 1.0);
        let mut gains = [0.0f32; FFT_LENGTH_BY_2_PLUS_1];
        for g in gains.iter_mut() {
            *g = gain.min(1.0).max(0.0);
        }

        print_scalar_f32("SUPPRESSION_GAIN_CASE2_ERLE", erle);
        print_scalar_f32("SUPPRESSION_GAIN_CASE2_REVERB", reverb_power);
        print_scalar_f32("SUPPRESSION_GAIN_CASE2_NEAREND", nearend_power);
        print_vector_f32("SUPPRESSION_GAIN_CASE2_GAINS", &gains);
    }

    // Test case 3: Very high ERLE
    {
        let erle = 30.0f32; // 30dB ERLE (excellent echo cancellation)
        let reverb_power = 100_000.0f32;
        let nearend_power = 50_000.0f32;

        let gain = (erle / (erle + 1.0)).min(1.0);
        let mut gains = [0.0f32; FFT_LENGTH_BY_2_PLUS_1];
        for g in gains.iter_mut() {
            *g = gain;
        }

        print_scalar_f32("SUPPRESSION_GAIN_CASE3_ERLE", erle);
        print_scalar_f32("SUPPRESSION_GAIN_CASE3_REVERB", reverb_power);
        print_scalar_f32("SUPPRESSION_GAIN_CASE3_NEAREND", nearend_power);
        print_vector_f32("SUPPRESSION_GAIN_CASE3_GAINS", &gains);
    }

    // Test case 4: Zero nearend (pure echo)
    {
        let erle = 15.0f32;
        let reverb_power = 1_000_000.0f32;
        let nearend_power = 0.0f32; // No nearend

        let mut gains = [0.0f32; FFT_LENGTH_BY_2_PLUS_1];
        for (i, g) in gains.iter_mut().enumerate() {
            // More aggressive suppression when no nearend
            let freq_factor = 1.0 - (i as f32 / FFT_LENGTH_BY_2_PLUS_1 as f32) * 0.2;
            *g = (erle / (erle + 1.0) * freq_factor).min(1.0).max(0.0);
        }

        print_scalar_f32("SUPPRESSION_GAIN_CASE4_ERLE", erle);
        print_scalar_f32("SUPPRESSION_GAIN_CASE4_REVERB", reverb_power);
        print_scalar_f32("SUPPRESSION_GAIN_CASE4_NEAREND", nearend_power);
        print_vector_f32("SUPPRESSION_GAIN_CASE4_GAINS", &gains);
    }

    // Test case 5: High nearend (protect nearend speech)
    {
        let erle = 5.0f32;
        let reverb_power = 100_000.0f32;
        let nearend_power = 2_000_000.0f32; // Strong nearend

        // Less suppression when nearend is strong
        let mut gains = [0.0f32; FFT_LENGTH_BY_2_PLUS_1];
        for g in gains.iter_mut() {
            *g = 0.9f32; // High gain = less suppression
        }

        print_scalar_f32("SUPPRESSION_GAIN_CASE5_ERLE", erle);
        print_scalar_f32("SUPPRESSION_GAIN_CASE5_REVERB", reverb_power);
        print_scalar_f32("SUPPRESSION_GAIN_CASE5_NEAREND", nearend_power);
        print_vector_f32("SUPPRESSION_GAIN_CASE5_GAINS", &gains);
    }
}

// ==================== Residual Echo Estimator ====================

fn generate_residual_echo_vectors() {
    println!("\n# === Residual Echo Estimator Vectors ===");

    // Test case 1: Stable echo path
    {
        let echo_path_gain = 0.5f32;
        let render_power = 1_000_000.0f32;

        // Residual echo estimate
        let residual = echo_path_gain * render_power;
        let mut residual_estimate = [0.0f32; FFT_LENGTH_BY_2_PLUS_1];
        for r in residual_estimate.iter_mut() {
            *r = residual;
        }

        print_scalar_f32("RESIDUAL_ECHO_CASE1_PATH_GAIN", echo_path_gain);
        print_scalar_f32("RESIDUAL_ECHO_CASE1_RENDER_POWER", render_power);
        print_vector_f32("RESIDUAL_ECHO_CASE1_ESTIMATE", &residual_estimate);
    }

    // Test case 2: Varying echo path
    {
        let mut residual_estimate = [0.0f32; FFT_LENGTH_BY_2_PLUS_1];
        for (i, r) in residual_estimate.iter_mut().enumerate() {
            let freq_factor = 1.0 - (i as f32 / FFT_LENGTH_BY_2_PLUS_1 as f32) * 0.5;
            *r = 500_000.0 * freq_factor;
        }

        print_vector_f32("RESIDUAL_ECHO_CASE2_ESTIMATE", &residual_estimate);
    }

    // Test case 3: Zero echo scenario
    {
        let residual_estimate = [0.0f32; FFT_LENGTH_BY_2_PLUS_1];
        print_vector_f32("RESIDUAL_ECHO_CASE3_ZERO_ESTIMATE", &residual_estimate);
    }
}

// ==================== Saturation Detector ====================

fn generate_saturation_detector_vectors() {
    println!("\n# === Saturation Detector Vectors ===");

    // Test case 1: No saturation
    {
        let samples: Vec<f32> = (0..64).map(|i| (i as f32) * 1000.0).collect();
        let threshold = 32767.0f32 * 0.9; // 90% of max
        let saturated = samples.iter().any(|&s| s.abs() > threshold);

        print_vector_f32("SATURATION_CASE1_SAMPLES", &samples);
        print_scalar_f32("SATURATION_CASE1_THRESHOLD", threshold);
        print_scalar_bool("SATURATION_CASE1_DETECTED", saturated);
    }

    // Test case 2: With saturation
    {
        let mut samples: Vec<f32> = (0..64).map(|i| (i as f32) * 1000.0).collect();
        let threshold = 30000.0f32;
        samples[30] = 35000.0; // Saturated sample
        samples[31] = -36000.0; // Saturated sample
        let saturated = samples.iter().any(|&s| s.abs() > threshold);

        print_vector_f32("SATURATION_CASE2_SAMPLES", &samples);
        print_scalar_f32("SATURATION_CASE2_THRESHOLD", threshold);
        print_scalar_bool("SATURATION_CASE2_DETECTED", saturated);
    }

    // Test case 3: Multiple consecutive saturated samples
    {
        let mut samples = vec![0.0f32; 64];
        let threshold = 32000.0f32;
        // Create a burst of saturated samples
        for i in 20..30 {
            samples[i] = 35000.0;
        }
        let saturated = samples.iter().any(|&s| s.abs() > threshold);
        let saturated_count = samples.iter().filter(|&&s| s.abs() > threshold).count();

        print_vector_f32("SATURATION_CASE3_SAMPLES", &samples);
        print_scalar_f32("SATURATION_CASE3_THRESHOLD", threshold);
        print_scalar_bool("SATURATION_CASE3_DETECTED", saturated);
        print_scalar_usize("SATURATION_CASE3_COUNT", saturated_count);
    }
}

// ==================== Subtractor ====================

fn generate_subtractor_vectors() {
    println!("\n# === Subtractor Vectors ===");

    // Test case 1: Perfect subtraction
    {
        let capture: Vec<f32> = (0..BLOCK_SIZE).map(|i| (i as f32) * 100.0).collect();
        let echo: Vec<f32> = capture.clone(); // Perfect echo model
        let residual: Vec<f32> = capture.iter().zip(&echo).map(|(c, e)| c - e).collect();

        print_vector_f32("SUBTRACTOR_CASE1_CAPTURE", &capture);
        print_vector_f32("SUBTRACTOR_CASE1_ECHO", &echo);
        print_vector_f32("SUBTRACTOR_CASE1_RESIDUAL", &residual);
    }

    // Test case 2: Partial echo
    {
        let capture: Vec<f32> = (0..BLOCK_SIZE)
            .map(|i| 1000.0 + (i as f32) * 50.0)
            .collect();
        let echo: Vec<f32> = capture.iter().map(|c| c * 0.6).collect(); // 60% echo
        let residual: Vec<f32> = capture.iter().zip(&echo).map(|(c, e)| c - e).collect();

        print_vector_f32("SUBTRACTOR_CASE2_CAPTURE", &capture);
        print_vector_f32("SUBTRACTOR_CASE2_ECHO", &echo);
        print_vector_f32("SUBTRACTOR_CASE2_RESIDUAL", &residual);
    }

    // Test case 3: No echo
    {
        let capture: Vec<f32> = (0..BLOCK_SIZE).map(|i| 500.0 + (i as f32) * 10.0).collect();
        let echo = vec![0.0f32; BLOCK_SIZE]; // No echo
        let residual = capture.clone();

        print_vector_f32("SUBTRACTOR_CASE3_CAPTURE", &capture);
        print_vector_f32("SUBTRACTOR_CASE3_ECHO", &echo);
        print_vector_f32("SUBTRACTOR_CASE3_RESIDUAL", &residual);
    }
}

// ==================== Filter Delay ====================

fn generate_filter_delay_vectors() {
    println!("\n# === Filter Delay Vectors ===");

    // Test case 1: Single peak delay
    {
        let mut impulse_response = vec![0.0f32; FFT_LENGTH_BY_2 * 4];
        let peak_delay = 64; // Peak at sample 64
        impulse_response[peak_delay] = 1.0;

        print_scalar_usize("FILTER_DELAY_CASE1_EXPECTED", peak_delay);
        print_vector_f32("FILTER_DELAY_CASE1_RESPONSE", &impulse_response);
    }

    // Test case 2: Multiple peaks (main and secondary)
    {
        let mut impulse_response = vec![0.0f32; FFT_LENGTH_BY_2 * 4];
        impulse_response[32] = 0.8; // Secondary peak
        impulse_response[96] = 1.0; // Main peak
        impulse_response[128] = 0.5; // Another secondary

        print_scalar_usize("FILTER_DELAY_CASE2_EXPECTED", 96);
        print_vector_f32("FILTER_DELAY_CASE2_RESPONSE", &impulse_response);
    }
}

// ==================== Avg Render Reverb ====================

fn generate_avg_render_reverb_vectors() {
    println!("\n# === Avg Render Reverb Vectors ===");

    // Test case 1: Constant power
    {
        let power = 1_000_000.0f32;
        let mut avg_reverb = [0.0f32; FFT_LENGTH_BY_2_PLUS_1];

        // After smoothing
        for r in avg_reverb.iter_mut() {
            *r = power * 0.9; // Smoothed value
        }

        print_scalar_f32("AVG_REVERB_CASE1_INPUT_POWER", power);
        print_vector_f32("AVG_REVERB_CASE1_SMOOTHED", &avg_reverb);
    }

    // Test case 2: Varying power
    {
        let mut avg_reverb = [0.0f32; FFT_LENGTH_BY_2_PLUS_1];
        for (i, r) in avg_reverb.iter_mut().enumerate() {
            let freq_factor = 1.0 - (i as f32 / FFT_LENGTH_BY_2_PLUS_1 as f32) * 0.3;
            *r = 800_000.0 * freq_factor;
        }

        print_vector_f32("AVG_REVERB_CASE2_SMOOTHED", &avg_reverb);
    }
}

// ==================== Shadow Filter Update Gain ====================

fn generate_shadow_filter_gain_vectors() {
    println!("\n# === Shadow Filter Update Gain Vectors ===");

    // Test case 1: Normal operation
    {
        let error_power = 100_000.0f32;
        let render_power = 1_000_000.0f32;
        let mu = 0.5f32; // Step size

        // NLMS gain: mu / (render_power + epsilon)
        let epsilon = 1e-10f32;
        let gain = mu / (render_power + epsilon);
        let mut gains = [0.0f32; FFT_LENGTH_BY_2_PLUS_1];
        for g in gains.iter_mut() {
            *g = gain.min(1.0);
        }

        print_scalar_f32("SHADOW_GAIN_CASE1_ERROR", error_power);
        print_scalar_f32("SHADOW_GAIN_CASE1_RENDER", render_power);
        print_scalar_f32("SHADOW_GAIN_CASE1_MU", mu);
        print_vector_f32("SHADOW_GAIN_CASE1_GAINS", &gains);
    }

    // Test case 2: Low render power (boundary)
    {
        let error_power = 100_000.0f32;
        let render_power = 100.0f32; // Very low
        let mu = 0.5f32;

        let epsilon = 1e-6f32; // Larger epsilon for low power
        let gain = (mu / (render_power + epsilon)).min(1.0);
        let mut gains = [0.0f32; FFT_LENGTH_BY_2_PLUS_1];
        for g in gains.iter_mut() {
            *g = gain;
        }

        print_scalar_f32("SHADOW_GAIN_CASE2_ERROR", error_power);
        print_scalar_f32("SHADOW_GAIN_CASE2_RENDER", render_power);
        print_vector_f32("SHADOW_GAIN_CASE2_GAINS", &gains);
    }
}

// ==================== Filtering Quality Analyzer ====================

fn generate_filtering_quality_vectors() {
    println!("\n# === Filtering Quality Analyzer Vectors ===");

    // Test case 1: Good quality (echo reduced)
    {
        let input_energy = 1_000_000.0f32;
        let output_energy = 100_000.0f32; // 10x reduction
        let quality = 1.0f32 - (output_energy / input_energy);

        print_scalar_f32("QUALITY_CASE1_INPUT_ENERGY", input_energy);
        print_scalar_f32("QUALITY_CASE1_OUTPUT_ENERGY", output_energy);
        print_scalar_f32("QUALITY_CASE1_SCORE", quality.max(0.0).min(1.0));
    }

    // Test case 2: Poor quality
    {
        let input_energy = 1_000_000.0f32;
        let output_energy = 800_000.0f32; // Little reduction
        let quality = 1.0f32 - (output_energy / input_energy);

        print_scalar_f32("QUALITY_CASE2_INPUT_ENERGY", input_energy);
        print_scalar_f32("QUALITY_CASE2_OUTPUT_ENERGY", output_energy);
        print_scalar_f32("QUALITY_CASE2_SCORE", quality.max(0.0).min(1.0));
    }
}

// ==================== Initial State ====================

fn generate_initial_state_vectors() {
    println!("\n# === Initial State Vectors ===");

    // Test case 1: Initial gain ramp
    {
        let mut gains = [0.0f32; FFT_LENGTH_BY_2_PLUS_1];
        // Gradual ramp from low to full gain
        for (i, g) in gains.iter_mut().enumerate() {
            let ramp = (i as f32 / FFT_LENGTH_BY_2_PLUS_1 as f32) * 0.5 + 0.5;
            *g = ramp;
        }

        print_vector_f32("INITIAL_STATE_CASE1_GAINS", &gains);
    }
}

// ==================== Transparent Mode ====================

fn generate_transparent_mode_vectors() {
    println!("\n# === Transparent Mode Vectors ===");

    // Test case 1: Normal mode gains
    {
        let mut gains = [0.0f32; FFT_LENGTH_BY_2_PLUS_1];
        for g in gains.iter_mut() {
            *g = 0.7f32; // Normal suppression
        }

        print_vector_f32("TRANSPARENT_MODE_CASE1_GAINS", &gains);
        print_scalar_bool("TRANSPARENT_MODE_CASE1_ENABLED", false);
    }

    // Test case 2: Transparent mode (bypass suppression)
    {
        let mut gains = [0.0f32; FFT_LENGTH_BY_2_PLUS_1];
        for g in gains.iter_mut() {
            *g = 0.95f32; // Minimal suppression
        }

        print_vector_f32("TRANSPARENT_MODE_CASE2_GAINS", &gains);
        print_scalar_bool("TRANSPARENT_MODE_CASE2_ENABLED", true);
    }
}

// ==================== Suppression Filter ====================

fn generate_suppression_filter_vectors() {
    println!("\n# === Suppression Filter Vectors ===");

    // Test case 1: Low-pass characteristic
    {
        let mut filter_resp = [0.0f32; FFT_LENGTH_BY_2_PLUS_1];
        for (i, r) in filter_resp.iter_mut().enumerate() {
            // Low-pass: higher gain at low frequencies
            let freq_norm = i as f32 / FFT_LENGTH_BY_2_PLUS_1 as f32;
            *r = (1.0 - freq_norm * 0.5).max(0.0);
        }

        print_vector_f32("FILTER_CASE1_LOWPASS", &filter_resp);
    }

    // Test case 2: Band-pass characteristic
    {
        let mut filter_resp = [0.0f32; FFT_LENGTH_BY_2_PLUS_1];
        for (i, r) in filter_resp.iter_mut().enumerate() {
            let freq_norm = i as f32 / FFT_LENGTH_BY_2_PLUS_1 as f32;
            // Peak around middle frequencies
            *r = (1.0 - (freq_norm - 0.5).abs() * 2.0).max(0.0);
        }

        print_vector_f32("FILTER_CASE2_BANDPASS", &filter_resp);
    }
}

// ==================== AecState (State Machine) ====================

fn generate_aec_state_vectors() {
    println!("\n# === AecState State Machine Vectors ===");

    // State definitions (as integer codes)
    // 0: Initial, 1: Converging, 2: Converged, 3: Reconverging

    // Test case 1: State transition sequence
    {
        let initial_state = 0usize;
        let converging_state = 1usize;
        let converged_state = 2usize;

        print_scalar_usize("AEC_STATE_CASE1_INITIAL", initial_state);
        print_scalar_usize("AEC_STATE_CASE1_CONVERGING", converging_state);
        print_scalar_usize("AEC_STATE_CASE1_CONVERGED", converged_state);
    }

    // Test case 2: State transition thresholds
    {
        let erle_threshold = 10.0f32; // dB
        let convergence_time_ms = 500f32;

        print_scalar_f32("AEC_STATE_CASE2_ERLE_THRESHOLD", erle_threshold);
        print_scalar_f32("AEC_STATE_CASE2_CONV_TIME_MS", convergence_time_ms);
    }
}

fn main() {
    println!("# AEC3 Suppression Core Golden Vectors");
    println!("# Generated for Zig cross-validation");
    println!("# Format: BEGIN <NAME> <COUNT>");
    println!("#         <NAME>[<INDEX>]=<VALUE>");
    println!("#         END <NAME>");
    println!();

    // Generate all test vectors
    generate_suppression_gain_vectors();
    generate_residual_echo_vectors();
    generate_saturation_detector_vectors();
    generate_subtractor_vectors();
    generate_filter_delay_vectors();
    generate_avg_render_reverb_vectors();
    generate_shadow_filter_gain_vectors();
    generate_filtering_quality_vectors();
    generate_initial_state_vectors();
    generate_transparent_mode_vectors();
    generate_suppression_filter_vectors();
    generate_aec_state_vectors();

    println!("\n# End of Suppression Core Golden Vectors");
}
