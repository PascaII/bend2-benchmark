#!/usr/bin/env python3
"""Verify and time every benchmark in Rust and Bend.

For each benchmark and size, every variant (language x thread count) must
print the same checksum (exact for integer benchmarks, relative tolerance for
float ones) before its timing is accepted. Reports the median of RUNS
measured runs after one warm-up, both in-program kernel time and wall time.

Usage: python3 bench/run.py [--quick] [--no-build] [names...]
"""

import json
import platform
import statistics
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BIN = ROOT / "bin"
RESULTS = ROOT / "results"
BEND = Path.home() / ".bend/bin/bend"
RUNS = 5
THREADS = 8

# name -> (kind, sizes, parallel)
BENCHES = {
    "orderbook": ("int", [1_000_000, 10_000_000, 50_000_000], False),
    "ringbuf": ("int", [10_000_000, 100_000_000, 400_000_000], False),
    "blackscholes": ("float", [2**18, 2**20, 2**22], True),
    "montecarlo": ("float", [2**16, 2**18, 2**20], True),
}
FLOAT_RTOL = 1e-4


def variants(name, parallel):
    rust, bend = str(BIN / f"{name}_rust"), str(BIN / f"{name}_bend")
    out = [("rust", 1, lambda n: [rust, str(n), "1"]),
           ("bend", 1, lambda n: [bend, str(n), "--threads", "1"])]
    if parallel:
        out += [("rust", THREADS, lambda n: [rust, str(n), str(THREADS)]),
                ("bend", THREADS, lambda n: [bend, str(n), "--threads", str(THREADS)])]
    return out


def run_once(cmd):
    t0 = time.perf_counter()
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    wall = (time.perf_counter() - t0) * 1000
    if p.returncode != 0:
        raise RuntimeError(f"{cmd} exited {p.returncode}: {p.stderr.strip()[:300]}")
    fields = {}
    for line in p.stdout.splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            fields[k.strip()] = v.strip()
    if "checksum" not in fields or "kernel_ms" not in fields:
        raise RuntimeError(f"{cmd}: unexpected output {p.stdout!r}")
    return fields["checksum"], float(fields["kernel_ms"]), wall


def same(kind, a, b):
    if kind == "int":
        return a == b
    fa, fb = float(a), float(b)
    return abs(fa - fb) <= FLOAT_RTOL * max(abs(fa), abs(fb), 1e-30)


def tool_versions():
    def out(cmd):
        try:
            return subprocess.run(cmd, capture_output=True, text=True).stdout.strip()
        except OSError:
            return "?"
    return {
        "bend": out([str(BEND), "version"]),
        "rustc": out(["rustc", "--version"]),
        "clang": out(["clang", "--version"]).splitlines()[0],
        "cpu": out(["sysctl", "-n", "machdep.cpu.brand_string"]),
        "cores": out(["sysctl", "-n", "hw.ncpu"]),
        "os": platform.platform(),
    }


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    quick = "--quick" in sys.argv
    names = args or list(BENCHES)
    if "--no-build" not in sys.argv:
        subprocess.run([str(ROOT / "build.sh"), *names], check=True, capture_output=True)
    runs = 1 if quick else RUNS

    rows = []
    for name in names:
        kind, sizes, parallel = BENCHES[name]
        for n in sizes[:2] if quick else sizes:
            results = []
            for lang, threads, mk in variants(name, parallel):
                cmd = mk(n)
                run_once(cmd)  # warm-up
                samples = [run_once(cmd) for _ in range(runs)]
                checks = {s[0] for s in samples}
                results.append({
                    "bench": name, "n": n, "lang": lang, "threads": threads,
                    "checksum": samples[0][0],
                    "stable": len(checks) == 1,
                    "kernel_ms": statistics.median(s[1] for s in samples),
                    "wall_ms": round(statistics.median(s[2] for s in samples), 1),
                    "kernel_samples": [s[1] for s in samples],
                })
            ref = results[0]["checksum"]
            for r in results:
                r["verified"] = r["stable"] and same(kind, ref, r["checksum"])
                print(f"{name:13} n={n:<9} {r['lang']:4} t={r['threads']} "
                      f"kernel={r['kernel_ms']:>8.0f}ms wall={r['wall_ms']:>8.1f}ms "
                      f"checksum={r['checksum']} {'OK' if r['verified'] else 'MISMATCH'}",
                      flush=True)
            rows += results

    RESULTS.mkdir(exist_ok=True)
    data = {"env": tool_versions(), "runs": runs, "rows": rows}
    (RESULTS / "results.json").write_text(json.dumps(data, indent=2))
    (RESULTS / "results.md").write_text(to_markdown(data))
    print(f"wrote {RESULTS / 'results.md'}")


def to_markdown(data):
    lines = ["| Benchmark | N | Rust 1T (ms) | Bend 1T (ms) | Bend/Rust 1T | "
             f"Rust {THREADS}T (ms) | Bend {THREADS}T (ms) | Bend/Rust {THREADS}T | Checksums |",
             "|---|---:|---:|---:|---:|---:|---:|---:|---|"]
    groups = {}
    for r in data["rows"]:
        groups.setdefault((r["bench"], r["n"]), {})[(r["lang"], r["threads"])] = r

    def cell(r):
        return "—" if r is None else f"{r['kernel_ms']:.0f}"

    def ratio(b, r):
        if not b or not r:
            return "—"
        if r["kernel_ms"] == 0:
            return "n/a"
        return f"{b['kernel_ms'] / r['kernel_ms']:.2f}×"

    for (bench, n), g in groups.items():
        r1, b1 = g.get(("rust", 1)), g.get(("bend", 1))
        rp, bp = g.get(("rust", THREADS)), g.get(("bend", THREADS))
        ok = all(r["verified"] for r in g.values())
        lines.append(f"| {bench} | {n:,} | {cell(r1)} | {cell(b1)} | {ratio(b1, r1)} | "
                     f"{cell(rp)} | {cell(bp)} | {ratio(bp, rp)} | "
                     f"{'match' if ok else 'MISMATCH'} |")
    env = data["env"]
    lines += ["", f"Kernel time, median of {data['runs']} runs after 1 warm-up. "
              f"{env['cpu']} ({env['cores']} cores), {env['bend']}, {env['rustc']}, {env['clang']}."]
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    main()
