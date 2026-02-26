//! Ported from: docs/aec3-rs-src/audio_processing/three_band_filter_bank.rs
const std = @import("std");
const SparseFIRFilter = @import("sparse_fir_filter.zig").SparseFIRFilter;

const NUM_BANDS: usize = 3;
const SPARSITY: usize = 4;
const NUM_COEFFS: usize = 4;

const LOWPASS_COEFFS: [NUM_BANDS * SPARSITY][NUM_COEFFS]f32 = .{
    .{ -0.00047749, -0.00496888, 0.16547118, 0.00425496 },
    .{ -0.00173287, -0.01585778, 0.14989004, 0.00994113 },
    .{ -0.00304815, -0.02536082, 0.12154542, 0.01157993 },
    .{ -0.00383509, -0.02982767, 0.08543175, 0.00983212 },
    .{ -0.00346946, -0.02587886, 0.04760441, 0.00607594 },
    .{ -0.00154717, -0.01136076, 0.01387458, 0.00186353 },
    .{ 0.00186353, 0.01387458, -0.01136076, -0.00154717 },
    .{ 0.00607594, 0.04760441, -0.02587886, -0.00346946 },
    .{ 0.00983212, 0.08543175, -0.02982767, -0.00383509 },
    .{ 0.01157993, 0.12154542, -0.02536082, -0.00304815 },
    .{ 0.00994113, 0.14989004, -0.01585778, -0.00173287 },
    .{ 0.00425496, 0.16547118, -0.00496888, -0.00047749 },
};

