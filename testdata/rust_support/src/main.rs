//! Generates Foundation golden vectors in text format for Zig cross-validation.
//!
//! Output format matches the convention used by `gen_fft_golden.rs`:
//!   BEGIN <NAME> <COUNT>
//!   <NAME>[<INDEX>]=<VALUE>
//!   END <NAME>
//!
//! Usage: cargo run --release --bin golden-generator > testdata/rust_foundation_golden_vectors.txt

fn fast_approx_log2f(input: f32) -> f32 {
    assert!(input > 0.0);
    let bits = input.to_bits();
    let mut out = bits as f32;
    out *= 1.192_092_9e-7_f32;
    out -= 126.942_695_f32;
    out
}

fn num_bands_for_rate(sample_rate_hz: i32) -> usize {
    if sample_rate_hz <= 0 {
        0
    } else {
        (sample_rate_hz as usize) / 16_000
    }
}

fn spectrum_from_packed(packed: &[f32; 128]) -> [f32; 65] {
    let mut re = [0.0f32; 65];
    let mut im = [0.0f32; 65];
    re[0] = packed[0];
    re[64] = packed[1];
    let mut src_idx = 2usize;
    for k in 1..64 {
        re[k] = packed[src_idx];
        im[k] = packed[src_idx + 1];
        src_idx += 2;
    }
    let mut p = [0.0f32; 65];
    for k in 0..65 {
        p[k] = re[k] * re[k] + im[k] * im[k];
    }
    p
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

fn print_vector_f64(name: &str, data: &[f64]) {
    println!("BEGIN {} {}", name, data.len());
    for (i, v) in data.iter().enumerate() {
        println!("{}[{}]={:.15}", name, i, v);
    }
    println!("END {}", name);
}

fn main() {
    // ── num_bands_for_rate ──
    let rates = [0i32, 16_000, 32_000, 48_000];
    let bands: Vec<usize> = rates.iter().map(|&r| num_bands_for_rate(r)).collect();
    print_vector_i32("NUM_BANDS_RATES", &rates);
    print_vector_usize("NUM_BANDS_EXPECTED", &bands);

    // ── fast_approx_log2f ──
    let count = 1000usize;
    let mut inputs = Vec::with_capacity(count);
    let mut outputs = Vec::with_capacity(count);
    for i in 0..count {
        let x = 0.01f32 + (i as f32) * (100.0 - 0.01) / ((count - 1) as f32);
        inputs.push(x);
        outputs.push(fast_approx_log2f(x));
    }
    print_vector_f32("FAST_LOG2_INPUT", &inputs);
    print_vector_f32("FAST_LOG2_EXPECTED", &outputs);

    // ── fft_data spectrum ──
    let cases = 10usize;
    let mut seed: u64 = 0x1234_5678_9abc_def0;
    for case_idx in 0..cases {
        let mut packed = [0.0f32; 128];
        for v in &mut packed {
            seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1);
            let u = ((seed >> 32) as u32) as f32 / (u32::MAX as f32);
            *v = u * 2.0 - 1.0;
        }
        let spectrum = spectrum_from_packed(&packed);
        print_vector_f32(&format!("SPECTRUM_PACKED_{}", case_idx), &packed);
        print_vector_f32(&format!("SPECTRUM_EXPECTED_{}", case_idx), &spectrum);
    }

    // ── config defaults ──
    let config_defaults: [f64; 20] = [
        250.0, 8.0, 5.0, 4.0, 13.0, 12.0, 1.0, 4.0, 1.5, 1.0, 0.83, 100.0, 150.0, 50.0, 1638400.0,
        4.0, 0.3, 0.4, 2.0, 0.25,
    ];
    print_vector_f64("CONFIG_DEFAULTS", &config_defaults);
}
