//! Generates NS (Noise Suppression) golden vectors for Zig cross-validation.
//!
//! This implements the same algorithm as the Zig NS module:
//! - Quantile-based noise estimation with histogram
//! - Decision-directed prior SNR estimation
//! - Speech probability estimation using tanh
//! - Wiener filter gain computation
//!
//! Usage: cargo run --release --bin ns-golden-generator > testdata/rust_ns_golden_vectors.txt 2>/dev/null

use std::f32::consts::PI;

const FFT_SIZE: usize = 256;
const FFT_SIZE_BY_2_PLUS_1: usize = 129;
const FRAME_SIZE: usize = FFT_SIZE;
const SAMPLE_RATE_HZ: f32 = 16_000.0;
const EPSILON: f32 = 1e-6;

// ============================================================================
// Histogram for quantile noise estimation (matches histograms.zig)
// ============================================================================

const HIST_BINS: usize = 64;

struct Histogram {
    counts: [u32; HIST_BINS],
    total: u32,
    min_value: f32,
    max_value: f32,
}

impl Histogram {
    fn new(min_value: f32, max_value: f32) -> Self {
        assert!(max_value > min_value);
        Self {
            counts: [0; HIST_BINS],
            total: 0,
            min_value,
            max_value,
        }
    }

    fn observe(&mut self, value: f32) {
        let clamped = value.clamp(self.min_value, self.max_value);
        let ratio = (clamped - self.min_value) / (self.max_value - self.min_value);
        let idx = ((ratio * (HIST_BINS - 1) as f32).floor() as usize).clamp(0, HIST_BINS - 1);
        self.counts[idx] += 1;
        self.total += 1;
    }

    fn quantile(&self, p: f32) -> f32 {
        if self.total == 0 {
            return self.min_value;
        }
        let q = p.clamp(0.0, 1.0);
        let target = (q * (self.total - 1) as f32).floor() as u32;

        let mut acc: u32 = 0;
        for (i, &count) in self.counts.iter().enumerate() {
            acc += count;
            if acc > target {
                let bin_ratio = i as f32 / (HIST_BINS - 1) as f32;
                return self.min_value + bin_ratio * (self.max_value - self.min_value);
            }
        }
        self.max_value
    }
}

// ============================================================================
// Quantile Noise Estimator (matches quantile_noise_estimator.zig)
// ============================================================================

struct QuantileNoiseEstimator {
    hist: [Histogram; FFT_SIZE_BY_2_PLUS_1],
    noise_quantile: [f32; FFT_SIZE_BY_2_PLUS_1],
    quantile: f32,
}

impl QuantileNoiseEstimator {
    fn new() -> Self {
        let mut hist: [Histogram; FFT_SIZE_BY_2_PLUS_1] = unsafe { std::mem::zeroed() };
        for h in hist.iter_mut() {
            *h = Histogram::new(0.0, 100.0);
        }
        Self {
            hist,
            noise_quantile: [1e-3; FFT_SIZE_BY_2_PLUS_1],
            quantile: 0.2,
        }
    }

    fn update(&mut self, magnitude2: &[f32; FFT_SIZE_BY_2_PLUS_1]) {
        for i in 0..FFT_SIZE_BY_2_PLUS_1 {
            self.hist[i].observe(magnitude2[i]);
            self.noise_quantile[i] = self.hist[i].quantile(self.quantile).max(EPSILON);
        }
    }

    fn noise(&self) -> &[f32; FFT_SIZE_BY_2_PLUS_1] {
        &self.noise_quantile
    }
}

// ============================================================================
// Noise Estimator (matches noise_estimator.zig)
// ============================================================================

struct NoiseEstimator {
    quantile: QuantileNoiseEstimator,
    noise_update_rate: f32,
    min_noise_floor: f32,
    noise_psd: [f32; FFT_SIZE_BY_2_PLUS_1],
}

impl NoiseEstimator {
    fn new(noise_update_rate: f32, min_noise_floor: f32) -> Self {
        Self {
            quantile: QuantileNoiseEstimator::new(),
            noise_update_rate,
            min_noise_floor,
            noise_psd: [min_noise_floor; FFT_SIZE_BY_2_PLUS_1],
        }
    }

    fn update(&mut self, magnitude2: &[f32; FFT_SIZE_BY_2_PLUS_1]) {
        self.quantile.update(magnitude2);
        let qn = self.quantile.noise();
        for i in 0..FFT_SIZE_BY_2_PLUS_1 {
            let next =
                self.noise_update_rate * self.noise_psd[i] + (1.0 - self.noise_update_rate) * qn[i];
            self.noise_psd[i] = next.max(self.min_noise_floor);
        }
    }

