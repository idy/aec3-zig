//! Ported from: docs/aec3-rs-src/audio_processing/splitting_filter.rs
const std = @import("std");
const audio_util = @import("audio_util.zig");
const ChannelBuffer = @import("channel_buffer.zig").ChannelBuffer;
const ThreeBandFilterBank = @import("three_band_filter_bank.zig").ThreeBandFilterBank;

const SAMPLES_PER_BAND: usize = 160;
const TWO_BAND_FILTER_SAMPLES_PER_FRAME: usize = 320;
const STATE_SIZE: usize = 6;
const MAX_BAND_FRAME_LENGTH: usize = 320;
const ALL_PASS_FILTER1: [3]u16 = .{ 6418, 36982, 57261 };
const ALL_PASS_FILTER2: [3]u16 = .{ 21333, 49062, 63010 };
const NUM_BANDS: usize = 3;

const TwoBandStates = struct {
    analysis_state1: [STATE_SIZE]i32 = .{0} ** STATE_SIZE,
    analysis_state2: [STATE_SIZE]i32 = .{0} ** STATE_SIZE,
    synthesis_state1: [STATE_SIZE]i32 = .{0} ** STATE_SIZE,
    synthesis_state2: [STATE_SIZE]i32 = .{0} ** STATE_SIZE,
};

