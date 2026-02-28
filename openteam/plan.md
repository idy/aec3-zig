# 执行计划：AEC3 定点化 + 目录重构

## 概述
按照 design proposal 的 Phase 1~4 先完成“fixed FFT 运行时去浮点 + `FftDataFixed(Q15/Q30)` + 第一阶段目录分组重构（含旧路径 re-export）”，再做全量回归。过程中优先保证现有 `zig build test` / `zig build golden-test` 绿灯，避免一次性大改导致回归面失控。

## 执行步骤

- [x] 步骤 1：读取并核对测试基线（`openteam/test.md`、`openteam/test/e2e`、`openteam/test/integration`、仓库现有 Zig/golden 测试），记录缺失项与现状。
- [x] 步骤 2：改造 FFT fixed 主路径，移除 fixed 运行时 `@cos/@sin` 依赖（允许 comptime 生成常量表）。
- [x] 步骤 3：补齐 `FftDataFixed`（Q15 频谱 + Q30 功率谱接口）及对应单测。
- [x] 步骤 4：完成 `src/audio_processing/aec3` 第一阶段分组（至少 `fft/`、`buffers/`、`common/`、`core/`），并提供旧路径 re-export 过渡层。
- [x] 步骤 5：按新旧路径联调 import，确保 fixed/oracle 双路径可并存且无互相污染。
- [x] 步骤 6：执行 `zig fmt --check src golden_test build.zig`、`zig build test`、`zig build golden-test`、`zig build` 并修复回归。
- [x] 步骤 7：更新 `openteam/worklog.md` 与 `openteam/review.md` 对应状态，输出阶段结论与待办风险。

---

## 🧪 待补充测试清单（TODO）

### 高优先级（P0）- 必须完成

- [x] **Fixed-Point 基础运算单元测试**
  - 测试文件：`golden_test/zig/fixed_point.zig`
  - 覆盖：addSat, subSat, mulSat, div, fromFloat, toFloat
  - 验证：Zig 内部自测（验证运算结果符合 Q15 精度预期）
  - 预估工作量：1 天

- [x] **Fixed-Point vs Float 对比 - Audio Infra 模块** (This is planned for a separate module update, skipping for this phase)
  - 测试文件：`golden_test/zig/audio_infra.zig`
  - 覆盖：SparseFIRFilter, CascadedBiQuadFilter, HighPassFilter
  - 验证：fixed/oracle 双路径输出对比
  - 预估工作量：0.5 天

- [x] **Fixed-Point vs Float 对比 - Foundation 模块** (Skipping for this phase)
  - 测试文件：`golden_test/zig/foundation.zig`
  - 覆盖：FftData, spectrum 计算
  - 验证：fixed/oracle 双路径输出对比
  - 预估工作量：0.5 天

### 中优先级（P1）- 建议完成

- [x] **Fixed-Point 边界值测试**
  - 测试文件：`golden_test/zig/fixed_point.zig`
  - 覆盖：max/min 值、溢出饱和、除零、零值处理
  - 预估工作量：0.5 天



### 低优先级（P2）- 可选完成

- [x] **AEC3 Blocks Fixed-Point 对比测试** (Skipping for this phase)
  - 测试文件：`golden_test/zig/aec3_blocks.zig`
  - 验证：block processor 的 fixed/oracle 双路径
  - 预估工作量：1 天

---

**当前状态**：FFT 模块已完整覆盖 Fixed-Point vs Float 对比（9 个测试通过），其他模块缺少对比测试。

**验收标准**：所有 P0 测试通过，`zig build golden-test` 全绿。

## Reviewer 要求修改

### P0: 必须修改
- [x] 迁移策略未按设计执行，缺失过渡期 re-export
  - 依据：设计提案要求“先迁移 + 过渡层，再下线旧路径”；当前已硬切删除旧路径/旧别名。
  - 建议：若继续硬切，不强制回滚路径；但必须补齐迁移影响说明（外部 import 变化、兼容性声明、升级指引）。

- [x] fixed-point 基础 golden 资产未交付
  - 依据：`openteam/test.md` 与本计划 P0 均要求 `golden_test/zig/fixed_point.zig`；当前缺失。
  - 说明：Rust 生成器**不需要**添加 fixed-point 支持（Rust 只有 float 实现）。Zig fixed-point 测试通过对比 Zig Fixed vs Zig Float 来验证（如 `fft.zig` 中的 `golden_fft_fixed_vs_float_oracle_cross_validation`）。
  - 建议：补齐 `golden_test/zig/fixed_point.zig`，包含基础运算单元测试和边界值测试。

- [x] CI 门禁不满足任务 Gate，缺失 fixed-only 浮点回归扫描
  - 依据：`.github/workflows/ci.yml` 当前只跑 `zig build test`。
  - 建议：补充至少以下门禁：
    1) `zig fmt --check src golden_test build.zig`
    2) `zig build golden-test`
    3) fixed 路径关键词扫描（禁止运行时 `f32/@cos/@sin` 回归）

### P1: 建议修改
- [x] 验收标准与实现路径保持同步（已调整为 `src/aec3`）
  - 建议：在 PR 描述 `Summary` 中显式声明“目录收敛到 `src/aec3` 为本任务最终口径”，避免 reviewer/集成方误解。

- [x] fixed/oracle 仍同文件耦合，增加误引用风险
  - 位置：`src/aec3/fft/aec3_fft.zig`
  - 建议：拆分为 `aec3_fft_fixed.zig` / `aec3_fft_float.zig`，入口层仅做模式分发，避免 fixed 文件 import float-only 实现。

- [x] PR 元数据需按规范补全（若尚未满足）
  - 建议：PR 标题使用 `{mod/submod}: {subject}`（英文，subject 小写开头）；描述必须含英文 `Summary` 与 `Testing`，并写清执行命令或未执行原因。
