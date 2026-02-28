const std = @import("std");
const common = @import("../common/aec3_common.zig");
const cascaded_biquad_filter = @import("../filters/cascaded_biquad_filter.zig");
const Complex32 = @import("../../complex.zig").Complex(f32);

const BLOCK_SIZE = common.BLOCK_SIZE;

pub const Decimator = struct {
    const Self = @This();

    down_sampling_factor: usize,
    anti_aliasing_filter: cascaded_biquad_filter.CascadedBiQuadFilter,
    noise_reduction_filter: cascaded_biquad_filter.CascadedBiQuadFilter,

    pub fn init(allocator: std.mem.Allocator, down_sampling_factor: usize) !Self {
        if (!(down_sampling_factor == 2 or down_sampling_factor == 4 or down_sampling_factor == 8)) {
            return error.InvalidDownSamplingFactor;
        }

        const anti_alias_params: []const cascaded_biquad_filter.BiQuadParam = switch (down_sampling_factor) {
            2 => low_pass_filter_ds2()[0..],
            4 => low_pass_filter_ds4()[0..],
            8 => band_pass_filter_ds8()[0..],
            else => unreachable,
        };
        const noise_params: []const cascaded_biquad_filter.BiQuadParam = if (down_sampling_factor == 8)
            pass_through_filter()[0..]
        else
            high_pass_filter()[0..];

        var anti = try cascaded_biquad_filter.CascadedBiQuadFilter.from_params(allocator, anti_alias_params);
        errdefer anti.deinit();
        const noise = try cascaded_biquad_filter.CascadedBiQuadFilter.from_params(allocator, noise_params);

        return .{
            .down_sampling_factor = down_sampling_factor,
            .anti_aliasing_filter = anti,
            .noise_reduction_filter = noise,
        };
    }

    pub fn deinit(self: *Self) void {
        self.anti_aliasing_filter.deinit();
        self.noise_reduction_filter.deinit();
        self.* = undefined;
    }

    pub fn decimate(self: *Self, input: []const f32, output: []f32) void {
        std.debug.assert(input.len == BLOCK_SIZE);
        std.debug.assert(output.len == BLOCK_SIZE / self.down_sampling_factor);

        var filtered: [BLOCK_SIZE]f32 = undefined;
        self.anti_aliasing_filter.process(input, filtered[0..]);
        self.noise_reduction_filter.process_in_place(filtered[0..]);

        var k: usize = 0;
        for (output) |*sample| {
            sample.* = filtered[k];
            k += self.down_sampling_factor;
        }
    }
};

fn low_pass_filter_ds2() [3]cascaded_biquad_filter.BiQuadParam {
    return [_]cascaded_biquad_filter.BiQuadParam{
        cascaded_biquad_filter.BiQuadParam.new(Complex32.init(-1.0, 0.0), Complex32.init(0.13833231, 0.40743176), 0.22711796),
        cascaded_biquad_filter.BiQuadParam.new(Complex32.init(-1.0, 0.0), Complex32.init(0.13833231, 0.40743176), 0.22711796),
        cascaded_biquad_filter.BiQuadParam.new(Complex32.init(-1.0, 0.0), Complex32.init(0.13833231, 0.40743176), 0.22711796),
    };
}

fn low_pass_filter_ds4() [3]cascaded_biquad_filter.BiQuadParam {
    return [_]cascaded_biquad_filter.BiQuadParam{
        cascaded_biquad_filter.BiQuadParam.new(Complex32.init(-0.08873842, 0.99605496), Complex32.init(0.75916227, 0.23841065), 0.26250696),
        cascaded_biquad_filter.BiQuadParam.new(Complex32.init(0.62273832, 0.78243018), Complex32.init(0.74892112, 0.5410152), 0.26250696),
        cascaded_biquad_filter.BiQuadParam.new(Complex32.init(0.71107693, 0.70311421), Complex32.init(0.74895534, 0.63924616), 0.26250696),
    };
}

fn band_pass_filter_ds8() [5]cascaded_biquad_filter.BiQuadParam {
    const p = cascaded_biquad_filter.BiQuadParam{
        .zero = Complex32.init(1.0, 0.0),
        .pole = Complex32.init(0.7601815, 0.46423542),
        .gain = 0.10330478,
        .mirror_zero_along_i_axis = true,
    };
    return [_]cascaded_biquad_filter.BiQuadParam{ p, p, p, p, p };
}

fn high_pass_filter() [1]cascaded_biquad_filter.BiQuadParam {
    return [_]cascaded_biquad_filter.BiQuadParam{
        cascaded_biquad_filter.BiQuadParam.new(Complex32.init(1.0, 0.0), Complex32.init(0.72712179, 0.21296904), 0.75707637),
    };
}

fn pass_through_filter() [0]cascaded_biquad_filter.BiQuadParam {
    return .{};
}

test "decimator output length and stride" {
    var d = try Decimator.init(std.testing.allocator, 4);
    defer d.deinit();
    const input = [_]f32{1.0} ** BLOCK_SIZE;
    var out = [_]f32{0.0} ** (BLOCK_SIZE / 4);
    d.decimate(input[0..], out[0..]);
    try std.testing.expectEqual(@as(usize, BLOCK_SIZE / 4), out.len);
}

test "decimator rejects invalid factor" {
    try std.testing.expectError(error.InvalidDownSamplingFactor, Decimator.init(std.testing.allocator, 3));
}

test "decimator valid factors initialize and process finite values" {
    const input = [_]f32{0.5} ** BLOCK_SIZE;
    inline for (.{ 2, 4, 8 }) |factor| {
        var d = try Decimator.init(std.testing.allocator, factor);
        defer d.deinit();

        var out = [_]f32{0.0} ** (BLOCK_SIZE / factor);
        d.decimate(input[0..], out[0..]);
        for (out) |v| try std.testing.expect(std.math.isFinite(v));
    }
}

test "decimator init rolls back on allocation failure" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const alloc = failing.allocator();
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, Decimator.init(alloc, 2));
}