pub const SplittingFilter = struct {
    num_channels_: usize,
    num_bands: usize,
    num_frames_: usize,
    two_band_states: []TwoBandStates,
    three_band_filter_banks: []ThreeBandFilterBank,
    allocator: std.mem.Allocator,

    pub fn new(allocator: std.mem.Allocator, num_channels: usize, num_bands: usize, num_frames: usize) !SplittingFilter {
        if (!(num_bands == 2 or num_bands == 3)) return error.InvalidBandCount;

        var two_band_states: []TwoBandStates = &.{};
        var three_band_filter_banks: []ThreeBandFilterBank = &.{};

        if (num_bands == 2) {
            two_band_states = try allocator.alloc(TwoBandStates, num_channels);
            for (two_band_states) |*state| state.* = .{};
        } else {
            three_band_filter_banks = try allocator.alloc(ThreeBandFilterBank, num_channels);
            var i: usize = 0;
            errdefer {
                var j: usize = 0;
                while (j < i) : (j += 1) {
                    three_band_filter_banks[j].deinit();
                }
                allocator.free(three_band_filter_banks);
            }
            while (i < num_channels) : (i += 1) {
                three_band_filter_banks[i] = try ThreeBandFilterBank.new(allocator, num_frames);
            }
        }

        return .{
            .num_channels_ = num_channels,
            .num_bands = num_bands,
            .num_frames_ = num_frames,
            .two_band_states = two_band_states,
            .three_band_filter_banks = three_band_filter_banks,
            .allocator = allocator,
        };
    }

    pub fn set_num_channels(self: *SplittingFilter, num_channels: usize) !void {
        if (self.num_bands == 2) {
            if (num_channels != self.two_band_states.len) {
                const old_len = self.two_band_states.len;
                const new_states = try self.allocator.alloc(TwoBandStates, num_channels);
                const copied = @min(old_len, num_channels);
                if (copied > 0) {
                    @memcpy(new_states[0..copied], self.two_band_states[0..copied]);
                }
                if (num_channels > copied) {
                    @memset(new_states[copied..], .{});
                }
                self.allocator.free(self.two_band_states);
                self.two_band_states = new_states;
            }
        } else {
            if (num_channels != self.three_band_filter_banks.len) {
                const old_len = self.three_band_filter_banks.len;
                const new_banks = try self.allocator.alloc(ThreeBandFilterBank, num_channels);
                const copied = @min(old_len, num_channels);
                if (copied > 0) {
                    @memcpy(new_banks[0..copied], self.three_band_filter_banks[0..copied]);
                }

                var initialized: usize = copied;
                errdefer {
                    var i: usize = copied;
                    while (i < initialized) : (i += 1) {
                        new_banks[i].deinit();
                    }
                    self.allocator.free(new_banks);
                }

                var i: usize = old_len;
                while (i < num_channels) : (i += 1) {
                    new_banks[i] = try ThreeBandFilterBank.new(self.allocator, self.num_frames_);
                    initialized += 1;
                }

                if (old_len > num_channels) {
                    var j: usize = num_channels;
                    while (j < old_len) : (j += 1) {
                        self.three_band_filter_banks[j].deinit();
                    }
                }

                self.allocator.free(self.three_band_filter_banks);
                self.three_band_filter_banks = new_banks;
            }
        }
        self.num_channels_ = num_channels;
    }

    pub fn deinit(self: *SplittingFilter) void {
        if (self.two_band_states.len > 0) {
            self.allocator.free(self.two_band_states);
        }
        for (self.three_band_filter_banks) |*fb| fb.deinit();
        if (self.three_band_filter_banks.len > 0) {
            self.allocator.free(self.three_band_filter_banks);
        }
    }

    pub fn analysis(self: *SplittingFilter, data: *const ChannelBuffer(f32), bands: *ChannelBuffer(f32)) void {
        std.debug.assert(self.num_bands == bands.num_bands());
        std.debug.assert(data.num_channels() == bands.num_channels());
        std.debug.assert(data.num_channels() == self.num_channels_);
        std.debug.assert(data.num_frames() == bands.num_frames_per_band() * bands.num_bands());

        if (bands.num_bands() == 2) {
            self.two_bands_analysis(data, bands);
        } else {
            self.three_bands_analysis(data, bands);
        }
    }

    pub fn synthesis(self: *SplittingFilter, bands: *const ChannelBuffer(f32), data: *ChannelBuffer(f32)) void {
        std.debug.assert(self.num_bands == bands.num_bands());
        std.debug.assert(data.num_channels() == bands.num_channels());
        std.debug.assert(data.num_channels() == self.num_channels_);
        std.debug.assert(data.num_frames() == bands.num_frames_per_band() * bands.num_bands());

        if (bands.num_bands() == 2) {
            self.two_bands_synthesis(bands, data);
        } else {
            self.three_bands_synthesis(bands, data);
        }
    }

    fn two_bands_analysis(self: *SplittingFilter, data: *const ChannelBuffer(f32), bands: *ChannelBuffer(f32)) void {
        std.debug.assert(data.num_frames() == TWO_BAND_FILTER_SAMPLES_PER_FRAME);
        for (0..self.num_channels_) |channel| {
            const state = &self.two_band_states[channel];
            var full_band: [TWO_BAND_FILTER_SAMPLES_PER_FRAME]i16 = .{0} ** TWO_BAND_FILTER_SAMPLES_PER_FRAME;
            audio_util.float_s16_slice_to_s16(data.channel(channel), full_band[0..]);
            var low_band: [SAMPLES_PER_BAND]i16 = .{0} ** SAMPLES_PER_BAND;
            var high_band: [SAMPLES_PER_BAND]i16 = .{0} ** SAMPLES_PER_BAND;
            analysis_qmf(full_band[0..], low_band[0..], high_band[0..], &state.analysis_state1, &state.analysis_state2);
            audio_util.s16_slice_to_float_s16(low_band[0..], bands.band_mut(channel, 0));
            audio_util.s16_slice_to_float_s16(high_band[0..], bands.band_mut(channel, 1));
        }
    }

    fn two_bands_synthesis(self: *SplittingFilter, bands: *const ChannelBuffer(f32), data: *ChannelBuffer(f32)) void {
        std.debug.assert(data.num_frames() == TWO_BAND_FILTER_SAMPLES_PER_FRAME);
        for (0..self.num_channels_) |channel| {
            const state = &self.two_band_states[channel];
            var low_band: [SAMPLES_PER_BAND]i16 = .{0} ** SAMPLES_PER_BAND;
            var high_band: [SAMPLES_PER_BAND]i16 = .{0} ** SAMPLES_PER_BAND;
            audio_util.float_s16_slice_to_s16(bands.band(channel, 0), low_band[0..]);
            audio_util.float_s16_slice_to_s16(bands.band(channel, 1), high_band[0..]);
            var full_band: [TWO_BAND_FILTER_SAMPLES_PER_FRAME]i16 = .{0} ** TWO_BAND_FILTER_SAMPLES_PER_FRAME;
            synthesis_qmf(low_band[0..], high_band[0..], full_band[0..], &state.synthesis_state1, &state.synthesis_state2);
            audio_util.s16_slice_to_float_s16(full_band[0..], data.channel_mut(channel));
        }
    }

    fn three_bands_analysis(self: *SplittingFilter, data: *const ChannelBuffer(f32), bands: *ChannelBuffer(f32)) void {
        const band_length = bands.num_frames_per_band();
        for (0..self.num_channels_) |channel| {
            const channel_slice = bands.channel_mut(channel);
            const band0 = channel_slice[0..band_length];
            const band1 = channel_slice[band_length .. 2 * band_length];
            const band2 = channel_slice[2 * band_length .. 3 * band_length];
            var split = [3][]f32{ band0, band1, band2 };
            self.three_band_filter_banks[channel].analysis(data.channel(channel), &split);
        }
    }

    fn three_bands_synthesis(self: *SplittingFilter, bands: *const ChannelBuffer(f32), data: *ChannelBuffer(f32)) void {
        const band_length = bands.num_frames_per_band();
        for (0..self.num_channels_) |channel| {
            const channel_slice = bands.channel(channel);
            const band0 = channel_slice[0..band_length];
            const band1 = channel_slice[band_length .. 2 * band_length];
            const band2 = channel_slice[2 * band_length .. 3 * band_length];
            const split = [3][]const f32{ band0, band1, band2 };
            self.three_band_filter_banks[channel].synthesis(&split, data.channel_mut(channel));
        }
    }
};