    fn noise(&self) -> &[f32; FFT_SIZE_BY_2_PLUS_1] {
        &self.noise_psd
    }
}

// ============================================================================
// Signal Model (matches signal_model.zig)
// ============================================================================

struct SignalModel {
    posterior_snr: [f32; FFT_SIZE_BY_2_PLUS_1],
}

impl SignalModel {
    fn new() -> Self {
        Self {
            posterior_snr: [1.0; FFT_SIZE_BY_2_PLUS_1],
        }
    }

    fn update(
        &mut self,
        magnitude2: &[f32; FFT_SIZE_BY_2_PLUS_1],
        noise: &[f32; FFT_SIZE_BY_2_PLUS_1],
    ) {
        for i in 0..FFT_SIZE_BY_2_PLUS_1 {
            let n = noise[i].max(EPSILON);
            self.posterior_snr[i] = (magnitude2[i] / n).clamp(0.0, 1e3);
        }
    }
}

// ============================================================================
// Prior Signal Model (matches prior_signal_model.zig)
// ============================================================================

struct PriorSignalModel {
    prior_snr: [f32; FFT_SIZE_BY_2_PLUS_1],
}

impl PriorSignalModel {
    fn new() -> Self {
        Self {
            prior_snr: [1.0; FFT_SIZE_BY_2_PLUS_1],
        }
    }

    fn update(
        &mut self,
        posterior_snr: &[f32; FFT_SIZE_BY_2_PLUS_1],
        prev_gain: &[f32; FFT_SIZE_BY_2_PLUS_1],
        smoothing: f32,
    ) {
        for i in 0..FFT_SIZE_BY_2_PLUS_1 {
            let decision_directed = prev_gain[i] * prev_gain[i] * posterior_snr[i];
            let candidate = smoothing * self.prior_snr[i] + (1.0 - smoothing) * decision_directed;
            self.prior_snr[i] = candidate.clamp(0.0, 1e3);
        }
    }
}

// ============================================================================
// Speech Probability Estimator (matches speech_probability_estimator.zig)
// ============================================================================

struct SpeechProbabilityEstimator;

impl SpeechProbabilityEstimator {
    fn estimate(
        &self,
        prior_snr: &[f32; FFT_SIZE_BY_2_PLUS_1],
        out_prob: &mut [f32; FFT_SIZE_BY_2_PLUS_1],
    ) {
        for i in 0..FFT_SIZE_BY_2_PLUS_1 {
            let x = 0.5 * (prior_snr[i] - 1.0);
            let tx = x.tanh();
            out_prob[i] = (0.5 * (1.0 + tx)).clamp(0.0, 1.0);
        }
    }
}

// ============================================================================
// Wiener Filter (matches wiener_filter.zig)
// ============================================================================

struct WienerFilter {
    floor_gain: f32,
    max_gain: f32,
}

impl WienerFilter {
    fn new(floor_gain: f32, max_gain: f32) -> Self {
        Self {
            floor_gain,
            max_gain,
        }
    }

    fn compute_gain(
        &self,
        prior_snr: &[f32; FFT_SIZE_BY_2_PLUS_1],
        speech_prob: &[f32; FFT_SIZE_BY_2_PLUS_1],
        out_gain: &mut [f32; FFT_SIZE_BY_2_PLUS_1],
    ) {
        for i in 0..FFT_SIZE_BY_2_PLUS_1 {
            let s = prior_snr[i].max(0.0);
            let p = speech_prob[i].clamp(0.0, 1.0);
            let h = p * s / (1.0 + s);
            out_gain[i] = h.clamp(self.floor_gain, self.max_gain);
        }
    }
}

// ============================================================================
// FFT (matches ns_fft.zig behavior)
// ============================================================================

fn fft(input: &[f32; FFT_SIZE]) -> ([f32; FFT_SIZE_BY_2_PLUS_1], [f32; FFT_SIZE_BY_2_PLUS_1]) {
    let mut re = [0.0f32; FFT_SIZE_BY_2_PLUS_1];
    let mut im = [0.0f32; FFT_SIZE_BY_2_PLUS_1];

    for k in 0..FFT_SIZE_BY_2_PLUS_1 {
        for i in 0..FFT_SIZE {
            let angle = 2.0 * PI * (k as f32) * (i as f32) / (FFT_SIZE as f32);
            re[k] += input[i] * angle.cos();
            im[k] -= input[i] * angle.sin();
        }
    }

    (re, im)
}

