# golden_test

This directory contains golden parity testing assets shared between Zig and Rust (`aec3-rs`).

## Directory layout

- `rust_support/`: Rust vector generators (`cargo` binaries)
- `vectors/`: generated golden vector text files
- `zig/`: Zig golden test suites
- `root.zig`: golden test entrypoint (used by `zig build golden-test`)

## Generate vectors

Run the following commands from the repository root.

### 1) Foundation vectors

```bash
cargo run --manifest-path golden_test/rust_support/Cargo.toml --release --bin golden-generator > golden_test/vectors/rust_foundation_golden_vectors.txt
```

### 2) FFT vectors

```bash
cargo run --manifest-path golden_test/rust_support/Cargo.toml --release --bin gen-fft-golden > golden_test/vectors/rust_fft_golden_vectors.txt
```

### 3) Audio infra vectors

```bash
cargo run --manifest-path golden_test/rust_support/Cargo.toml --release --bin gen-audio-infra-golden > golden_test/vectors/rust_audio_infra_golden_vectors.txt
```

### 4) NS vectors

```bash
cargo run --manifest-path golden_test/rust_support/Cargo.toml --release --bin ns-golden-generator > golden_test/vectors/rust_ns_golden_vectors.txt 2>/dev/null
```

You can generate only a specific NS case via an environment variable:

```bash
NS_CASE=silence cargo run --manifest-path golden_test/rust_support/Cargo.toml --release --bin ns-golden-generator > golden_test/vectors/rust_ns_golden_vectors.txt 2>/dev/null
```

Allowed values: `silence` / `lowamp` / `fullscale` / `speechnoise` / `all`.

## Run golden tests

```bash
zig build golden-test
```

To also validate unit tests:

```bash
zig build test
```
