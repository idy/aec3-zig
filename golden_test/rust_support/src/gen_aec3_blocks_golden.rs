//! Generates AEC3 Building Blocks golden vectors in text format for Zig cross-validation.
//!
//! Output format:
//!   BEGIN <NAME> <COUNT>
//!   <NAME>[<INDEX>]=<VALUE>
//!   END <NAME>
//!
//! Usage: cargo run --release --bin aec3-blocks-golden > ../vectors/rust_aec3_blocks_golden_vectors.txt

// AEC3 Constants (from aec3_common)
const FFT_LENGTH_BY_2: usize = 64;
const FFT_LENGTH_BY_2_PLUS_1: usize = FFT_LENGTH_BY_2 + 1;
const FFT_LENGTH: usize = 2 * FFT_LENGTH_BY_2;
const FRAME_SIZE: usize = 160;
const SUB_FRAME_LENGTH: usize = FRAME_SIZE / 2;
const BLOCK_SIZE: usize = FFT_LENGTH_BY_2;

// --- Print utilities ---

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

// --- Moving Average ---

fn moving_average(input: &[f32], window_size: usize) -> Vec<f32> {
    if window_size == 0 || input.len() < window_size {
        return Vec::new();
    }

    let output_len = input.len() - window_size + 1;
    let mut output = Vec::with_capacity(output_len);

    for i in 0..output_len {
        let sum: f32 = input[i..i + window_size].iter().sum();
        output.push(sum / window_size as f32);
    }

    output
}

fn generate_moving_average_vectors() {
    // Test case 1: Simple sequence [1, 2, 3, 4, 5, 6, 7, 8]
    let input1: Vec<f32> = (1..=8).map(|x| x as f32).collect();
    let window1: usize = 2;
    let expected1 = moving_average(&input1, window1);

    print_vector_f32("MA_INPUT_SIMPLE", &input1);
    print_vector_usize("MA_WINDOW_SIMPLE", &[window1]);
    print_vector_f32("MA_EXPECTED_SIMPLE", &expected1);

    // Test case 2: Window size equals sequence length
    let input2: Vec<f32> = (1..=5).map(|x| x as f32).collect();
    let window2: usize = 5;
    let expected2 = moving_average(&input2, window2);

    print_vector_f32("MA_INPUT_FULL_WINDOW", &input2);
    print_vector_usize("MA_WINDOW_FULL", &[window2]);
    print_vector_f32("MA_EXPECTED_FULL_WINDOW", &expected2);

    // Test case 3: Window size 1 (identity)
    let input3: Vec<f32> = (1..=5).map(|x| x as f32).collect();
    let window3: usize = 1;
    let expected3 = moving_average(&input3, window3);

    print_vector_f32("MA_INPUT_WINDOW_1", &input3);
    print_vector_usize("MA_WINDOW_1", &[window3]);
    print_vector_f32("MA_EXPECTED_WINDOW_1", &expected3);

    // Test case 4: Larger window with sine wave
    let count = 100;
    let mut input4 = Vec::with_capacity(count);
    for i in 0..count {
        let x = (i as f32) * 0.1;
        input4.push(x.sin());
    }
    let window4: usize = 10;
    let expected4 = moving_average(&input4, window4);

    print_vector_f32("MA_INPUT_SINE", &input4);
    print_vector_usize("MA_WINDOW_SINE", &[window4]);
    print_vector_f32("MA_EXPECTED_SINE", &expected4);
}

// --- Decimator ---

fn decimate(input: &[f32], factor: usize) -> Vec<f32> {
    if factor == 0 {
        return Vec::new();
    }

    let output_len = (input.len() + factor - 1) / factor;
    let mut output = Vec::with_capacity(output_len);

    for i in 0..output_len {
        output.push(input[i * factor]);
    }

    output
}

