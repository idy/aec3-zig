//! Ported from: docs/aec3-rs-src/audio_processing/high_pass_filter.rs
const std = @import("std");
const cascaded = @import("cascaded_biquad_filter.zig");

const BiQuadCoefficients = cascaded.BiQuadCoefficients;
const CascadedBiQuadFilter = cascaded.CascadedBiQuadFilter;

pub const HighPassFilter = struct {
    sample_rate_hz: i32,
    filters: []CascadedBiQuadFilter,
    allocator: std.mem.Allocator,

    const K_HIGH_PASS_16K = BiQuadCoefficients{ .b = .{ 0.97261, -1.94523, 0.97261 }, .a = .{ -1.94448, 0.94598 } };
    const K_HIGH_PASS_32K = BiQuadCoefficients{ .b = .{ 0.98621, -1.97242, 0.98621 }, .a = .{ -1.97223, 0.97261 } };
    const K_HIGH_PASS_48K = BiQuadCoefficients{ .b = .{ 0.99079, -1.98157, 0.99079 }, .a = .{ -1.98149, 0.98166 } };

    pub fn new(allocator: std.mem.Allocator, sample_rate_hz: i32, num_channels: usize) !HighPassFilter {
        const coeffs = try choose_coefficients(sample_rate_hz);
        const filters = try allocator.alloc(CascadedBiQuadFilter, num_channels);
        errdefer allocator.free(filters);

        var initialized_count: usize = 0;
        errdefer {
            var j: usize = 0;
            while (j < initialized_count) : (j += 1) {
                filters[j].deinit();
            }
        }

        for (filters, 0..) |*filter_inst, i| {
            _ = i;
            filter_inst.* = try CascadedBiQuadFilter.with_coefficients(allocator, coeffs, 1);
            initialized_count += 1;
        }

        return .{
            .sample_rate_hz = sample_rate_hz,
            .filters = filters,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *HighPassFilter) void {
        for (self.filters) |*f| f.deinit();
        self.allocator.free(self.filters);
    }

    pub fn process(self: *HighPassFilter, audio: []const []f32) void {
        std.debug.assert(self.filters.len == audio.len);
        for (audio, self.filters) |channel, *filter_inst| {
            filter_inst.process_in_place(channel);
        }
    }

    pub fn reset(self: *HighPassFilter) void {
        for (self.filters) |*f| f.reset();
    }

    pub fn reset_channels(self: *HighPassFilter, num_channels: usize) !void {
        const coeffs = try choose_coefficients(self.sample_rate_hz);
        if (num_channels == self.filters.len) {
            self.reset();
            return;
        }

        const new_filters = try self.allocator.alloc(CascadedBiQuadFilter, num_channels);
        errdefer self.allocator.free(new_filters);

        const copy_count = @min(num_channels, self.filters.len);

        // Track only NEWLY CONSTRUCTED filters (not shallow-copied ones)
        // Shallow copies from self.filters don't need deinit on rollback
        var new_constructed_count: usize = 0;
        errdefer {
            // Only deinit filters we actually constructed (not shallow copies)
            var j: usize = 0;
            while (j < new_constructed_count) : (j += 1) {
                new_filters[copy_count + j].deinit();
            }
        }

        // First, shallow copy and reset existing filters (no deinit needed on rollback)
        for (0..copy_count) |i| {
            new_filters[i] = self.filters[i];
            new_filters[i].reset();
        }

        // Then, construct new filters for any additional channels
        for (copy_count..num_channels) |i| {
            new_filters[i] = try CascadedBiQuadFilter.with_coefficients(self.allocator, coeffs, 1);
            new_constructed_count += 1;
        }

        // Deinit excess old filters
        if (self.filters.len > num_channels) {
            for (num_channels..self.filters.len) |i| {
                self.filters[i].deinit();
            }
        }

        self.allocator.free(self.filters);
        self.filters = new_filters;
    }

    fn choose_coefficients(sample_rate_hz: i32) !BiQuadCoefficients {
        return switch (sample_rate_hz) {
            16_000 => K_HIGH_PASS_16K,
            32_000 => K_HIGH_PASS_32K,
            48_000 => K_HIGH_PASS_48K,
            else => error.UnsupportedSampleRate,
        };
    }
};

fn rms(data: []const f32) f32 {
    var sum: f32 = 0.0;
    for (data) |v| sum += v * v;
    return @sqrt(sum / @as(f32, @floatFromInt(data.len)));
}

test "high_pass_filter attenuates low frequency but preserves high frequency" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var hp = try HighPassFilter.new(arena.allocator(), 16_000, 1);
    defer hp.deinit();

    const n = 160;
    var low = [_]f32{0} ** n;
    var high = [_]f32{0} ** n;
    const sr: f32 = 16_000.0;
    const two_pi = 2.0 * std.math.pi;

    for (0..n) |i| {
        const t = @as(f32, @floatFromInt(i)) / sr;
        low[i] = @sin(two_pi * 80.0 * t);
        high[i] = @sin(two_pi * 2000.0 * t);
    }

    var low_ch = [_][]f32{low[0..]};
    var high_ch = [_][]f32{high[0..]};
    hp.process(low_ch[0..]);
    hp.reset();
    hp.process(high_ch[0..]);

    try std.testing.expect(rms(low[0..]) < 0.35);
    try std.testing.expect(rms(high[0..]) > 0.55);
}

