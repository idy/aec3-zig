const std = @import("std");

pub fn build(b: *std.Build) void {
    // 编译选项
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 创建主模块
    const aec3_mod = b.addModule("aec3", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 创建静态库
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lib = b.addLibrary(.{
        .name = "aec3",
        .root_module = lib_mod,
    });
    b.installArtifact(lib);

    // 创建单元测试（全部使用模块内联测试）
    const unit_tests = b.addTest(.{
        .name = "aec3_test",
        .root_module = aec3_mod,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // 创建 golden 向量测试（独立于 src 单元测试）
    const golden_mod = b.createModule(.{
        .root_source_file = b.path("golden_test/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    golden_mod.addImport("aec3", aec3_mod);

    const golden_tests = b.addTest(.{
        .name = "aec3_golden_test",
        .root_module = golden_mod,
    });
    const run_golden_tests = b.addRunArtifact(golden_tests);
    const golden_test_step = b.step("golden-test", "Run golden vector tests");
    golden_test_step.dependOn(&run_golden_tests.step);

    // 创建 benchmark
    const bench_mod = b.createModule(.{
        .root_source_file = b.path("src/benchmark.zig"),
        .target = target,
        .optimize = .ReleaseFast, // benchmark 总是用 ReleaseFast
    });
    bench_mod.addImport("aec3", aec3_mod);

    const bench_exe = b.addExecutable(.{
        .name = "benchmark",
        .root_module = bench_mod,
    });

    const run_bench = b.addRunArtifact(bench_exe);
    const bench_step = b.step("bench", "Run benchmarks");
    bench_step.dependOn(&run_bench.step);
}
