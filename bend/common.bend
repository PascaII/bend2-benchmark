import Base

# Shared helpers for every benchmark. Keep in sync with rust/src/lib.rs.

# LCG step: s * 1664525 + 1013904223 (mod 2^32)
def Rng.next(s: U32) -> U32:
  (s * 1664525 + 1013904223 : U32)

# Stateless 32-bit hash of an index (murmur3 finalizer on i + golden ratio)
def Rng.hash(i: U32) -> U32:
  +a = (i + 2654435769 : U32)
  +b = (a .^. (a >> 16n) : U32)
  +c = (b * 2246822507 : U32)
  +d = (c .^. (c >> 13n) : U32)
  +e = (d * 3266489909 : U32)
  (e .^. (e >> 16n) : U32)

# Uniform in (0, 1]: ((s >> 8) + 1) * 2^-24
def Rng.unit(s: U32) -> F32:
  F32.mul(U32.to_f32(((s >> 8n) + 1 : U32)), 0.000000059604645)

def Arg.or(m: Maybe<&2, U32>, dflt: U32) -> U32:
  match m:
    case Some{v}:
      v
    case None{}:
      dflt

# First command-line argument parsed as U32, or dflt
def Arg.first(args: List<String>, dflt: U32) -> U32:
  match args:
    case Con{s, rest}:
      Arg.or(U32.read(s), dflt)
    case Nil{}:
      dflt
