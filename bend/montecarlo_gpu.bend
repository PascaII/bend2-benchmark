import Base
import ./common.bend as C

# Monte Carlo Asian option pricing. See specs/04_montecarlo.md.
# Constants (f32, exact literals from the spec):
#   S0=100.0 K=100.0 STEPS=64 DRIFT=0.00015625 VOLSDT=0.025
#   TWO_PI=6.2831855 DISC=0.9704455 INV_STEPS=0.015625

type PathSt is Type:
  PathSt{x: U32, S: F32, sumS: F32}

## One GBM path of 64 steps, Box-Muller (cos branch), returns the payoff.

def path.step(st: PathSt) -> PathSt:
  match st:
    case PathSt{x, S, sumS}:
      +x1 = C.Rng.next(x)
      u1 = C.Rng.unit(x1)
      +x2 = C.Rng.next(x1)
      u2 = C.Rng.unit(x2)
      z = F32.mul(F32.sqrt(F32.mul(F32.neg(2.0), F32.log(u1))), F32.cos(F32.mul(6.2831855, u2)))
      +newS = F32.mul(S, F32.exp(F32.add(0.00015625, F32.mul(0.025, z))))
      newsumS = F32.add(sumS, newS)
      PathSt{x2, newS, newsumS}

def path.loop(fuel: Nat, st: PathSt) -> PathSt:
  match fuel:
    case 0n:
      st
    case 1n+f:
      path.loop(f, path.step(st))

def payoff.from(st: PathSt) -> F32:
  match st:
    case PathSt{x, S, sumS}:
      avg = F32.mul(sumS, 0.015625)
      F32.max(F32.sub(avg, 100.0), 0.0)

def payoff(p: U32) -> F32:
  x0 = C.Rng.hash(p)
  init : PathSt = PathSt{x0, 100.0, 0.0}
  payoff.from(path.loop(64n, init))

## Leaf: sequential ascending sum of payoff(lo..lo+n), n <= 1024.

def leaf.loop(fuel: Nat, +i: U32, acc: F32) -> F32:
  match fuel:
    case 0n:
      acc
    case 1n+f:
      leaf.loop(f, (i + 1 : U32), F32.add(acc, payoff(i)))

def leaf(lo: U32, n: U32) -> F32:
  leaf.loop(U32.to_nat(n), lo, 0.0)

## Reduction tree: fixed shape, parallel let at every level above the leaf.
## `lv` = log2(n / 1024), precomputed once so the recursion is a plain
## self-recursive Nat-fuel def (no mutual recursion between a fuel-match and
## a Bool-branch helper, which Bend's termination checker rejects).

type LvSt is Type:
  LvSt{n: U32, lv: Nat, done: Bool}

def levels.step.branch2(cond: Bool, n: U32, lv: Nat) -> LvSt:
  match cond:
    case True{}:
      LvSt{n, lv, True{}}
    case False{}:
      LvSt{(n >> 1n : U32), (1n + lv : Nat), False{}}

def levels.step.branch(done: Bool, +n: U32, lv: Nat) -> LvSt:
  match done:
    case True{}:
      LvSt{n, lv, True{}}
    case False{}:
      cond = U32.is_le(n, 1024)
      levels.step.branch2(cond, n, lv)

def levels.step(st: LvSt) -> LvSt:
  match st:
    case LvSt{n, lv, done}:
      levels.step.branch(done, n, lv)

def levels.loop(fuel: Nat, st: LvSt) -> LvSt:
  match fuel:
    case 0n:
      st
    case 1n+f:
      levels.loop(f, levels.step(st))

def levels.result(st: LvSt) -> Nat:
  match st:
    case LvSt{n, lv, done}:
      lv

def levels(n: U32) -> Nat:
  levels.result(levels.loop(32n, LvSt{n, 0n, False{}}))

def tree(lv: Nat, +lo: U32, n: U32) -> F32:
  match lv:
    case 0n:
      leaf(lo, n)
    case 1n+ +p:
      +half = (n >> 1n : U32)
      a b = tree(p, lo, half) tree(p, (lo + half : U32), half)
      F32.add(a, b)

def kernel(+n: U32) -> F32:
  +lv : Nat = levels(n)
  total = tree!(lv, 0, n)   # `!`: run the whole fork tree on the GPU (Metal on macOS)
  F32.mul(F32.div(total, U32.to_f32(n)), 0.9704455)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +n : U32 = C.Arg.first(args, 65536)
    +t0 : Nat <- IO.now()
    r : F32 = kernel(n)
    IO.print("checksum: " ++ F32.show(r))
    t1 : Nat <- IO.now()
    IO.print("kernel_ms: " ++ Nat.show(Nat.sub(t1, t0)))