fn ifft(re: &[f32; FFT_SIZE_BY_2_PLUS_1], im: &[f32; FFT_SIZE_BY_2_PLUS_1]) -> [f32; FFT_SIZE] {
    let mut out = [0.0f32; FFT_SIZE];

    for i in 0..FFT_SIZE {
        let mut sum = 0.0f32;
        for k in 0..FFT_SIZE_BY_2_PLUS_1 {
            let angle = 2.0 * PI * (k as f32) * (i as f32) / (FFT_SIZE as f32);
            sum += re[k] * angle.cos() - im[k] * angle.sin();
            if k > 0 && k < FFT_SIZE_BY_2_PLUS_1 - 1 {
                // Conjugate symmetric contribution
                sum += re[k] * angle.cos() + im[k] * angle.sin();
            }
        }
        out[i] = sum / (FFT_SIZE as f32);
    }

    out
}

// ============================================================================
// Noise Suppressor (matches noise_suppressor.zig)
// ============================================================================

struct NoiseSuppressor {
    noise_estimator: NoiseEstimator,
    signal_model: SignalModel,
    prior_model: PriorSignalModel,
    speech_prob_estimator: SpeechProbabilityEstimator,
    wiener_filter: WienerFilter,
    prev_gain: [f32; FFT_SIZE_BY_2_PLUS_1],
    prior_snr_smoothing: f32,
}

impl NoiseSuppressor {
    fn new() -> Self {
        // Default config matches Zig: level=moderate, noise_update_rate=0.98
        Self {
            noise_estimator: NoiseEstimator::new(0.98, 1e-4),
            signal_model: SignalModel::new(),
            prior_model: PriorSignalModel::new(),
            speech_prob_estimator: SpeechProbabilityEstimator,
            wiener_filter: WienerFilter::new(0.12, 1.0),
            prev_gain: [1.0; FFT_SIZE_BY_2_PLUS_1],
            prior_snr_smoothing: 0.85,
        }
    }

    fn analyze(&mut self, frame: &[f32; FRAME_SIZE]) {
        let (real, imag) = fft(frame);

        let mut magnitude2 = [0.0f32; FFT_SIZE_BY_2_PLUS_1];
        for i in 0..FFT_SIZE_BY_2_PLUS_1 {
            magnitude2[i] = real[i] * real[i] + imag[i] * imag[i];
        }

        self.noise_estimator.update(&magnitude2);
    }

    fn process(&mut self, frame: &mut [f32; FRAME_SIZE]) {
        let (real, imag) = fft(frame);

        let mut magnitude2 = [0.0f32; FFT_SIZE_BY_2_PLUS_1];
        for i in 0..FFT_SIZE_BY_2_PLUS_1 {
            magnitude2[i] = real[i] * real[i] + imag[i] * imag[i];
        }

        let noise_psd = *self.noise_estimator.noise();
        self.signal_model.update(&magnitude2, &noise_psd);
        self.prior_model.update(
            &self.signal_model.posterior_snr,
            &self.prev_gain,
            self.prior_snr_smoothing,
        );

        let mut speech_prob = [0.0f32; FFT_SIZE_BY_2_PLUS_1];
        self.speech_prob_estimator
            .estimate(&self.prior_model.prior_snr, &mut speech_prob);

        let mut gain = [0.0f32; FFT_SIZE_BY_2_PLUS_1];
        self.wiener_filter
            .compute_gain(&self.prior_model.prior_snr, &speech_prob, &mut gain);

        let mut real_scaled = real;
        let mut imag_scaled = imag;
        for i in 0..FFT_SIZE_BY_2_PLUS_1 {
            real_scaled[i] *= gain[i];
            imag_scaled[i] *= gain[i];
            self.prev_gain[i] = gain[i];
        }

        let out = ifft(&real_scaled, &imag_scaled);

        // Apply 0.5 scale to match the 2.0 scale in ifft (matches Zig)
        for i in 0..FRAME_SIZE {
            frame[i] = (out[i] * 0.5).clamp(-1.0, 1.0);
        }
    }
}

// ============================================================================
// Golden vector output
// ============================================================================

fn print_vector_f32(name: &str, data: &[f32]) {
    println!("BEGIN {} {}", name, data.len());
    for (i, v) in data.iter().enumerate() {
        println!("{}[{}]={:.9}", name, i, v);
    }
    println!("END {}", name);
}