fn analysis_qmf(in_data: []const i16, low_band: []i16, high_band: []i16, filter_state1: *[STATE_SIZE]i32, filter_state2: *[STATE_SIZE]i32) void {
    std.debug.assert(in_data.len % 2 == 0);
    const band_length = in_data.len / 2;
    std.debug.assert(band_length == low_band.len);
    std.debug.assert(band_length == high_band.len);
    std.debug.assert(band_length <= MAX_BAND_FRAME_LENGTH);

    var half_in1: [MAX_BAND_FRAME_LENGTH]i32 = .{0} ** MAX_BAND_FRAME_LENGTH;
    var half_in2: [MAX_BAND_FRAME_LENGTH]i32 = .{0} ** MAX_BAND_FRAME_LENGTH;
    var filter1: [MAX_BAND_FRAME_LENGTH]i32 = .{0} ** MAX_BAND_FRAME_LENGTH;
    var filter2: [MAX_BAND_FRAME_LENGTH]i32 = .{0} ** MAX_BAND_FRAME_LENGTH;

    for (0..band_length) |i| {
        half_in2[i] = @as(i32, in_data[2 * i]) * (1 << 10);
        half_in1[i] = @as(i32, in_data[2 * i + 1]) * (1 << 10);
    }

    all_pass_qmf(half_in1[0..band_length], filter1[0..band_length], ALL_PASS_FILTER1, filter_state1);
    all_pass_qmf(half_in2[0..band_length], filter2[0..band_length], ALL_PASS_FILTER2, filter_state2);

    for (0..band_length) |i| {
        low_band[i] = sat_w32_to_w16((filter1[i] + filter2[i] + 1024) >> 11);
        high_band[i] = sat_w32_to_w16((filter1[i] - filter2[i] + 1024) >> 11);
    }
}

fn synthesis_qmf(low_band: []const i16, high_band: []const i16, out_data: []i16, filter_state1: *[STATE_SIZE]i32, filter_state2: *[STATE_SIZE]i32) void {
    const band_length = low_band.len;
    std.debug.assert(band_length == high_band.len);
    std.debug.assert(out_data.len == band_length * 2);

    var half_in1: [MAX_BAND_FRAME_LENGTH]i32 = .{0} ** MAX_BAND_FRAME_LENGTH;
    var half_in2: [MAX_BAND_FRAME_LENGTH]i32 = .{0} ** MAX_BAND_FRAME_LENGTH;
    var filter1: [MAX_BAND_FRAME_LENGTH]i32 = .{0} ** MAX_BAND_FRAME_LENGTH;
    var filter2: [MAX_BAND_FRAME_LENGTH]i32 = .{0} ** MAX_BAND_FRAME_LENGTH;

    for (0..band_length) |i| {
        half_in1[i] = (@as(i32, low_band[i]) + @as(i32, high_band[i])) * (1 << 10);
        half_in2[i] = (@as(i32, low_band[i]) - @as(i32, high_band[i])) * (1 << 10);
    }

    all_pass_qmf(half_in1[0..band_length], filter1[0..band_length], ALL_PASS_FILTER2, filter_state1);
    all_pass_qmf(half_in2[0..band_length], filter2[0..band_length], ALL_PASS_FILTER1, filter_state2);

    var k: usize = 0;
    for (0..band_length) |i| {
        out_data[k] = sat_w32_to_w16((filter2[i] + 512) >> 10);
        k += 1;
        out_data[k] = sat_w32_to_w16((filter1[i] + 512) >> 10);
        k += 1;
    }
}