fn generate_decimator_vectors() {
    // Test case 1: Factor 2
    let input1: Vec<f32> = (0..16).map(|x| x as f32).collect();
    let factor1: usize = 2;
    let expected1 = decimate(&input1, factor1);

    print_vector_f32("DEC_INPUT_FACTOR_2", &input1);
    print_vector_usize("DEC_FACTOR_2", &[factor1]);
    print_vector_usize("DEC_EXPECTED_LEN_2", &[expected1.len()]);
    print_vector_f32("DEC_EXPECTED_FACTOR_2", &expected1);

    // Test case 2: Factor 4
    let input2: Vec<f32> = (0..32).map(|x| x as f32 * 0.5).collect();
    let factor2: usize = 4;
    let expected2 = decimate(&input2, factor2);

    print_vector_f32("DEC_INPUT_FACTOR_4", &input2);
    print_vector_usize("DEC_FACTOR_4", &[factor2]);
    print_vector_usize("DEC_EXPECTED_LEN_4", &[expected2.len()]);
    print_vector_f32("DEC_EXPECTED_FACTOR_4", &expected2);

    // Test case 3: Factor 1 (identity)
    let input3: Vec<f32> = (0..8).map(|x| x as f32).collect();
    let factor3: usize = 1;
    let expected3 = decimate(&input3, factor3);

    print_vector_f32("DEC_INPUT_FACTOR_1", &input3);
    print_vector_usize("DEC_FACTOR_1", &[factor3]);
    print_vector_f32("DEC_EXPECTED_FACTOR_1", &expected3);

    // Test case 4: Sine wave decimation
    let count = 64;
    let mut input4 = Vec::with_capacity(count);
    for i in 0..count {
        let x = (i as f32) * 0.1;
        input4.push(x.sin());
    }
    let factor4: usize = 4;
    let expected4 = decimate(&input4, factor4);

    print_vector_f32("DEC_INPUT_SINE", &input4);
    print_vector_usize("DEC_FACTOR_SINE", &[factor4]);
    print_vector_f32("DEC_EXPECTED_SINE", &expected4);
}

// --- Frame Blocker / Block Framer ---

fn frame_to_block(frames: &[f32], frame_size: usize, block_size: usize) -> Vec<f32> {
    let total_samples = frames.len();
    let num_blocks = total_samples / block_size;
    let mut blocks = Vec::with_capacity(num_blocks * block_size);

    for i in 0..num_blocks * block_size {
        blocks.push(frames[i]);
    }

    blocks
}

fn block_to_frames(blocks: &[f32], frame_size: usize) -> Vec<f32> {
    // Frames are extracted from blocks sequentially
    blocks.to_vec()
}

fn generate_frame_blocker_framer_vectors() {
    // Test case 1: Simple round-trip
    // 2 blocks of 64 samples each = 128 samples
    // Frames of 80 samples each
    let block_size = BLOCK_SIZE; // 64
    let frame_size = SUB_FRAME_LENGTH; // 80

    // Create test input: 2 full blocks
    let mut input_blocks = Vec::with_capacity(2 * block_size);
    for i in 0..(2 * block_size) {
        input_blocks.push((i as f32) * 0.1);
    }

    print_vector_f32("FB_INPUT_BLOCKS", &input_blocks);
    print_vector_usize("FB_BLOCK_SIZE", &[block_size]);
    print_vector_usize("FB_FRAME_SIZE", &[frame_size]);

    // Simulate frame_blocker: blocks -> frames
    // Then block_framer: frames -> blocks (round-trip)
    // For exact round-trip, we need aligned sizes
    let aligned_samples = (input_blocks.len() / frame_size) * frame_size;
    let mut frames = Vec::with_capacity(aligned_samples);
    for i in 0..aligned_samples {
        frames.push(input_blocks[i]);
    }

    // Convert back to blocks (round-trip)
    let output_blocks = block_to_frames(&frames, frame_size);

    print_vector_f32("FB_FRAMES_EXTRACTED", &frames);
    print_vector_f32("FB_ROUNDTRIP_OUTPUT", &output_blocks);

    // Test case 2: Cross-boundary scenario
    // Input that crosses block boundaries
    let mut input2 = Vec::with_capacity(200);
    for i in 0..200 {
        input2.push((i as f32) * 0.05 + 1.0);
    }

    print_vector_f32("FB_CROSS_BOUNDARY_INPUT", &input2);

    // Extract frames and convert back
    let aligned_len2 = (input2.len() / frame_size) * frame_size;
    let mut frames2 = Vec::with_capacity(aligned_len2);
    for i in 0..aligned_len2 {
        frames2.push(input2[i]);
    }
    let output2 = block_to_frames(&frames2, frame_size);

    print_vector_f32("FB_CROSS_BOUNDARY_FRAMES", &frames2);
    print_vector_f32("FB_CROSS_BOUNDARY_OUTPUT", &output2);
}

