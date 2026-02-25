//! Ported from: docs/aec3-rs-src/audio_processing/aec3/aec3_common.rs
const std = @import("std");

/// SIMD optimization level for AEC3.
pub const Aec3Optimization = enum {
    none,
    sse2,
    neon,
};

pub const NUM_BLOCKS_PER_SECOND: usize = 250;
pub const METRICS_REPORTING_INTERVAL_BLOCKS: usize = 10 * NUM_BLOCKS_PER_SECOND;
pub const METRICS_COMPUTATION_BLOCKS: usize = 11;
pub const METRICS_COLLECTION_BLOCKS: usize = METRICS_REPORTING_INTERVAL_BLOCKS - METRICS_COMPUTATION_BLOCKS;
pub const FFT_LENGTH_BY_2: usize = 64;
pub const FFT_LENGTH_BY_2_PLUS_1: usize = FFT_LENGTH_BY_2 + 1;
pub const FFT_LENGTH_BY_2_MINUS_1: usize = FFT_LENGTH_BY_2 - 1;
pub const FFT_LENGTH: usize = 2 * FFT_LENGTH_BY_2;
pub const FFT_LENGTH_BY_2_LOG2: usize = 6;
pub const RENDER_TRANSFER_QUEUE_SIZE_FRAMES: usize = 100;
pub const MAX_NUM_BANDS: usize = 3;
pub const FRAME_SIZE: usize = 160;
pub const SUB_FRAME_LENGTH: usize = FRAME_SIZE / 2;
pub const BLOCK_SIZE: usize = FFT_LENGTH_BY_2;
pub const BLOCK_SIZE_LOG2: usize = FFT_LENGTH_BY_2_LOG2;
pub const EXTENDED_BLOCK_SIZE: usize = 2 * FFT_LENGTH_BY_2;
pub const MATCHED_FILTER_WINDOW_SIZE_SUB_BLOCKS: usize = 32;
pub const MATCHED_FILTER_ALIGNMENT_SHIFT_SIZE_SUB_BLOCKS: usize = MATCHED_FILTER_WINDOW_SIZE_SUB_BLOCKS * 3 / 4;

/// Returns the number of bands for a given sample rate.
/// 16kHz -> 1 band, 32kHz -> 2 bands, 48kHz -> 3 bands.
pub fn num_bands_for_rate(sample_rate_hz: i32) usize {
    if (sample_rate_hz <= 0) return 0;
    return @as(usize, @intCast(sample_rate_hz)) / 16_000;
}

/// Returns true if the sample rate is a valid full-band rate (16kHz, 32kHz, or 48kHz).
pub fn valid_full_band_rate(sample_rate_hz: i32) bool {
    return sample_rate_hz == 16_000 or sample_rate_hz == 32_000 or sample_rate_hz == 48_000;
}

/// Returns the time domain length in samples for a given filter length in blocks.
pub fn get_time_domain_length(filter_length_blocks: usize) usize {
    return filter_length_blocks * FFT_LENGTH_BY_2;
}

/// Returns the size of the downsampled buffer.
pub fn get_down_sampled_buffer_size(down_sampling_factor: usize, num_matched_filters: usize) !usize {
    if (down_sampling_factor == 0) return error.InvalidDownSamplingFactor;
    const blocks_per_factor = BLOCK_SIZE / down_sampling_factor;
    return blocks_per_factor *
        (MATCHED_FILTER_ALIGNMENT_SHIFT_SIZE_SUB_BLOCKS * num_matched_filters + MATCHED_FILTER_WINDOW_SIZE_SUB_BLOCKS + 1);
}

/// Returns the size of the render delay buffer.
pub fn get_render_delay_buffer_size(down_sampling_factor: usize, num_matched_filters: usize, filter_length_blocks: usize) !usize {
    if (down_sampling_factor == 0) return error.InvalidDownSamplingFactor;
    const base = try get_down_sampled_buffer_size(down_sampling_factor, num_matched_filters);
    const blocks_per_factor = BLOCK_SIZE / down_sampling_factor;
    return base / blocks_per_factor + filter_length_blocks + 1;
}

/// Fast approximation of log2 using IEEE 754 bit manipulation.
/// Note: input must be positive.
pub fn fast_approx_log2f(input: f32) f32 {
    std.debug.assert(input > 0.0);
    const bits: u32 = @bitCast(input);
    var out: f32 = @floatFromInt(bits);
    out *= 1.192_092_9e-7;
    out -= 126.942_695;
    return out;
}

/// Converts log2 value to decibels.
pub fn log2_to_db(in_log2: f32) f32 {
    return 3.010_299_956_639_812 * in_log2;
}

/// Detects the available SIMD optimization at runtime.
pub fn detect_optimization() Aec3Optimization {
    const has_sse2 = detectSse2();
    const has_neon = detectNeon();
    return resolve_optimization(has_sse2, has_neon);
}

fn resolve_optimization(has_sse2: bool, has_neon: bool) Aec3Optimization {
    if (has_sse2) return .sse2;
    if (has_neon) return .neon;
    return .none;
}

