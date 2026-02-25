use std::fs::{create_dir_all, File};
use std::io::{BufWriter, Write};

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

fn write_u32(w: &mut BufWriter<File>, v: u32) {
    w.write_all(&v.to_le_bytes()).unwrap();
}

fn write_u64(w: &mut BufWriter<File>, v: u64) {
    w.write_all(&v.to_le_bytes()).unwrap();
}

fn write_i32(w: &mut BufWriter<File>, v: i32) {
    w.write_all(&v.to_le_bytes()).unwrap();
}

fn write_f32(w: &mut BufWriter<File>, v: f32) {
    w.write_all(&v.to_le_bytes()).unwrap();
}

fn main() {
    create_dir_all("tests/golden").unwrap();

    {
        let file = File::create("tests/golden/golden_aec3_common.bin").unwrap();
        let mut w = BufWriter::new(file);

        let rates = [0i32, 16_000, 32_000, 48_000];
        write_u32(&mut w, rates.len() as u32);
        for rate in rates {
            write_i32(&mut w, rate);
            write_u64(&mut w, num_bands_for_rate(rate) as u64);
        }

        let count = 1000u32;
        write_u32(&mut w, count);
        for i in 0..count {
            let x = 0.01f32 + (i as f32) * (100.0 - 0.01) / ((count - 1) as f32);
            write_f32(&mut w, x);
            write_f32(&mut w, fast_approx_log2f(x));
        }
        w.flush().unwrap();
    }

    {
        let file = File::create("tests/golden/golden_fft_data_spectrum.bin").unwrap();
        let mut w = BufWriter::new(file);

        let cases = 10u32;
        write_u32(&mut w, cases);
        let mut seed: u64 = 0x1234_5678_9abc_def0;
        for _ in 0..cases {
            let mut packed = [0.0f32; 128];
            for v in &mut packed {
                seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1);
                let u = ((seed >> 40) as u32) as f32 / (u32::MAX as f32);
                *v = u * 2.0 - 1.0;
                write_f32(&mut w, *v);
            }
            let spectrum = spectrum_from_packed(&packed);
            for v in spectrum {
                write_f32(&mut w, v);
            }
        }
        w.flush().unwrap();
    }

    {
        let file = File::create("tests/golden/golden_config_default.bin").unwrap();
        let mut w = BufWriter::new(file);

        // Ordered scalar snapshot of key default values.
        write_u32(&mut w, 20);
        let values: [f64; 20] = [
            250.0, 8.0, 5.0, 4.0, 13.0, 12.0, 1.0, 4.0, 1.5, 1.0, 0.83, 100.0, 150.0, 50.0,
            1638400.0, 4.0, 0.3, 0.4, 2.0, 0.25,
        ];
        for v in values {
            w.write_all(&v.to_le_bytes()).unwrap();
        }
        w.flush().unwrap();
    }
}
