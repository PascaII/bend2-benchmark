//! Shared helpers for every benchmark. Keep in sync with bend/common.bend.

use std::time::Instant;

/// LCG step: s * 1664525 + 1013904223 (mod 2^32)
#[inline(always)]
pub fn rng_next(s: u32) -> u32 {
    s.wrapping_mul(1664525).wrapping_add(1013904223)
}

/// Stateless 32-bit hash of an index (murmur3 finalizer on i + golden ratio)
#[inline(always)]
pub fn rng_hash(i: u32) -> u32 {
    let a = i.wrapping_add(2654435769);
    let b = a ^ (a >> 16);
    let c = b.wrapping_mul(2246822507);
    let d = c ^ (c >> 13);
    let e = d.wrapping_mul(3266489909);
    e ^ (e >> 16)
}

/// Uniform in (0, 1]: ((s >> 8) + 1) * 2^-24
#[inline(always)]
pub fn rng_unit(s: u32) -> f32 {
    ((s >> 8) + 1) as f32 * 0.000000059604645_f32
}

/// Positional command-line argument `idx` (0-based) parsed as u32, or `dflt`
pub fn arg(idx: usize, dflt: u32) -> u32 {
    std::env::args()
        .nth(idx + 1)
        .and_then(|s| s.parse().ok())
        .unwrap_or(dflt)
}

/// Milliseconds elapsed since `t0`, truncated like Bend's IO.now()
pub fn elapsed_ms(t0: Instant) -> u128 {
    t0.elapsed().as_millis()
}
