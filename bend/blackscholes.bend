import Base
import ./common.bend as C

# ----------------------------------------------------------- shared math --

# normal pdf: PDF_C * exp((-0.5 * x) * x)
def npdf(+x: F32) -> F32:
  F32.mul(0.3989422804, F32.exp(F32.mul(F32.mul(F32.neg(0.5), x), x)))

# there is no `if`: branch on a computed Bool through a helper def
def pick(c: Bool, a: F32, b: F32) -> F32:
  match c:
    case True{}:
      a
    case False{}:
      b

# normal cdf, Abramowitz & Stegun 26.2.17
def ncdf(+x: F32) -> F32:
  +ax = F32.abs(x)
  +t = F32.div(1.0, F32.add(1.0, F32.mul(0.2316419, ax)))
  +poly = F32.mul(t, F32.add(0.319381530, F32.mul(t, F32.add(F32.neg(0.356563782), F32.mul(t, F32.add(1.781477937, F32.mul(t, F32.add(F32.neg(1.821255978), F32.mul(t, 1.330274429)))))))))
  +c = F32.sub(1.0, F32.mul(npdf(ax), poly))
  pick(F32.is_ge(x, 0.0), c, F32.sub(1.0, c))

# d1 = (log(S / K) + (r + (0.5 * sig) * sig) * T) / (sig * sqrt(T))
def d1of(+s: F32, +k: F32, +t: F32, +r: F32, +sig: F32) -> F32:
  F32.div(F32.add(F32.log(F32.div(s, k)), F32.mul(F32.add(r, F32.mul(F32.mul(0.5, sig), sig)), t)), F32.mul(sig, F32.sqrt(t)))

# European call: S * ncdf(d1) - (K * exp((-r) * T)) * ncdf(d2)
def call(+s: F32, +k: F32, +t: F32, +r: F32, +sig: F32) -> F32:
  +d1 = d1of(s, k, t, r, sig)
  +d2 = F32.sub(d1, F32.mul(sig, F32.sqrt(t)))
  F32.sub(F32.mul(s, ncdf(d1)), F32.mul(F32.mul(k, F32.exp(F32.mul(F32.neg(r), t))), ncdf(d2)))

# vega: (S * npdf(d1)) * sqrt(T)
def vega(+s: F32, +k: F32, +t: F32, +r: F32, +sig: F32) -> F32:
  +d1 = d1of(s, k, t, r, sig)
  F32.mul(F32.mul(s, npdf(d1)), F32.sqrt(t))

# ------------------------------------------------------- implied vol --

type IV is Type:
  IV{s: F32, k: F32, t: F32, r: F32, price: F32, sig: F32}

# one Newton step, then clamp sig into [0.01, 3.0]
def iv.step(st: IV) -> IV:
  IV{+s, +k, +t, +r, +price, +sig} = st
  +c = call(s, k, t, r, sig)
  +v = vega(s, k, t, r, sig)
  +ns = F32.sub(sig, F32.div(F32.sub(c, price), F32.max(v, 0.0001)))
  IV{s, k, t, r, price, F32.min(F32.max(ns, 0.01), 3.0)}

def iv.loop(fuel: Nat, st: IV) -> IV:
  match fuel:
    case 0n:
      st
    case 1n+p:
      iv.loop(p, iv.step(st))

def iv.sum(st: IV) -> F32:
  IV{s, k, t, r, price, sig} = st
  F32.add(price, sig)

def option_value(i: U32) -> F32:
  +h = C.Rng.hash(i)
  +s = {100.0 : F32}
  +r = {0.03 : F32}
  +k = F32.add(90.0, F32.mul(U32.to_f32((h .&. 63 : U32)), 0.3125))
  +t = F32.add(0.25, F32.mul(U32.to_f32(((h >> 6n) .&. 63 : U32)), 0.015625))
  +sv = F32.add(0.15, F32.mul(U32.to_f32(((h >> 12n) .&. 63 : U32)), 0.005))
  +price = call(s, k, t, r, sv)
  iv.sum(iv.loop(8n, IV{s, k, t, r, price, 0.3}))

# ---------------------------------------------- fixed reduction tree --

# leaf: acc = acc + option_value(i) for i in lo .. lo + cnt, ascending
def tree.block(fuel: Nat, +i: U32, acc: F32) -> F32:
  match fuel:
    case 0n:
      acc
    case 1n+p:
      tree.block(p, (i + 1 : U32), F32.add(acc, option_value(i)))

# tree(fuel, lo, hs) sums 2^(fuel + 10) options starting at lo; hs = n / 2
def tree(fuel: Nat, +lo: U32, +hs: U32) -> F32:
  match fuel:
    case 0n:
      tree.block(U32.to_nat((hs * 2 : U32)), lo, 0.0)
    case 1n+ +p:
      +nh = (hs >> 1n : U32)
      a b = tree(p, lo, nh) tree(p, (lo + hs : U32), nh)
      F32.add(a, b)

# log2(n) - 10 = splits above the 1024-option leaf; 32n is a safe upper bound
def depth.add(stop: Bool, acc: Nat) -> Nat:
  match stop:
    case True{}:
      acc
    case False{}:
      Nat.add(acc, 1n)

def depth(fuel: Nat, +n: U32, acc: Nat) -> Nat:
  match fuel:
    case 0n:
      acc
    case 1n+p:
      depth(p, (n >> 1n : U32), depth.add(U32.is_eq((n >> 11n : U32), 0), acc))

def kernel(+n: U32) -> F32:
  +f = depth(32n, n, 0n)
  tree(f, 0, (n >> 1n : U32))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +n : U32 = C.Arg.first(args, 65536)
    +t0 : Nat <- IO.now()
    +checksum : F32 = kernel(n)
    IO.print("checksum: " ++ F32.show(checksum))
    t1 : Nat <- IO.now()
    IO.print("kernel_ms: " ++ Nat.show(Nat.sub(t1, t0)))
