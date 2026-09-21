import Base
import ./common.bend as C

# L2 order book + matching engine. See specs/01_orderbook.md.
# Array layout: one Array<U32> of 2048 slots; bid[p] = arr[p], ask[p] = arr[1024+p].

type Book is Type:
  Book{arr: Array<U32>, bb: U32, ba: U32, tq: U32, tn: U32, s: U32}

type BuySt is Type:
  BuySt{arr: Array<U32>, ba: U32, tq: U32, tn: U32, qty: U32, limit: U32}

type SellSt is Type:
  SellSt{arr: Array<U32>, bb: U32, tq: U32, tn: U32, qty: U32, limit: U32}

type ScanSt is Type:
  ScanSt{arr: Array<U32>, off: U32, q: U32, found: Bool, result: U32}

## scan_up: next higher non-empty ask level above p (offset 1024), else 1023

def scan_up.step4(iszero: Bool, arr: Array<U32>, off: U32, +nq: U32) -> ScanSt:
  match iszero:
    case True{}:
      ScanSt{arr, off, nq, False{}, 1023}
    case False{}:
      ScanSt{arr, off, nq, True{}, nq}

def scan_up.step3(av: Array<U32> & U32, off: U32, nq: U32) -> ScanSt:
  (arr, v) = av
  scan_up.step4(U32.is_eq(v, 0), arr, off, nq)

def scan_up.step2(found: Bool, arr: Array<U32>, +off: U32, q: U32, result: U32) -> ScanSt:
  match found:
    case True{}:
      ScanSt{arr, off, q, True{}, result}
    case False{}:
      +nq = (q + 1 : U32)
      idx = (off + nq : U32)
      scan_up.step3(arr[idx], off, nq)

def scan_up.step(st: ScanSt) -> ScanSt:
  match st:
    case ScanSt{arr, off, q, found, result}:
      scan_up.step2(found, arr, off, q, result)

def scan_up.loop(fuel: Nat, st: ScanSt) -> ScanSt:
  match fuel:
    case 0n:
      st
    case 1n+f:
      scan_up.loop(f, scan_up.step(st))

def scan_up.result(st: ScanSt) -> Array<U32> & U32:
  match st:
    case ScanSt{arr, off, q, found, result}:
      (arr, result)

def scan_up(arr: Array<U32>, p: U32) -> Array<U32> & U32:
  +p2 = p
  fuel = U32.to_nat((1023 - p2 : U32))
  scan_up.result(scan_up.loop(fuel, ScanSt{arr, 1024, p2, False{}, 1023}))

## scan_down: next lower non-empty bid level below p (offset 0), else 0

def scan_down.step4(iszero: Bool, arr: Array<U32>, off: U32, +nq: U32) -> ScanSt:
  match iszero:
    case True{}:
      ScanSt{arr, off, nq, False{}, 0}
    case False{}:
      ScanSt{arr, off, nq, True{}, nq}

def scan_down.step3(av: Array<U32> & U32, off: U32, nq: U32) -> ScanSt:
  (arr, v) = av
  scan_down.step4(U32.is_eq(v, 0), arr, off, nq)

def scan_down.step2(found: Bool, arr: Array<U32>, +off: U32, q: U32, result: U32) -> ScanSt:
  match found:
    case True{}:
      ScanSt{arr, off, q, True{}, result}
    case False{}:
      +nq = (q - 1 : U32)
      idx = (off + nq : U32)
      scan_down.step3(arr[idx], off, nq)

def scan_down.step(st: ScanSt) -> ScanSt:
  match st:
    case ScanSt{arr, off, q, found, result}:
      scan_down.step2(found, arr, off, q, result)

def scan_down.loop(fuel: Nat, st: ScanSt) -> ScanSt:
  match fuel:
    case 0n:
      st
    case 1n+f:
      scan_down.loop(f, scan_down.step(st))

def scan_down.result(st: ScanSt) -> Array<U32> & U32:
  match st:
    case ScanSt{arr, off, q, found, result}:
      (arr, result)

def scan_down(arr: Array<U32>, p: U32) -> Array<U32> & U32:
  +p2 = p
  fuel = U32.to_nat(p2)
  scan_down.result(scan_down.loop(fuel, ScanSt{arr, 0, p2, False{}, 0}))

