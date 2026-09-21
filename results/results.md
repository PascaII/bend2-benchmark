| Benchmark | N | Rust 1T (ms) | Bend 1T (ms) | Bend/Rust 1T | Rust 8T (ms) | Bend 8T (ms) | Bend/Rust 8T | Checksums |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| orderbook | 1,000,000 | 10 | 66 | 6.60× | — | — | — | match |
| orderbook | 10,000,000 | 103 | 662 | 6.43× | — | — | — | match |
| orderbook | 50,000,000 | 512 | 3324 | 6.49× | — | — | — | match |
| ringbuf | 10,000,000 | 13 | 15 | 1.15× | — | — | — | match |
| ringbuf | 100,000,000 | 138 | 149 | 1.08× | — | — | — | match |
| ringbuf | 400,000,000 | 554 | 597 | 1.08× | — | — | — | match |
| blackscholes | 262,144 | 59 | 24 | 0.41× | 11 | 6 | 0.55× | match |
| blackscholes | 1,048,576 | 223 | 94 | 0.42× | 42 | 19 | 0.45× | match |
| blackscholes | 4,194,304 | 899 | 377 | 0.42× | 170 | 81 | 0.48× | match |
| montecarlo | 65,536 | 45 | 103 | 2.29× | 9 | 23 | 2.56× | match |
| montecarlo | 262,144 | 175 | 407 | 2.33× | 36 | 78 | 2.17× | match |
| montecarlo | 1,048,576 | 708 | 1611 | 2.28× | 132 | 322 | 2.44× | match |

Kernel time, median of 5 runs after 1 warm-up. Apple M3 (8 cores), bend 2.0.24, rustc 1.91.1 (ed61e7d7e 2025-11-07), Apple clang version 21.0.0 (clang-2100.3.34.2).
