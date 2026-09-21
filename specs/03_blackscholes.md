# 03 — Black-Scholes pricing + implied volatility (`blackscholes`)

Price N European calls with Black-Scholes, then recover each option's implied
volatility from its price with 8 Newton iterations. Options desks / market
makers do exactly this, continuously, across whole option chains.
Parallel: the options are independent, reduced with a fixed binary tree so the
float result is identical for any thread count.

All floating point is **f32**. Write every expression in exactly the order
shown (no algebraic rearrangement), so Rust and Bend round identically.

## Math

```
PDF_C = 0.3989422804           # 1/sqrt(2*pi)

npdf(x) = PDF_C * exp(-0.5 * x * x)            # (-0.5 * x) * x

ncdf(x):                        # Abramowitz & Stegun 26.2.17
  ax   = abs(x)
  t    = 1.0 / (1.0 + 0.2316419 * ax)
  poly = t * (0.319381530 + t * (-0.356563782 + t * (1.781477937
           + t * (-1.821255978 + t * 1.330274429))))
  c    = 1.0 - npdf(ax) * poly
  if x >= 0.0: return c  else: return 1.0 - c

call(S, K, T, r, sig):
  sqt  = sqrt(T)
  d1   = (log(S / K) + (r + 0.5 * sig * sig) * T) / (sig * sqt)
  d2   = d1 - sig * sqt
  return S * ncdf(d1) - K * exp(-r * T) * ncdf(d2)

vega(S, K, T, r, sig):
  sqt  = sqrt(T)
  d1   = (same expression as in call)
  return S * npdf(d1) * sqt
```

Evaluation order for products: left to right, e.g. `0.5 * sig * sig` is
`(0.5 * sig) * sig`, `S * npdf(d1) * sqt` is `(S * npdf(d1)) * sqt`,
`K * exp(-r * T) * ncdf(d2)` is `(K * exp(-r*T)) * ncdf(d2)`.
`-r * T` is `(-r) * T`. `abs`, `exp`, `log`, `sqrt` are the f32 library
functions (`f32::abs/exp/ln/sqrt`, Bend `F32.abs/exp/log/sqrt`).

## One option (index i: u32)

```
h        = rng_hash(i)
S        = 100.0
r        = 0.03
K        = 90.0 + f32(h & 63) * 0.3125              # 90 .. 109.69
T        = 0.25 + f32((h >> 6) & 63) * 0.015625     # 0.25 .. 1.23
sig_true = 0.15 + f32((h >> 12) & 63) * 0.005       # 0.15 .. 0.465
price    = call(S, K, T, r, sig_true)

sig = 0.3
repeat 8 times:
  c   = call(S, K, T, r, sig)
  v   = vega(S, K, T, r, sig)
  sig = sig - (c - price) / max(v, 0.0001)
  sig = min(max(sig, 0.01), 3.0)

option_value(i) = price + sig
```

## Reduction (fixed tree, independent of threads)

`N` must be a power of two >= 1024 (harness guarantees it).

```
tree(lo, n):                         # n power of two
  if n <= 1024:
    acc = 0.0
    for i in lo .. lo+n (ascending): acc = acc + option_value(i)
    return acc
  half = n / 2
  return tree(lo, half) + tree(lo + half, half)

checksum = tree(0, N)                # f32
```

- Rust: threads T (power of two, default 1). Spawn with `std::thread::scope`
  for the top log2(T) levels of `tree`, sequential below. Same float result.
- Bend: fork both halves with a parallel let at every level above the leaf:
  `a b = tree(lo, half) tree(lo + half, half)`. The runtime decides threads.

## Output

Print `checksum: <f32>` then `kernel_ms: <ms>`. Default N = 65536.
Tolerance: relative 1e-4 between languages.

## Bend hints

- Negative float literals may not parse; use `F32.neg(0.356563782)` or
  subtract. `max`/`min`: `F32.max`/`F32.min` exist.
- `if x >= 0.0` → match on `F32.is_ge(x, 0.0)` via a helper def (no `if`; can
  only `match` a parameter).
- `n` and `lo` can be U32; recursion depth for `tree` needs `Nat` fuel =
  log2(n) levels (e.g. pass `k: Nat` with `n = 2^k`, leaf when `k == 10n`), or
  structure the fuel however is convenient.
