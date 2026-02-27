# 执行计划：移植 AEC3 核心构建块 (Building Blocks)

## 概述
基于 Reviewer 的 P0/P1 反馈进入整改阶段：优先修复 golden 假测试、`block_framer`/`frame_blocker` 状态机、`block_delay_buffer` 多通道逻辑，再按“每个公开函数 1 正常 + 1 边界/错误”补齐测试门槛，最后完成全量构建测试与提交质量要求。

## 执行步骤
- [x] 步骤 1：替换 `golden_test/zig/aec3_blocks.zig` 中 TODO/占位断言，所有 case 改为调用真实 Zig 实现并校验结果。
- [x] 步骤 2：重构 `block_framer` 的 `buffered/from_block/remain` 推导与边界检查，补齐首帧 + 连续多帧跨边界 round-trip 测试。
- [x] 步骤 3：修复 `frame_blocker` 的 `buffered_len` 状态推进规则，新增“至少连续 5 次调用”稳定性测试。
- [x] 步骤 4：修复 `block_delay_buffer`，改为 channel×band 双循环处理，补齐 2 通道 + 多 band 延迟一致性测试。
- [x] 步骤 5：对 11 个模块逐个补齐公开函数测试覆盖（正常 + 边界/错误），并补 failing allocator 回滚测试。
- [x] 步骤 6：全量验收：`zig fmt --check --ast-check src golden_test build.zig`、`zig build test`、`zig build golden-test`、`zig build` 全通过。
- [ ] 步骤 7：提交前自检 PR 说明模板（英文 `Summary` + `Testing`）以满足 P1 要求。

## 当前已完成（基线）
- [x] 11 个 building blocks 已有 Zig 初版实现并接入 `src/root.zig` 导出。
- [x] `zig build test` 已通过。
- [x] `zig build golden-test` 已通过。
- [x] `zig build` 已通过。
- [x] `zig fmt --check --ast-check src golden_test build.zig` 已通过。

## Reviewer 要求修改

### P0: 必须修改
- [x] `golden_test/zig/aec3_blocks.zig` 不能再是 TODO 占位测试。
- [x] 修复 `block_framer` 的状态机与边界计算，保证初始状态即可稳定运行。
- [x] 修复 `frame_blocker` 连续调用断言失败问题。
- [x] 修复 `block_delay_buffer` 多通道处理错误。
- [x] 补齐公开函数测试覆盖到验收门槛。

### P1: 建议修改
- [ ] PR 标题与描述需为英文，并包含 `Summary` 与 `Testing`。

## Reviewer 回检（2026-02-27）

### 已确认修复
- [x] 移除 `golden_test/zig/aec3_blocks.zig` 中 TODO 占位。
- [x] 修复 `block_delay_buffer` 仅处理 channel 0 的问题。

### P0: 回检后仍必须修改
- [x] 修复 `frame_blocker` 连续调用断言失败（状态机不闭合）。
  - 结果：已重构 `buffered/need/remain` 推导，状态闭合；新增 10 次连续调用稳定性测试并通过。

- [x] 修复 `block_framer` 连续调用后落入 `buffered=0` 不可处理状态。
  - 结果：已增加 `buffered==0` 处理分支并修正循环推进；新增 10 次连续调用稳定测试并通过。

- [x] 提升 golden 断言强度，禁止宽松阈值掩盖错误。
  - 结果：已移除 `abs < 20.0`；基础 case 使用 `expectApproxEqAbs(1e-5)`，跨边界 case 使用误差统计阈值（max/mean/p95）断言。

- [x] 继续补齐公开函数“正常 + 边界”成对覆盖。
  - 结果：11 个模块已补齐公开 API 的正常/边界覆盖，并补充关键 OOM 回滚测试。
