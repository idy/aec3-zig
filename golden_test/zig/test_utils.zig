const std = @import("std");

pub fn parseNamedF32(text: []const u8, comptime name: []const u8, comptime N: usize) [N]f32 {
    var out: [N]f32 = undefined;
    var seen = [_]bool{false} ** N;
    const prefix = std.fmt.comptimePrint("{s}[", .{name});

    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (!std.mem.startsWith(u8, line, prefix)) continue;

        const close = std.mem.indexOfScalarPos(u8, line, prefix.len, ']') orelse @panic("invalid index line");
        const eq = std.mem.indexOfScalarPos(u8, line, close + 1, '=') orelse @panic("invalid value line");

        const idx = std.fmt.parseInt(usize, line[prefix.len..close], 10) catch @panic("invalid index parse");
        if (idx >= N) @panic("index out of range");
        const val = std.fmt.parseFloat(f32, line[eq + 1 ..]) catch @panic("invalid float parse");

        out[idx] = val;
        seen[idx] = true;
    }

    for (seen) |ok| {
        if (!ok) @panic("golden vector incomplete");
    }
    return out;
}

pub fn parseNamedF64(text: []const u8, comptime name: []const u8, comptime N: usize) [N]f64 {
    var out: [N]f64 = undefined;
    var seen = [_]bool{false} ** N;
    const prefix = std.fmt.comptimePrint("{s}[", .{name});

    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (!std.mem.startsWith(u8, line, prefix)) continue;

        const close = std.mem.indexOfScalarPos(u8, line, prefix.len, ']') orelse @panic("invalid index line");
        const eq = std.mem.indexOfScalarPos(u8, line, close + 1, '=') orelse @panic("invalid value line");

        const idx = std.fmt.parseInt(usize, line[prefix.len..close], 10) catch @panic("invalid index parse");
        if (idx >= N) @panic("index out of range");
        const val = std.fmt.parseFloat(f64, line[eq + 1 ..]) catch @panic("invalid float parse");

        out[idx] = val;
        seen[idx] = true;
    }

    for (seen) |ok| {
        if (!ok) @panic("golden vector incomplete");
    }
    return out;
}

pub fn parseNamedUsize(text: []const u8, comptime name: []const u8, comptime N: usize) [N]usize {
    var out: [N]usize = undefined;
    var seen = [_]bool{false} ** N;
    const prefix = std.fmt.comptimePrint("{s}[", .{name});

    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (!std.mem.startsWith(u8, line, prefix)) continue;

        const close = std.mem.indexOfScalarPos(u8, line, prefix.len, ']') orelse @panic("invalid index line");
        const eq = std.mem.indexOfScalarPos(u8, line, close + 1, '=') orelse @panic("invalid value line");

        const idx = std.fmt.parseInt(usize, line[prefix.len..close], 10) catch @panic("invalid index parse");
        if (idx >= N) @panic("index out of range");
        const val = std.fmt.parseInt(usize, line[eq + 1 ..], 10) catch @panic("invalid int parse");

        out[idx] = val;
        seen[idx] = true;
    }

    for (seen) |ok| {
        if (!ok) @panic("golden vector incomplete");
    }
    return out;
}

pub fn parseNamedI32(text: []const u8, comptime name: []const u8, comptime N: usize) [N]i32 {
    var out: [N]i32 = undefined;
    var seen = [_]bool{false} ** N;
    const prefix = std.fmt.comptimePrint("{s}[", .{name});

    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (!std.mem.startsWith(u8, line, prefix)) continue;

        const close = std.mem.indexOfScalarPos(u8, line, prefix.len, ']') orelse @panic("invalid index line");
        const eq = std.mem.indexOfScalarPos(u8, line, close + 1, '=') orelse @panic("invalid value line");

        const idx = std.fmt.parseInt(usize, line[prefix.len..close], 10) catch @panic("invalid index parse");
        if (idx >= N) @panic("index out of range");
        const val = std.fmt.parseInt(i32, line[eq + 1 ..], 10) catch @panic("invalid int parse");

        out[idx] = val;
        seen[idx] = true;
    }

    for (seen) |ok| {
        if (!ok) @panic("golden vector incomplete");
    }
    return out;
}

pub fn expectUlpEq(a: f32, b: f32, max_ulp: u32) !void {
    if (std.math.isNan(a) or std.math.isNan(b)) {
        return std.testing.expect(false);
    }
    const diff = ulpDiff(a, b);
    try std.testing.expect(diff <= max_ulp);
}

pub const ErrorThresholds = struct {
    max_abs: f32,
    mean_abs: f32,
    p95_abs: f32,
};

