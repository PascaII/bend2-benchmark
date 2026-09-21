# 02 — Multi-symbol fixed-size ring buffer (`ringbuf`)

A 2-D circular buffer `SYMS x WIN` of fixed-point tick values (e.g. price
deltas in ticks, or trade sizes), one ring per symbol, maintaining O(1) rolling
sum and sum of squares per symbol and emitting a "breakout" signal when a new
value is well above that symbol's rolling mean. This is how rolling features
are really kept in a trading system: preallocated, no allocation on the hot
path, integer/fixed-point math. Sequential (no threads).

## State

```
SYMS = 64
WIN  = 256                         # power of two
buf[SYMS * WIN] : u32 = 0          # symbol k's ring is buf[k*WIN .. k*WIN+WIN)
head[SYMS]      : u32 = 0          # next write slot per symbol, 0..WIN-1
sum[SYMS]       : u32 = 0          # wrapping
sumsq[SYMS]     : u32 = 0          # wrapping
signals : u32 = 0                  # wrapping
acc     : u32 = 0                  # wrapping
s       : u32 = 7                  # LCG state
```

Bend note: a single `Array<U32>` of 16384 + 3*64 = 16576 slots does not fit a
power of two; use one array of 32768 slots with the layout
`buf` at `[0, 16384)`, `head` at `16384 + k`, `sum` at `16448 + k`, `sumsq` at
`16512 + k` — or separate arrays. Either is fine; Rust may use separate arrays.

## Tick stream (N ticks)

```
repeat N times:
  s   = rng_next(s)
  r   = s >> 8
  k   = r & 63                     # symbol
  v   = (r >> 6) & 4095            # new value, 0..4095
  h   = head[k]
  idx = k * 256 + h                # (k << 8) + h
  old = buf[idx]
  buf[idx] = v
  head[k]  = (h + 1) & 255
  sum[k]   = sum[k]   + v   - old          (wrapping)
  sumsq[k] = sumsq[k] + v*v - old*old      (wrapping; compute v*v and old*old wrapping)
  # breakout: v more than 25% above rolling mean (mean = sum/256)
  #   v*256 > sum + sum/4   <=>   (v << 8) > sum[k] + (sum[k] >> 2)
  if (v << 8) > sum[k] + (sum[k] >> 2):    (the right side is a wrapping add)
    signals = signals + 1
  acc = acc ^ (sum[k] + sumsq[k])          (wrapping add, then xor)
```

Use the updated `sum[k]`/`sumsq[k]` values (after this tick) for the signal
and `acc`.

## Output

```
checksum = signals * 2654435761 + acc      (wrapping u32)
```

Print `checksum: <u32>` then `kernel_ms: <ms>`. Default N = 1_000_000.
