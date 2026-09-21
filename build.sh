#!/bin/sh
# Build all benchmarks (or those named as args) into bin/<name>_rust and bin/<name>_bend.
set -e
cd "$(dirname "$0")"
BEND="${BEND:-$HOME/.bend/bin/bend}"
mkdir -p bin
NAMES="${*:-orderbook ringbuf blackscholes montecarlo montecarlo_gpu}"
(cd rust && cargo build --release --quiet)
for n in $NAMES; do
  if [ -f "rust/target/release/$n" ]; then cp "rust/target/release/$n" "bin/${n}_rust"; fi
  if [ -f "bend/$n.bend" ]; then (cd bend && "$BEND" "$n.bend" -o "../bin/${n}_bend"); fi
done
ls -la bin
