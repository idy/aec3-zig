//! Generates audio-infrastructure golden vectors in text format for Zig cross-validation.
//!
//! Usage:
//!   cargo run --release --bin gen-audio-infra-golden > ../vectors/rust_audio_infra_golden_vectors.txt

use std::f32::consts::PI;

const KERNEL_SIZE: usize = 32;
const KERNEL_OFFSET_COUNT: usize = 32;
const KERNEL_STORAGE_SIZE: usize = KERNEL_SIZE * (KERNEL_OFFSET_COUNT + 1);

const NUM_BANDS: usize = 3;
const SPARSITY: usize = 4;

const LOWPASS_COEFFS: [[f32; 4]; NUM_BANDS * SPARSITY] = [
    [-0.00047749, -0.00496888, 0.16547118, 0.00425496],
    [-0.00173287, -0.01585778, 0.14989004, 0.00994113],
    [-0.00304815, -0.02536082, 0.12154542, 0.01157993],
    [-0.00383509, -0.02982767, 0.08543175, 0.00983212],
    [-0.00346946, -0.02587886, 0.04760441, 0.00607594],
    [-0.00154717, -0.01136076, 0.01387458, 0.00186353],
    [0.00186353, 0.01387458, -0.01136076, -0.00154717],
    [0.00607594, 0.04760441, -0.02587886, -0.00346946],
    [0.00983212, 0.08543175, -0.02982767, -0.00383509],
    [0.01157993, 0.12154542, -0.02536082, -0.00304815],
    [0.00994113, 0.14989004, -0.01585778, -0.00173287],
    [0.00425496, 0.16547118, -0.00496888, -0.00047749],
];

#[derive(Clone)]
struct SparseFir {
    sparsity: usize,
    offset: usize,
    coeffs: Vec<f32>,
    state: Vec<f32>,
}

impl SparseFir {
    fn new(nonzero_coeffs: &[f32], sparsity: usize, offset: usize) -> Self {
        let state_len = if nonzero_coeffs.len() > 1 {
            sparsity * (nonzero_coeffs.len() - 1) + offset
        } else {
            offset
        };
        Self {
            sparsity,
            offset,
            coeffs: nonzero_coeffs.to_vec(),
            state: vec![0.0; state_len],
        }
    }

    fn filter(&mut self, input: &[f32]) -> Vec<f32> {
        let mut output = vec![0.0f32; input.len()];
        self.filter_into(input, &mut output);
        output
    }

    fn filter_into(&mut self, input: &[f32], output: &mut [f32]) {
        assert_eq!(input.len(), output.len());

        for (i, out) in output.iter_mut().enumerate() {
            let mut acc = 0.0f32;
            for tap in 0..self.coeffs.len() {
                let idx = tap * self.sparsity + self.offset;
                if i >= idx {
                    acc += input[i - idx] * self.coeffs[tap];
                } else {
                    let state_index = i + (self.coeffs.len() - tap - 1) * self.sparsity;
                    if state_index < self.state.len() {
                        acc += self.state[state_index] * self.coeffs[tap];
                    }
                }
            }
            *out = acc;
        }

        if !self.state.is_empty() {
            let state_len = self.state.len();
            if input.len() >= state_len {
                self.state
                    .copy_from_slice(&input[input.len() - state_len..]);
            } else {
                self.state.copy_within(input.len().., 0);
                self.state[state_len - input.len()..].copy_from_slice(input);
            }
        }
    }
}

#[derive(Clone, Copy)]
struct Biquad {
    b: [f32; 3],
    a: [f32; 2],
    x: [f32; 2],
    y: [f32; 2],
}

impl Biquad {
    fn new(b: [f32; 3], a: [f32; 2]) -> Self {
        Self {
            b,
            a,
            x: [0.0; 2],
            y: [0.0; 2],
        }
    }

    fn process_in_place(&mut self, data: &mut [f32]) {
        for sample in data {
            let input = *sample;
            let out = self.b[0] * input + self.b[1] * self.x[0] + self.b[2] * self.x[1]
                - self.a[0] * self.y[0]
                - self.a[1] * self.y[1];
            self.x[1] = self.x[0];
            self.x[0] = input;
            self.y[1] = self.y[0];
            self.y[0] = out;
            *sample = out;
        }
    }
}

