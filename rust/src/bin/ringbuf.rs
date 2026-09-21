use quantbench::{arg, elapsed_ms, rng_next};
use std::time::Instant;

fn kernel(n: u32) -> u32 {
    let mut buf = [0u32; 64 * 256];
    let mut head = [0u32; 64];
    let mut sum = [0u32; 64];
    let mut sumsq = [0u32; 64];
    let mut signals: u32 = 0;
    let mut acc: u32 = 0;
    let mut s: u32 = 7;

    for _ in 0..n {
        s = rng_next(s);
        let r = s >> 8;
        let k = r & 63;
        let v = (r >> 6) & 4095;
        let h = head[k as usize];
        let idx = (k * 256 + h) as usize;
        let old = buf[idx];
        buf[idx] = v;
        head[k as usize] = (h + 1) & 255;
        sum[k as usize] = sum[k as usize].wrapping_add(v).wrapping_sub(old);
        sumsq[k as usize] = sumsq[k as usize]
            .wrapping_add(v.wrapping_mul(v))
            .wrapping_sub(old.wrapping_mul(old));
        let sumk = sum[k as usize];
        let sumsqk = sumsq[k as usize];
        let threshold = sumk.wrapping_add(sumk >> 2);
        if (v << 8) > threshold {
            signals = signals.wrapping_add(1);
        }
        acc ^= sumk.wrapping_add(sumsqk);
    }

    signals.wrapping_mul(2654435761).wrapping_add(acc)
}

fn main() {
    let n = arg(0, 1_000_000);
    let t0 = Instant::now();
    let r = kernel(n);
    let r = std::hint::black_box(r);
    println!("checksum: {}", r);
    println!("kernel_ms: {}", elapsed_ms(t0));
}
