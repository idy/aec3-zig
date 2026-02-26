# NS (Noise Suppression) module BUILD file

filegroup(
    name = "ns_sources",
    srcs = glob(["*.zig"]),
    visibility = ["//visibility:public"],
)

# NS 单元测试 - 包装 zig 测试
test_suite(
    name = "ns_tests",
    tests = [
        ":ns_unit_tests",
        ":fast_math_tests",
        ":noise_suppressor_integration_tests",
    ],
)

sh_test(
    name = "ns_unit_tests",
    srcs = ["//tools:zig_ns_test.sh"],
    data = [":ns_sources"],
    args = ["ns_unit_tests"],
    tags = ["ns", "zig"],
)

sh_test(
    name = "fast_math_tests",
    srcs = ["//tools:zig_ns_test.sh"],
    data = [":ns_sources"],
    args = ["fast_math"],
    tags = ["ns", "zig", "math"],
)

sh_test(
    name = "noise_suppressor_integration_tests",
    srcs = ["//tools:zig_ns_test.sh"],
    data = [":ns_sources"],
    args = ["noise_suppressor"],
    tags = ["ns", "zig", "integration"],
)
