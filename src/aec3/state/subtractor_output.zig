const std = @import("std");

pub const SubtractorOutput = struct {
    allocator: std.mem.Allocator,
    residual: []f32,
    residual_energy: f32,

    pub fn fromSlice(allocator: std.mem.Allocator, residual: []const f32) !SubtractorOutput {
        if (residual.len == 0) return error.EmptyInput;
        const owned = try allocator.alloc(f32, residual.len);
        @memcpy(owned, residual);
        return .{
            .allocator = allocator,
            .residual = owned,
            .residual_energy = computeEnergy(owned),
        };
    }

    pub fn update(self: *SubtractorOutput, residual: []const f32) !void {
        if (residual.len == 0) return error.EmptyInput;
        if (residual.len != self.residual.len) return error.LengthMismatch;
        @memcpy(self.residual, residual);
        self.residual_energy = computeEnergy(self.residual);
    }

    pub fn deinit(self: *SubtractorOutput) void {
        self.allocator.free(self.residual);
        self.residual = &[_]f32{};
        self.residual_energy = 0.0;
    }

    fn computeEnergy(samples: []const f32) f32 {
        var energy: f32 = 0.0;
        for (samples) |sample| energy += sample * sample;
        return energy;
    }
};

test "subtractor_output structure initialization" {
    const allocator = std.testing.allocator;
    const input = [_]f32{ 1.0, -1.0, 0.5 };
    var output = try SubtractorOutput.fromSlice(allocator, input[0..]);
    defer output.deinit();

    try std.testing.expectEqual(@as(usize, 3), output.residual.len);
    try std.testing.expectApproxEqAbs(@as(f32, 2.25), output.residual_energy, 1e-6);
}

test "subtractor_output empty data handling" {
    try std.testing.expectError(error.EmptyInput, SubtractorOutput.fromSlice(std.testing.allocator, &[_]f32{}));
}

test "subtractor_output update operations" {
    const allocator = std.testing.allocator;
    const input = [_]f32{ 1.0, 1.0 };
    const update_values = [_]f32{ 2.0, 0.0 };

    var output = try SubtractorOutput.fromSlice(allocator, input[0..]);
    defer output.deinit();

    try output.update(update_values[0..]);
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), output.residual_energy, 1e-6);
}
