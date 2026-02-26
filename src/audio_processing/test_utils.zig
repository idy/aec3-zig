const std = @import("std");

pub fn mean_abs_error(a: []const f32, b: []const f32) f32 {
    std.debug.assert(a.len == b.len);
    var sum: f32 = 0.0;
    for (a, b) |x, y| {
        sum += @abs(x - y);
    }
    return sum / @as(f32, @floatFromInt(a.len));
}
