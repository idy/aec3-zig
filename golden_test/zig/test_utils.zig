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

pub fn expectSliceApproxEq(expected: []const f32, actual: []const f32, max_rel_err: f32, max_abs_err: f32) !void {
    std.debug.assert(expected.len == actual.len);

    var mismatch_count: usize = 0;
    var max_rel_found: f32 = 0.0;
    var max_abs_found: f32 = 0.0;

    for (expected, actual, 0..) |e, a, i| {
        const abs_diff = @abs(e - a);
        const rel_diff = if (@abs(e) > 1e-10) abs_diff / @abs(e) else abs_diff;

        max_rel_found = @max(max_rel_found, rel_diff);
        max_abs_found = @max(max_abs_found, abs_diff);

        if (rel_diff > max_rel_err and abs_diff > max_abs_err) {
            if (mismatch_count < 5) {
                std.debug.print(
                    "Mismatch at [{}]: expected={e:.9}, actual={e:.9}, rel_err={e:.6}, abs_err={e:.9}\n",
                    .{ i, e, a, rel_diff, abs_diff },
                );
            }
            mismatch_count += 1;
        }
    }

    if (mismatch_count > 0) {
        std.debug.print(
            "Total mismatches: {}/{}, max_rel_err={e:.6}, max_abs_err={e:.9}\n",
            .{ mismatch_count, expected.len, max_rel_found, max_abs_found },
        );
        return error.ApproxEqFailed;
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
