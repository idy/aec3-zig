# Review Log - port-foundation

## 2026-02-25 17:38:05 +0800

### 结论
**Reject**

这版代码能编译、能跑测试，但离“可验收”还差关键硬指标，不是擦边球问题，是实打实的验收失败。

### 执行记录
- ✅ `zig build`：通过
- ✅ `zig build test`：通过（含 smoke 输出）
- ✅ `zig build -Dtarget=thumb-freestanding-none`：通过
- ✅ `zig build bench`：可运行，输出如下
  - `bench_fast_approx_log2f: ns/op=0.62`
  - `bench_fft_data_spectrum: ns/op=0.26`
  - `bench_audio_util_conversions: ns/op=139.31`

### 阻断项清单（必须修）
1. **Rust 对齐错误：`ChannelLayout.surround` 映射错了**
   - 位置：`src/audio_processing/channel_layout.zig`
   - 当前：`.surround => 3`
   - Rust 参考：`channel_layout.rs` 中 `Surround => 4`
   - 影响：核心语义不一致，属于功能错误，不是风格问题。

2. **Rust 对齐错误：`detect_optimization()` 语义退化**
   - 位置：`src/audio_processing/aec3/aec3_common.zig`
   - 当前实现按架构直接返回 SSE2/NEON（x86/aarch64 即真）
   - Rust 参考使用运行时特性检测（`is_x86_feature_detected!` / `is_*_feature_detected!`）
   - 影响：行为与参考实现不一致，可能在特性不可用平台误判优化路径。

3. **fixed-point-first 验收未闭环（关键项）**
   - 虽有 `NumericMode` 封闭枚举（`float32`/`fixed_mcu_q15`），但没有看到“默认 fixed_mcu_q15”在公开入口被明确固定为默认实例化路径。
   - 双轨验证只做了 Rust->Zig(float) 的部分 golden；**缺少系统化 Zig fixed_mcu_q15 -> Zig float 对照**（仅 smoke FIR 不能覆盖 foundation 公共 API）。
   - 这条是 review-checklist 的核心要求，不能跳过。

4. **测试覆盖门禁未达成：并非每个公开函数都有测试+边界测试**
   - 任务要求：每个公开函数至少 1 个测试 + 至少 1 个边界测试。
   - 当前仅覆盖了部分路径，存在大量“调用即算覆盖”的弱测试。
   - 典型缺口示例：
     - `aec3_common.get_down_sampled_buffer_size/get_render_delay_buffer_size`：缺少 `down_sampling_factor=0` 等非法输入边界行为测试（assert/panic 语义未验证）
     - `channel_buffer.ChannelBuffer.new`：缺少 `frames=0/channels=0/frames%bands!=0` 的边界验证测试
     - `audio_frame.update_frame`：缺少超过 `MAX_DATA_SIZE_SAMPLES` 的边界语义测试
     - `config.zig` 多个 `default()` 仅 `_ = ...` 触发调用，未验证值与 Rust 一致，不能算有效覆盖

5. **PR 元信息不合规（当前无法验收）**
   - `gh pr status` 显示当前分支无关联 PR。
   - 因此无法检查“英文标题 + 英文描述 + Summary/Testing”规范，验收条件未满足。

6. **不应提交项风险：二进制 golden 文件直接入库**
   - 发现：`tests/golden/*.bin`
   - 按规则，二进制文件若必须提交应走 git-lfs 或给出明确豁免说明。
   - 请确认仓库策略（若保留需在 PR 中说明必要性与体积控制）。

### 需要开发者继续完成的事项
1. 修正 `ChannelLayout.surround` 通道数映射，并补充回归测试。
2. 将 `detect_optimization()` 改为与 Rust 语义一致的运行时能力检测（不是按架构拍脑袋）。
3. 明确 fixed-point-first 默认入口（默认 fixed_mcu_q15）并在代码层可验证。
4. 补齐双轨对照：至少覆盖本 worktree 公共 API 的 fixed->float 对照策略与阈值说明。
5. 按“公开函数 100% + 每函数边界测试”补全测试，不接受 `_ = func()` 这种伪覆盖。
6. 创建 PR，并按规范改写为英文标题/描述，至少包含 `Summary` 与 `Testing`（写明执行命令与结果）。
7. 对 `tests/golden/*.bin` 给出策略（LFS 或豁免说明）。

## 2026-02-25 17:41:01 +0800

### 结论
**Needs Fixes**

### 执行记录
- ✅ `zig build`：通过
- ✅ `zig build test`：通过（含 smoke 输出，`Max error: 1.1582 LSBs`）
- ✅ `zig build -Dtarget=thumb-freestanding-none`：通过
- ✅ `zig build bench`：可运行
  - `bench_fast_approx_log2f: 0.63 ns/op`
  - `bench_fft_data_spectrum: 0.26 ns/op`
  - `bench_audio_util_conversions: 136.50 ns/op`

### 阻断项清单（必须修）
1. **Rust 对齐错误：`ChannelLayout.surround` 通道数不一致**
   - Zig: `src/audio_processing/channel_layout.zig` 将 `.surround` 归到 3 通道。
   - Rust 参考: `.openteam/docs/aec3-rs-src/audio_processing/channel_layout.rs` 中 `Surround` 归到 4 通道。
   - 这是语义错误，会直接影响布局推断/后续处理。

2. **Rust 对齐错误：`detect_optimization()` 检测语义退化**
   - Zig 仅按架构判断（x86/x86_64 一律 SSE2，arm/aarch64 一律 NEON）。
   - Rust 使用运行时特性检测（`is_x86_feature_detected!` / `is_*_feature_detected!`）。
   - 当前行为与参考实现不一致。

3. **“每个公开函数至少 1 个边界测试”未达标**
   - 典型缺口：
     - `ChannelBuffer.new` 缺少 `frames=0/channels=0/frames%bands!=0` 的断言语义测试。
     - `AudioFrame.update_frame` 缺少超 `MAX_DATA_SIZE_SAMPLES` 的边界断言测试。
     - `aec3_common.get_down_sampled_buffer_size/get_render_delay_buffer_size` 缺少非法参数（如 `down_sampling_factor=0`）边界语义测试。
     - `config.zig` 大量 `pub default()` 仅被“调用到”，未验证关键输出字段或边界约束。

4. **Rust 对比策略落地不完整**
   - 已有 Rust->Zig(float) 的 3 个 golden 用例，但覆盖面仅限少数函数。
   - Zig(fixed)->Zig(float) 目前主要依赖 `smoke_fir`，尚未形成对本 worktree 公共 API 的系统化对照矩阵与阈值记录。

5. **性能验收结论写反/不成立**
   - 任务标准写明“Zig 性能 ≥ Rust”。
   - 实测（本地）`audio_util_conversions` 为 Zig `136.50 ns/op`，Rust `66.72 ns/op`，Zig 慢于 Rust。
   - 不能再写“3 项 benchmark 均满足”，需要修正文档结论与口径。

### 需要开发者继续完成的事项
1. 修正 `ChannelLayout.surround` 映射并补回归测试。
2. 将 `detect_optimization()` 改为与 Rust 一致的运行时能力检测语义。
3. 按“公开函数 100% + 每函数至少 1 个边界测试”补齐测试，不接受仅调用不校验。
4. 扩展双轨对比：至少覆盖本 worktree 公共 API 的 fixed->float 对照，并记录误差阈值。
5. 重新跑 benchmark，修正结论；若 Zig 慢于 Rust，必须给出原因与后续优化计划。