struct SincResamplerRef {
    io_sample_rate_ratio: f64,
    request_frames: usize,
    kernel_storage: Vec<f32>,
    kernel_pre_sinc_storage: Vec<f32>,
    kernel_window_storage: Vec<f32>,
    input_buffer: Vec<f32>,
    virtual_source_idx: f64,
    buffer_primed: bool,
    block_size: usize,
    r0: usize,
    r1: usize,
    r2: usize,
    r3: usize,
    r4: usize,
}

impl SincResamplerRef {
    fn new(io_sample_rate_ratio: f64, request_frames: usize) -> Self {
        assert!(request_frames > 0);
        assert!(io_sample_rate_ratio > 0.0);

        let input_buffer_size = request_frames + KERNEL_SIZE;
        let mut s = Self {
            io_sample_rate_ratio,
            request_frames,
            kernel_storage: vec![0.0; KERNEL_STORAGE_SIZE],
            kernel_pre_sinc_storage: vec![0.0; KERNEL_STORAGE_SIZE],
            kernel_window_storage: vec![0.0; KERNEL_STORAGE_SIZE],
            input_buffer: vec![0.0; input_buffer_size],
            virtual_source_idx: 0.0,
            buffer_primed: false,
            block_size: 0,
            r0: 0,
            r1: 0,
            r2: KERNEL_SIZE / 2,
            r3: 0,
            r4: 0,
        };

        s.initialize_kernel();
        s.flush();
        assert!(s.block_size > KERNEL_SIZE);
        s
    }

    fn flush(&mut self) {
        self.virtual_source_idx = 0.0;
        self.buffer_primed = false;
        self.input_buffer.fill(0.0);
        self.update_regions(false);
    }

    fn resample(&mut self, frames: usize, source: &[f32]) -> Vec<f32> {
        let mut destination = vec![0.0f32; frames];
        if frames == 0 {
            return destination;
        }

        let mut consumed = 0usize;

        if !self.buffer_primed {
            Self::fill_input(
                source,
                &mut consumed,
                &mut self.input_buffer[self.r0..self.r0 + self.request_frames],
            );
            self.buffer_primed = true;
        }

        let current_ratio = self.io_sample_rate_ratio;
        let mut remaining = frames;
        let mut dest_index = 0usize;

        while remaining > 0 {
            let mut iterations = (((self.block_size as f64) - self.virtual_source_idx)
                / current_ratio)
                .ceil() as i64;
            if iterations < 0 {
                iterations = 0;
            }

            while iterations > 0 {
                let source_idx_f = self.virtual_source_idx.max(0.0);
                let source_idx = source_idx_f.floor() as usize;
                let subsample_remainder = source_idx_f - (source_idx as f64);
                let virtual_offset_idx = subsample_remainder * (KERNEL_OFFSET_COUNT as f64);
                let offset_idx_raw = virtual_offset_idx.floor() as usize;
                let offset_idx = offset_idx_raw.min(KERNEL_OFFSET_COUNT - 1);
                let interp = virtual_offset_idx - (offset_idx as f64);
                let k1_start = offset_idx * KERNEL_SIZE;

                let k1 = &self.kernel_storage[k1_start..k1_start + KERNEL_SIZE];
                let k2 = &self.kernel_storage[k1_start + KERNEL_SIZE..k1_start + 2 * KERNEL_SIZE];

                let input_idx = self.r1 + source_idx;
                let input = &self.input_buffer[input_idx..input_idx + KERNEL_SIZE];
                destination[dest_index] = convolve(input, k1, k2, interp);

                dest_index += 1;
                remaining -= 1;
                self.virtual_source_idx += current_ratio;
                if remaining == 0 {
                    return destination;
                }

                iterations -= 1;
            }

            self.virtual_source_idx -= self.block_size as f64;

            let carry = self.input_buffer[self.r3..self.r3 + KERNEL_SIZE].to_vec();
            self.input_buffer[self.r1..self.r1 + KERNEL_SIZE].copy_from_slice(&carry);

            if self.r0 == self.r2 {
                self.update_regions(true);
            }

            Self::fill_input(
                source,
                &mut consumed,
                &mut self.input_buffer[self.r0..self.r0 + self.request_frames],
            );
        }

        destination
    }

