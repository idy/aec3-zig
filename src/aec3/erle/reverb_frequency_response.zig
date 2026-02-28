//! Ported from: docs/aec3-rs-src/audio_processing/aec3/reverb_frequency_response.rs
//! Estimates the frequency-dependent reverb tail response from the adaptive filter.
const std = @import("std");
const common = @import("../common/aec3_common.zig");

const FFT_LENGTH_BY_2_PLUS_1 = common.FFT_LENGTH_BY_2_PLUS_1;

/// Computes the average decay ratio between the tail and direct-path frequency responses.
fn average_decay_within_filter(
    freq_resp_direct_path: *const [FFT_LENGTH_BY_2_PLUS_1]f32,
    freq_resp_tail: *const [FFT_LENGTH_BY_2_PLUS_1]f32,
) f32 {
    const SKIP_BINS: usize = 1;
    var direct_energy: f32 = 0.0;
    for (freq_resp_direct_path[SKIP_BINS..]) |v| {
        direct_energy += v;
    }
    if (direct_energy == 0.0) return 0.0;
    var tail_energy: f32 = 0.0;
    for (freq_resp_tail[SKIP_BINS..]) |v| {
        tail_energy += v;
    }
    return tail_energy / direct_energy;
}

/// Estimates the frequency-shaped reverb tail response from the adaptive filter.
pub const ReverbFrequencyResponse = struct {
    const Self = @This();

    average_decay: f32,
    tail_response: [FFT_LENGTH_BY_2_PLUS_1]f32,

    pub fn init() Self {
        return .{
            .average_decay = 0.0,
            .tail_response = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1,
        };
    }

    /// Updates the tail response estimate from the filter frequency response.
    ///
    /// `frequency_response` is the per-block frequency response of the adaptive filter.
    /// `filter_delay_blocks` is the estimated filter delay in blocks.
    /// `linear_filter_quality` is an optional quality metric (None skips update).
    /// `stationary_block` — skip update when the signal is stationary.
    pub fn update(
        self: *Self,
        freq_response: []const [FFT_LENGTH_BY_2_PLUS_1]f32,
        filter_delay_blocks: i32,
        linear_filter_quality: ?f32,
        stationary_block: bool,
    ) void {
        if (stationary_block) return;
        const quality = linear_filter_quality orelse return;
        if (freq_response.len == 0) return;
        if (filter_delay_blocks < 0) return;
        const delay: usize = @intCast(filter_delay_blocks);
        if (delay >= freq_response.len) return;
        self.update_internal(freq_response, delay, quality);
    }

    /// Returns the current tail frequency response estimate.
    pub fn frequency_response(self: *const Self) *const [FFT_LENGTH_BY_2_PLUS_1]f32 {
        return &self.tail_response;
    }

    fn update_internal(
        self: *Self,
        freq_response: []const [FFT_LENGTH_BY_2_PLUS_1]f32,
        filter_delay_blocks: usize,
        linear_filter_quality: f32,
    ) void {
        const freq_resp_tail = &freq_response[freq_response.len - 1];
        const freq_resp_direct_path = &freq_response[filter_delay_blocks];
        const avg_decay = average_decay_within_filter(freq_resp_direct_path, freq_resp_tail);
        const smoothing = 0.2 * linear_filter_quality;
        self.average_decay += smoothing * (avg_decay - self.average_decay);

        for (&self.tail_response, freq_resp_direct_path) |*dst, dp| {
            dst.* = dp * self.average_decay;
        }

        // Smooth: lift bins that are lower than their neighbours' average.
        if (FFT_LENGTH_BY_2_PLUS_1 > 2) {
            for (1..FFT_LENGTH_BY_2_PLUS_1 - 1) |k| {
                const avg_neighbour = 0.5 * (self.tail_response[k - 1] + self.tail_response[k + 1]);
                if (avg_neighbour > self.tail_response[k]) {
                    self.tail_response[k] = avg_neighbour;
                }
            }
        }
    }
};

// ---------------------------------------------------------------------------
// Inline tests
// ---------------------------------------------------------------------------

