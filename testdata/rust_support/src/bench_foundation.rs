use std::time::Instant;

fn fast_approx_log2f(input: f32) -> f32 {
    let bits = input.to_bits();
    let mut out = bits as f32;
    out *= 1.192_092_9e-7_f32;
    out -= 126.942_695_f32;
    out
}

fn bench_fast_approx_log2f() {
    let iterations = 10_000usize;
    let mut acc = 0.0f32;
    let start = Instant::now();
    for i in 0..iterations {
        let x = 0.01f32 + (i % 1000) as f32 * 0.1;
        acc += fast_approx_log2f(x);
    }
    let ns = start.elapsed().as_nanos() as f64;
    println!(
        "bench_fast_approx_log2f: total={}ns ns/op={:.2} acc={:.3}",
        ns as u128,
        ns / iterations as f64,
        acc
    );
}

fn spectrum(re: &[f32; 65], im: &[f32; 65], out: &mut [f32; 65]) {
    for i in 0..65 {
        out[i] = re[i] * re[i] + im[i] * im[i];
    }
}

fn bench_fft_data_spectrum() {
    let iterations = 10_000usize;
    let mut re = [0.0f32; 65];
    let mut im = [0.0f32; 65];
    for i in 0..65 {
        re[i] = i as f32 * 0.1;
        im[i] = i as f32 * 0.05;
    }
    let mut out = [0.0f32; 65];

    let start = Instant::now();
    for _ in 0..iterations {
        spectrum(&re, &im, &mut out);
    }
    let ns = start.elapsed().as_nanos() as f64;
    println!(
        "bench_fft_data_spectrum: total={}ns ns/op={:.2} out0={:.3}",
        ns as u128,
        ns / iterations as f64,
        out[0]
    );
}

fn float_s16_to_s16(v: f32) -> i16 {
    let mut clamped = v.min(32767.0).max(-32768.0);
    clamped += clamped.signum() * 0.5;
    clamped as i16
}

fn bench_audio_util_conversions() {
    let iterations = 10_000usize;
    let mut src = [0i16; 480];
    for i in 0..src.len() {
        src[i] = (i as i32 - 240).clamp(i16::MIN as i32, i16::MAX as i32) as i16;
    }

    let mut fbuf = [0.0f32; 480];
    let mut dst = [0i16; 480];
    let start = Instant::now();
    for _ in 0..iterations {
        for (s, d) in src.iter().zip(fbuf.iter_mut()) {
            *d = *s as f32;
        }
        for (s, d) in fbuf.iter().zip(dst.iter_mut()) {
            *d = float_s16_to_s16(*s);
        }
    }
    let ns = start.elapsed().as_nanos() as f64;
    println!(
        "bench_audio_util_conversions: total={}ns ns/op={:.2} dst0={}",
        ns as u128,
        ns / iterations as f64,
        dst[0]
    );
}

fn main() {
    bench_fast_approx_log2f();
    bench_fft_data_spectrum();
    bench_audio_util_conversions();
}
