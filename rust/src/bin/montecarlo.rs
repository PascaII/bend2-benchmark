//! Monte Carlo Asian option pricing. See specs/04_montecarlo.md.

use quantbench::{arg, elapsed_ms, rng_hash, rng_next, rng_unit};
use std::time::Instant;

const S0: f32 = 100.0;
const K: f32 = 100.0;
const STEPS: u32 = 64;
const DRIFT: f32 = 0.00015625;
const VOLSDT: f32 = 0.025;
const TWO_PI: f32 = 6.2831855;
const DISC: f32 = 0.9704455;
const INV_STEPS: f32 = 0.015625;
const LEAF: u32 = 1024;

/// Payoff of a single GBM path (index p), 64 steps, Box-Muller (cos branch).
fn payoff(p: u32) -> f32 {
    let mut x = rng_hash(p);
    let mut s = S0;
    let mut sum_s = 0.0f32;
    for _ in 0..STEPS {
        x = rng_next(x);
        let u1 = rng_unit(x);
        x = rng_next(x);
        let u2 = rng_unit(x);
        let z = ((-2.0f32) * u1.ln()).sqrt() * (TWO_PI * u2).cos();
        s = s * (DRIFT + VOLSDT * z).exp();
        sum_s = sum_s + s;
    }
    let avg = sum_s * INV_STEPS;
    (avg - K).max(0.0)
}

/// Sequential ascending sum of payoff(lo..lo+n), n <= LEAF.
fn leaf(lo: u32, n: u32) -> f32 {
    let mut acc = 0.0f32;
    for p in lo..lo + n {
        acc = acc + payoff(p);
    }
    acc
}

/// Fixed reduction tree, independent of thread count in its shape; the top
/// `par_depth` levels are split across `std::thread::scope`, everything
/// below runs sequentially in the same recursive shape.
fn tree(lo: u32, n: u32, par_depth: u32) -> f32 {
    if n <= LEAF {
        return leaf(lo, n);
    }
    let half = n / 2;
    if par_depth > 0 {
        std::thread::scope(|scope| {
            let handle = scope.spawn(|| tree(lo, half, par_depth - 1));
            let b = tree(lo + half, half, par_depth - 1);
            let a = handle.join().unwrap();
            a + b
        })
    } else {
        let a = tree(lo, half, 0);
        let b = tree(lo + half, half, 0);
        a + b
    }
}

fn log2_pow2(mut t: u32) -> u32 {
    let mut lv = 0;
    while t > 1 {
        t >>= 1;
        lv += 1;
    }
    lv
}

fn kernel(n: u32, threads: u32) -> f32 {
    let par_depth = log2_pow2(threads.max(1));
    let total = tree(0, n, par_depth);
    (total / n as f32) * DISC
}

fn main() {
    let n = arg(0, 65536);
    let threads = arg(1, 1);
    let t0 = Instant::now();
    let r = kernel(n, threads);
    let r = std::hint::black_box(r);
    println!("checksum: {}", r);
    println!("kernel_ms: {}", elapsed_ms(t0));
}