pub const ErrorStats = struct {
    max_abs: f32,
    mean_abs: f32,
    p95_abs: f32,
    max_abs_index: usize,
    expected_at_max: f32,
    actual_at_max: f32,
};

pub const ErrorStatsError = error{
    OutOfMemory,
    EmptyInput,
    LengthMismatch,
    ApproxEqStatsFailed,
};

pub const print_error_stats: bool = false;

pub fn computeErrorStats(
    allocator: std.mem.Allocator,
    expected: []const f32,
    actual: []const f32,
) ErrorStatsError!ErrorStats {
    if (expected.len != actual.len) return ErrorStatsError.LengthMismatch;
    if (expected.len == 0) return ErrorStatsError.EmptyInput;

    var abs_errors = try allocator.alloc(f32, expected.len);
    defer allocator.free(abs_errors);

    var max_abs: f32 = 0.0;
    var max_abs_index: usize = 0;
    var expected_at_max: f32 = expected[0];
    var actual_at_max: f32 = actual[0];
    var sum_abs: f64 = 0.0;

    for (expected, actual, 0..) |e, a, i| {
        const abs_err = @abs(e - a);
        abs_errors[i] = abs_err;
        sum_abs += abs_err;

        if (abs_err > max_abs) {
            max_abs = abs_err;
            max_abs_index = i;
            expected_at_max = e;
            actual_at_max = a;
        }
    }

    var i: usize = 1;
    while (i < abs_errors.len) : (i += 1) {
        const key = abs_errors[i];
        var j = i;
        while (j > 0 and abs_errors[j - 1] > key) : (j -= 1) {
            abs_errors[j] = abs_errors[j - 1];
        }
        abs_errors[j] = key;
    }

    const n = abs_errors.len;
    const rank_ceil = (95 * n + 99) / 100;
    const p95_index = if (rank_ceil == 0) 0 else rank_ceil - 1;

    return .{
        .max_abs = max_abs,
        .mean_abs = @as(f32, @floatCast(sum_abs / @as(f64, @floatFromInt(n)))),
        .p95_abs = abs_errors[p95_index],
        .max_abs_index = max_abs_index,
        .expected_at_max = expected_at_max,
        .actual_at_max = actual_at_max,
    };
}

pub fn expectErrorStatsWithin(
    allocator: std.mem.Allocator,
    expected: []const f32,
    actual: []const f32,
    thresholds: ErrorThresholds,
    context: []const u8,
) ErrorStatsError!void {
    const stats = computeErrorStats(allocator, expected, actual) catch |err| {
        if (err == ErrorStatsError.LengthMismatch) {
            std.debug.print(
                "[{s}] error stats input length mismatch: expected_len={}, actual_len={}\n",
                .{ context, expected.len, actual.len },
            );
        }
        return err;
    };

    if (print_error_stats) {
        std.debug.print(
            "[{s}] error stats: len={}, max_abs={e:.9} @idx={}, mean_abs={e:.9}, p95_abs={e:.9}, expected@max={e:.9}, actual@max={e:.9}\n",
            .{
                context,
                expected.len,
                stats.max_abs,
                stats.max_abs_index,
                stats.mean_abs,
                stats.p95_abs,
                stats.expected_at_max,
                stats.actual_at_max,
            },
        );
    }

    const max_fail = stats.max_abs > thresholds.max_abs;
    const mean_fail = stats.mean_abs > thresholds.mean_abs;
    const p95_fail = stats.p95_abs > thresholds.p95_abs;

    if (max_fail or mean_fail or p95_fail) {
        std.debug.print(
            "[{s}] error stats exceeded: len={}, max_abs={e:.9} (th={e:.9}) @idx={}, mean_abs={e:.9} (th={e:.9}), p95_abs={e:.9} (th={e:.9}), expected@max={e:.9}, actual@max={e:.9}\n",
            .{
                context,
                expected.len,
                stats.max_abs,
                thresholds.max_abs,
                stats.max_abs_index,
                stats.mean_abs,
                thresholds.mean_abs,
                stats.p95_abs,
                thresholds.p95_abs,
                stats.expected_at_max,
                stats.actual_at_max,
            },
        );
        return ErrorStatsError.ApproxEqStatsFailed;
    }
}

fn orderedUlpBits(x: f32) i32 {
    const bits_u32: u32 = @bitCast(x);
    const bits_i32: i32 = @bitCast(bits_u32);
    return if (bits_i32 < 0) std.math.minInt(i32) - bits_i32 else bits_i32;
}

fn ulpDiff(a: f32, b: f32) u32 {
    const oa = orderedUlpBits(a);
    const ob = orderedUlpBits(b);
    return @intCast(@abs(oa - ob));
}