## buy: match against asks (arr[1024+ba]) while qty > 0 and ba <= limit

def buy.step.checkzero.got(av: Array<U32> & U32, tq: U32, tn: U32, qty: U32, limit: U32) -> BuySt:
  (arr, ba) = av
  BuySt{arr, ba, tq, tn, qty, limit}

def buy.step.checkzero(iszero: Bool, arr: Array<U32>, ba: U32, tq: U32, tn: U32, qty: U32, limit: U32) -> BuySt:
  match iszero:
    case True{}:
      buy.step.checkzero.got(scan_up(arr, ba), tq, tn, qty, limit)
    case False{}:
      BuySt{arr, ba, tq, tn, qty, limit}

def buy.step.got(av: Array<U32> & U32, +ba: U32, tq: U32, tn: U32, +qty: U32, limit: U32) -> BuySt:
  (arr, +avail) = av
  +take = U32.min(qty, avail)
  +newavail = (avail - take : U32)
  arr2 = arr[(1024 + ba : U32)] <- newavail
  newqty = (qty - take : U32)
  newtq = (tq + take : U32)
  newtn = (tn + (take * ba : U32) : U32)
  buy.step.checkzero(U32.is_eq(newavail, 0), arr2, ba, newtq, newtn, newqty, limit)

def buy.step.branch(cond: Bool, arr: Array<U32>, +ba: U32, tq: U32, tn: U32, qty: U32, limit: U32) -> BuySt:
  match cond:
    case False{}:
      BuySt{arr, ba, tq, tn, qty, limit}
    case True{}:
      buy.step.got(arr[(1024 + ba : U32)], ba, tq, tn, qty, limit)

def buy.step(st: BuySt) -> BuySt:
  match st:
    case BuySt{arr, +ba, tq, tn, +qty, +limit}:
      cond = Bool.and(U32.is_gt(qty, 0), U32.is_le(ba, limit))
      buy.step.branch(cond, arr, ba, tq, tn, qty, limit)

def buy.loop(fuel: Nat, st: BuySt) -> BuySt:
  match fuel:
    case 0n:
      st
    case 1n+f:
      buy.loop(f, buy.step(st))

def buy(arr: Array<U32>, ba: U32, tq: U32, tn: U32, limit: U32, qty: U32) -> BuySt:
  +qty2 = qty
  fuel = U32.to_nat(qty2)
  buy.loop(fuel, BuySt{arr, ba, tq, tn, qty2, limit})

## sell: match against bids (arr[bb]) while qty > 0 and bb >= limit

def sell.step.checkzero.got(av: Array<U32> & U32, tq: U32, tn: U32, qty: U32, limit: U32) -> SellSt:
  (arr, bb) = av
  SellSt{arr, bb, tq, tn, qty, limit}

def sell.step.checkzero(iszero: Bool, arr: Array<U32>, bb: U32, tq: U32, tn: U32, qty: U32, limit: U32) -> SellSt:
  match iszero:
    case True{}:
      sell.step.checkzero.got(scan_down(arr, bb), tq, tn, qty, limit)
    case False{}:
      SellSt{arr, bb, tq, tn, qty, limit}

def sell.step.got(av: Array<U32> & U32, +bb: U32, tq: U32, tn: U32, +qty: U32, limit: U32) -> SellSt:
  (arr, +avail) = av
  +take = U32.min(qty, avail)
  +newavail = (avail - take : U32)
  arr2 = arr[bb] <- newavail
  newqty = (qty - take : U32)
  newtq = (tq + take : U32)
  newtn = (tn + (take * bb : U32) : U32)
  sell.step.checkzero(U32.is_eq(newavail, 0), arr2, bb, newtq, newtn, newqty, limit)

def sell.step.branch(cond: Bool, arr: Array<U32>, +bb: U32, tq: U32, tn: U32, qty: U32, limit: U32) -> SellSt:
  match cond:
    case False{}:
      SellSt{arr, bb, tq, tn, qty, limit}
    case True{}:
      sell.step.got(arr[bb], bb, tq, tn, qty, limit)

