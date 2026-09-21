# Bend2 vs Rust on trading & quant kernels

[Bend 2](https://github.com/bendlang/bend) claims *"as fast as C on the CPU,
faster on 10000s of cores"* and *"blocks AI mistakes via proof"* (`LAWS.bend`).
This repo tests both claims on four kernels that show up in real trading
systems: the question is whether a proof-checked functional language can
compete with Rust on the code trading firms actually write. Each kernel is
implemented twice, in Rust and in Bend, against the same exact specification,
and a timing only counts if both languages print the same checksum.

## TL;DR

| Kernel | What it is | Bend vs Rust, 1 core | 8 cores |
|---|---|---|---|
| `orderbook` | L2 price-level book + matching engine, 50M orders | **6.5× slower** | (sequential) |
| `ringbuf` | 64-symbol × 256-tick ring buffer, O(1) rolling sum/sumsq + signal, 400M ticks | **1.08× slower** (≈ parity) | (sequential) |
| `blackscholes` | Black-Scholes price + 8-step Newton implied vol, 4M options | **2.4× faster** ⚠️ see below | 2.1× faster |
| `montecarlo` | Asian option, 64-step GBM paths, 1M paths | **2.3× slower** | 2.4× slower |
| `montecarlo` on the **GPU** (`tree!`) | same kernel, Apple M3 Metal | — | 1.3× faster than 8-core Rust at 1M paths, ≈4× at 4M |

- **Flat numeric loops** (ring buffer, float math): parity with Rust,
  impressive for a pure, affine, proof-checked functional language.
- **Branchy, stateful code** (the order book, the core of any trading
  system): 6.5× slower.
- **Parallelism** is trivial to express (`a b = f(x) g(y)`) and scales ~5× on
  8 cores like Rust's `std::thread`, but doesn't close a single-core gap.
- **GPU**: one character (`tree(…)` → `tree!(…)`) moves the Monte Carlo
  pricer onto the GPU. That is Bend's real differentiator.

## Methodology

- **One spec, two implementations.** `specs/` holds exact pseudocode,
  including floating-point operation order, so both languages round
  identically.
- **No I/O in the timed region.** Inputs come from a shared deterministic RNG
  inside the kernel.
- **Correctness gates timing.** Every run prints a checksum; integer kernels
  must match exactly, float kernels within 1e-4 (in practice bit for bit,
  across languages and thread counts).
- **Robust timing.** Median of 5 runs after a warm-up. `python3 bench/run.py`
  rebuilds, verifies and regenerates `results/`.
- **Idiomatic, not tuned.** No SIMD, no `unsafe`, no hand-optimisation in
  either language.

## Results

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="media/orderbook_dark.svg">
  <img src="media/orderbook_light.svg" alt="Order book, 50M orders: Rust 1 core 512 ms, Bend 1 core 3.32 s" width="740">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="media/ringbuf_dark.svg">
  <img src="media/ringbuf_light.svg" alt="Ring buffer, 400M ticks: Rust 1 core 554 ms, Bend 1 core 597 ms" width="740">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="media/blackscholes_dark.svg">
  <img src="media/blackscholes_light.svg" alt="Black-Scholes, 4.2M options: Rust 1 core 899 ms, Rust 8 cores 170 ms, Bend 1 core 377 ms, Bend 8 cores 81 ms" width="740">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="media/montecarlo_dark.svg">
  <img src="media/montecarlo_light.svg" alt="Monte Carlo, 1M paths: Rust 1 core 708 ms, Rust 8 cores 132 ms, Bend 1 core 1.61 s, Bend 8 cores 322 ms, Bend GPU 103 ms" width="740">
</picture>

Apple M3 (8 cores), macOS, bend 2.0.24 (emits C, compiled by clang 21 `-O3`),
rustc 1.91.1 (`-C target-cpu=native`, LTO fat, codegen-units=1).

| Benchmark | N | Rust 1T (ms) | Bend 1T (ms) | Bend/Rust 1T | Rust 8T (ms) | Bend 8T (ms) | Bend/Rust 8T | Checksums |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| orderbook | 1,000,000 | 10 | 66 | 6.60× | — | — | — | match |
| orderbook | 10,000,000 | 103 | 662 | 6.43× | — | — | — | match |
| orderbook | 50,000,000 | 512 | 3324 | 6.49× | — | — | — | match |
| ringbuf | 10,000,000 | 13 | 15 | 1.15× | — | — | — | match |
| ringbuf | 100,000,000 | 138 | 149 | 1.08× | — | — | — | match |
| ringbuf | 400,000,000 | 554 | 597 | 1.08× | — | — | — | match |
| blackscholes | 262,144 | 59 | 24 | 0.41× | 11 | 6 | 0.55× | match |
| blackscholes | 1,048,576 | 223 | 94 | 0.42× | 42 | 19 | 0.45× | match |
| blackscholes | 4,194,304 | 899 | 377 | 0.42× | 170 | 81 | 0.48× | match |
| montecarlo | 65,536 | 45 | 103 | 2.29× | 9 | 23 | 2.56× | match |
| montecarlo | 262,144 | 175 | 407 | 2.33× | 36 | 78 | 2.17× | match |
| montecarlo | 1,048,576 | 708 | 1611 | 2.28× | 132 | 322 | 2.44× | match |

(Bend/Rust < 1 means Bend is faster.)

**GPU** (`bin/montecarlo_gpu_bend`): 103 ms at 1M paths and 125–150 ms at 4M,
against 540–600 ms for 8-thread Rust at 4M. A fixed ~100 ms launch cost means
it only pays off from ~1M paths; results match the CPU to 3e-6 (Metal's own
`cos`/`exp`/`log`). Rust has no GPU variant: that would mean hand-writing
Metal or wgpu kernels, exactly the work Bend removes.

## The kernels

The exact pseudocode for each is in `specs/`.

1. **`orderbook`**: 1024-tick L2 book (aggregated quantity per level, no
   per-order queues) with best bid/ask tracking, limit orders that sweep
   levels, market orders and cancels. Integer-only, sequential: the
   matching-engine hot path.
2. **`ringbuf`**: preallocated 64-symbol × 256-tick circular buffer with O(1)
   rolling sum / sum of squares and a fixed-point "value > 1.25 × mean"
   signal. How rolling features are really kept: no allocation, integer math.
3. **`blackscholes`**: price a European call, then recover its implied vol
   with 8 Newton steps (f32), as options market makers do across chains. A
   fixed reduction tree keeps the sum identical for any thread count.
4. **`montecarlo`**: arithmetic Asian call over 64-step GBM paths
   (Box–Muller). Path-dependent exotics have no closed form, so desks use
   Monte Carlo. Embarrassingly parallel: Bend's best case.

## Analysis

**Order book (6.5× slower).** 417 lines of Bend against 149 of Rust: with no
`if`, every branch is a helper def matching a `Bool`, and with no mutual
recursion every loop is one self-recursive def over a state record. The
compiler handles this well (records flatten into registers, loops become
native tail loops, an array access is a mask plus a load). The remaining gap
most likely comes from the runtime's calling convention: multi-value returns
go through an out-array between dozens of small compiled loops. The kernel
inlines into one state machine, so a profiler can't pin it down further.

**Ring buffer (parity).** Bend's `Array` is *typed* as a binary tree, but the
native runtime stores `Array<U32>` as a flat buffer with O(1) get and set, so
a tight integer loop over arrays compiles to roughly what Rust does.

**Black-Scholes (Bend 2.4× faster): verified, not fully explained.**

- Checksums are bit-identical across Rust, Bend 1T and Bend 8T, and match an
  independent float64 Python reference to 2e-7.
- Bend's emitted C makes exactly the spec's 35 `exp` and 17 `log` calls per
  option, so no work is skipped.
- That C, compiled by hand with `clang -O3`, reproduces the speed (413 ms at
  4M); a hand-written C version runs at Rust speed (~900 ms) with `expf`,
  double `exp` or hand-hoisted invariants alike.

The exact codegen reason is not isolated. Read this as "Bend's C backend did
very well on this kernel", not "Bend beats Rust at float math".

**Monte Carlo (2.3× slower on 1 and 8 cores).** Same shape as Black-Scholes,
with a 64-step inner loop and 4 transcendental calls per step. Both languages
scale well (Bend 5.0×, Rust 5.4× on 8 cores), so the single-core gap carries
over.

### Why the Bend README shows Bend beating C

Bend's own pinned results (`bench/runtime/_pin_/apple_m4_max.txt`) compare
against **single-threaded** C ("Single-threaded, 1-to-1 with the Bend
program"). On one core Bend is slower than C on 15 of 16 benchmarks (median
~1.2×, up to 4.4× on hashmap). "Faster than C" means Bend on 16 cores or the
GPU against C on one core. This repo finds the same pattern, except that Rust
here also gets 8 threads.

## Verdict for trading systems

Bend could fit offline pricing and risk (Monte Carlo, greeks across books),
research backtests, and anything embarrassingly parallel you would otherwise
hand-port to CUDA or Metal. Not yet the latency path:

- **No 64-bit or signed integers.** Ticks × quantities overflow u32 quickly,
  and nanosecond timestamps don't fit. This alone rules out production order
  handling.
- **Latency.** The order book is 6.5× slower, and a runtime with its own
  event loop, scheduler and heap doesn't belong on a tick-to-trade path.
- **Ergonomics.** No `if`, no mutual recursion, destructuring only on
  parameters, affine variables. See `docs/BEND_NOTES.md`.

## LAWS.bend: does "proof blocks mistakes" hold?

`laws/` models the matching engine's sweep (an aggressive order against a list
of resting quantities) and proves four laws (`bend laws/PROOF.bend` →
`All terms check.`):