fn main() {
    // Output header only (no cargo logs)
    println!("# NS (Noise Suppression) Golden Vectors");
    println!("# Generated by gen_ns_golden.rs");
    println!("# Algorithm: Full NS chain matching Zig implementation");
    println!("# Components: QuantileNoiseEstimator, SignalModel, PriorSignalModel, SpeechProbability, WienerFilter");
    println!("# Covers: silence, low amplitude, near full scale, speech+noise");
    println!();

    // Case 1: Silence (all zeros)
    {
        let mut ns = NoiseSuppressor::new();
        let mut frame = [0.0f32; FRAME_SIZE];

        // Warm-up
        for _ in 0..5 {
            ns.analyze(&frame);
            ns.process(&mut frame);
        }

        // Final pass with fresh silence
        frame = [0.0f32; FRAME_SIZE];
        let input = frame.clone();
        ns.analyze(&frame);
        ns.process(&mut frame);

        print_vector_f32("NS_SILENCE_INPUT", &input);
        print_vector_f32("NS_SILENCE_OUTPUT", &frame);
        print_vector_f32("NS_SILENCE_NOISE", ns.noise_estimator.noise());
    }

    // Case 2: Low amplitude signal
    {
        let mut ns = NoiseSuppressor::new();
        let mut frame = [0.0f32; FRAME_SIZE];

        // Generate low amplitude sine wave
        for i in 0..FRAME_SIZE {
            let t = i as f32 / SAMPLE_RATE_HZ;
            frame[i] = 0.001 * (2.0 * PI * 500.0 * t).sin();
        }

        let input = frame.clone();
        print_vector_f32("NS_LOWAMP_INPUT", &input);

        // Warm-up
        for _ in 0..5 {
            ns.analyze(&frame);
            ns.process(&mut frame);
        }

        // Regenerate input for final pass
        for i in 0..FRAME_SIZE {
            let t = i as f32 / SAMPLE_RATE_HZ;
            frame[i] = 0.001 * (2.0 * PI * 500.0 * t).sin();
        }
        ns.analyze(&frame);
        ns.process(&mut frame);

        print_vector_f32("NS_LOWAMP_OUTPUT", &frame);
        print_vector_f32("NS_LOWAMP_NOISE", ns.noise_estimator.noise());
    }

    // Case 3: Near full scale signal
    {
        let mut ns = NoiseSuppressor::new();
        let mut frame = [0.0f32; FRAME_SIZE];

        // Generate near full scale sine wave
        for i in 0..FRAME_SIZE {
            let t = i as f32 / SAMPLE_RATE_HZ;
            frame[i] = 0.9 * (2.0 * PI * 1000.0 * t).sin();
        }

        let input = frame.clone();
        print_vector_f32("NS_FULLSCALE_INPUT", &input);

        // Warm-up
        for _ in 0..5 {
            ns.analyze(&frame);
            ns.process(&mut frame);
        }

        // Regenerate input for final pass
        for i in 0..FRAME_SIZE {
            let t = i as f32 / SAMPLE_RATE_HZ;
            frame[i] = 0.9 * (2.0 * PI * 1000.0 * t).sin();
        }
        ns.analyze(&frame);
        ns.process(&mut frame);

        print_vector_f32("NS_FULLSCALE_OUTPUT", &frame);
        print_vector_f32("NS_FULLSCALE_NOISE", ns.noise_estimator.noise());
    }

    // Case 4: Speech + noise (mixed signal)
    {
        let mut ns = NoiseSuppressor::new();
        let mut frame = [0.0f32; FRAME_SIZE];

        // Generate speech-like signal (multiple harmonics) + noise
        for i in 0..FRAME_SIZE {
            let t = i as f32 / SAMPLE_RATE_HZ;
            let speech = 0.3 * (2.0 * PI * 200.0 * t).sin()
                + 0.15 * (2.0 * PI * 400.0 * t).sin()
                + 0.08 * (2.0 * PI * 800.0 * t).sin();
            let noise = 0.05 * ((i % 7) as f32 - 3.0) / 3.0;
            frame[i] = speech + noise;
        }

        let input = frame.clone();
        print_vector_f32("NS_SPEECHNOISE_INPUT", &input);

        // Warm-up
        for _ in 0..10 {
            ns.analyze(&frame);
            ns.process(&mut frame);
        }

        // Regenerate input for final pass
        for i in 0..FRAME_SIZE {
            let t = i as f32 / SAMPLE_RATE_HZ;
            let speech = 0.3 * (2.0 * PI * 200.0 * t).sin()
                + 0.15 * (2.0 * PI * 400.0 * t).sin()
                + 0.08 * (2.0 * PI * 800.0 * t).sin();
            let noise = 0.05 * ((i % 7) as f32 - 3.0) / 3.0;
            frame[i] = speech + noise;
        }

        ns.analyze(&frame);
        ns.process(&mut frame);

        print_vector_f32("NS_SPEECHNOISE_OUTPUT", &frame);
        print_vector_f32("NS_SPEECHNOISE_NOISE", ns.noise_estimator.noise());
    }
}

use std::process::abort;

fn assert(condition: bool) {
    if !condition {
        abort();
    }
}