def sell.step(st: SellSt) -> SellSt:
  match st:
    case SellSt{arr, +bb, tq, tn, +qty, +limit}:
      cond = Bool.and(U32.is_gt(qty, 0), U32.is_ge(bb, limit))
      sell.step.branch(cond, arr, bb, tq, tn, qty, limit)

def sell.loop(fuel: Nat, st: SellSt) -> SellSt:
  match fuel:
    case 0n:
      st
    case 1n+f:
      sell.loop(f, sell.step(st))

def sell(arr: Array<U32>, bb: U32, tq: U32, tn: U32, limit: U32, qty: U32) -> SellSt:
  +qty2 = qty
  fuel = U32.to_nat(qty2)
  sell.loop(fuel, SellSt{arr, bb, tq, tn, qty2, limit})

## LIMIT order handling

def finish_limit_buy4(isnew: Bool, arr: Array<U32>, bb: U32, ba: U32, tq: U32, tn: U32, s: U32, price: U32) -> Book:
  match isnew:
    case True{}:
      Book{arr, price, ba, tq, tn, s}
    case False{}:
      Book{arr, bb, ba, tq, tn, s}

def finish_limit_buy3(av: Array<U32> & U32, +bb: U32, ba: U32, tq: U32, tn: U32, s: U32, +price: U32, rem: U32) -> Book:
  (arr, +cur) = av
  arr2 = arr[price] <- (cur + rem : U32)
  finish_limit_buy4(U32.is_gt(price, bb), arr2, bb, ba, tq, tn, s, price)

def finish_limit_buy2(hasrem: Bool, arr: Array<U32>, bb: U32, ba: U32, tq: U32, tn: U32, s: U32, +price: U32, rem: U32) -> Book:
  match hasrem:
    case False{}:
      Book{arr, bb, ba, tq, tn, s}
    case True{}:
      finish_limit_buy3(arr[price], bb, ba, tq, tn, s, price, rem)

def finish_limit_buy(bres: BuySt, bb: U32, s: U32, +price: U32) -> Book:
  match bres:
    case BuySt{arr, ba, tq, tn, +rem, limit}:
      finish_limit_buy2(U32.is_gt(rem, 0), arr, bb, ba, tq, tn, s, price, rem)

def do_limit_buy(arr: Array<U32>, bb: U32, ba: U32, tq: U32, tn: U32, s: U32, +price: U32, qty: U32) -> Book:
  finish_limit_buy(buy(arr, ba, tq, tn, price, qty), bb, s, price)

def finish_limit_sell4(isnew: Bool, arr: Array<U32>, bb: U32, ba: U32, tq: U32, tn: U32, s: U32, price: U32) -> Book:
  match isnew:
    case True{}:
      Book{arr, bb, price, tq, tn, s}
    case False{}:
      Book{arr, bb, ba, tq, tn, s}

def finish_limit_sell3(av: Array<U32> & U32, bb: U32, +ba: U32, tq: U32, tn: U32, s: U32, +price: U32, rem: U32) -> Book:
  (arr, +cur) = av
  arr2 = arr[(1024 + price : U32)] <- (cur + rem : U32)
  finish_limit_sell4(U32.is_lt(price, ba), arr2, bb, ba, tq, tn, s, price)

def finish_limit_sell2(hasrem: Bool, arr: Array<U32>, bb: U32, ba: U32, tq: U32, tn: U32, s: U32, +price: U32, rem: U32) -> Book:
  match hasrem:
    case False{}:
      Book{arr, bb, ba, tq, tn, s}
    case True{}:
      finish_limit_sell3(arr[(1024 + price : U32)], bb, ba, tq, tn, s, price, rem)

def finish_limit_sell(sres: SellSt, ba: U32, s: U32, +price: U32) -> Book:
  match sres:
    case SellSt{arr, bb, tq, tn, +rem, limit}:
      finish_limit_sell2(U32.is_gt(rem, 0), arr, bb, ba, tq, tn, s, price, rem)

def do_limit_sell(arr: Array<U32>, bb: U32, ba: U32, tq: U32, tn: U32, s: U32, +price: U32, qty: U32) -> Book:
  finish_limit_sell(sell(arr, bb, tq, tn, price, qty), ba, s, price)