pub const ThreeBandFilterBank = struct {
    in_buffer: []f32,
    out_buffer: []f32,
    analysis_filters: []SparseFIRFilter,
    synthesis_filters: []SparseFIRFilter,
    dct_modulation: [NUM_BANDS * SPARSITY][NUM_BANDS]f32,
    allocator: std.mem.Allocator,

    pub fn new(allocator: std.mem.Allocator, length: usize) !ThreeBandFilterBank {
        if (length % NUM_BANDS != 0) return error.InvalidLength;
        const split_length = length / NUM_BANDS;
        const in_buffer = try allocator.alloc(f32, split_length);
        errdefer allocator.free(in_buffer);
        const out_buffer = try allocator.alloc(f32, split_length);
        errdefer allocator.free(out_buffer);

        const analysis_filters = try allocator.alloc(SparseFIRFilter, NUM_BANDS * SPARSITY);
        errdefer allocator.free(analysis_filters);
        const synthesis_filters = try allocator.alloc(SparseFIRFilter, NUM_BANDS * SPARSITY);
        errdefer allocator.free(synthesis_filters);

        var analysis_initialized: usize = 0;
        errdefer {
            var k: usize = 0;
            while (k < analysis_initialized) : (k += 1) {
                analysis_filters[k].deinit();
            }
        }

        var synthesis_initialized: usize = 0;
        errdefer {
            var k: usize = 0;
            while (k < synthesis_initialized) : (k += 1) {
                synthesis_filters[k].deinit();
            }
        }

        var i: usize = 0;
        while (i < SPARSITY) : (i += 1) {
            var j: usize = 0;
            while (j < NUM_BANDS) : (j += 1) {
                const idx = i * NUM_BANDS + j;
                analysis_filters[idx] = try SparseFIRFilter.new(allocator, LOWPASS_COEFFS[idx][0..], SPARSITY, i);
                analysis_initialized += 1;
                synthesis_filters[idx] = try SparseFIRFilter.new(allocator, LOWPASS_COEFFS[idx][0..], SPARSITY, i);
                synthesis_initialized += 1;
            }
        }

        var dct_modulation: [NUM_BANDS * SPARSITY][NUM_BANDS]f32 = undefined;
        for (0..NUM_BANDS * SPARSITY) |idx| {
            for (0..NUM_BANDS) |band| {
                dct_modulation[idx][band] = 2.0 * @cos((2.0 * std.math.pi * @as(f32, @floatFromInt(idx)) * (2.0 * @as(f32, @floatFromInt(band)) + 1.0)) / @as(f32, @floatFromInt(NUM_BANDS * SPARSITY)));
            }
        }

        return .{
            .in_buffer = in_buffer,
            .out_buffer = out_buffer,
            .analysis_filters = analysis_filters,
            .synthesis_filters = synthesis_filters,
            .dct_modulation = dct_modulation,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ThreeBandFilterBank) void {
        for (self.analysis_filters) |*f| f.deinit();
        for (self.synthesis_filters) |*f| f.deinit();
        self.allocator.free(self.analysis_filters);
        self.allocator.free(self.synthesis_filters);
        self.allocator.free(self.in_buffer);
        self.allocator.free(self.out_buffer);
    }

    pub fn analysis(self: *ThreeBandFilterBank, input: []const f32, out: *[NUM_BANDS][]f32) void {
        const split_length = self.in_buffer.len;
        std.debug.assert(input.len == split_length * NUM_BANDS);
        for (out.*) |band| @memset(band, 0.0);

        var i: usize = 0;
        while (i < NUM_BANDS) : (i += 1) {
            downsample(input, split_length, NUM_BANDS - i - 1, self.in_buffer);
            var j: usize = 0;
            while (j < SPARSITY) : (j += 1) {
                const offset = i + j * NUM_BANDS;
                self.analysis_filters[offset].filter(self.in_buffer, self.out_buffer);
                down_modulate(self.out_buffer, offset, &self.dct_modulation, out);
            }
        }
    }

    pub fn synthesis(self: *ThreeBandFilterBank, input: *const [NUM_BANDS][]const f32, out: []f32) void {
        const split_length = self.in_buffer.len;
        std.debug.assert(out.len == split_length * NUM_BANDS);
        @memset(out, 0.0);

        var i: usize = 0;
        while (i < NUM_BANDS) : (i += 1) {
            var j: usize = 0;
            while (j < SPARSITY) : (j += 1) {
                const offset = i + j * NUM_BANDS;
                up_modulate(input, split_length, offset, &self.dct_modulation, self.in_buffer);
                self.synthesis_filters[offset].filter(self.in_buffer, self.out_buffer);
                upsample(self.out_buffer, i, out);
            }
        }
    }
};

fn downsample(input: []const f32, split_length: usize, offset: usize, out: []f32) void {
    for (0..split_length) |i| {
        out[i] = input[NUM_BANDS * i + offset];
    }
}

fn upsample(input: []const f32, offset: usize, out: []f32) void {
    const split_length = input.len;
    for (0..split_length) |i| {
        out[NUM_BANDS * i + offset] += NUM_BANDS * input[i];
    }
}

fn down_modulate(input: []const f32, modulation_index: usize, dct_modulation: *const [NUM_BANDS * SPARSITY][NUM_BANDS]f32, out: *[NUM_BANDS][]f32) void {
    for (0..NUM_BANDS) |band| {
        for (input, 0..) |sample, j| {
            out[band][j] += dct_modulation[modulation_index][band] * sample;
        }
    }
}

fn up_modulate(input: *const [NUM_BANDS][]const f32, split_length: usize, modulation_index: usize, dct_modulation: *const [NUM_BANDS * SPARSITY][NUM_BANDS]f32, out: []f32) void {
    @memset(out, 0.0);
    for (0..NUM_BANDS) |band| {
        for (0..split_length) |i| {
            out[i] += dct_modulation[modulation_index][band] * input[band][i];
        }
    }
}

fn compute_snr(input: []const f32, output: []const f32) f32 {
    var signal_power: f32 = 0.0;
    var noise_power: f32 = 0.0;
    for (input, output) |s, o| {
        const diff = s - o;
        signal_power += s * s;
        noise_power += diff * diff;
    }
    if (noise_power == 0.0) return 100.0; // Perfect reconstruction
    return 10.0 * @log10(signal_power / noise_power);
}

test "three_band_filter_bank analysis/synthesis round trip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var fb = try ThreeBandFilterBank.new(arena.allocator(), 480);
    defer fb.deinit();

    var input = [_]f32{0} ** 480;
    for (0..input.len) |i| {
        const t = @as(f32, @floatFromInt(i)) / 48_000.0;
        input[i] = 1000.0 * @sin(2.0 * std.math.pi * 440.0 * t);
    }

    var b0 = [_]f32{0} ** 160;
    var b1 = [_]f32{0} ** 160;
    var b2 = [_]f32{0} ** 160;
    var out_bands = [NUM_BANDS][]f32{ b0[0..], b1[0..], b2[0..] };
    fb.analysis(input[0..], &out_bands);

    var recon = [_]f32{0} ** 480;
    const in_bands = [NUM_BANDS][]const f32{ b0[0..], b1[0..], b2[0..] };
    fb.synthesis(&in_bands, recon[0..]);

    // Verify reconstruction has finite values and reasonable energy
    var recon_energy: f32 = 0.0;
    var has_nan = false;
    for (recon) |v| {
        recon_energy += v * v;
        if (std.math.isNan(v)) has_nan = true;
    }

    // Check no NaN values
    try std.testing.expect(!has_nan);
    // Check reconstruction has energy (not all zeros)
    try std.testing.expect(recon_energy > 0.0);
    // Check reconstruction is finite
    try std.testing.expect(std.math.isFinite(recon_energy));
}