| Law | Meaning |
|---|---|
| `take_le_qty` | a fill never takes more than the order wants |
| `take_le_level` | a fill never takes more than the level holds (no negative liquidity) |
| `sweep_conserves_order` | filled + unfilled remainder == submitted quantity |
| `sweep_conserves_book` | filled + resting volume after == resting volume before (matching never creates or destroys liquidity) |

**It works as advertised on what it covers:** injecting a bug (counting the
level's quantity as filled instead of the amount taken) makes the check fail
with the mismatching terms, and checking is instant. But:

- The laws cover a **`Nat` model**, not the benchmarked `U32` code. `U32`
  proofs mean bit-level reasoning, and `F32` ops are opaque, so **nothing can
  be proven about the float kernels at all**.
- A law only blocks the mistakes it states.
- Proofs aren't free: 4 laws needed ~170 lines of proofs and `Nat` lemmas,
  since Base ships almost none.

## Build and run

```sh
curl -fsSL https://bend-lang.com/install.sh | sh      # installs ~/.bend/bin/bend
export PATH="$HOME/.bend/bin:$PATH"                  # the installer doesn't
./build.sh                                           # → bin/<name>_{rust,bend}
python3 bench/run.py                                 # verify checksums + time everything (~3 min)

bin/orderbook_rust 10000000                          # prints checksum + kernel_ms
bin/orderbook_bend 10000000 --threads 1
bin/montecarlo_rust 1048576 8                        # Rust: 2nd arg = threads
bin/montecarlo_bend 1048576 --threads 8              # Bend: runtime flag
bin/montecarlo_gpu_bend 1048576                      # GPU (Metal / CUDA)

~/.bend/bin/bend laws/PROOF.bend                     # check the laws
```

Layout: `specs/` exact specifications · `bend/`, `rust/src/bin/`
implementations · `bend/common.bend`, `rust/src/lib.rs` shared RNG and CLI
helpers · `laws/` laws and proofs · `results/` raw measurements ·
`docs/BEND_NOTES.md` Bend2 idioms and traps.

## Caveats

- One machine (Apple M3), no CUDA GPU; Bend's headline GPU numbers are for
  NVIDIA.
- The order book is aggregated L2. An L3 book with per-order queues would
  stress allocation and pointer chasing more, where Bend was weakest.
- 1 ms timer resolution: the smallest 8-thread rows (6–11 ms) are noisy.
- Bend forced u32/f32-only designs. Production Rust would use i64/f64, which
  changes nothing about Rust's speed but everything about Bend's
  applicability.

## License

MIT, see [LICENSE](LICENSE).
