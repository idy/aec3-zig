//! Ported from: docs/aec3-rs-src/audio_processing/logging/apm_data_dumper.rs
const std = @import("std");

/// Diagnostic logging level.
pub const DiagnosticLevel = enum(u8) {
    production = 0,
    developer = 1,
    deep_debug = 2,
};

/// APM data dumper (no-op stub implementation).
pub const ApmDataDumper = struct {
    instance_index_: usize,

    /// Creates a new ApmDataDumper with the specified index.
    pub fn new(index: usize) ApmDataDumper {
        return .{ .instance_index_ = index };
    }

    /// Creates a new ApmDataDumper with a unique auto-incrementing index.
    pub fn new_unique() ApmDataDumper {
        var counter = CounterHolder.counter();
        const index = counter.fetchAdd(1, .monotonic);
        return new(index);
    }

    /// Returns the instance index.
    pub fn instance_index(self: ApmDataDumper) usize {
        return self.instance_index_;
    }

    /// No-op: Sets the activated state.
    pub fn set_activated(_: bool) void {}
    /// No-op: Sets the diagnostics level.
    pub fn set_diagnostics_level(_: DiagnosticLevel) void {}
    /// No-op: Sets the output directory.
    pub fn set_output_directory(_: []const u8) void {}
    /// No-op: Initiates a new set of recordings.
    pub fn initiate_new_set_of_recordings(_: *const ApmDataDumper) void {}
    /// No-op: Dumps a raw f32 value.
    pub fn dump_raw_f32(_: *const ApmDataDumper, _: DiagnosticLevel, _: []const u8, _: f32) void {}
    /// No-op: Dumps a slice of raw f32 values.
    pub fn dump_raw_f32_slice(_: *const ApmDataDumper, _: DiagnosticLevel, _: []const u8, _: []const f32) void {}
    /// No-op: Dumps a raw i32 value.
    pub fn dump_raw_i32(_: *const ApmDataDumper, _: DiagnosticLevel, _: []const u8, _: i32) void {}
    /// No-op: Dumps a slice of raw i32 values.
    pub fn dump_raw_i32_slice(_: *const ApmDataDumper, _: DiagnosticLevel, _: []const u8, _: []const i32) void {}
    /// No-op: Dumps a raw usize value.
    pub fn dump_raw_usize(_: *const ApmDataDumper, _: DiagnosticLevel, _: []const u8, _: usize) void {}
    /// No-op: Dumps a slice of raw usize values.
    pub fn dump_raw_usize_slice(_: *const ApmDataDumper, _: DiagnosticLevel, _: []const u8, _: []const usize) void {}

    /// No-op: Dumps audio as WAV file.
    pub fn dump_wav(
        _: *const ApmDataDumper,
        _: DiagnosticLevel,
        _: []const u8,
        _: usize,
        _: []const f32,
        _: usize,
        _: usize,
    ) void {}
};

const CounterHolder = struct {
    var g_counter = std.atomic.Value(usize).init(0);

    fn counter() *std.atomic.Value(usize) {
        return &g_counter;
    }
};

test "test_new_unique_increments" {
    const a = ApmDataDumper.new_unique();
    const b = ApmDataDumper.new_unique();
    try std.testing.expect(b.instance_index() > a.instance_index());
}

test "test_noop_methods_dont_crash" {
    const d = ApmDataDumper.new_unique();
    ApmDataDumper.set_activated(true);
    ApmDataDumper.set_diagnostics_level(.developer);
    ApmDataDumper.set_output_directory(".");
    d.initiate_new_set_of_recordings();
    d.dump_raw_f32(.production, "x", 1.0);
    d.dump_raw_f32_slice(.production, "x", &[_]f32{ 1.0, 2.0 });
    d.dump_raw_i32(.production, "x", 1);
    d.dump_raw_i32_slice(.production, "x", &[_]i32{ 1, 2 });
    d.dump_raw_usize(.production, "x", 1);
    d.dump_raw_usize_slice(.production, "x", &[_]usize{ 1, 2 });
    d.dump_wav(.production, "x", 2, &[_]f32{ 0.1, 0.2 }, 16_000, 1);
}
