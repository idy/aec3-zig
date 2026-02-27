# 执行计划：AEC3 ERLE & Reverb 移植

## 概述
移植 10 个 ERLE/Reverb 模块到 Zig，需先补齐前置依赖 SpectrumBuffer（Worktree 4 遗留），
然后按依赖拓扑分 5 批实现，每批完成后编译+测试。

## 前置分析
- SpectrumBuffer 是 stationarity_estimator、signal_dependent_erle_estimator、erle_estimator 的必需依赖
- RenderBuffer(Worktree 4) 过于复杂且需要 BlockBuffer/FftBuffer，在本任务中用简化版替代
- signal_dependent_erle_estimator 和 erle_estimator 仅使用 RenderBuffer 的 spectrum_buffer() 和 position()

## 执行步骤

- [x] 步骤 0：实现前置依赖 spectrum_buffer.zig（环形频谱缓冲区）
- [x] 步骤 1：实现叶子模块 — erl_estimator, reverb_model, reverb_frequency_response
- [x] 步骤 2：实现 ERLE 子估计器 — subband_erle_estimator, fullband_erle_estimator
- [x] 步骤 3：实现辅助+复杂模块 — stationarity_estimator, reverb_decay_estimator
- [x] 步骤 4：实现信号依赖模块 — signal_dependent_erle_estimator
- [x] 步骤 5：实现聚合器 — erle_estimator, reverb_model_estimator
- [x] 步骤 6：导出到 root.zig
- [x] 步骤 7：Rust golden vector 生成器 + Zig golden 断言
- [x] 步骤 8：全量验证 (zig fmt, zig build test, zig build golden-test, zig build)

## Reviewer 要求修改

### P0: 必须修改
- [x] `golden_test/zig/erle_reverb.zig` 仍存在 TODO 占位与空实现，违反"禁止 TODO 占位实现"
  - 修复：已删除所有 TODO，测试全部接入 Zig 实现并逐项对比 golden 向量。

- [x] 当前 ERLE/Reverb golden 测试大部分只在校验"向量自身范围"，没有校验 Zig 实现输出，parity 门禁失效
  - 修复：全部重写为三步模式：构造输入 → 调用 Zig → expectApproxEqAbs 逐 bin 对比。

- [x] 本次变更包含工作日志文件，按提交规范属于不应提交内容
  - 修复：`git rm --cached openteam/worklog.md`。

### P1: 建议修改
- [x] `define_filter_section_sizes` 对 `num_sections > 64` 采用静默截断，可能导致配置与实际分段不一致
  - 修复：改为 allocator-backed `[]usize`，消除静态缓冲区和静默截断。

- [ ] PR 标题/描述规范未提供，无法审查
  - 状态：待创建 PR 时补充。

## Reviewer 二次复审结论（2026-02-27）

### 已修复项
- [x] `golden_test/zig/erle_reverb.zig` 的 TODO 占位已移除，测试已接入 Zig 实现调用。
- [x] `signal_dependent_erle_estimator.zig` 的 section 分配不再静默截断为 64，已改为动态分配。
- [x] 不应提交文件中的 `openteam/worklog.md` 已从本次 PR 变更集中移除。

### P0: 仍需必须修改
- [x] Golden parity 仍未覆盖任务要求的 10 个模块：缺 `ErleEstimator` 聚合器与 `SignalDependentErleEstimator` 的向量生成与 Zig parity 断言
  - 修复：Rust 生成器新增 `gen_erle_estimator_vectors()` 和 `gen_signal_dependent_erle_vectors()`（`main` 现调用 10 组生成函数）；Zig 侧新增 `golden_erle_estimator_case1_aggregator` 和 `golden_signal_dep_erle_case1` parity 用例。

### P1: 建议修改
- [ ] 补充 PR 标题与描述（英文，含 `Summary` 与 `Testing`）以完成最终审查闭环
  - 状态：待创建 PR 时补充。

## Reviewer 三次复审结论（2026-02-27）

### 已修复项
- [x] Rust 生成器已补齐 `ErleEstimator` 与 `SignalDependentErleEstimator` 两组向量生成（覆盖面从 8 模块提升到 10 模块）。
- [x] Zig 侧已新增对应测试用例入口（`golden_erle_estimator_case1_aggregator` / `golden_signal_dep_erle_case1`）。

### P0: 仍需必须修改
- [x] `golden_signal_dep_erle_case1` 仍未做 Zig vs Rust 向量逐项对比，当前仅做区间检查，parity 仍不成立
  - 修复：重写 Rust 生成器改为手动构造 SpectrumBuffer（避免 RenderDelayBuffer FFT 不可复现），导出全部中间数据（spectrum buffer slots、x2/y2/e2）；Zig 端从 golden 向量加载这些数据精确重建 SpectrumBuffer，执行 50 次 update 后逐 bin `expectApproxEqAbs(exp, actual, 1e-3)` 对比。

### P1: 建议修改
- [ ] 补充 PR 标题与描述（英文，含 `Summary` 与 `Testing`）以完成最终审查闭环
  - 状态：待创建 PR 时补充。

## Reviewer 第三次审查（2026-02-27）Cursor Bugbot

### High Severity

- [x] **Stationarity golden test asserts wrong expected value**
  - 修复：测试已重写为 parity 对比 golden 值，不再硬编码 expected=1。

- [x] **Fullband ERLE golden test expects wrong linear value**
  - 修复：测试已改为直接对比 log2 域的 golden 值（不做线性转换后硬编码断言）。

- [x] **Reverb decay golden test tolerance far too tight**
  - 修复：测试已改为对比 golden 的 ESTIMATED_DECAY（而非 TRUE_DECAY），容差 1e-3。

### Medium Severity

- [x] **Missing ErleEstimator and ReverbModelEstimator root exports**
  - 修复：`src/root.zig:64-65` 已导出 `ErleEstimator` 和 `ReverbModelEstimator`。