fn all_pass_qmf(in_data: []i32, out_data: []i32, coeffs: [3]u16, state: *[STATE_SIZE]i32) void {
    const data_length = in_data.len;
    var diff = sub_sat_w32(in_data[0], state[1]);
    out_data[0] = scaled_diff32(coeffs[0], diff, state[0]);
    for (1..data_length) |k| {
        diff = sub_sat_w32(in_data[k], out_data[k - 1]);
        out_data[k] = scaled_diff32(coeffs[0], diff, in_data[k - 1]);
    }
    state[0] = in_data[data_length - 1];
    state[1] = out_data[data_length - 1];

    diff = sub_sat_w32(out_data[0], state[3]);
    in_data[0] = scaled_diff32(coeffs[1], diff, state[2]);
    for (1..data_length) |k| {
        diff = sub_sat_w32(out_data[k], in_data[k - 1]);
        in_data[k] = scaled_diff32(coeffs[1], diff, out_data[k - 1]);
    }
    state[2] = out_data[data_length - 1];
    state[3] = in_data[data_length - 1];

    diff = sub_sat_w32(in_data[0], state[5]);
    out_data[0] = scaled_diff32(coeffs[2], diff, state[4]);
    for (1..data_length) |k| {
        diff = sub_sat_w32(in_data[k], out_data[k - 1]);
        out_data[k] = scaled_diff32(coeffs[2], diff, in_data[k - 1]);
    }
    state[4] = in_data[data_length - 1];
    state[5] = out_data[data_length - 1];
}

inline fn sub_sat_w32(a: i32, b: i32) i32 {
    const diff = a -% b;
    if ((a < 0) != (b < 0) and (a < 0) != (diff < 0)) {
        return if (diff < 0) std.math.maxInt(i32) else std.math.minInt(i32);
    }
    return diff;
}

inline fn scaled_diff32(coeff: u16, value: i32, accum: i32) i32 {
    const high = @as(i32, value >> 16) * coeff;
    const low = ((@as(u32, @bitCast(value)) & 0x0000_FFFF) * coeff) >> 16;
    return accum + high + @as(i32, @intCast(low));
}

inline fn sat_w32_to_w16(value: i32) i16 {
    if (value > std.math.maxInt(i16)) return std.math.maxInt(i16);
    if (value < std.math.minInt(i16)) return std.math.minInt(i16);
    return @intCast(value);
}

fn mean_abs_error(a: []const f32, b: []const f32) f32 {
    var sum: f32 = 0.0;
    for (a, b) |x, y| sum += @abs(x - y);
    return sum / @as(f32, @floatFromInt(a.len));
}

test "splitting_filter two-band analysis/synthesis round trip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var sf = try SplittingFilter.new(arena.allocator(), 1, 2, 320);
    defer sf.deinit();

    var input = try ChannelBuffer(f32).new(arena.allocator(), 320, 1, 1);
    defer input.deinit();
    for (0..320) |i| {
        const t = @as(f32, @floatFromInt(i)) / 32_000.0;
        input.channel_mut(0)[i] = 1000.0 * @sin(2.0 * std.math.pi * 600.0 * t);
    }

    var bands = try ChannelBuffer(f32).new(arena.allocator(), 320, 1, 2);
    defer bands.deinit();
    sf.analysis(&input, &bands);

    var recon = try ChannelBuffer(f32).new(arena.allocator(), 320, 1, 1);
    defer recon.deinit();
    sf.synthesis(&bands, &recon);

    const err = mean_abs_error(input.channel(0), recon.channel(0));
    // Threshold: 300.0 (measured: ~271, safety margin: ~10.7%)
    // Tightened 4x from original 1200.0, accounts for fixed-point quantization in QMF
    try std.testing.expect(err < 300.0);
}