    fn update_regions(&mut self, second_load: bool) {
        self.r0 = if second_load {
            KERNEL_SIZE
        } else {
            KERNEL_SIZE / 2
        };
        self.r3 = self.r0 + self.request_frames - KERNEL_SIZE;
        self.r4 = self.r0 + self.request_frames - KERNEL_SIZE / 2;
        self.block_size = self.r4 - self.r2;
        self.r1 = 0;
    }

    fn initialize_kernel(&mut self) {
        let alpha = 0.16f64;
        let a0 = 0.5 * (1.0 - alpha);
        let a1 = 0.5;
        let a2 = 0.5 * alpha;
        let sinc_factor = sinc_scale_factor(self.io_sample_rate_ratio);

        for offset_idx in 0..=KERNEL_OFFSET_COUNT {
            let subsample_offset = (offset_idx as f64) / (KERNEL_OFFSET_COUNT as f64);
            for i in 0..KERNEL_SIZE {
                let idx = i + offset_idx * KERNEL_SIZE;
                let half_kernel = (KERNEL_SIZE as f64) / 2.0;
                let pre_sinc = PI as f64 * ((i as f64) - half_kernel - subsample_offset);
                self.kernel_pre_sinc_storage[idx] = pre_sinc as f32;

                let x = ((i as f64) - subsample_offset) / (KERNEL_SIZE as f64);
                let window =
                    a0 - a1 * (2.0 * PI as f64 * x).cos() + a2 * (4.0 * PI as f64 * x).cos();
                self.kernel_window_storage[idx] = window as f32;

                let value = if pre_sinc == 0.0 {
                    sinc_factor
                } else {
                    (sinc_factor * pre_sinc).sin() / pre_sinc
                };
                self.kernel_storage[idx] = (window * value) as f32;
            }
        }
    }

    fn fill_input(source: &[f32], consumed: &mut usize, dest: &mut [f32]) {
        let available = source.len().saturating_sub((*consumed).min(source.len()));
        let n = available.min(dest.len());
        if n > 0 {
            dest[0..n].copy_from_slice(&source[*consumed..*consumed + n]);
            *consumed += n;
        }
        if n < dest.len() {
            dest[n..].fill(0.0);
        }
    }
}

struct ThreeBandFilterBankRef {
    in_buffer: Vec<f32>,
    out_buffer: Vec<f32>,
    analysis_filters: Vec<SparseFir>,
    synthesis_filters: Vec<SparseFir>,
    dct_modulation: [[f32; NUM_BANDS]; NUM_BANDS * SPARSITY],
}

impl ThreeBandFilterBankRef {
    fn new(length: usize) -> Self {
        assert_eq!(length % NUM_BANDS, 0);
        let split_length = length / NUM_BANDS;

        let mut analysis_filters = Vec::with_capacity(NUM_BANDS * SPARSITY);
        let mut synthesis_filters = Vec::with_capacity(NUM_BANDS * SPARSITY);
        for i in 0..SPARSITY {
            for j in 0..NUM_BANDS {
                let idx = i * NUM_BANDS + j;
                analysis_filters.push(SparseFir::new(&LOWPASS_COEFFS[idx], SPARSITY, i));
                synthesis_filters.push(SparseFir::new(&LOWPASS_COEFFS[idx], SPARSITY, i));
            }
        }

        let mut dct_modulation = [[0.0f32; NUM_BANDS]; NUM_BANDS * SPARSITY];
        for idx in 0..(NUM_BANDS * SPARSITY) {
            for band in 0..NUM_BANDS {
                dct_modulation[idx][band] = 2.0
                    * ((2.0 * PI * (idx as f32) * (2.0 * (band as f32) + 1.0)
                        / ((NUM_BANDS * SPARSITY) as f32))
                        .cos());
            }
        }

        Self {
            in_buffer: vec![0.0; split_length],
            out_buffer: vec![0.0; split_length],
            analysis_filters,
            synthesis_filters,
            dct_modulation,
        }
    }

