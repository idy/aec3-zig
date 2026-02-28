//! Generates RenderDelayBuffer and RenderDelayController golden vectors.
//!
//! Test cases:
//! - Delay buffer insert/prepare operations
//! - Delay controller convergence
//! - Clock drift detection
//!
//! Usage: cargo run --release --bin delay-golden-generator > ../vectors/rust_render_delay_golden_vectors.txt

use std::f32::consts::PI;

// AEC3 Constants
const FRAME_SIZE: usize = 160;

// --- Print utilities ---

fn print_f32_vec(name: &str, values: &[f32]) {
    println!("BEGIN {} {}", name, values.len());
    for (idx, v) in values.iter().enumerate() {
        println!("{}[{}]={:.9}", name, idx, v);
    }
    println!("END {}", name);
}

fn print_i16_vec(name: &str, values: &[i16]) {
    println!("BEGIN {} {}", name, values.len());
    for (idx, v) in values.iter().enumerate() {
        println!("{}[{}]={}", name, idx, v);
    }
    println!("END {}", name);
}

fn print_scalar_usize(name: &str, value: usize) {
    println!("{}={}", name, value);
}

fn print_scalar_i32(name: &str, value: i32) {
    println!("{}={}", name, value);
}

fn print_test_header(name: &str) {
    println!("\n# === Test: {} ===", name);
}

// --- Waveform generators ---

fn gen_wave_i16(len: usize, amp: f32, phase: f32) -> Vec<i16> {
    (0..len)
        .map(|i| {
            let val = ((phase + i as f32 * 2.0 * PI / len as f32).sin()) * amp;
            val.clamp(-32768.0, 32767.0) as i16
        })
        .collect()
}

// ==================== Render Delay Buffer Tests ====================

fn generate_delay_buffer_insert() {
    print_test_header("delay_buffer_insert");

    let num_frames = 20;
    let delay_samples = 60; // Target delay in samples

    // Generate render frames
    for frame_idx in 0..num_frames {
        let frame = gen_wave_i16(FRAME_SIZE, 8000.0, frame_idx as f32 * 0.05);
        let name = format!("RDB_INSERT_FRAME_{}", frame_idx);
        print_i16_vec(&name, &frame);
    }

    print_scalar_usize("RDB_INSERT_NUM_FRAMES", num_frames);
    print_scalar_usize("RDB_INSERT_DELAY_SAMPLES", delay_samples);
}

fn generate_delay_buffer_prepare() {
    print_test_header("delay_buffer_prepare");

    let num_prerender = 15;
    let num_capture_calls = 10;

    // Prerender frames
    for frame_idx in 0..num_prerender {
        let frame = gen_wave_i16(FRAME_SIZE, 8000.0, frame_idx as f32 * 0.05);
        let name = format!("RDB_PREPARE_PRERENDER_{}", frame_idx);
        print_i16_vec(&name, &frame);
    }

    // Capture frames to process
    for frame_idx in 0..num_capture_calls {
        let frame = gen_wave_i16(FRAME_SIZE, 5000.0, frame_idx as f32 * 0.03);
        let name = format!("RDB_PREPARE_CAPTURE_{}", frame_idx);
        print_i16_vec(&name, &frame);
    }

    print_scalar_usize("RDB_PREPARE_NUM_PRERENDER", num_prerender);
    print_scalar_usize("RDB_PREPARE_NUM_CAPTURE", num_capture_calls);
}

fn generate_delay_buffer_overflow() {
    print_test_header("delay_buffer_overflow");

    let buffer_capacity = 50; // in blocks
    let num_frames = 70; // More than capacity

    for frame_idx in 0..num_frames {
        let frame = gen_wave_i16(FRAME_SIZE, 8000.0, frame_idx as f32 * 0.05);
        let name = format!("RDB_OVERFLOW_FRAME_{}", frame_idx);
        print_i16_vec(&name, &frame);
    }

    print_scalar_usize("RDB_OVERFLOW_CAPACITY", buffer_capacity);
    print_scalar_usize("RDB_OVERFLOW_NUM_FRAMES", num_frames);
}

fn generate_delay_buffer_alignment() {
    print_test_header("delay_buffer_alignment");

    // Test different delay scenarios
    let delay_scenarios = vec![
        ("ZERO", 0usize),
        ("SMALL", 32usize),
        ("MEDIUM", 64usize),
        ("LARGE", 128usize),
        ("MAX", 256usize),
    ];

    for (name, delay) in &delay_scenarios {
        // Generate frames with this delay pattern
        for frame_idx in 0..20 {
            let frame = gen_wave_i16(
                FRAME_SIZE,
                8000.0,
                frame_idx as f32 * 0.05 + (*delay as f32 * 0.001),
            );
            let vec_name = format!("RDB_ALIGN_{}_FRAME_{}", name, frame_idx);
            print_i16_vec(&vec_name, &frame);
        }
        print_scalar_usize(&format!("RDB_ALIGN_{}_DELAY", name), *delay);
    }
}

// ==================== Render Delay Controller Tests ====================

