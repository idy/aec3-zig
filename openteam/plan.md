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
