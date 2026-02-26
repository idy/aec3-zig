# Rust FFT Golden Vectors

This fixture file is generated from the Rust reference implementation and consumed by Zig tests.

- Rust repo: `/tmp/aec3-rs`
- Rust commit: `667e9a8ede5905c0dce56e4a8b85880a020dd77a`
- Generator: `/tmp/aec3-rs/examples/gen_fft_golden.rs`

## Regeneration command

```bash
cargo run --quiet --example gen_fft_golden > /tmp/rust_fft_golden_vectors_lines.txt
cp /tmp/rust_fft_golden_vectors_lines.txt src/test_support/rust_fft_golden_vectors.txt
```

The Zig tests parse `rust_fft_golden_vectors.txt` and compare per-bin/per-sample values with explicit error thresholds.
