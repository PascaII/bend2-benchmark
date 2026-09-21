import Base
import ./common.bend as C

# Multi-symbol fixed-size ring buffer. See specs/02_ringbuf.md.
# Separate arrays: buf[64*256], head[64], sum[64], sumsq[64].

type St is Type:
  St{buf: Array<U32>, head: Array<U32>, sum: Array<U32>, sumsq: Array<U32>,
     signals: U32, acc: U32, s: U32}

def Bool.if_then(c: Bool, a: U32, b: U32) -> U32:
  match c:
    case True{}:
      a
    case False{}:
      b

## tick: one RNG-driven update, threaded through the four arrays one read at a time

def tick.gotsumsq(qv: Array<U32> & U32, buf2: Array<U32>, head2: Array<U32>, sum2: Array<U32>, +k: U32, +v: U32, +old: U32, +sum_k: U32, +signals: U32, acc: U32, s2: U32) -> St:
  (sumsq, +old_sq) = qv
  +sumsq_k = (old_sq + (v * v : U32) - (old * old : U32) : U32)
  sumsq2 = sumsq[k] <- sumsq_k
  +threshold = (sum_k + (sum_k >> 2n) : U32)
  is_breakout = U32.is_gt((v << 8n : U32), threshold)
  new_signals = Bool.if_then(is_breakout, (signals + 1 : U32), signals)
  new_acc = (acc .^. (sum_k + sumsq_k : U32) : U32)
  St{buf2, head2, sum2, sumsq2, new_signals, new_acc, s2}

def tick.gotsum(sv: Array<U32> & U32, buf2: Array<U32>, head2: Array<U32>, sumsq: Array<U32>, +k: U32, +v: U32, +old: U32, signals: U32, acc: U32, s2: U32) -> St:
  (sum, +old_sum) = sv
  +sum_k = (old_sum + v - old : U32)
  sum2 = sum[k] <- sum_k
  tick.gotsumsq(sumsq[k], buf2, head2, sum2, k, v, old, sum_k, signals, acc, s2)

def tick.gotbuf(bv: Array<U32> & U32, head2: Array<U32>, sum: Array<U32>, sumsq: Array<U32>, +idx: U32, +k: U32, +v: U32, signals: U32, acc: U32, s2: U32) -> St:
  (buf, +old) = bv
  buf2 = buf[idx] <- v
  tick.gotsum(sum[k], buf2, head2, sumsq, k, v, old, signals, acc, s2)

def tick.gothead(hv: Array<U32> & U32, buf: Array<U32>, sum: Array<U32>, sumsq: Array<U32>, +k: U32, +v: U32, signals: U32, acc: U32, s2: U32) -> St:
  (head, +h) = hv
  head2 = head[k] <- ((h + 1 : U32) .&. 255 : U32)
  +idx = (k * 256 + h : U32)
  tick.gotbuf(buf[idx], head2, sum, sumsq, idx, k, v, signals, acc, s2)

def tick(st: St) -> St:
  match st:
    case St{buf, head, sum, sumsq, signals, acc, s}:
      +s2 = C.Rng.next(s)
      +r = (s2 >> 8n : U32)
      +k = (r .&. 63 : U32)
      v = ((r >> 6n) .&. 4095 : U32)
      tick.gothead(head[k], buf, sum, sumsq, k, v, signals, acc, s2)

def loop(n: Nat, st: St) -> St:
  match n:
    case 0n:
      st
    case 1n+p:
      loop(p, tick(st))

def checksum(st: St) -> U32:
  match st:
    case St{buf, head, sum, sumsq, +signals, +acc, s}:
      (signals * 2654435761 + acc : U32)

def kernel(n: U32) -> U32:
  buf : Array<U32> = [0 : U32*16384n]
  head : Array<U32> = [0 : U32*64n]
  sum : Array<U32> = [0 : U32*64n]
  sumsq : Array<U32> = [0 : U32*64n]
  init : St = St{buf, head, sum, sumsq, (0 : U32), (0 : U32), (7 : U32)}
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
