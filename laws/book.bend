import Base

# A proof-friendly model of one side of the matching engine in
# bend/orderbook.bend: the opposite side is a list of resting quantities,
# best price first, and an aggressive order of `qty` sweeps it.
# Nat instead of U32: unbounded, so the laws hold without overflow caveats.

type Sweep is Data:
  Sweep{rem: Nat, filled: Nat, book: List<&2, Nat>}

# quantity taken from one level: min(qty, level)
def Book.take(+q: Nat, +l: Nat) -> Nat:
  Nat.min(q, l)

# total resting quantity on the side
def Book.total(xs: List<&2, Nat>) -> Nat:
  match xs:
    case Nil{}:
      0n
    case Con{l, rest}:
      Nat.add(l, Book.total(rest))

def Book.sweep.cons(+l: Nat, +t: Nat, s: Sweep) -> Sweep:
  Sweep{rem, filled, book} = s
  Sweep{rem, Nat.add(t, filled), Con{Nat.sub(l, t), book}}

# match qty against the levels in order; returns remainder, filled, new levels
def Book.sweep(xs: List<&2, Nat>, +q: Nat) -> Sweep:
  match xs:
    case Nil{}:
      Sweep{q, 0n, Nil{}}
    case Con{+l, rest}:
      Book.sweep.cons(l, Book.take(q, l), Book.sweep(rest, Nat.sub(q, Book.take(q, l))))

def Sweep.rem(s: Sweep) -> Nat:
  Sweep{r, f, b} = s
  r

def Sweep.filled(s: Sweep) -> Nat:
  Sweep{r, f, b} = s
  f

def Sweep.book(s: Sweep) -> List<&2, Nat>:
  Sweep{r, f, b} = s
  b
