import Base
import ./book.bend as B
import ./lemmas.bend as L
import ./LAWS.bend as Laws

def Laws.take_le_qty(q, l):
  match q l:
    case 0n _:
      {==}
    case 1n+qp 0n:
      {==}
    case 1n+qp 1n+lp:
      Laws.take_le_qty(qp, lp)

def Laws.take_le_level(q, l):
  match q l:
    case 0n 0n:
      {==}
    case 0n 1n+lp:
      {==}
    case 1n+qp 0n:
      {==}
    case 1n+qp 1n+lp:
      Laws.take_le_level(qp, lp)

# one level of the sweep adds its take t to `filled` and leaves `rem` alone
law cons_order:
  for +l: Nat
  for +t: Nat
  for s: B.Sweep
  {Nat.add(B.Sweep.filled(B.Book.sweep.cons(l, t, s)), B.Sweep.rem(B.Book.sweep.cons(l, t, s)))
    == Nat.add(t, Nat.add(B.Sweep.filled(s), B.Sweep.rem(s))) : Nat}

def cons_order(l, t, s):
  match s:
    case B.Sweep{r, f, b}:
      L.Nat.add_assoc(t, f, r)

def Laws.sweep_conserves_order(xs, q):
  match xs:
    case Nil{}:
      {==}
    case Con{+l, +rest}:
      +t = B.Book.take(q, l)
      +s = B.Book.sweep(rest, Nat.sub(q, t))
      %Equal.sym(Nat, Nat.add(B.Sweep.filled(B.Book.sweep.cons(l, t, s)), B.Sweep.rem(B.Book.sweep.cons(l, t, s))), Nat.add(t, Nat.add(B.Sweep.filled(s), B.Sweep.rem(s))), cons_order(l, t, s)) : {_ == q : Nat}
      %Equal.sym(Nat, Nat.add(B.Sweep.filled(s), B.Sweep.rem(s)), Nat.sub(q, t), Laws.sweep_conserves_order(rest, Nat.sub(q, t))) : {Nat.add(t, _) == q : Nat}
      L.Nat.min_sub_l(q, l)

# one level of the sweep: its take t moves from the level to `filled`
law cons_book:
  for +l: Nat
  for +t: Nat
  for s: B.Sweep
  {Nat.add(B.Sweep.filled(B.Book.sweep.cons(l, t, s)), B.Book.total(B.Sweep.book(B.Book.sweep.cons(l, t, s))))
    == Nat.add(Nat.add(t, Nat.sub(l, t)), Nat.add(B.Sweep.filled(s), B.Book.total(B.Sweep.book(s)))) : Nat}

def cons_book(l, t, s):
  match s:
    case B.Sweep{r, +f, +b}:
      L.Nat.add_swap_mid(t, f, Nat.sub(l, t), B.Book.total(b))

def Laws.sweep_conserves_book(xs, q):
  match xs:
    case Nil{}:
      {==}
    case Con{+l, +rest}:
      +t = B.Book.take(q, l)
      +s = B.Book.sweep(rest, Nat.sub(q, t))
      +fs = B.Sweep.filled(s)
      +bs = B.Book.total(B.Sweep.book(s))
      %Equal.sym(Nat, Nat.add(B.Sweep.filled(B.Book.sweep.cons(l, t, s)), B.Book.total(B.Sweep.book(B.Book.sweep.cons(l, t, s)))), Nat.add(Nat.add(t, Nat.sub(l, t)), Nat.add(fs, bs)), cons_book(l, t, s)) : {_ == Nat.add(l, B.Book.total(rest)) : Nat}
      %Equal.sym(Nat, Nat.add(fs, bs), B.Book.total(rest), Laws.sweep_conserves_book(rest, Nat.sub(q, t))) : {Nat.add(Nat.add(t, Nat.sub(l, t)), _) == Nat.add(l, B.Book.total(rest)) : Nat}
      %Equal.sym(Nat, Nat.add(t, Nat.sub(l, t)), l, L.Nat.min_sub_r(q, l)) : {Nat.add(_, B.Book.total(rest)) == Nat.add(l, B.Book.total(rest)) : Nat}
      {==}
