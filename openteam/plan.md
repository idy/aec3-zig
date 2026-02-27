# 执行计划：移植 AEC3 Metrics 与叶子节点

## 概述
按 task.md 与 test.md 要求，先补齐 12 个 leaf 模块及 inline tests，再导出到 `src/root.zig`，最后完成格式化与全量测试验证。

## 执行步骤
- [x] 步骤 1：实现 `src/audio_processing/aec3/test_utils.zig`，提供统一测试数据生成函数。
- [x] 步骤 2：实现 4 个 Metrics 模块（api_call_jitter/block_processor/render_delay_controller/echo_remover）及对应 inline tests。
- [x] 步骤 3：实现 subtractor_output 与 subtractor_output_analyzer，并覆盖空输入、非法参数、趋势测试。
- [x] 步骤 4：实现 nearend/dominant/subband 三个检测器，并覆盖阈值、滞回、融合与非法 band 数测试。
- [x] 步骤 5：实现 echo_audibility、comfort_noise_generator、main_filter_update_gain，并覆盖随机可重复性与平滑性测试。
- [x] 步骤 6：更新 `src/root.zig` 导出，运行 `zig fmt --check --ast-check src golden_test build.zig`、`zig build test`、`zig build golden-test`、`zig build` 完成验收。
