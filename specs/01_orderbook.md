# 01 — Limit order book / matching engine (`orderbook`)

A price-level (L2) limit order book with a matching engine, driven by a
synthetic order stream. This is the classic trading-system hot path: an
array indexed by price tick, best-bid/best-ask tracking, marketable limit orders sweeping the
opposite side. Sequential (no threads).

## State

```
TICKS    = 1024                 # prices are ticks 0..1023
bid[1024], ask[1024] : u32 = 0  # resting quantity per price level
best_bid : u32 = 0              # 0    = "no bids"   (price 0 never used)
best_ask : u32 = 1023           # 1023 = "no asks"   (price 1023 never used)
traded_qty      : u32 = 0       # wrapping
traded_notional : u32 = 0       # wrapping: sum of take * price
s : u32 = 1                     # LCG state
```

Bend note: one `Array<U32>` of 2048 slots is fine: bids at `[p]`, asks at
`[1024 + p]`. Rust may use two `[u32; 1024]` arrays.

## Helpers

```
scan_down(p):   # next lower non-empty bid level below p, else 0
  for q = p-1 down to 1: if bid[q] > 0: return q
  return 0

scan_up(p):     # next higher non-empty ask level above p, else 1023
  for q = p+1 up to 1022: if ask[q] > 0: return q
  return 1023

buy(limit, qty):              # match against asks, rest remainder? see caller
  while qty > 0 and best_ask <= limit:
    take = min(qty, ask[best_ask])
    ask[best_ask] -= take
    qty -= take
    traded_qty      = traded_qty + take                (wrapping)
    traded_notional = traded_notional + take*best_ask  (wrapping)
    if ask[best_ask] == 0: best_ask = scan_up(best_ask)
  return qty                  # unfilled remainder

sell(limit, qty):             # match against bids
  while qty > 0 and best_bid >= limit:
    take = min(qty, bid[best_bid])
    bid[best_bid] -= take
    qty -= take
    traded_qty      += take                (wrapping)
    traded_notional += take*best_bid       (wrapping)
    if bid[best_bid] == 0: best_bid = scan_down(best_bid)
  return qty
```

(`best_ask <= limit` is false when there are no asks because 1023 > any limit
used. `best_bid >= limit` is false when there are no bids because all limits
are >= 1.)

## Order stream (N orders)

```
repeat N times:
  s    = rng_next(s)
  r    = s >> 8                      # 24 random bits
  kind = r & 15                      # 0..15
  side = (r >> 4) & 1                # 0 = buy, 1 = sell
  off  = (r >> 5) & 31               # 0..31
  qty  = ((r >> 10) & 63) + 1        # 1..64
  if side == 0: price = 496 + off    # buy prices  496..527
  else:         price = 497 + off    # sell prices 497..528

  if kind < 10:                      # LIMIT order (may cross the spread)
    if side == 0:
      rem = buy(price, qty)
      if rem > 0:
        bid[price] += rem
        if price > best_bid: best_bid = price
    else:
      rem = sell(price, qty)
      if rem > 0:
        ask[price] += rem
        if price < best_ask: best_ask = price
  else if kind < 13:                 # MARKET order; remainder discarded
    if side == 0: buy(1022, qty)
    else:         sell(1, qty)
  else:                              # CANCEL at that level (kind 13..15)
    if side == 0:
      bid[price] -= min(bid[price], qty)
      if bid[price] == 0 and price == best_bid: best_bid = scan_down(price)
    else:
      ask[price] -= min(ask[price], qty)
      if ask[price] == 0 and price == best_ask: best_ask = scan_up(price)
```

## Output

```
checksum = traded_qty * 31 + traded_notional + best_bid * 7 + best_ask   (all wrapping u32)
```

Print `checksum: <u32>` then `kernel_ms: <ms>`. Default N = 1_000_000.

## Bend hints

- Loops are `Nat`-fuel tail recursion. `scan_down(p)` can use fuel
  `U32.to_nat(p)`; `scan_up(p)` fuel `U32.to_nat(1023 - p)`. The `while` loops
  in `buy`/`sell` terminate because every iteration removes >= 1 unit of qty,
  so use fuel `U32.to_nat(qty)`.
- The book state (array, best_bid, best_ask, traded_qty, traded_notional) is
  threaded through calls; returning several values means returning a
  constructor/tuple, e.g. a `type Book is Type: Book{arr: Array<U32>, bb: U32,
  ba: U32, tq: U32, tn: U32}`.
- `a[i]` sugar returns the array back beside the element (see guide "Arrays").
