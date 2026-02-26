pub const FFT_SIZE: usize = 256;
pub const FFT_SIZE_BY_2_PLUS_1: usize = FFT_SIZE / 2 + 1;
pub const SAMPLE_RATE_HZ: u32 = 16_000;
pub const FRAME_SIZE: usize = FFT_SIZE;
pub const EPSILON: f32 = 1e-6;
