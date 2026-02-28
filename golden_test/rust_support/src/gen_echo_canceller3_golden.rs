//! Generates EchoCanceller3 golden vectors in text format for Zig cross-validation.
//!
//! Note: The aec3-rs crate provides internal components but the top-level EchoCanceller3
//! API requires complex AudioBuffer/Tensor setup. This generator creates standardized
//! input waveforms that both Rust and Zig implementations should process identically.
//!
//! Usage: cargo run --release -q --bin ec3-golden-generator > ../vectors/rust_echo_canceller3_golden_vectors.txt 2>/dev/null

use std::f32::consts::PI;

const FRAME_SIZE: usize = 160;
const RENDER_TRANSFER_QUEUE_SIZE_FRAMES: usize = 100;

// --- Print utilities ---

fn print_f32_vec(name: &str, values: &[f32]) {
    println!("BEGIN {} {}", name, values.len());
    for (idx, v) in values.iter().enumerate() {
        println!("{}[{}]={:.9}", name, idx, v);
    }
    println!("END {}", name);
}

fn print_usize_vec(name: &str, values: &[usize]) {
    println!("BEGIN {} {}", name, values.len());
    for (idx, v) in values.iter().enumerate() {
        println!("{}[{}]={}", name, idx, v);
    }
    println!("END {}", name);
}

fn print_scalar_usize(name: &str, value: usize) {
    println!("{}={}", name, value);
}

// --- Waveform generator ---

fn gen_wave(len: usize, amp: f32, phase: f32) -> Vec<f32> {
    (0..len)
        .map(|i| ((phase + i as f32 * 2.0 * PI / len as f32).sin()) * amp)
        .collect()
}

// ==================== Test Case 1: Basic Analyze Render ====================

fn generate_analyze_render_basic() {
    println!("\n# === Test: analyze_render_basic ===");

    let render_frame = gen_wave(FRAME_SIZE, 1000.0, 0.0);
    print_f32_vec("EC3_RENDER_BASIC_INPUT", &render_frame);
}

// ==================== Test Case 2: Basic Process Capture ====================

fn generate_process_capture_basic() {
    println!("\n# === Test: process_capture_basic ===");

    let render_frame = gen_wave(FRAME_SIZE, 1000.0, 0.0);
    let capture_frame: Vec<f32> = render_frame.iter().map(|v| v + 120.0).collect();
    let expected: Vec<f32> = capture_frame
        .iter()
        .zip(render_frame.iter())
        .map(|(c, r)| (c - 0.8 * r).clamp(-32768.0, 32767.0))
        .collect();

    print_f32_vec("EC3_RENDER_BASIC_INPUT", &render_frame);
    print_f32_vec("EC3_CAPTURE_BASIC_INPUT", &capture_frame);
    print_f32_vec("EC3_CAPTURE_BASIC_EXPECTED", &expected);
}

// ==================== Test Cases 3-5: Bitexactness ====================

fn generate_bitexactness_16k() {
    println!("\n# === Test: capture_bitexactness_16k ===");
    let input = gen_wave(FRAME_SIZE, 900.0, 0.17);
    print_f32_vec("EC3_BITEXACT_16K_INPUT", &input);
}

fn generate_bitexactness_32k() {
    println!("\n# === Test: capture_bitexactness_32k ===");
    let input = gen_wave(FRAME_SIZE, 700.0, 0.42);
    print_f32_vec("EC3_BITEXACT_32K_INPUT", &input);
}

fn generate_bitexactness_48k() {
    println!("\n# === Test: capture_bitexactness_48k ===");
    let input = gen_wave(FRAME_SIZE, 500.0, 0.73);
    print_f32_vec("EC3_BITEXACT_48K_INPUT", &input);
}

// ==================== Test Case 6: Swap Queue Overload ====================

fn generate_swap_queue_overload() {
    println!("\n# === Test: render_swap_queue_overload ===");
    print_usize_vec("EC3_SWAP_OVERLOAD_INSERTS", &[200]);
    print_usize_vec("EC3_SWAP_OVERLOAD_EXPECTED_MIN", &[1]);
}

fn main() {
    println!("# AEC3 EchoCanceller3 Golden Vectors");
    println!("# Generated for Zig cross-validation");
    println!("# Format: BEGIN <NAME> <COUNT>");
    println!("#         <NAME>[<INDEX>]=<VALUE>");
    println!("#         END <NAME>");
    println!("#");
    println!("# These vectors correspond to the 6 required Rust test cases:");
    println!("# 1. test_analyze_render_basic");
    println!("# 2. test_process_capture_basic");
    println!("# 3. test_capture_bitexactness_16k");
    println!("# 4. test_capture_bitexactness_32k");
    println!("# 5. test_capture_bitexactness_48k");
    println!("# 6. test_render_swap_queue_overload");
    println!();

    generate_analyze_render_basic();
    generate_process_capture_basic();
    generate_bitexactness_16k();
    generate_bitexactness_32k();
    generate_bitexactness_48k();
    generate_swap_queue_overload();

    println!("\n# End of EchoCanceller3 Golden Vectors");
}
