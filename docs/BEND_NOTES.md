# Bend2 working notes (verified against bend 2.0.24)

Read `bend guide` (≈600 lines, the authoritative reference) once. These notes
are the traps we already hit, each verified by compiling a test program.

The binary is `~/.bend/bin/bend` (it is NOT on PATH by default).

## Toolchain

```sh
~/.bend/bin/bend file.bend --check-only      # type/termination check only
~/.bend/bin/bend file.bend -o ../bin/name    # native binary via clang
../bin/name 1000000                          # run; runtime flags go after args
../bin/name 1000000 --threads 1              # force single core
~/.bend/bin/bend base Array                  # print Base defs under a name
```

Do NOT run `main` without `-o`: an IO main is compiled anyway, but a value
main is normalised by the checker (very slow).

## Numbers

- Only `U32` (wrapping), `F32`, `Nat` (loop fuel; compiled to an immediate
  48-bit integer, so `U32.to_nat(n)` is O(1)). No U64, no signed ints.
- Operators need a type annotation and spaces: `(a * b + 1 : U32)`,
  `(x .&. 63 : U32)`, `(x .^. y : U32)`, `(x >> 8n : U32)` (shift amount is
  a `Nat` literal), `(a < b : U32)` returns `Bool`.
- No negative literals: write `F32.neg(0.5)`, not `-0.5`.
- Equality is a call: `U32.is_eq(a, b)`; `==` is only for proofs/types.
- F32: `F32.add sub mul div neg abs sqrt exp log cos sin min max is_lt is_ge…`,
  `U32.to_f32(u)`, `F32.show(x)`.

## Control flow

- There is no `if`. Branch with a helper def that `match`es a `Bool`
  parameter:
  ```python
  def pick(c: Bool, a: U32, b: U32) -> U32:
    match c:
      case True{}:
        a
      case False{}:
        b
  ```
- `match` (and destructuring lets like `(a, v) = x` / `K{..} = x`) only work
  on a **parameter or pattern-bound variable**, never a computed value. Pass a
  computed value to a helper def and destructure it there.
- No mutual recursion (a helper may NOT call back into the loop that called
  it). Loops are single self-recursive defs with `Nat` fuel as the FIRST
  argument that shrinks:
  ```python
  def loop(n: Nat, st: St) -> St:
    match n:
      case 0n:
        st
      case 1n+p:
        loop(p, step(st))        # step is non-recursive
  ```
  Pattern that works: **state record + non-recursive `step(St) -> St` + fuel
  loop**. A `while` becomes fuel = an upper bound on iterations, with a flag or
  a no-op step once done (or `@unsafe def` with free recursion — last resort,
  note it in your report).
- Tail calls compile to loops. Non-tail recursion allocates frames.

## Linearity (affine by default)

- Every variable may be used at most once. Mark `+x` to reuse a `Data` value
  (U32, F32, Bool, Nat, data types): in params `def f(+x: U32)`, in lets
  `+y = ...`, in patterns `St{+a, b}`, in IO binds `+t : Nat <- IO.now()`.
- `Array<T>` and anything containing one must be `is Type` and is never
  copyable. Thread it through every call and return it.

## Arrays (size must be a power of two)

```python
a = [0 : U32*2048n]             # 2048 zeros
a[i] <- v                       # write; as a statement it rebinds a
f(a[i], ...)                    # read: yields a PAIR (Array<U32> & U32)
```

A read hands the array back beside the value, and you cannot destructure the
computed pair in place — pass it to a helper whose parameter is the pair:

```python
def step.got(av: Array<U32> & U32, +i: U32) -> St:
  (a, +v) = av
  a[i] <- (v + 1 : U32)
  St{a, (i + 1 : U32)}

def step(st: St) -> St:
  St{a, +i} = st
  step.got(a[i], i)
```

Indexes wrap modulo the size. `Array` is *typed* as a binary tree
(`ALeaf`/`ANode`), but the native runtime stores it as a flat block (`BUF` of
u32 for `Array<U32>`); `get`/`set`/`swap`/`size` are O(1) intrinsics. Only a
user-written `match` on `ANode` splits (copies) it — never do that on a hot
path.

## Records holding arrays

```python
type Book is Type:              # Type, because it holds an Array
  Book{arr: Array<U32>, bb: U32, ba: U32}
```

## IO, args, timing (copy this shape)

```python
import Base
import ./common.bend as C

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +n : U32 = C.Arg.first(args, 1000000)
    +t0 : Nat <- IO.now()
    r : U32 = kernel(n)
    IO.print("checksum: " ++ U32.show(r))       # forces evaluation
    t1 : Nat <- IO.now()
    IO.print("kernel_ms: " ++ Nat.show(Nat.sub(t1, t0)))
```

## Parallelism

`a b = f(x) g(y)` is a parallel let: both calls may run on different cores.
Build a balanced binary fork tree; leaves should be flat tail loops. An
`Array` cannot go down a fork tree (single owner) — generate data from the
index instead (see `C.Rng.hash`).
