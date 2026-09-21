# Common contract for every benchmark

Every benchmark exists twice: `rust/src/bin/<name>.rs` and `bend/<name>.bend`.
Both MUST compute bit-identical integer results (or float results within the
tolerance stated in the spec) for the same arguments.

## Numeric model

Bend2 only has `U32` (wrapping 32-bit unsigned), `F32` (IEEE single) and `Nat`
(unbounded, slow — only for loop fuel). There is no 64-bit type and no signed
integer. Therefore:

- Rust uses `u32` with `wrapping_*` ops wherever the spec says "wrapping".
- Rust uses `f32` for all floating point (never f64), with the exact operation
  order written in the spec, so rounding matches.
- Division/modulo by powers of two are written as shifts/masks in the spec.

## Shared helpers (already implemented, do not change)

| Name | Rust (`quantbench::`) | Bend (`import ./common.bend as C`) |
|---|---|---|
| LCG step | `rng_next(s)` | `C.Rng.next(s)` |
| index hash | `rng_hash(i)` | `C.Rng.hash(i)` |
| uniform (0,1] from u32 | `rng_unit(s)` | `C.Rng.unit(s)` |
| first CLI arg as u32 | `arg(0, dflt)` | `C.Arg.first(args, dflt)` |

## CLI and output protocol

```
<binary> <N> [threads]
```

- `N` = problem size (meaning defined per spec).
- Rust: optional second positional arg = worker threads (default 1). Only the
  parallel benchmarks use it; sequential ones ignore it.
- Bend: thread count is the runtime flag `--threads T` (appended by the
  harness); the Bend program only reads `N`.

Each program prints exactly two lines to stdout:

```
checksum: <value>
kernel_ms: <integer milliseconds>
```

`kernel_ms` measures only the kernel (after arg parsing, including input
generation which is part of the kernel by design). In Bend: `t0 <- IO.now()`,
compute, `IO.print` the checksum (this forces evaluation), then
`t1 <- IO.now()`, print `kernel_ms`. Rust mirrors this with `Instant`, and
MUST pass the result through `std::hint::black_box` before printing so the work
cannot be elided.

Integer checksums print as plain decimal u32. Float checksums: Rust prints
`{}` of the f32; Bend prints `F32.show(x)`. The harness compares floats with a
relative tolerance.

## Style

- No external crates. Rust threads via `std::thread::scope`.
- Implement straightforwardly. Do not micro-optimise beyond what the spec
  says; no SIMD intrinsics, no unsafe.
- Bend: prefer `Nat`-fuel tail recursion (termination-checked) over
  `@unsafe`. Read `docs/BEND_NOTES.md` first.
