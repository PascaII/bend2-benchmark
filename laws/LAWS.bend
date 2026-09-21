import Base
import ./book.bend as B

# LAW: taking min(qty, level) never takes more than the order wants
law take_le_qty:
  for +q: Nat
  for +l: Nat
  {Nat.is_le(B.Book.take(q, l), q) == True{} : Bool}

# LAW: ...and never more than the level holds (no negative liquidity)
law take_le_level:
  for +q: Nat
  for +l: Nat
  {Nat.is_le(B.Book.take(q, l), l) == True{} : Bool}

# LAW: an aggressive order is fully accounted for:
#      filled + unfilled remainder == submitted quantity
law sweep_conserves_order:
  for xs: List<&2, Nat>
  for +q: Nat
  {Nat.add(B.Sweep.filled(B.Book.sweep(xs, q)), B.Sweep.rem(B.Book.sweep(xs, q))) == q : Nat}

# LAW: matching moves liquidity, it never creates or destroys it:
#      filled + resting volume after the sweep == resting volume before
law sweep_conserves_book:
  for xs: List<&2, Nat>
  for +q: Nat
  {Nat.add(B.Sweep.filled(B.Book.sweep(xs, q)), B.Book.total(B.Sweep.book(B.Book.sweep(xs, q)))) == B.Book.total(xs) : Nat}