    fn analysis(&mut self, input: &[f32]) -> [Vec<f32>; NUM_BANDS] {
        let split_length = self.in_buffer.len();
        assert_eq!(input.len(), split_length * NUM_BANDS);

        let mut out = [
            vec![0.0f32; split_length],
            vec![0.0f32; split_length],
            vec![0.0f32; split_length],
        ];

        for i in 0..NUM_BANDS {
            downsample(input, split_length, NUM_BANDS - i - 1, &mut self.in_buffer);
            for j in 0..SPARSITY {
                let offset = i + j * NUM_BANDS;
                self.analysis_filters[offset].filter_into(&self.in_buffer, &mut self.out_buffer);
                down_modulate(&self.out_buffer, offset, &self.dct_modulation, &mut out);
            }
        }

        out
    }

    fn synthesis(&mut self, input: [&[f32]; NUM_BANDS]) -> Vec<f32> {
        let split_length = self.in_buffer.len();
        let mut out = vec![0.0f32; split_length * NUM_BANDS];

        for i in 0..NUM_BANDS {
            for j in 0..SPARSITY {
                let offset = i + j * NUM_BANDS;
                up_modulate(
                    &input,
                    split_length,
                    offset,
                    &self.dct_modulation,
                    &mut self.in_buffer,
                );
                self.synthesis_filters[offset].filter_into(&self.in_buffer, &mut self.out_buffer);
                upsample(&self.out_buffer, i, &mut out);
            }
        }

        out
    }
}

fn downsample(input: &[f32], split_length: usize, offset: usize, out: &mut [f32]) {
    for i in 0..split_length {
        out[i] = input[NUM_BANDS * i + offset];
    }
}

fn upsample(input: &[f32], offset: usize, out: &mut [f32]) {
    let split_length = input.len();
    for i in 0..split_length {
        out[NUM_BANDS * i + offset] += (NUM_BANDS as f32) * input[i];
    }
}

fn down_modulate(
    input: &[f32],
    modulation_index: usize,
    dct_modulation: &[[f32; NUM_BANDS]; NUM_BANDS * SPARSITY],
    out: &mut [Vec<f32>; NUM_BANDS],
) {
    for band in 0..NUM_BANDS {
        for (j, sample) in input.iter().enumerate() {
            out[band][j] += dct_modulation[modulation_index][band] * sample;
        }
    }
}

fn up_modulate(
    input: &[&[f32]; NUM_BANDS],
    split_length: usize,
    modulation_index: usize,
    dct_modulation: &[[f32; NUM_BANDS]; NUM_BANDS * SPARSITY],
    out: &mut [f32],
) {
    out.fill(0.0);
    for band in 0..NUM_BANDS {
        for i in 0..split_length {
            out[i] += dct_modulation[modulation_index][band] * input[band][i];
        }
    }
}

fn convolve(input: &[f32], k1: &[f32], k2: &[f32], interp: f64) -> f32 {
    let mut sum1 = 0.0f32;
    let mut sum2 = 0.0f32;
    for i in 0..KERNEL_SIZE {
        sum1 += input[i] * k1[i];
        sum2 += input[i] * k2[i];
    }
    ((1.0 - interp) * (sum1 as f64) + interp * (sum2 as f64)) as f32
}

