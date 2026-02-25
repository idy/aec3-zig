# Golden vectors policy

These binary files are intentionally versioned to guarantee deterministic,
cross-language regression checks for the Foundation port.

## Why binary files are kept

- They are the canonical Rust-generated oracle inputs/outputs used by
  `src/test_golden.zig`.
- Keeping them in-repo makes CI deterministic and avoids hidden environment
  drift from regenerating vectors on every run.

## Regeneration

```bash
rustc tests/golden_generator.rs -O -o /tmp/golden_generator_pf
/tmp/golden_generator_pf
```

After regeneration, re-run:

```bash
zig build test
```