test "reverb_frequency_response init is zero" {
    const rfr = ReverbFrequencyResponse.init();
    try std.testing.expectEqual(@as(f32, 0.0), rfr.average_decay);
    for (rfr.tail_response) |v| {
        try std.testing.expectEqual(@as(f32, 0.0), v);
    }
}

test "reverb_frequency_response skip on stationary" {
    var rfr = ReverbFrequencyResponse.init();
    var freq_resp = [_][FFT_LENGTH_BY_2_PLUS_1]f32{[_]f32{1.0} ** FFT_LENGTH_BY_2_PLUS_1} ** 3;
    rfr.update(&freq_resp, 0, 1.0, true);
    try std.testing.expectEqual(@as(f32, 0.0), rfr.average_decay);
}

test "reverb_frequency_response skip on null quality" {
    var rfr = ReverbFrequencyResponse.init();
    var freq_resp = [_][FFT_LENGTH_BY_2_PLUS_1]f32{[_]f32{1.0} ** FFT_LENGTH_BY_2_PLUS_1} ** 3;
    rfr.update(&freq_resp, 0, null, false);
    try std.testing.expectEqual(@as(f32, 0.0), rfr.average_decay);
}

test "reverb_frequency_response skip on negative delay" {
    var rfr = ReverbFrequencyResponse.init();
    var freq_resp = [_][FFT_LENGTH_BY_2_PLUS_1]f32{[_]f32{1.0} ** FFT_LENGTH_BY_2_PLUS_1} ** 3;
    rfr.update(&freq_resp, -1, 1.0, false);
    try std.testing.expectEqual(@as(f32, 0.0), rfr.average_decay);
}

test "reverb_frequency_response skip on empty" {
    var rfr = ReverbFrequencyResponse.init();
    const freq_resp: []const [FFT_LENGTH_BY_2_PLUS_1]f32 = &.{};
    rfr.update(freq_resp, 0, 1.0, false);
    try std.testing.expectEqual(@as(f32, 0.0), rfr.average_decay);
}

test "reverb_frequency_response skip on delay beyond length" {
    var rfr = ReverbFrequencyResponse.init();
    var freq_resp = [_][FFT_LENGTH_BY_2_PLUS_1]f32{[_]f32{1.0} ** FFT_LENGTH_BY_2_PLUS_1} ** 3;
    rfr.update(&freq_resp, 5, 1.0, false); // delay=5 >= len=3
    try std.testing.expectEqual(@as(f32, 0.0), rfr.average_decay);
}

test "reverb_frequency_response updates with valid input" {
    var rfr = ReverbFrequencyResponse.init();
    // Create a 4-block frequency response where tail energy < direct path energy.
    var freq_resp: [4][FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;
    for (&freq_resp) |*block| {
        block.* = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    }
    // Direct path at block 1 has energy.
    for (&freq_resp[1]) |*v| v.* = 10.0;
    // Tail (last block) has smaller energy.
    for (&freq_resp[3]) |*v| v.* = 2.0;

    rfr.update(&freq_resp, 1, 1.0, false);
    // average_decay should be smoothed toward (2/10)=0.2 with smoothing=0.2*1=0.2
    // So: 0 + 0.2*(0.2 - 0) = 0.04
    try std.testing.expect(rfr.average_decay > 0.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.04), rfr.average_decay, 0.01);
}

test "reverb_frequency_response converges over iterations" {
    var rfr = ReverbFrequencyResponse.init();
    var freq_resp: [4][FFT_LENGTH_BY_2_PLUS_1]f32 = undefined;
    for (&freq_resp) |*block| block.* = [_]f32{0.0} ** FFT_LENGTH_BY_2_PLUS_1;
    for (&freq_resp[0]) |*v| v.* = 10.0;
    for (&freq_resp[3]) |*v| v.* = 5.0;

    for (0..200) |_| {
        rfr.update(&freq_resp, 0, 1.0, false);
    }
    // Should converge toward tail/direct = 5/10 = 0.5 (approximately, bin 0 excluded).
    // Due to smoothing factor 0.2, after 200 iters it should be close.
    try std.testing.expect(rfr.average_decay > 0.3);
    try std.testing.expect(rfr.average_decay < 0.6);
}
