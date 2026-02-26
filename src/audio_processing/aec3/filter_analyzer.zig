const std = @import("std");

pub const FilterMetrics = struct {
    tap_mse: f32,
    tap_energy: f32,
    converged: bool,
};

pub const FilterAnalyzer = struct {
    convergence_mse_threshold: f32,

    pub fn init(convergence_mse_threshold: f32) !FilterAnalyzer {
        if (!(convergence_mse_threshold > 0.0)) return error.InvalidConfiguration;
        return .{ .convergence_mse_threshold = convergence_mse_threshold };
    }

    pub fn analyze(self: *const FilterAnalyzer, taps: []const f32, reference_taps: []const f32) !FilterMetrics {
        if (taps.len != reference_taps.len) return error.LengthMismatch;
        if (taps.len == 0) return error.EmptyInput;

        var mse: f32 = 0.0;
        var energy: f32 = 0.0;
        for (taps, reference_taps) |actual, expected| {
            const diff = actual - expected;
            mse += diff * diff;
            energy += actual * actual;
        }
        mse /= @as(f32, @floatFromInt(taps.len));
        return .{
            .tap_mse = mse,
            .tap_energy = energy,
            .converged = mse <= self.convergence_mse_threshold,
        };
    }
};

test "filter_analyzer computes mse and convergence" {
    var analyzer = try FilterAnalyzer.init(1e-3);
    const ref = [_]f32{ 0.5, -0.25, 0.1, 0.0 };
    const near = [_]f32{ 0.5, -0.249, 0.101, 0.0 };
    const metrics = try analyzer.analyze(near[0..], ref[0..]);
    try std.testing.expect(metrics.tap_mse < 1e-3);
    try std.testing.expect(metrics.converged);
}

test "filter_analyzer validates boundaries" {
    var analyzer = try FilterAnalyzer.init(1e-3);
    try std.testing.expectError(error.LengthMismatch, analyzer.analyze(&[_]f32{1.0}, &[_]f32{ 1.0, 2.0 }));
    try std.testing.expectError(error.EmptyInput, analyzer.analyze(&[_]f32{}, &[_]f32{}));
    try std.testing.expectError(error.InvalidConfiguration, FilterAnalyzer.init(0.0));
}
