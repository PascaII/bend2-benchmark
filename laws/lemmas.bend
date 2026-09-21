import Base

# Nat arithmetic lemmas needed by PROOF.bend (Base ships almost none).

law Nat.add_assoc:
  for a: Nat
  for -b: Nat
  for -c: Nat
  {Nat.add(Nat.add(a, b), c) == Nat.add(a, Nat.add(b, c)) : Nat}

def Nat.add_assoc(a, b, c):
  match a:
    case 0n:
      {==}
    case 1n+p:
      %Nat.add_assoc(p, b, c) : {1n+Nat.add(Nat.add(p, b), c) == 1n+_ : Nat}
      {==}

# min(q, l) + (q - min(q, l)) == q
law Nat.min_sub_l:
  for +q: Nat
  for +l: Nat
  {Nat.add(Nat.min(q, l), Nat.sub(q, Nat.min(q, l))) == q : Nat}

def Nat.min_sub_l(q, l):
  match q l:
    case 0n _:
      {==}
    case 1n+qp 0n:
      {==}
    case 1n+qp 1n+lp:
      %Nat.min_sub_l(qp, lp) : {1n+Nat.add(Nat.min(qp, lp), Nat.sub(qp, Nat.min(qp, lp))) == 1n+_ : Nat}
      {==}

law Nat.add_succ_r:
  for a: Nat
  for -x: Nat
  {Nat.add(a, 1n+x) == 1n+Nat.add(a, x) : Nat}

def Nat.add_succ_r(a, x):
  match a:
    case 0n:
      {==}
    case 1n+p:
      %Nat.add_succ_r(p, x) : {1n+Nat.add(p, 1n+x) == 1n+_ : Nat}
      {==}

# left-commutativity: b + (c + d) == c + (b + d)
law Nat.add_lcomm:
  for b: Nat
  for +c: Nat
  for +d: Nat
  {Nat.add(b, Nat.add(c, d)) == Nat.add(c, Nat.add(b, d)) : Nat}

def Nat.add_lcomm(b, c, d):
  match b:
    case 0n:
      {==}
    case 1n+p:
      %Equal.sym(Nat, Nat.add(c, 1n+Nat.add(p, d)), 1n+Nat.add(c, Nat.add(p, d)), Nat.add_succ_r(c, Nat.add(p, d))) : {1n+Nat.add(p, Nat.add(c, d)) == _ : Nat}
      %Nat.add_lcomm(p, c, d) : {1n+Nat.add(p, Nat.add(c, d)) == 1n+_ : Nat}
      {==}

# (a + b) + (c + d) == (a + c) + (b + d)
law Nat.add_swap_mid:
  for a: Nat
  for +b: Nat
  for +c: Nat
  for +d: Nat
  {Nat.add(Nat.add(a, b), Nat.add(c, d)) == Nat.add(Nat.add(a, c), Nat.add(b, d)) : Nat}

def Nat.add_swap_mid(a, b, c, d):
  match a:
    case 0n:
      Nat.add_lcomm(b, c, d)
    case 1n+p:
      %Nat.add_swap_mid(p, b, c, d) : {1n+Nat.add(Nat.add(p, b), Nat.add(c, d)) == 1n+_ : Nat}
      {==}

# min(q, l) + (l - min(q, l)) == l
law Nat.min_sub_r:
  for +q: Nat
  for +l: Nat
  {Nat.add(Nat.min(q, l), Nat.sub(l, Nat.min(q, l))) == l : Nat}

def Nat.min_sub_r(q, l):
  match q l:
    case 0n 0n:
      {==}
    case 0n 1n+lp:
      {==}
    case 1n+qp 0n:
      {==}
    case 1n+qp 1n+lp:
      %Nat.min_sub_r(qp, lp) : {1n+Nat.add(Nat.min(qp, lp), Nat.sub(lp, Nat.min(qp, lp))) == 1n+_ : Nat}
      {==}