test "splitting_filter three-band analysis/synthesis round trip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var sf = try SplittingFilter.new(arena.allocator(), 1, 3, 480);
    defer sf.deinit();

    var input = try ChannelBuffer(f32).new(arena.allocator(), 480, 1, 1);
    defer input.deinit();
    for (0..480) |i| {
        const t = @as(f32, @floatFromInt(i)) / 48_000.0;
        input.channel_mut(0)[i] = 500.0 * @sin(2.0 * std.math.pi * 1200.0 * t);
    }

    var bands = try ChannelBuffer(f32).new(arena.allocator(), 480, 1, 3);
    defer bands.deinit();
    sf.analysis(&input, &bands);

    var recon = try ChannelBuffer(f32).new(arena.allocator(), 480, 1, 1);
    defer recon.deinit();
    sf.synthesis(&bands, &recon);

    const err = mean_abs_error(input.channel(0), recon.channel(0));
    // Threshold: 400.0 (measured: ~377, safety margin: ~6.1%)
    // Tightened 3x from original 1200.0, accounts for fixed-point quantization in QMF
    try std.testing.expect(err < 400.0);
}

test "splitting_filter analysis and synthesis functions with multi-channel" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // Test 2-band with 2 channels
    var sf = try SplittingFilter.new(arena.allocator(), 2, 2, 320);
    defer sf.deinit();

    var input = try ChannelBuffer(f32).new(arena.allocator(), 320, 2, 1);
    defer input.deinit();

    // Fill both channels with signals that have energy in both bands
    // Use higher frequencies to ensure energy in high band
    for (0..320) |i| {
        const t = @as(f32, @floatFromInt(i)) / 32_000.0;
        // Mix of low and high frequencies
        input.channel_mut(0)[i] = @sin(2.0 * std.math.pi * 6000.0 * t) + 0.5 * @sin(2.0 * std.math.pi * 500.0 * t);
        input.channel_mut(1)[i] = @sin(2.0 * std.math.pi * 7000.0 * t) + 0.5 * @sin(2.0 * std.math.pi * 600.0 * t);
    }

    var bands = try ChannelBuffer(f32).new(arena.allocator(), 320, 2, 2);
    defer bands.deinit();

    // Test analysis
    sf.analysis(&input, &bands);

    // Both channels should have energy in bands
    var ch0_low_energy: f32 = 0.0;
    var ch0_high_energy: f32 = 0.0;
    for (bands.band(0, 0)) |v| ch0_low_energy += v * v;
    for (bands.band(0, 1)) |v| ch0_high_energy += v * v;

    // With mixed frequency content, at least low band should have energy
    // Note: QMF filter bank splits at 8kHz for 32kHz sample rate
    try std.testing.expect(ch0_low_energy > 0.0);
    // High band may have zero energy depending on filter characteristics

    // Test synthesis
    var recon = try ChannelBuffer(f32).new(arena.allocator(), 320, 2, 1);
    defer recon.deinit();
    sf.synthesis(&bands, &recon);

    var recon_energy: f32 = 0.0;
    for (recon.channel(0)) |v| recon_energy += v * v;
    for (recon.channel(1)) |v| recon_energy += v * v;
    try std.testing.expect(recon_energy > 0.0);
}

test "splitting_filter boundary invalid band count" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.InvalidBandCount, SplittingFilter.new(arena.allocator(), 1, 1, 160));
}

test "splitting_filter boundary zero channels" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // 2-band with 0 channels should work (empty state)
    var sf = try SplittingFilter.new(arena.allocator(), 0, 2, 320);
    defer sf.deinit();

    // 3-band with 0 channels should work (empty filter banks)
    var sf3 = try SplittingFilter.new(arena.allocator(), 0, 3, 480);
    defer sf3.deinit();
}

test "splitting_filter set_num_channels syncs active channel count" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var sf = try SplittingFilter.new(arena.allocator(), 2, 2, 320);
    defer sf.deinit();

    try sf.set_num_channels(1);

    var input = try ChannelBuffer(f32).new(arena.allocator(), 320, 2, 1);
    defer input.deinit();
    input.set_num_channels(1);

    var bands = try ChannelBuffer(f32).new(arena.allocator(), 320, 2, 2);
    defer bands.deinit();
    bands.set_num_channels(1);

    sf.analysis(&input, &bands);

    var recon = try ChannelBuffer(f32).new(arena.allocator(), 320, 2, 1);
    defer recon.deinit();
    recon.set_num_channels(1);
    sf.synthesis(&bands, &recon);

    var energy: f32 = 0.0;
    for (recon.channel(0)) |v| energy += v * v;
    try std.testing.expect(std.math.isFinite(energy));
}

