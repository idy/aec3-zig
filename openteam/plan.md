# 执行计划：AEC3 ERLE & Reverb 移植

## 概述
移植 10 个 ERLE/Reverb 模块到 Zig，需先补齐前置依赖 SpectrumBuffer（Worktree 4 遗留），
然后按依赖拓扑分 5 批实现，每批完成后编译+测试。

## 前置分析
- SpectrumBuffer 是 stationarity_estimator、signal_dependent_erle_estimator、erle_estimator 的必需依赖
- RenderBuffer(Worktree 4) 过于复杂且需要 BlockBuffer/FftBuffer，在本任务中用简化版替代
- signal_dependent_erle_estimator 和 erle_estimator 仅使用 RenderBuffer 的 spectrum_buffer() 和 position()

## 执行步骤

- [ ] 步骤 0：实现前置依赖 spectrum_buffer.zig（环形频谱缓冲区）
- [ ] 步骤 1：实现叶子模块 — erl_estimator, reverb_model, reverb_frequency_response
- [ ] 步骤 2：实现 ERLE 子估计器 — subband_erle_estimator, fullband_erle_estimator
- [ ] 步骤 3：实现辅助+复杂模块 — stationarity_estimator, reverb_decay_estimator
- [ ] 步骤 4：实现信号依赖模块 — signal_dependent_erle_estimator
- [ ] 步骤 5：实现聚合器 — erle_estimator, reverb_model_estimator
- [ ] 步骤 6：导出到 root.zig
- [ ] 步骤 7：Rust golden vector 生成器 + Zig golden 断言
- [ ] 步骤 8：全量验证 (zig fmt, zig build test, zig build golden-test, zig build)

## Reviewer 要求修改

### P0: 必须修改
- [ ] `golden_test/zig/erle_reverb.zig` 仍存在 TODO 占位与空实现，违反“禁止 TODO 占位实现”
  - 位置：`golden_test/zig/erle_reverb.zig:31-37, 47`
  - 建议：删除 TODO 占位，补齐真实可执行断言；用 Zig 实现实际计算后与 golden 向量逐项对比。

- [ ] 当前 ERLE/Reverb golden 测试大部分只在校验“向量自身范围”，没有校验 Zig 实现输出，parity 门禁失效
  - 位置：`golden_test/zig/erle_reverb.zig`（全文件；`aec3` 仅在注释中出现，未实际调用实现）
  - 建议：每个 case 至少包含“构造输入 -> 调用 Zig 模块 -> 与 Rust golden 比较（容差断言）”三步，不能只做范围断言。

- [ ] 本次变更包含工作日志文件，按提交规范属于不应提交内容
  - 位置：`openteam/worklog.md`
  - 建议：从最终 PR 变更中移除工作日志类文件（如 `worklog.md` / `*.log`），避免污染交付。

### P1: 建议修改
- [ ] `define_filter_section_sizes` 对 `num_sections > 64` 采用静默截断，可能导致配置与实际分段不一致
  - 位置：`src/audio_processing/aec3/signal_dependent_erle_estimator.zig:39-46`
  - 建议：改为显式参数校验并返回 error（或 assert 并在配置层限制），不要静默降级。

- [ ] PR 标题/描述规范未提供，无法审查
  - 位置：PR 元数据（非仓库文件）
  - 建议：补充英文标题（动词开头）与英文描述，且描述包含 `Summary` 与 `Testing` 两节。
