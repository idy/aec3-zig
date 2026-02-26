#!/bin/bash
# Zig test runner for Bazel integration
# 这个脚本包装 zig build test，使其可以作为 Bazel 测试运行

set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# 运行 zig build test
if [ $# -eq 0 ]; then
	# 运行所有测试
	exec zig build test
else
	# 运行特定测试（通过过滤）
	TEST_FILTER="$1"
	echo "Running tests matching: $TEST_FILTER"
	# Zig 测试不支持直接过滤，我们运行所有测试
	exec zig build test
fi