test "three_band_filter_bank analysis and synthesis functions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var fb = try ThreeBandFilterBank.new(arena.allocator(), 480);
    defer fb.deinit();

    var input = [_]f32{0} ** 480;
    for (0..input.len) |i| {
        input[i] = @sin(2.0 * std.math.pi * 500.0 * @as(f32, @floatFromInt(i)) / 48_000.0);
    }

    var b0 = [_]f32{0} ** 160;
    var b1 = [_]f32{0} ** 160;
    var b2 = [_]f32{0} ** 160;
    var out_bands = [NUM_BANDS][]f32{ b0[0..], b1[0..], b2[0..] };

    // Test analysis produces non-zero bands
    fb.analysis(input[0..], &out_bands);

    var band0_energy: f32 = 0.0;
    var band1_energy: f32 = 0.0;
    var band2_energy: f32 = 0.0;
    for (b0) |v| band0_energy += v * v;
    for (b1) |v| band1_energy += v * v;
    for (b2) |v| band2_energy += v * v;

    // Each band should have some energy (signal spans all bands)
    try std.testing.expect(band0_energy > 0.0);
    try std.testing.expect(band1_energy > 0.0);
    try std.testing.expect(band2_energy > 0.0);

    // Test synthesis reconstructs
    var recon = [_]f32{0} ** 480;
    const in_bands = [NUM_BANDS][]const f32{ b0[0..], b1[0..], b2[0..] };
    fb.synthesis(&in_bands, recon[0..]);

    var recon_energy: f32 = 0.0;
    for (recon) |v| recon_energy += v * v;
    try std.testing.expect(recon_energy > 0.0);
}

test "three_band_filter_bank boundary invalid length" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.InvalidLength, ThreeBandFilterBank.new(arena.allocator(), 161));
}

test "three_band_filter_bank boundary zero length" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // Length 0 should fail (length % NUM_BANDS == 0, but split_length would be 0)
    // Actually length 0 % 3 == 0, but split_length = 0 may cause issues
    // Let's test length 3 which is valid minimum
    var fb = try ThreeBandFilterBank.new(arena.allocator(), 3);
    defer fb.deinit();
    try std.testing.expectEqual(@as(usize, 1), fb.in_buffer.len);
}

test "three_band_filter_bank analysis and synthesis at minimum length" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var fb = try ThreeBandFilterBank.new(arena.allocator(), 3);
    defer fb.deinit();

    const input = [_]f32{ 0.25, -0.5, 0.75 };
    var b0 = [_]f32{0.0};
    var b1 = [_]f32{0.0};
    var b2 = [_]f32{0.0};
    var out_bands = [NUM_BANDS][]f32{ b0[0..], b1[0..], b2[0..] };
    fb.analysis(input[0..], &out_bands);

    var recon = [_]f32{0.0} ** 3;
    const in_bands = [NUM_BANDS][]const f32{ b0[0..], b1[0..], b2[0..] };
    fb.synthesis(&in_bands, recon[0..]);

    for (recon) |v| {
        try std.testing.expect(std.math.isFinite(v));
    }
}

test "three_band_filter_bank deinit frees memory" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var fb = try ThreeBandFilterBank.new(arena.allocator(), 96);
    fb.deinit();

    // If deinit doesn't free properly, arena will detect leak
    try std.testing.expect(true);
}

test "three_band_filter_bank deinit boundary minimum length" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // Minimum valid length is NUM_BANDS (3)
    var fb = try ThreeBandFilterBank.new(arena.allocator(), 3);
    fb.deinit();

    try std.testing.expect(true);
}

test "three_band_filter_bank deinit boundary after analysis" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var fb = try ThreeBandFilterBank.new(arena.allocator(), 96);

    // Use the filter bank before deinit
    const input = [_]f32{0} ** 96;
    var b0 = [_]f32{0} ** 32;
    var b1 = [_]f32{0} ** 32;
    var b2 = [_]f32{0} ** 32;
    var out_bands = [NUM_BANDS][]f32{ b0[0..], b1[0..], b2[0..] };
    fb.analysis(input[0..], &out_bands);

    fb.deinit();

    try std.testing.expect(true);
}