fn detectSse2() bool {
    const builtin = @import("builtin");
    if (!builtin.cpu.arch.isX86()) {
        return false;
    }

    const leaf1 = x86CpuidLeaf1();
    const sse2_bit: u32 = 1 << 26;
    return (leaf1.edx & sse2_bit) != 0;
}

fn detectNeon() bool {
    const builtin = @import("builtin");
    const arch = builtin.cpu.arch;
    if (!arch.isArm() and !arch.isAARCH64()) {
        return false;
    }

    if (builtin.os.tag == .linux) {
        const hwcap = std.os.linux.getauxval(std.elf.AT_HWCAP);
        if (arch.isAARCH64()) {
            const HWCAP_ASIMD: usize = 1 << 1;
            return (hwcap & HWCAP_ASIMD) != 0;
        }
        const HWCAP_NEON: usize = 1 << 12;
        return (hwcap & HWCAP_NEON) != 0;
    }

    if (arch.isAARCH64()) {
        return std.Target.aarch64.featureSetHas(builtin.cpu.features, .neon);
    }
    return std.Target.arm.featureSetHas(builtin.cpu.features, .neon);
}

const X86Leaf1 = struct {
    eax: u32,
    ebx: u32,
    ecx: u32,
    edx: u32,
};

fn x86CpuidLeaf1() X86Leaf1 {
    var eax: u32 = 1;
    var ebx: u32 = 0;
    var ecx: u32 = 0;
    var edx: u32 = 0;
    asm volatile ("cpuid"
        : [out_eax] "={eax}" (eax),
          [out_ebx] "={ebx}" (ebx),
          [out_ecx] "={ecx}" (ecx),
          [out_edx] "={edx}" (edx),
        : [in_eax] "{eax}" (eax),
          [in_ecx] "{ecx}" (ecx),
    );
    return .{ .eax = eax, .ebx = ebx, .ecx = ecx, .edx = edx };
}

test "test_num_bands_for_rate" {
    try std.testing.expectEqual(@as(usize, 1), num_bands_for_rate(16_000));
    try std.testing.expectEqual(@as(usize, 2), num_bands_for_rate(32_000));
    try std.testing.expectEqual(@as(usize, 3), num_bands_for_rate(48_000));
    try std.testing.expectEqual(@as(usize, 0), num_bands_for_rate(0));
}

test "test_valid_full_band_rate" {
    try std.testing.expect(valid_full_band_rate(16_000));
    try std.testing.expect(valid_full_band_rate(32_000));
    try std.testing.expect(valid_full_band_rate(48_000));
    try std.testing.expect(!valid_full_band_rate(8_001));
}

test "test_time_domain_length" {
    try std.testing.expectEqual(@as(usize, 0), get_time_domain_length(0));
    try std.testing.expectEqual(@as(usize, 64), get_time_domain_length(1));
    try std.testing.expectEqual(@as(usize, 128), get_time_domain_length(2));
}

test "test_down_sampled_buffer_size" {
    const expected = (BLOCK_SIZE / 4) * (MATCHED_FILTER_ALIGNMENT_SHIFT_SIZE_SUB_BLOCKS * 4 + MATCHED_FILTER_WINDOW_SIZE_SUB_BLOCKS + 1);
    try std.testing.expectEqual(expected, try get_down_sampled_buffer_size(4, 4));
}

test "test_render_delay_buffer_size" {
    const base = try get_down_sampled_buffer_size(4, 4);
    const expected = base / (BLOCK_SIZE / 4) + 12 + 1;
    try std.testing.expectEqual(expected, try get_render_delay_buffer_size(4, 4, 12));
}

test "test_invalid_down_sampling_factor_is_rejected" {
    try std.testing.expectError(error.InvalidDownSamplingFactor, get_down_sampled_buffer_size(0, 4));
    try std.testing.expectError(error.InvalidDownSamplingFactor, get_render_delay_buffer_size(0, 4, 12));
}

test "test_fast_approx_log2f" {
    const values = [_]f32{ 0.5, 1.0, 2.0, 4.0, 100.0, 0.01 };
    for (values) |v| {
        const approx = fast_approx_log2f(v);
        const exact = @log2(v);
        try std.testing.expect(@abs(approx - exact) < 0.2);
    }
}

test "test_log2_to_db" {
    try std.testing.expectApproxEqAbs(@as(f32, 6.020_599_913), log2_to_db(2.0), 1e-6);
}

test "test_detect_optimization" {
    const v = detect_optimization();
    try std.testing.expect(v == .none or v == .sse2 or v == .neon);
}

test "test_detect_optimization_priority_semantics" {
    try std.testing.expectEqual(Aec3Optimization.none, resolve_optimization(false, false));
    try std.testing.expectEqual(Aec3Optimization.neon, resolve_optimization(false, true));
    try std.testing.expectEqual(Aec3Optimization.sse2, resolve_optimization(true, false));
    try std.testing.expectEqual(Aec3Optimization.sse2, resolve_optimization(true, true));
}