def branch_limit_side(isbuy: Bool, arr: Array<U32>, bb: U32, ba: U32, tq: U32, tn: U32, s: U32, price: U32, qty: U32) -> Book:
  match isbuy:
    case True{}:
      do_limit_buy(arr, bb, ba, tq, tn, s, price, qty)
    case False{}:
      do_limit_sell(arr, bb, ba, tq, tn, s, price, qty)

def do_limit(arr: Array<U32>, bb: U32, ba: U32, tq: U32, tn: U32, s: U32, +side: U32, price: U32, qty: U32) -> Book:
  branch_limit_side(U32.is_eq(side, 0), arr, bb, ba, tq, tn, s, price, qty)

## MARKET order handling (remainder discarded)

def market_buy_done(bres: BuySt, bb: U32, s: U32) -> Book:
  match bres:
    case BuySt{arr, ba, tq, tn, rem, limit}:
      Book{arr, bb, ba, tq, tn, s}

def market_sell_done(sres: SellSt, ba: U32, s: U32) -> Book:
  match sres:
    case SellSt{arr, bb, tq, tn, rem, limit}:
      Book{arr, bb, ba, tq, tn, s}

def branch_market_side(isbuy: Bool, arr: Array<U32>, bb: U32, ba: U32, tq: U32, tn: U32, s: U32, qty: U32) -> Book:
  match isbuy:
    case True{}:
      market_buy_done(buy(arr, ba, tq, tn, 1022, qty), bb, s)
    case False{}:
      market_sell_done(sell(arr, bb, tq, tn, 1, qty), ba, s)

def do_market(arr: Array<U32>, bb: U32, ba: U32, tq: U32, tn: U32, s: U32, +side: U32, qty: U32) -> Book:
  branch_market_side(U32.is_eq(side, 0), arr, bb, ba, tq, tn, s, qty)

## CANCEL order handling

def cancel_bid4(av: Array<U32> & U32, tq: U32, tn: U32, s: U32, ba: U32) -> Book:
  (arr, newbb) = av
  Book{arr, newbb, ba, tq, tn, s}

def cancel_bid3(cond: Bool, arr: Array<U32>, bb: U32, ba: U32, tq: U32, tn: U32, s: U32) -> Book:
  match cond:
    case True{}:
      cancel_bid4(scan_down(arr, bb), tq, tn, s, ba)
    case False{}:
      Book{arr, bb, ba, tq, tn, s}

def cancel_bid2(av: Array<U32> & U32, +bb: U32, ba: U32, tq: U32, tn: U32, s: U32, +price: U32, qty: U32) -> Book:
  (arr, +cur) = av
  +d = U32.min(cur, qty)
  +newval = (cur - d : U32)
  arr2 = arr[price] <- newval
  cond = Bool.and(U32.is_eq(newval, 0), U32.is_eq(price, bb))
  cancel_bid3(cond, arr2, bb, ba, tq, tn, s)

def cancel_bid(arr: Array<U32>, bb: U32, ba: U32, tq: U32, tn: U32, s: U32, +price: U32, qty: U32) -> Book:
  cancel_bid2(arr[price], bb, ba, tq, tn, s, price, qty)

def cancel_ask4(av: Array<U32> & U32, bb: U32, tq: U32, tn: U32, s: U32) -> Book:
  (arr, newba) = av
  Book{arr, bb, newba, tq, tn, s}

def cancel_ask3(cond: Bool, arr: Array<U32>, bb: U32, ba: U32, tq: U32, tn: U32, s: U32) -> Book:
  match cond:
    case True{}:
      cancel_ask4(scan_up(arr, ba), bb, tq, tn, s)
    case False{}:
      Book{arr, bb, ba, tq, tn, s}

def cancel_ask2(av: Array<U32> & U32, bb: U32, +ba: U32, tq: U32, tn: U32, s: U32, +price: U32, qty: U32) -> Book:
  (arr, +cur) = av
  +d = U32.min(cur, qty)
  +newval = (cur - d : U32)
  arr2 = arr[(1024 + price : U32)] <- newval
  cond = Bool.and(U32.is_eq(newval, 0), U32.is_eq(price, ba))
  cancel_ask3(cond, arr2, bb, ba, tq, tn, s)

