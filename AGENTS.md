# AGENTS.md

Repository guide for autonomous coding agents working in this Zig codebase.

## 0) Scope and current architecture

- Language: Zig (0.15.x toolchain expected).
- Build system: **Zig build only** (`build.zig`); this repository does **not** use Bazel.
- Main module: `src/root.zig`.
- Build script: `build.zig`.
- Golden parity suite: `golden_test/`.
- Rust vector generators: `golden_test/rust_support/`.
- Golden vectors: `golden_test/vectors/*.txt`.

## 1) Required workflow (high priority)

1. Keep tests **inline** in implementation modules (`test "..." { ... }`).
2. Reusable test helpers go into a colocated `test_utils.zig`.
3. For any **new golden test**, you must add/update a vector generator in `golden_test/rust_support` and commit generated vectors into `golden_test/vectors/` in the same change.
4. Golden Zig suites under `golden_test/zig` must follow the same style:
   - inline tests,
   - shared helpers in `golden_test/zig/test_utils.zig`,
   - no duplicate helper implementations.

### Project coding habits (must follow)

- **Test style**: prefer inline tests in implementation files; avoid adding standalone test-only files unless absolutely necessary.
- **Shared test helpers**: use `test_utils.zig` for reusable helpers (both `src/**/test_utils.zig` and `golden_test/zig/test_utils.zig`).
- **Golden vector generation**: use `golden_test/rust_support` binaries as the single source for generating vectors written to `golden_test/vectors/`.

### Adding new golden tests (required)

When introducing a new golden parity case:

1. Add or update a Rust generator program in `golden_test/rust_support/src/`.
2. Wire it in `golden_test/rust_support/Cargo.toml` as a runnable `[[bin]]` if needed.
3. Generate vectors and write them to `golden_test/vectors/*.txt`.
4. Add/update Zig golden assertions under `golden_test/zig/*.zig` (inline tests + `test_utils.zig`).
5. Commit **both** code and generated vector files together; do not leave vectors uncommitted.

## 2) Build / test / format commands

### Core commands

- Build library/executables:
  - `zig build`
- Run unit tests (configured in `build.zig`):
  - `zig build test`
- Run golden tests:
  - `zig build golden-test`
- Run benchmark executable:
  - `zig build bench`

### Formatting / lint-like checks

- Format all Zig files in place:
  - `zig fmt src golden_test build.zig`
- Check formatting without modifying files:
  - `zig fmt --check src golden_test build.zig`
- Parse/AST validation while formatting check:
  - `zig fmt --check --ast-check src golden_test build.zig`

### Run a single test (important)

- Single inline unit test from one module:
  - `zig test src/audio_processing/audio_buffer.zig --test-filter "audio_buffer multi-channel read write"`
- Another example:
  - `zig test src/audio_processing/high_pass_filter.zig --test-filter "reset_channels failed growth keeps prior state"`
- Filtered run through build step (works for broader suites):
  - `zig build test -- --test-filter "audio_buffer"`
  - `zig build golden-test -- --test-filter "golden_num_bands_for_rate"`

## 3) Golden vector generation

Run from repository root:

- Foundation vectors:
  - `cargo run --manifest-path golden_test/rust_support/Cargo.toml --release --bin golden-generator > golden_test/vectors/rust_foundation_golden_vectors.txt`
- FFT vectors:
  - `cargo run --manifest-path golden_test/rust_support/Cargo.toml --release --bin gen-fft-golden > golden_test/vectors/rust_fft_golden_vectors.txt`
- Audio infra vectors:
  - `cargo run --manifest-path golden_test/rust_support/Cargo.toml --release --bin gen-audio-infra-golden > golden_test/vectors/rust_audio_infra_golden_vectors.txt`
- NS vectors:
  - `cargo run --manifest-path golden_test/rust_support/Cargo.toml --release --bin ns-golden-generator > golden_test/vectors/rust_ns_golden_vectors.txt 2>/dev/null`

Optional NS case selection:

- `NS_CASE=silence cargo run --manifest-path golden_test/rust_support/Cargo.toml --release --bin ns-golden-generator > golden_test/vectors/rust_ns_golden_vectors.txt 2>/dev/null`

Allowed `NS_CASE`: `silence`, `lowamp`, `fullscale`, `speechnoise`, `all`.

## 4) File and naming conventions

### Zig source layout

- Public exports are centralized in `src/root.zig`.
- Core DSP/domain modules live under `src/audio_processing/**`.
- API structs/configs live under `src/api/**`.
- Bench entry: `src/benchmark.zig`.

### Naming

- Types: `PascalCase` (e.g., `AudioBuffer`, `SplittingFilter`).
- Functions/variables/files: `snake_case` (e.g., `set_num_channels`, `test_utils.zig`).
- Constants: `UPPER_SNAKE_CASE` for true constants.
- Tests: descriptive lowercase phrases in `test "..."` names.

### Imports

- Keep `const std = @import("std");` first.
- Then external/root imports (`@import("aec3")` in golden suite).
- Then local module imports.
- Avoid unused imports; remove dead imports promptly.

## 5) Error handling and resource management

- Prefer explicit error unions (`!T`) and `try` propagation.
- Use `errdefer` for rollback on partial initialization.
- For optional resources, prefer function-scoped cleanup when needed:
  - `errdefer if (opt) |*v| v.deinit();`
- Do not leave objects in partially mutated state after failed operations.
- Avoid panic-based control flow for expected allocation failures.

## 6) Testing conventions in this repo

- Keep unit tests near implementation (inline test blocks).
- Keep helper duplication low:
  - module-level shared helper => `src/.../test_utils.zig`
  - golden shared helper => `golden_test/zig/test_utils.zig`
- Use deterministic numeric tolerances and document why tolerances are chosen.
- For allocator-failure/rollback behavior, add explicit failing-allocator tests.

## 7) Numerical and DSP-specific guidance

- Favor fixed-point-first behavior where module design requires it.
- Be explicit about sample rates, frame lengths, and band counts.
- Keep conversions bounded/saturated where applicable.
- Preserve invariants across `set_num_channels` / reset / resize operations.

## 8) What to avoid

- Do not introduce placeholder TODO implementations.
- Do not duplicate test helper logic across files.
- Do not add golden vectors outside `golden_test/vectors/`.
- Do not mix runtime file IO when `@embedFile` is the established path.

## 9) Pre-PR checklist for agents

1. `zig fmt --check src golden_test build.zig`
2. `zig build test`
3. `zig build golden-test`
4. `zig build`
5. If vectors changed, confirm generator command and source commit/reason.
