const std = @import("std");
const config = @import("../../api/config.zig");
const common = @import("aec3_common.zig");

const BLOCK_SIZE = common.BLOCK_SIZE;
const NUM_BLOCKS_PER_SECOND = common.NUM_BLOCKS_PER_SECOND;

pub const MixingVariant = enum {
    downmix,
    adaptive,
    fixed,
};

fn choose_mixing_variant(num_channels: usize, cfg: config.AlignmentMixing) MixingVariant {
    std.debug.assert(num_channels > 0);
    if (num_channels == 1) return .fixed;
    if (cfg.downmix) return .downmix;
    if (cfg.adaptive_selection) return .adaptive;
    return .fixed;
}

pub const AlignmentMixer = struct {
    const Self = @This();

    num_channels: usize,
    one_by_num_channels: f32,
    excitation_energy_threshold: f32,
    prefer_first_two_channels: bool,
    selection_variant: MixingVariant,
    strong_block_counters: [2]usize,
    cumulative_energies: []f32,
    selected_channel: usize,
    block_counter: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, num_channels: usize, cfg: config.AlignmentMixing) !Self {
        if (num_channels == 0) return error.InvalidChannelCount;
        const variant = choose_mixing_variant(num_channels, cfg);
        const cumulative = if (variant == .adaptive) try allocator.alloc(f32, num_channels) else &[_]f32{};
        errdefer if (variant == .adaptive) allocator.free(cumulative);
        if (variant == .adaptive) @memset(cumulative, 0.0);

        return .{
            .num_channels = num_channels,
            .one_by_num_channels = 1.0 / @as(f32, @floatFromInt(num_channels)),
            .excitation_energy_threshold = @as(f32, @floatFromInt(BLOCK_SIZE)) * cfg.activity_power_threshold,
            .prefer_first_two_channels = cfg.prefer_first_two_channels,
            .selection_variant = variant,
            .strong_block_counters = .{ 0, 0 },
            .cumulative_energies = cumulative,
            .selected_channel = 0,
            .block_counter = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.selection_variant == .adaptive) self.allocator.free(self.cumulative_energies);
        self.* = undefined;
    }

    pub fn produce_output(self: *Self, x: []const [BLOCK_SIZE]f32, y: *[BLOCK_SIZE]f32) void {
        std.debug.assert(x.len == self.num_channels);
        switch (self.selection_variant) {
            .downmix => self.downmix(x, y),
            .adaptive => {
                const ch = self.select_channel(x);
                y.* = x[ch];
            },
            .fixed => y.* = x[0],
        }
    }

    fn downmix(self: Self, x: []const [BLOCK_SIZE]f32, y: *[BLOCK_SIZE]f32) void {
        @memset(y, 0.0);
        for (x) |channel| {
            for (channel, 0..) |sample, i| y[i] += sample;
        }
        for (y) |*sample| sample.* *= self.one_by_num_channels;
    }

    fn select_channel(self: *Self, x: []const [BLOCK_SIZE]f32) usize {
        const blocks_to_choose = NUM_BLOCKS_PER_SECOND / 2;
        const good_signal_in_lr = self.prefer_first_two_channels and
            (self.strong_block_counters[0] > blocks_to_choose or self.strong_block_counters[1] > blocks_to_choose);
        const num_channels_to_analyze = if (good_signal_in_lr) @min(@as(usize, 2), self.num_channels) else self.num_channels;
        const NUM_BLOCKS_BEFORE_SMOOTHING: usize = 60 * NUM_BLOCKS_PER_SECOND;
        const SMOOTHING: f32 = 1.0 / (10.0 * @as(f32, @floatFromInt(NUM_BLOCKS_PER_SECOND)));
        self.block_counter += 1;

        for (0..num_channels_to_analyze) |ch| {
            var x2_sum: f32 = 0.0;
            for (x[ch]) |sample| x2_sum += sample * sample;
            if (ch < 2 and x2_sum > self.excitation_energy_threshold) self.strong_block_counters[ch] += 1;

            if (self.block_counter <= NUM_BLOCKS_BEFORE_SMOOTHING) {
                self.cumulative_energies[ch] += x2_sum;
            } else {
                self.cumulative_energies[ch] += SMOOTHING * (x2_sum - self.cumulative_energies[ch]);
            }
        }

        if (self.block_counter == NUM_BLOCKS_BEFORE_SMOOTHING) {
            const factor = 1.0 / @as(f32, @floatFromInt(NUM_BLOCKS_BEFORE_SMOOTHING));
            for (0..num_channels_to_analyze) |ch| self.cumulative_energies[ch] *= factor;
        }

        var strongest: usize = 0;
        for (1..num_channels_to_analyze) |ch| {
            if (self.cumulative_energies[ch] > self.cumulative_energies[strongest]) strongest = ch;
        }

        if ((good_signal_in_lr and self.selected_channel > 1) or
            (self.cumulative_energies[strongest] > 2.0 * self.cumulative_energies[self.selected_channel]))
        {
            self.selected_channel = strongest;
        }
        return @min(self.selected_channel, self.num_channels - 1);
    }
};

test "alignment_mixer downmix average" {
    const cfg = config.AlignmentMixing{
        .downmix = true,
        .adaptive_selection = false,
        .activity_power_threshold = 0.01,
        .prefer_first_two_channels = false,
    };
    var mixer = try AlignmentMixer.init(std.testing.allocator, 2, cfg);
    defer mixer.deinit();

    var x = [_][BLOCK_SIZE]f32{ [_]f32{1.0} ** BLOCK_SIZE, [_]f32{3.0} ** BLOCK_SIZE };
    var y: [BLOCK_SIZE]f32 = undefined;
    mixer.produce_output(x[0..], &y);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), y[0], 1e-6);
}