// --- Clock Drift Detector ---

fn detect_drift(samples: &[f32], threshold: f32) -> (f32, bool) {
    // Simple drift detection based on cumulative sum deviation
    if samples.len() < 2 {
        return (0.0, false);
    }

    let mut sum: f32 = 0.0;
    let mut sum_sq: f32 = 0.0;

    for &s in samples {
        sum += s;
        sum_sq += s * s;
    }

    let mean = sum / samples.len() as f32;
    let variance = sum_sq / samples.len() as f32 - mean * mean;
    let level = variance.sqrt();

    let drift_detected = level > threshold;

    (level, drift_detected)
}

fn generate_clockdrift_detector_vectors() {
    let threshold: f32 = 0.5;

    // Test case 1: Stable clock (low variance)
    let stable_samples: Vec<f32> = (0..100).map(|_| 1.0).collect();
    let (level1, drift1) = detect_drift(&stable_samples, threshold);

    print_vector_f32("CD_STABLE_INPUT", &stable_samples);
    print_vector_f32("CD_THRESHOLD", &[threshold]);
    print_vector_f32("CD_STABLE_LEVEL", &[level1]);
    print_vector_i32("CD_STABLE_DRIFT", &[if drift1 { 1 } else { 0 }]);

    // Test case 2: Drifting clock (linear ramp = high variance)
    let mut drift_samples = Vec::with_capacity(100);
    for i in 0..100 {
        drift_samples.push((i as f32) * 0.1);
    }
    let (level2, drift2) = detect_drift(&drift_samples, threshold);

    print_vector_f32("CD_DRIFT_INPUT", &drift_samples);
    print_vector_f32("CD_DRIFT_LEVEL", &[level2]);
    print_vector_i32("CD_DRIFT_DETECTED", &[if drift2 { 1 } else { 0 }]);

    // Test case 3: Sine wave (periodic, medium variance)
    let mut sine_samples = Vec::with_capacity(100);
    for i in 0..100 {
        sine_samples.push(((i as f32) * 0.2).sin());
    }
    let (level3, drift3) = detect_drift(&sine_samples, threshold);

    print_vector_f32("CD_SINE_INPUT", &sine_samples);
    print_vector_f32("CD_SINE_LEVEL", &[level3]);
    print_vector_i32("CD_SINE_DRIFT", &[if drift3 { 1 } else { 0 }]);

    // Test case 4: Gradual drift (increasing variance)
    let mut gradual_samples = Vec::with_capacity(100);
    for i in 0..100 {
        let ramp = (i as f32) * 0.01;
        let noise = ((i as f32) * 0.5).sin() * 0.1;
        gradual_samples.push(ramp + noise);
    }
    let (level4, drift4) = detect_drift(&gradual_samples, threshold);

    print_vector_f32("CD_GRADUAL_INPUT", &gradual_samples);
    print_vector_f32("CD_GRADUAL_LEVEL", &[level4]);
    print_vector_i32("CD_GRADUAL_DRIFT", &[if drift4 { 1 } else { 0 }]);
}

// --- Block Buffer Ring Operations ---

