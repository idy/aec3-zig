#!/bin/bash
# NS module test runner for Bazel integration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "=== Running NS Module Tests via Zig ==="
echo "Project root: $PROJECT_ROOT"

# 运行 zig build test，它会执行所有测试（包括 NS 模块）
exec zig build test
