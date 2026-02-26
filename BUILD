# Root BUILD file for sunny-circuit project
# 这是一个 Zig 项目，使用 Bazel 作为包装器调用 zig build/test

# 构建库
genrule(
    name = "aec3_lib",
    srcs = glob(["src/**/*.zig"]),
    outs = ["libaec3.a"],
    cmd = """
        cd $(location build.zig)/..
        zig build -Doptimize=ReleaseFast
        cp zig-out/lib/libaec3.a $@
    """,
    visibility = ["//visibility:public"],
)

# 运行所有测试
genrule(
    name = "run_zig_tests",
    srcs = glob(["src/**/*.zig"]),
    outs = ["test_result.txt"],
    cmd = """
        cd $(location build.zig)/..
        zig build test 2>&1 | tee $@
        if [ $$? -ne 0 ]; then
            echo "Tests failed" >&2
            exit 1
        fi
    """,
)

# 测试目标 - 包装 zig build test
test_suite(
    name = "all_tests",
    tests = [
        ":zig_unit_tests",
    ],
)

# 使用 sh_test 包装 zig build test
sh_test(
    name = "zig_unit_tests",
    srcs = ["//tools:zig_test_runner.sh"],
    data = glob(["src/**/*.zig"]) + [
        "build.zig",
        ".gitignore",
    ],
    tags = ["zig"],
)