fn generate_block_buffer_vectors() {
    // Test vectors for ring buffer operations
    let capacity: usize = 4;
    let block_size: usize = BLOCK_SIZE; // 64

    // Simulate ring buffer: write 6 blocks to capacity-4 buffer
    let mut written_blocks: Vec<Vec<f32>> = Vec::new();
    for block_idx in 0..6 {
        let mut block = Vec::with_capacity(block_size);
        for i in 0..block_size {
            block.push((block_idx * 100 + i) as f32);
        }
        written_blocks.push(block);
    }

    // Expected after ring wrap: only last 4 blocks remain
    // blocks[2], blocks[3], blocks[4], blocks[5]
    print_vector_usize("BB_CAPACITY", &[capacity]);
    print_vector_usize("BB_BLOCK_SIZE", &[block_size]);
    print_vector_usize("BB_NUM_WRITTEN", &[written_blocks.len()]);

    // Flatten expected blocks (last 4)
    let mut expected_flat = Vec::new();
    for block in written_blocks.iter().skip(2) {
        expected_flat.extend_from_slice(block);
    }
    print_vector_f32("BB_EXPECTED_RING_CONTENTS", &expected_flat);

    // Expected read indices after operations
    let write_idx: usize = 2; // Wrapped position
    let read_idx: usize = 2;
    print_vector_usize("BB_EXPECTED_WRITE_IDX", &[write_idx]);
    print_vector_usize("BB_EXPECTED_READ_IDX", &[read_idx]);
}

// --- FFT Buffer ---

fn generate_fft_buffer_vectors() {
    let capacity: usize = 3;
    let fft_size: usize = FFT_LENGTH_BY_2_PLUS_1; // 65

    // Create test FFT data
    let mut fft_data: Vec<Vec<f32>> = Vec::new();
    for fft_idx in 0..5 {
        let mut fft = Vec::with_capacity(fft_size);
        for i in 0..fft_size {
            fft.push((fft_idx as f32) * 10.0 + (i as f32) * 0.1);
        }
        fft_data.push(fft);
    }

    print_vector_usize("FFT_BUF_CAPACITY", &[capacity]);
    print_vector_usize("FFT_BUF_SIZE", &[fft_size]);
    print_vector_usize("FFT_BUF_NUM_WRITTEN", &[fft_data.len()]);

    // Expected: only last 3 FFTs remain
    let mut expected_flat = Vec::new();
    for fft in fft_data.iter().skip(2) {
        expected_flat.extend_from_slice(fft);
    }
    print_vector_f32("FFT_BUF_EXPECTED_CONTENTS", &expected_flat);

    // Index tests
    let size: usize = 4;
    let test_indices: Vec<usize> = vec![0, 1, 2, 3];
    let inc_results: Vec<usize> = test_indices
        .iter()
        .map(|&i| if i + 1 < size { i + 1 } else { 0 })
        .collect();
    let dec_results: Vec<usize> = test_indices
        .iter()
        .map(|&i| if i > 0 { i - 1 } else { size - 1 })
        .collect();

    print_vector_usize("FFT_BUF_INC_INPUT", &test_indices);
    print_vector_usize("FFT_BUF_INC_EXPECTED", &inc_results);
    print_vector_usize("FFT_BUF_DEC_INPUT", &test_indices);
    print_vector_usize("FFT_BUF_DEC_EXPECTED", &dec_results);
}

fn main() {
    // Section: Moving Average
    println!("# === Moving Average Tests ===");
    generate_moving_average_vectors();

    // Section: Decimator
    println!("# === Decimator Tests ===");
    generate_decimator_vectors();

    // Section: Frame Blocker / Block Framer
    println!("# === Frame Blocker / Block Framer Tests ===");
    generate_frame_blocker_framer_vectors();

    // Section: Clock Drift Detector
    println!("# === Clock Drift Detector Tests ===");
    generate_clockdrift_detector_vectors();

    // Section: Block Buffer
    println!("# === Block Buffer Tests ===");
    generate_block_buffer_vectors();

    // Section: FFT Buffer
    println!("# === FFT Buffer Tests ===");
    generate_fft_buffer_vectors();
}
