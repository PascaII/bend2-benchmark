# 04 — Monte Carlo Asian option pricing (`montecarlo`)

Price an arithmetic-average Asian call by simulating N geometric Brownian
motion paths of 64 steps each. Path-dependent exotics have no closed form, so
desks price and risk them by Monte Carlo — embarrassingly parallel, and the
kind of workload Bend's fork/join runtime is built for.

All floating point is **f32**, expressions in exactly the order shown.

## Constants

```
S0     = 100.0
K      = 100.0
STEPS  = 64
DRIFT  = 0.00015625       # (r - 0.5*sigma^2) * dt, r=0.03, sigma=0.2, dt=1/64
VOLSDT = 0.025            # sigma * sqrt(dt)
TWO_PI = 6.2831855
DISC   = 0.9704455        # exp(-r*T), T = 1
INV_STEPS = 0.015625      # 1/64
```

## One path (index p: u32)

```
x    = rng_hash(p)
S    = S0
sumS = 0.0
repeat STEPS times:
  x  = rng_next(x); u1 = rng_unit(x)
  x  = rng_next(x); u2 = rng_unit(x)
  z  = sqrt(-2.0 * log(u1)) * cos(TWO_PI * u2)     # Box-Muller, cos branch
  S  = S * exp(DRIFT + VOLSDT * z)
  sumS = sumS + S
avg    = sumS * INV_STEPS
payoff(p) = max(avg - K, 0.0)
```

`-2.0 * log(u1)` is `(-2.0) * log(u1)`.

## Reduction (fixed tree, independent of threads)

`N` must be a power of two >= 1024.

```
tree(lo, n):
  if n <= 1024:
    acc = 0.0
    for p in lo .. lo+n (ascending): acc = acc + payoff(p)
    return acc
  half = n / 2
  return tree(lo, half) + tree(lo + half, half)

checksum = tree(0, N) / f32(N) * DISC       # (tree / f32(N)) * DISC
```

- Rust: threads T (power of two, default 1); `std::thread::scope` at the top
  log2(T) tree levels, sequential below.
- Bend: parallel let at every level above the leaf.

## Output

Print `checksum: <f32>` (the option price, ~5.7) then `kernel_ms: <ms>`.
Default N = 65536. Tolerance: relative 1e-4.

## Bend hints

- `F32.log`, `F32.cos`, `F32.sqrt`, `F32.exp`, `F32.max`, `U32.to_f32`.
- Negative literal: `F32.neg(2.0)` or `F32.sub(0.0, 2.0)`.
- The 64-step loop is `Nat` fuel `64n` tail recursion carrying `x, S, sumS`.
