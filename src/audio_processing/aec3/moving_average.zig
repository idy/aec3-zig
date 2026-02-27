const std = @import("std");

pub const MovingAverage = struct {
    const Self = @This();

    num_elements: usize,
    memory: []f32,
    history_len: usize,
    scaling: f32,
    mem_index: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, num_elements: usize, window_length: usize) !Self {
        std.debug.assert(num_elements > 0);
        std.debug.assert(window_length > 0);

        const history_len = window_length -| 1;
        const memory = try allocator.alloc(f32, num_elements * history_len);
        @memset(memory, 0.0);
        return .{
            .num_elements = num_elements,
            .memory = memory,
            .history_len = history_len,
            .scaling = 1.0 / @as(f32, @floatFromInt(window_length)),
            .mem_index = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.memory);
        self.* = undefined;
    }

    pub fn average(self: *Self, input: []const f32, output: []f32) void {
        std.debug.assert(input.len == self.num_elements);
        std.debug.assert(output.len == self.num_elements);
        @memcpy(output, input);

        if (self.history_len > 0) {
            for (0..self.history_len) |h| {
                const start = h * self.num_elements;
                const mem = self.memory[start .. start + self.num_elements];
                for (mem, 0..) |v, i| output[i] += v;
            }
        }
        for (output) |*v| v.* *= self.scaling;

        if (self.history_len == 0) return;
        const start = self.mem_index * self.num_elements;
        @memcpy(self.memory[start .. start + self.num_elements], input);
        self.mem_index = (self.mem_index + 1) % self.history_len;
    }
};

test "moving_average known sequence" {
    var ma = try MovingAverage.init(std.testing.allocator, 1, 2);
    defer ma.deinit();
    var out = [_]f32{0};

    ma.average(&[_]f32{1}, out[0..]);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), out[0], 1e-6);
    ma.average(&[_]f32{2}, out[0..]);
    try std.testing.expectApproxEqAbs(@as(f32, 1.5), out[0], 1e-6);
}