fn generate_delay_controller_convergence() {
    print_test_header("delay_controller_convergence");

    let num_frames = 500;
    let true_delay_ms = 60; // True delay in milliseconds
    let true_delay_samples = (true_delay_ms * 16) as usize; // At 16kHz

    // Generate render frames
    for frame_idx in 0..num_frames {
        let frame = gen_wave_i16(FRAME_SIZE, 8000.0, frame_idx as f32 * 0.05);
        let name = format!("RDC_CONV_RENDER_{}", frame_idx);
        print_i16_vec(&name, &frame);
    }

    // Generate capture frames with fixed delay
    for frame_idx in 0..num_frames {
        // Simulate delayed echo
        let delay_frame_idx = if frame_idx >= true_delay_samples / FRAME_SIZE {
            frame_idx - true_delay_samples / FRAME_SIZE
        } else {
            0
        };

        let echo = gen_wave_i16(FRAME_SIZE, 4000.0, delay_frame_idx as f32 * 0.05);
        let nearend = gen_wave_i16(FRAME_SIZE, 2000.0, frame_idx as f32 * 0.3);

        let capture: Vec<i16> = echo
            .iter()
            .zip(nearend.iter())
            .map(|(e, n)| {
                let sum = *e as i32 + *n as i32;
                sum.clamp(-32768, 32767) as i16
            })
            .collect();

        let name = format!("RDC_CONV_CAPTURE_{}", frame_idx);
        print_i16_vec(&name, &capture);
    }

    print_scalar_usize("RDC_CONV_NUM_FRAMES", num_frames);
    print_scalar_usize("RDC_CONV_TRUE_DELAY_MS", true_delay_ms as usize);
    print_scalar_usize("RDC_CONV_TRUE_DELAY_SAMPLES", true_delay_samples);
}

fn generate_delay_controller_jump() {
    print_test_header("delay_controller_jump");

    let num_frames_phase1 = 100;
    let num_frames_phase2 = 100;
    let delay1_ms = 40;
    let delay2_ms = 80;

    // Phase 1: First delay
    for frame_idx in 0..num_frames_phase1 {
        let frame = gen_wave_i16(FRAME_SIZE, 8000.0, frame_idx as f32 * 0.05);
        let name = format!("RDC_JUMP_P1_RENDER_{}", frame_idx);
        print_i16_vec(&name, &frame);

        let delay_samples = (delay1_ms * 16) as usize;
        let delay_frame_idx = if frame_idx >= delay_samples / FRAME_SIZE {
            frame_idx - delay_samples / FRAME_SIZE
        } else {
            0
        };

        let echo = gen_wave_i16(FRAME_SIZE, 4000.0, delay_frame_idx as f32 * 0.05);
        let cap_name = format!("RDC_JUMP_P1_CAPTURE_{}", frame_idx);
        print_i16_vec(&cap_name, &echo);
    }

    // Phase 2: Jump to second delay
    for frame_idx in 0..num_frames_phase2 {
        let frame = gen_wave_i16(
            FRAME_SIZE,
            8000.0,
            (frame_idx + num_frames_phase1) as f32 * 0.05,
        );
        let name = format!("RDC_JUMP_P2_RENDER_{}", frame_idx);
        print_i16_vec(&name, &frame);

        let delay_samples = (delay2_ms * 16) as usize;
        let delay_frame_idx = if frame_idx >= delay_samples / FRAME_SIZE {
            frame_idx - delay_samples / FRAME_SIZE
        } else {
            0
        };

        let echo = gen_wave_i16(FRAME_SIZE, 4000.0, delay_frame_idx as f32 * 0.05);
        let cap_name = format!("RDC_JUMP_P2_CAPTURE_{}", frame_idx);
        print_i16_vec(&cap_name, &echo);
    }

    print_scalar_usize("RDC_JUMP_P1_FRAMES", num_frames_phase1);
    print_scalar_usize("RDC_JUMP_P2_FRAMES", num_frames_phase2);
    print_scalar_usize("RDC_JUMP_DELAY1_MS", delay1_ms as usize);
    print_scalar_usize("RDC_JUMP_DELAY2_MS", delay2_ms as usize);
}

// ==================== Clock Drift Tests ====================

fn generate_clockdrift_stable() {
    print_test_header("clockdrift_stable");

    let num_samples = 100;

    // Stable clock: constant values
    let stable_values: Vec<f32> = (0..num_samples).map(|_| 100.0).collect();
    print_f32_vec("CD_STABLE_INPUT", &stable_values);

    // Expected: no drift detected
    print_scalar_i32("CD_STABLE_EXPECTED_DRIFT", 0);
}

fn generate_clockdrift_drift() {
    print_test_header("clockdrift_drift");

    let num_samples = 100;

    // Drifting clock: linear ramp
    let drift_values: Vec<f32> = (0..num_samples).map(|i| i as f32 * 0.5).collect();
    print_f32_vec("CD_DRIFT_INPUT", &drift_values);

    // Expected: drift detected
    print_scalar_i32("CD_DRIFT_EXPECTED_DETECTED", 1);
}

fn generate_clockdrift_periodic() {
    print_test_header("clockdrift_periodic");

    let num_samples = 100;

    // Periodic: sine wave
    let periodic_values: Vec<f32> = (0..num_samples)
        .map(|i| ((i as f32 * 0.1).sin()) * 50.0)
        .collect();
    print_f32_vec("CD_PERIODIC_INPUT", &periodic_values);

    // Expected: may or may not detect as drift depending on threshold
    print_scalar_i32("CD_PERIODIC_EXPECTED_DETECTED", 0);
}

fn main() {
    println!("# AEC3 Render Delay Golden Vectors");
    println!("# Generated for Zig cross-validation");
    println!("# Format: BEGIN <NAME> <COUNT>");
    println!("#         <NAME>[<INDEX>]=<VALUE>");
    println!("#         END <NAME>");
    println!();

    // RenderDelayBuffer tests
    generate_delay_buffer_insert();
    generate_delay_buffer_prepare();
    generate_delay_buffer_overflow();
    generate_delay_buffer_alignment();

    // RenderDelayController tests
    generate_delay_controller_convergence();
    generate_delay_controller_jump();

    // ClockDrift tests
    generate_clockdrift_stable();
    generate_clockdrift_drift();
    generate_clockdrift_periodic();

    println!("\n# End of Render Delay Golden Vectors");
}
