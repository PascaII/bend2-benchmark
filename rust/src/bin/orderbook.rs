//! L2 order book + matching engine benchmark. See specs/01_orderbook.md.

use quantbench::{arg, elapsed_ms, rng_next};
use std::time::Instant;

const TICKS: usize = 1024;

struct Book {
    bid: [u32; TICKS],
    ask: [u32; TICKS],
    best_bid: u32,
    best_ask: u32,
    traded_qty: u32,
    traded_notional: u32,
}

fn scan_down(bid: &[u32; TICKS], p: u32) -> u32 {
    let mut q = p;
    while q > 1 {
        q -= 1;
        if bid[q as usize] > 0 {
            return q;
        }
    }
    0
}

fn scan_up(ask: &[u32; TICKS], p: u32) -> u32 {
    let mut q = p;
    while q < 1022 {
        q += 1;
        if ask[q as usize] > 0 {
            return q;
        }
    }
    1023
}

fn buy(b: &mut Book, limit: u32, mut qty: u32) -> u32 {
    while qty > 0 && b.best_ask <= limit {
        let take = qty.min(b.ask[b.best_ask as usize]);
        b.ask[b.best_ask as usize] -= take;
        qty -= take;
        b.traded_qty = b.traded_qty.wrapping_add(take);
        b.traded_notional = b
            .traded_notional
            .wrapping_add(take.wrapping_mul(b.best_ask));
        if b.ask[b.best_ask as usize] == 0 {
            b.best_ask = scan_up(&b.ask, b.best_ask);
        }
    }
    qty
}

fn sell(b: &mut Book, limit: u32, mut qty: u32) -> u32 {
    while qty > 0 && b.best_bid >= limit {
        let take = qty.min(b.bid[b.best_bid as usize]);
        b.bid[b.best_bid as usize] -= take;
        qty -= take;
        b.traded_qty = b.traded_qty.wrapping_add(take);
        b.traded_notional = b
            .traded_notional
            .wrapping_add(take.wrapping_mul(b.best_bid));
        if b.bid[b.best_bid as usize] == 0 {
            b.best_bid = scan_down(&b.bid, b.best_bid);
        }
    }
    qty
}

fn kernel(n: u32) -> u32 {
    let mut book = Book {
        bid: [0u32; TICKS],
        ask: [0u32; TICKS],
        best_bid: 0,
        best_ask: 1023,
        traded_qty: 0,
        traded_notional: 0,
    };
    let mut s: u32 = 1;

    for _ in 0..n {
        s = rng_next(s);
        let r = s >> 8;
        let kind = r & 15;
        let side = (r >> 4) & 1;
        let off = (r >> 5) & 31;
        let qty = ((r >> 10) & 63) + 1;
        let price = if side == 0 { 496 + off } else { 497 + off };

        if kind < 10 {
            // LIMIT order
            if side == 0 {
                let rem = buy(&mut book, price, qty);
                if rem > 0 {
                    book.bid[price as usize] += rem;
                    if price > book.best_bid {
                        book.best_bid = price;
                    }
                }
            } else {
                let rem = sell(&mut book, price, qty);
                if rem > 0 {
                    book.ask[price as usize] += rem;
                    if price < book.best_ask {
                        book.best_ask = price;
                    }
                }
            }
        } else if kind < 13 {
            // MARKET order; remainder discarded
            if side == 0 {
                buy(&mut book, 1022, qty);
            } else {
                sell(&mut book, 1, qty);
            }
        } else {
            // CANCEL
            if side == 0 {
                let d = book.bid[price as usize].min(qty);
                book.bid[price as usize] -= d;
                if book.bid[price as usize] == 0 && price == book.best_bid {
                    book.best_bid = scan_down(&book.bid, price);
                }
            } else {
                let d = book.ask[price as usize].min(qty);
                book.ask[price as usize] -= d;
                if book.ask[price as usize] == 0 && price == book.best_ask {
                    book.best_ask = scan_up(&book.ask, price);
                }
            }
        }
    }

    book.traded_qty
        .wrapping_mul(31)
        .wrapping_add(book.traded_notional)
        .wrapping_add(book.best_bid.wrapping_mul(7))
        .wrapping_add(book.best_ask)
}

fn main() {
    let n = arg(0, 1_000_000);
    let t0 = Instant::now();
    let r = kernel(n);
    let r = std::hint::black_box(r);
    println!("checksum: {}", r);
    println!("kernel_ms: {}", elapsed_ms(t0));
}