fn sinc_scale_factor(io_ratio: f64) -> f64 {
    let factor = if io_ratio > 1.0 { 1.0 / io_ratio } else { 1.0 };
    factor * 0.9
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

fn algorithmic_delay_seconds(source_rate_hz: i32) -> f32 {
    if source_rate_hz <= 0 {
        0.0
    } else {
        (1.0 / source_rate_hz as f32) * (KERNEL_SIZE as f32 / 2.0)
    }
}

fn main() {
    // ── Sparse FIR golden vectors (stateful two-block run) ──
    let mut sparse = SparseFir::new(&[0.8, -0.3, 0.1], 2, 1);
    let block1: [f32; 8] = [0.1, 0.4, -0.2, 0.7, -0.5, 0.3, 0.9, -0.8];
    let block2: [f32; 8] = [0.6, -0.1, 0.2, -0.4, 0.5, -0.7, 0.8, -0.9];
    let out1 = sparse.filter(&block1);
    let out2 = sparse.filter(&block2);

    print_vector_f32("SPARSE_FIR_BLOCK1_IN8", &block1);
    print_vector_f32("SPARSE_FIR_BLOCK2_IN8", &block2);
    print_vector_f32("SPARSE_FIR_BLOCK1_OUT8", &out1);
    print_vector_f32("SPARSE_FIR_BLOCK2_OUT8", &out2);

    // ── Cascaded biquad golden vector ──
    let mut biquad = Biquad::new([0.98621, -1.97242, 0.98621], [-1.97223, 0.97261]);
    let mut biquad_in = [0.0f32; 32];
    for (i, v) in biquad_in.iter_mut().enumerate() {
        let x = i as f32;
        *v = 0.45 * (x * 0.17).sin() - 0.21 * (x * 0.09).cos() + ((i as i32 - 16) as f32 / 256.0);
    }
    let mut biquad_out = biquad_in;
    biquad.process_in_place(&mut biquad_out);
    print_vector_f32("CASCADED_BIQUAD_INPUT32", &biquad_in);
    print_vector_f32("CASCADED_BIQUAD_OUTPUT32", &biquad_out);

    // ── HighPassFilter-compatible golden vector (single-channel, 16k coeffs) ──
    let mut hp_biquad = Biquad::new([0.97261, -1.94523, 0.97261], [-1.94448, 0.94598]);
    let mut hp_in = [0.0f32; 64];
    for (i, v) in hp_in.iter_mut().enumerate() {
        let t = i as f32 / 16000.0;
        *v = (2.0 * PI * 90.0 * t).sin() + 0.4 * (2.0 * PI * 1800.0 * t).sin();
    }
    let mut hp_out = hp_in;
    hp_biquad.process_in_place(&mut hp_out);
    print_vector_f32("HIGH_PASS_INPUT64", &hp_in);
    print_vector_f32("HIGH_PASS_OUTPUT64", &hp_out);

    // ── SincResampler golden vector ──
    let mut sinc_input = [0.0f32; 64];
    for (i, v) in sinc_input.iter_mut().enumerate() {
        let x = i as f32;
        *v = 0.3 * (x * 0.21).sin() + 0.17 * (x * 0.07).cos() + ((i as i32 - 32) as f32 / 256.0);
    }
    let mut sinc = SincResamplerRef::new(64.0 / 192.0, 64);
    let sinc_out = sinc.resample(48, &sinc_input);
    print_vector_f32("SINC_RESAMPLER_INPUT64", &sinc_input);
    print_vector_f32("SINC_RESAMPLER_OUTPUT48", &sinc_out);

    // ── ThreeBandFilterBank golden vectors ──
    let mut three_band_in = [0.0f32; 96];
    for (i, v) in three_band_in.iter_mut().enumerate() {
        let t = (i as f32) / 48_000.0;
        *v = 0.8 * (2.0 * PI * 440.0 * t).sin() + 0.35 * (2.0 * PI * 3300.0 * t).sin();
    }
    let mut fb = ThreeBandFilterBankRef::new(96);
    let bands = fb.analysis(&three_band_in);
    let recon = fb.synthesis([&bands[0], &bands[1], &bands[2]]);
    print_vector_f32("THREE_BAND_INPUT96", &three_band_in);
    print_vector_f32("THREE_BAND_ANALYSIS_BAND0_32", &bands[0]);
    print_vector_f32("THREE_BAND_ANALYSIS_BAND1_32", &bands[1]);
    print_vector_f32("THREE_BAND_ANALYSIS_BAND2_32", &bands[2]);
    print_vector_f32("THREE_BAND_RECON96", &recon);

    // ── PushSincResampler::algorithmic_delay_seconds golden vectors ──
    let delay_rates: [i32; 5] = [-16000, 0, 8000, 16000, 48000];
    let delay_expected: Vec<f32> = delay_rates
        .iter()
        .map(|&hz| algorithmic_delay_seconds(hz))
        .collect();
    print_vector_i32("PUSH_SINC_DELAY_RATES5", &delay_rates);
    print_vector_f32("PUSH_SINC_DELAY_EXPECTED5", &delay_expected);
}