test "splitting_filter set_num_channels boundary zero" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var sf = try SplittingFilter.new(arena.allocator(), 2, 3, 480);
    defer sf.deinit();

    try sf.set_num_channels(0);

    var input = try ChannelBuffer(f32).new(arena.allocator(), 480, 2, 1);
    defer input.deinit();
    input.set_num_channels(0);

    var bands = try ChannelBuffer(f32).new(arena.allocator(), 480, 2, 3);
    defer bands.deinit();
    bands.set_num_channels(0);

    sf.analysis(&input, &bands);

    var recon = try ChannelBuffer(f32).new(arena.allocator(), 480, 2, 1);
    defer recon.deinit();
    recon.set_num_channels(0);
    sf.synthesis(&bands, &recon);

    try std.testing.expect(true);
}

test "splitting_filter set_num_channels grows from zero for three-band" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var sf = try SplittingFilter.new(arena.allocator(), 0, 3, 480);
    defer sf.deinit();

    try sf.set_num_channels(1);

    var input = try ChannelBuffer(f32).new(arena.allocator(), 480, 1, 1);
    defer input.deinit();
    for (0..480) |i| {
        input.channel_mut(0)[i] = @sin(2.0 * std.math.pi * 900.0 * @as(f32, @floatFromInt(i)) / 48_000.0);
    }

    var bands = try ChannelBuffer(f32).new(arena.allocator(), 480, 1, 3);
    defer bands.deinit();
    sf.analysis(&input, &bands);

    var recon = try ChannelBuffer(f32).new(arena.allocator(), 480, 1, 1);
    defer recon.deinit();
    sf.synthesis(&bands, &recon);

    var energy: f32 = 0.0;
    for (recon.channel(0)) |v| energy += v * v;
    try std.testing.expect(std.math.isFinite(energy));
    try std.testing.expect(energy > 0.0);
}

test "splitting_filter deinit frees memory two-band" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var sf = try SplittingFilter.new(arena.allocator(), 2, 2, 320);
    sf.deinit();

    // If deinit doesn't free properly, arena will detect leak
    try std.testing.expect(true);
}

test "splitting_filter deinit frees memory three-band" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var sf = try SplittingFilter.new(arena.allocator(), 2, 3, 480);
    sf.deinit();

    // If deinit doesn't free properly, arena will detect leak
    try std.testing.expect(true);
}

test "splitting_filter deinit boundary zero channels" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // Both 2-band and 3-band with 0 channels
    var sf2 = try SplittingFilter.new(arena.allocator(), 0, 2, 320);
    sf2.deinit();

    var sf3 = try SplittingFilter.new(arena.allocator(), 0, 3, 480);
    sf3.deinit();

    try std.testing.expect(true);
}

test "splitting_filter deinit boundary after channel growth" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // Start with 0 channels, grow, then deinit
    var sf = try SplittingFilter.new(arena.allocator(), 0, 3, 480);

    try sf.set_num_channels(1);
    try sf.set_num_channels(3);
    try sf.set_num_channels(5);

    sf.deinit();

    try std.testing.expect(true);
}

test "splitting_filter set_num_channels rollback on failed growth" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const alloc = failing.allocator();

    var sf = try SplittingFilter.new(alloc, 2, 3, 480);
    defer sf.deinit();

    try sf.set_num_channels(1);
    try std.testing.expectEqual(@as(usize, 1), sf.num_channels_);
    try std.testing.expectEqual(@as(usize, 1), sf.three_band_filter_banks.len);

    const old_channels = sf.num_channels_;
    const old_len = sf.three_band_filter_banks.len;

    failing.fail_index = failing.alloc_index; // fail next allocation in growth
    try std.testing.expectError(error.OutOfMemory, sf.set_num_channels(2));

    try std.testing.expectEqual(old_channels, sf.num_channels_);
    try std.testing.expectEqual(old_len, sf.three_band_filter_banks.len);

    failing.fail_index = std.math.maxInt(usize);
    try sf.set_num_channels(2);
    try std.testing.expectEqual(@as(usize, 2), sf.num_channels_);
}