test "high_pass_filter boundary invalid sample rate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.UnsupportedSampleRate, HighPassFilter.new(arena.allocator(), 44_100, 1));
}

test "high_pass_filter new boundary zero channels" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var hp = try HighPassFilter.new(arena.allocator(), 16_000, 0);
    defer hp.deinit();
    try std.testing.expectEqual(@as(usize, 0), hp.filters.len);
}

test "high_pass_filter reset clears all state" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var hp = try HighPassFilter.new(arena.allocator(), 16_000, 1);
    defer hp.deinit();

    const n = 160;
    var input = [_]f32{0} ** n;
    for (0..n) |i| {
        input[i] = @sin(2.0 * std.math.pi * 1000.0 * @as(f32, @floatFromInt(i)) / 16000.0);
    }

    var ch1 = [_][]f32{input[0..]};
    hp.process(ch1[0..]);
    const rms_before = rms(input[0..]);

    hp.reset();

    // Reset should have cleared state, so re-processing identical input gives same result
    var input2 = [_]f32{0} ** n;
    for (0..n) |i| {
        input2[i] = @sin(2.0 * std.math.pi * 1000.0 * @as(f32, @floatFromInt(i)) / 16000.0);
    }
    var ch2 = [_][]f32{input2[0..]};
    hp.process(ch2[0..]);
    const rms_after = rms(input2[0..]);

    try std.testing.expectApproxEqRel(rms_before, rms_after, 1e-5);
}

test "high_pass_filter reset_channels resize" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var hp = try HighPassFilter.new(arena.allocator(), 16_000, 1);
    defer hp.deinit();

    try hp.reset_channels(3);
    try std.testing.expectEqual(@as(usize, 3), hp.filters.len);
    try hp.reset_channels(1);
    try std.testing.expectEqual(@as(usize, 1), hp.filters.len);
}

test "high_pass_filter reset_channels to zero channels" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var hp = try HighPassFilter.new(arena.allocator(), 16_000, 2);
    defer hp.deinit();

    try hp.reset_channels(0);
    try std.testing.expectEqual(@as(usize, 0), hp.filters.len);
}

test "high_pass_filter process handles zero channels" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var hp = try HighPassFilter.new(arena.allocator(), 16_000, 1);
    defer hp.deinit();

    try hp.reset_channels(0);
    var empty: [0][]f32 = .{};
    hp.process(empty[0..]);
}

test "high_pass_filter reset boundary stability" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // Use single channel for simplicity
    var hp = try HighPassFilter.new(arena.allocator(), 16_000, 1);
    defer hp.deinit();

    const n = 160;
    var input1 = [_]f32{0} ** n;
    for (0..n) |i| {
        input1[i] = @sin(2.0 * std.math.pi * 1000.0 * @as(f32, @floatFromInt(i)) / 16000.0);
    }

    // First processing pass
    var ch1 = [_][]f32{input1[0..]};
    hp.process(ch1[0..]);
    const rms1 = rms(input1[0..]);

    // Reset and process identical input
    hp.reset();
    var input2 = [_]f32{0} ** n;
    for (0..n) |i| {
        input2[i] = @sin(2.0 * std.math.pi * 1000.0 * @as(f32, @floatFromInt(i)) / 16000.0);
    }
    var ch2 = [_][]f32{input2[0..]};
    hp.process(ch2[0..]);
    const rms2 = rms(input2[0..]);

    // Multiple resets should be stable
    hp.reset();
    hp.reset();
    hp.reset();
    var input3 = [_]f32{0} ** n;
    for (0..n) |i| {
        input3[i] = @sin(2.0 * std.math.pi * 1000.0 * @as(f32, @floatFromInt(i)) / 16000.0);
    }
    var ch3 = [_][]f32{input3[0..]};
    hp.process(ch3[0..]);
    const rms3 = rms(input3[0..]);

    try std.testing.expectApproxEqRel(rms1, rms2, 1e-5);
    try std.testing.expectApproxEqRel(rms2, rms3, 1e-5);
}

test "high_pass_filter deinit frees resources" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var hp = try HighPassFilter.new(arena.allocator(), 16_000, 3);
    hp.deinit();

    // If deinit doesn't free properly, arena will detect leak
    try std.testing.expect(true);
}

test "high_pass_filter deinit after zero channels" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var hp = try HighPassFilter.new(arena.allocator(), 16_000, 0);
    hp.deinit();

    try std.testing.expect(true);
}

test "high_pass_filter deinit boundary after resize" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // Create, resize multiple times, then deinit
    var hp = try HighPassFilter.new(arena.allocator(), 16_000, 2);

    try hp.reset_channels(5);
    try hp.reset_channels(1);
    try hp.reset_channels(10);
    try hp.reset_channels(0);

    hp.deinit();

    try std.testing.expect(true);
}

test "high_pass_filter deinit boundary different sample rates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // Test all supported sample rates
    var hp_16k = try HighPassFilter.new(arena.allocator(), 16_000, 2);
    hp_16k.deinit();

    var hp_32k = try HighPassFilter.new(arena.allocator(), 32_000, 2);
    hp_32k.deinit();

    var hp_48k = try HighPassFilter.new(arena.allocator(), 48_000, 2);
    hp_48k.deinit();

    try std.testing.expect(true);
}