def cancel_ask(arr: Array<U32>, bb: U32, ba: U32, tq: U32, tn: U32, s: U32, +price: U32, qty: U32) -> Book:
  cancel_ask2(arr[(1024 + price : U32)], bb, ba, tq, tn, s, price, qty)

def branch_cancel_side(isbid: Bool, arr: Array<U32>, bb: U32, ba: U32, tq: U32, tn: U32, s: U32, price: U32, qty: U32) -> Book:
  match isbid:
    case True{}:
      cancel_bid(arr, bb, ba, tq, tn, s, price, qty)
    case False{}:
      cancel_ask(arr, bb, ba, tq, tn, s, price, qty)

def do_cancel(arr: Array<U32>, bb: U32, ba: U32, tq: U32, tn: U32, s: U32, +side: U32, price: U32, qty: U32) -> Book:
  branch_cancel_side(U32.is_eq(side, 0), arr, bb, ba, tq, tn, s, price, qty)

## Dispatch on kind

def branch_market(is_market: Bool, arr: Array<U32>, bb: U32, ba: U32, tq: U32, tn: U32, s: U32, side: U32, price: U32, qty: U32) -> Book:
  match is_market:
    case True{}:
      do_market(arr, bb, ba, tq, tn, s, side, qty)
    case False{}:
      do_cancel(arr, bb, ba, tq, tn, s, side, price, qty)

def branch_kind(is_limit: Bool, +kind: U32, arr: Array<U32>, bb: U32, ba: U32, tq: U32, tn: U32, s: U32, side: U32, price: U32, qty: U32) -> Book:
  match is_limit:
    case True{}:
      do_limit(arr, bb, ba, tq, tn, s, side, price, qty)
    case False{}:
      branch_market(U32.is_lt(kind, 13), arr, bb, ba, tq, tn, s, side, price, qty)

def dispatch(arr: Array<U32>, bb: U32, ba: U32, tq: U32, tn: U32, s: U32, +kind: U32, side: U32, price: U32, qty: U32) -> Book:
  branch_kind(U32.is_lt(kind, 10), kind, arr, bb, ba, tq, tn, s, side, price, qty)

def branch_price(c: Bool, off: U32) -> U32:
  match c:
    case True{}:
      (496 + off : U32)
    case False{}:
      (497 + off : U32)

def pick_price(side: U32, off: U32) -> U32:
  branch_price(U32.is_eq(side, 0), off)

def apply(arr: Array<U32>, bb: U32, ba: U32, tq: U32, tn: U32, s: U32, +r: U32) -> Book:
  kind = (r .&. 15 : U32)
  +side = ((r >> 4n) .&. 1 : U32)
  off = ((r >> 5n) .&. 31 : U32)
  qty = (((r >> 10n) .&. 63 : U32) + 1 : U32)
  price = pick_price(side, off)
  dispatch(arr, bb, ba, tq, tn, s, kind, side, price, qty)

## Main order-stream loop

def step(st: Book) -> Book:
  match st:
    case Book{arr, bb, ba, tq, tn, s}:
      +ns = C.Rng.next(s)
      apply(arr, bb, ba, tq, tn, ns, (ns >> 8n : U32))

def loop(fuel: Nat, st: Book) -> Book:
  match fuel:
    case 0n:
      st
    case 1n+f:
      loop(f, step(st))

def checksum(st: Book) -> U32:
  match st:
    case Book{arr, bb, ba, tq, tn, s}:
      (tq * 31 + tn + bb * 7 + ba : U32)

def kernel(n: U32) -> U32:
  arr = [0 : U32*2048n]
  init : Book = Book{arr, (0 : U32), (1023 : U32), (0 : U32), (0 : U32), (1 : U32)}
  checksum(loop(U32.to_nat(n), init))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +n : U32 = C.Arg.first(args, 1000000)
    +t0 : Nat <- IO.now()
    r : U32 = kernel(n)
    IO.print("checksum: " ++ U32.show(r))
    t1 : Nat <- IO.now()
    IO.print("kernel_ms: " ++ Nat.show(Nat.sub(t1, t0)))
