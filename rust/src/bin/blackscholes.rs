//! 03 — Black-Scholes pricing + implied volatility (`blackscholes`)
//!
//! Prices N European calls with Black-Scholes and recovers each option's
//! implied volatility from its price with 8 Newton iterations. Everything is
//! f32 in the exact operation order of specs/03_blackscholes.md, so it agrees
//! bit-for-bit with `bend/blackscholes.bend`.
//!
//! Reduction is the spec's fixed binary tree: the top log2(T) levels are given
//! to threads as contiguous blocks (sequential inside), and the partial sums
//! are combined pairwise in tree order, so the f32 result does not depend on
//! the thread count.

use quantbench::{arg, elapsed_ms, rng_hash};
use std::hint::black_box;
use std::time::Instant;

/// 1 / sqrt(2 * pi)
const PDF_C: f32 = 0.3989422804;

/// Normal pdf: `PDF_C * exp((-0.5 * x) * x)`
#[inline(always)]
fn npdf(x: f32) -> f32 {
    PDF_C * (-0.5 * x * x).exp()
}

/// Normal cdf, Abramowitz & Stegun 26.2.17
#[inline(always)]
fn ncdf(x: f32) -> f32 {
    let ax = x.abs();
    let t = 1.0 / (1.0 + 0.2316419 * ax);
    let poly = t
        * (0.319381530
            + t * (-0.356563782
                + t * (1.781477937
                    + t * (-1.821255978 + t * 1.330274429))));
    let c = 1.0 - npdf(ax) * poly;
    if x >= 0.0 {
        c
    } else {
        1.0 - c
    }
}

/// `d1 = (log(S / K) + (r + (0.5 * sig) * sig) * T) / (sig * sqrt(T))`
#[inline(always)]
fn d1_of(s: f32, k: f32, t: f32, r: f32, sig: f32) -> f32 {
    ((s / k).ln() + (r + 0.5 * sig * sig) * t) / (sig * t.sqrt())
}

/// European call: `S * ncdf(d1) - (K * exp((-r) * T)) * ncdf(d2)`
#[inline(always)]
fn call(s: f32, k: f32, t: f32, r: f32, sig: f32) -> f32 {
    let sqt = t.sqrt();
    let d1 = d1_of(s, k, t, r, sig);
    let d2 = d1 - sig * sqt;
    s * ncdf(d1) - (k * (-r * t).exp()) * ncdf(d2)
}

/// Vega: `(S * npdf(d1)) * sqrt(T)`
#[inline(always)]
fn vega(s: f32, k: f32, t: f32, r: f32, sig: f32) -> f32 {
    let sqt = t.sqrt();
    let d1 = d1_of(s, k, t, r, sig);
    (s * npdf(d1)) * sqt
}

/// `price + sig` for option `i`
#[inline(always)]
fn option_value(i: u32) -> f32 {
    let h = rng_hash(i);
    let s = 100.0f32;
    let r = 0.03f32;
    let k = 90.0 + (h & 63) as f32 * 0.3125;
    let t = 0.25 + ((h >> 6) & 63) as f32 * 0.015625;
    let sig_true = 0.15 + ((h >> 12) & 63) as f32 * 0.005;

    let price = call(s, k, t, r, sig_true);
    let mut sig = 0.3f32;
    for _ in 0..8 {
        let c = call(s, k, t, r, sig);
        let v = vega(s, k, t, r, sig);
        sig = sig - (c - price) / v.max(0.0001);
        sig = sig.max(0.01).min(3.0);
    }
    price + sig
}

/// Leaf: `acc = acc + option_value(i)` for `i` in `lo .. lo + n`, ascending
fn block(lo: u32, n: u32) -> f32 {
    let mut acc = 0.0f32;
    for i in lo..lo + n {
        acc += option_value(i);
    }
    acc
}

/// Sequential part of `tree(lo, n)` (one block of the threaded split)
fn tree_seq(lo: u32, n: u32) -> f32 {
    if n <= 1024 {
        block(lo, n)
    } else {
        let half = n / 2;
        tree_seq(lo, half) + tree_seq(lo + half, half)
    }
}

fn main() {
    let n = arg(0, 65536);
    let threads = arg(1, 1).max(1);

    // Split only where the split is exact: each block must hold a power-of-two
    // number of options >= 1024, so every thread count reduces in the same
    // f32 order as the sequential tree.
    let mut parts = 1u32;
    while parts * 2 <= threads && n % (parts * 2) == 0 && n / (parts * 2) >= 1024 {
        parts *= 2;
    }

    let t0 = Instant::now();
    let size = n / parts;
    let mut partial: Vec<f32> = Vec::with_capacity(parts as usize);
    std::thread::scope(|scope| {
        let mut handles = Vec::with_capacity(parts as usize);
        for p in 0..parts {
            let lo = p * size;
            handles.push(scope.spawn(move || tree_seq(lo, size)));
        }
        for h in handles {
            partial.push(h.join().unwrap());
        }
    });
    // fixed binary tree over the partial sums
    while partial.len() > 1 {
        let mut next = Vec::with_capacity(partial.len() / 2);
        for pair in partial.chunks_exact(2) {
            next.push(pair[0] + pair[1]);
        }
        partial = next;
    }
    let checksum = black_box(partial[0]);
    let ms = elapsed_ms(t0);

    println!("checksum: {}", checksum);
    println!("kernel_ms: {}", ms);
}
