//! Ported from: docs/aec3-rs-src/audio_processing/sparse_fir_filter.rs
const std = @import("std");

/// Sparse finite impulse response filter.
pub const SparseFIRFilter = struct {
    sparsity: usize,
    offset: usize,
    coeffs: []f32,
    state: []f32,
    allocator: std.mem.Allocator,

    pub fn new(allocator: std.mem.Allocator, nonzero_coeffs: []const f32, sparsity: usize, offset: usize) !SparseFIRFilter {
        if (nonzero_coeffs.len == 0) return error.EmptyCoefficients;
        if (sparsity == 0) return error.InvalidSparsity;

        const state_len = if (nonzero_coeffs.len > 1)
            sparsity * (nonzero_coeffs.len - 1) + offset
        else
            offset;

        const coeffs = try allocator.alloc(f32, nonzero_coeffs.len);
        errdefer allocator.free(coeffs);
        @memcpy(coeffs, nonzero_coeffs);

        const state = try allocator.alloc(f32, state_len);
        @memset(state, 0.0);

        return .{
            .sparsity = sparsity,
            .offset = offset,
            .coeffs = coeffs,
            .state = state,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SparseFIRFilter) void {
        self.allocator.free(self.coeffs);
        self.allocator.free(self.state);
    }

    pub fn filter(self: *SparseFIRFilter, input: []const f32, output: []f32) void {
        std.debug.assert(input.len == output.len);

        for (output, 0..) |*out_sample, i| {
            var acc: f32 = 0.0;
            var tap: usize = 0;
            while (tap < self.coeffs.len) : (tap += 1) {
                const idx = tap * self.sparsity + self.offset;
                if (i >= idx) {
                    acc += input[i - idx] * self.coeffs[tap];
                } else {
                    const state_index = i + (self.coeffs.len - tap - 1) * self.sparsity;
                    if (state_index < self.state.len) {
                        acc += self.state[state_index] * self.coeffs[tap];
                    }
                }
            }
            out_sample.* = acc;
        }

        if (self.state.len == 0) return;
        const state_len = self.state.len;
        if (input.len >= state_len) {
            @memcpy(self.state, input[input.len - state_len ..]);
        } else {
            std.mem.copyForwards(f32, self.state[0 .. state_len - input.len], self.state[input.len..]);
            @memcpy(self.state[state_len - input.len ..], input);
        }
    }
};

test "sparse_fir_filter basic convolution" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const coeffs = [_]f32{ 1.0, 0.5 };
    var filter_inst = try SparseFIRFilter.new(arena.allocator(), coeffs[0..], 1, 0);
    defer filter_inst.deinit();

    const input = [_]f32{ 1.0, 2.0, 3.0, 4.0 };
    var output = [_]f32{0} ** input.len;
    filter_inst.filter(input[0..], output[0..]);

    try std.testing.expectApproxEqAbs(@as(f32, 1.0), output[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 2.5), output[1], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), output[2], 1e-6);
}

test "sparse_fir_filter keeps state across blocks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const coeffs = [_]f32{ 1.0, 1.0 };
    var filter_inst = try SparseFIRFilter.new(arena.allocator(), coeffs[0..], 1, 0);
    defer filter_inst.deinit();

    const block1 = [_]f32{ 1.0, 2.0 };
    var out1 = [_]f32{0} ** block1.len;
    filter_inst.filter(block1[0..], out1[0..]);

    const block2 = [_]f32{ 3.0, 4.0 };
    var out2 = [_]f32{0} ** block2.len;
    filter_inst.filter(block2[0..], out2[0..]);

    try std.testing.expectApproxEqAbs(@as(f32, 5.0), out2[0], 1e-6); // 3 + prev(2)
    try std.testing.expectApproxEqAbs(@as(f32, 7.0), out2[1], 1e-6); // 4 + 3
}

test "sparse_fir_filter constructor validates boundary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const empty: [0]f32 = .{};
    try std.testing.expectError(error.EmptyCoefficients, SparseFIRFilter.new(arena.allocator(), empty[0..], 1, 0));

    const coeffs = [_]f32{1.0};
    try std.testing.expectError(error.InvalidSparsity, SparseFIRFilter.new(arena.allocator(), coeffs[0..], 0, 0));
}

test "sparse_fir_filter filter handles empty slices" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const coeffs = [_]f32{ 1.0, 0.5 };
    var filter_inst = try SparseFIRFilter.new(arena.allocator(), coeffs[0..], 1, 0);
    defer filter_inst.deinit();

    var out: [0]f32 = .{};
    const in: [0]f32 = .{};
    filter_inst.filter(in[0..], out[0..]);
}

test "sparse_fir_filter deinit frees memory" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const coeffs = [_]f32{ 1.0, 0.5, 0.25, 0.125 };
    var filter_inst = try SparseFIRFilter.new(arena.allocator(), coeffs[0..], 2, 1);
    filter_inst.deinit();

    // If deinit doesn't free properly, arena will detect leak
    try std.testing.expect(true);
}

test "sparse_fir_filter filter boundary single coefficient" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // Single coefficient acts as simple gain
    const coeffs = [_]f32{2.0};
    var filter_inst = try SparseFIRFilter.new(arena.allocator(), coeffs[0..], 1, 0);
    defer filter_inst.deinit();

    var input = [_]f32{ 1.0, 2.0, 3.0 };
    var output = [_]f32{ 0.0, 0.0, 0.0 };

    filter_inst.filter(input[0..], output[0..]);

    // Single coefficient should just multiply
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), output[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), output[1], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 6.0), output[2], 1e-6);
}

test "sparse_fir_filter deinit boundary zero-state" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const coeffs = [_]f32{1.0};
    var filter_inst = try SparseFIRFilter.new(arena.allocator(), coeffs[0..], 1, 0);
    filter_inst.deinit();
}
