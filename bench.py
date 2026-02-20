#!/usr/bin/env python3
"""bench.py — Mini benchmark runner

Usage:
    ./bench.py                   # run all benchmarks
    ./bench.py greet             # run a specific benchmark
    ./bench.py greet -n 200      # custom iterations
    ./bench.py greet -n 50 -w 10 # custom warmup
"""

import argparse
import os
import statistics
import subprocess
import sys
from pathlib import Path

# ── config ────────────────────────────────────────────────────────────────────

ROOT = Path(__file__).parent.resolve()
BENCH_DIR = ROOT / "benchmarks"
RXT_BIN = ROOT / "zig-out" / "bin" / "rxt"

# extension → command prefix (use None to skip)
RUNNERS: dict[str, list[str] | None] = {
    "rxt": None,   # filled in after build check
    "lua": ["lua"],
    "py":  ["python3"],
    "js":  ["node"],
    "rb":  ["ruby"],
    "sh":  ["bash"],
}

# ── colours ───────────────────────────────────────────────────────────────────

BOLD   = "\033[1m"
DIM    = "\033[2m"
CYAN   = "\033[36m"
GREEN  = "\033[32m"
YELLOW = "\033[33m"
RED    = "\033[31m"
RESET  = "\033[0m"

def bold(s):   return f"{BOLD}{s}{RESET}"
def dim(s):    return f"{DIM}{s}{RESET}"
def green(s):  return f"{GREEN}{s}{RESET}"
def cyan(s):   return f"{CYAN}{s}{RESET}"
def yellow(s): return f"{YELLOW}{s}{RESET}"
def red(s):    return f"{RED}{s}{RESET}"

# ── build helpers ─────────────────────────────────────────────────────────────

def _zig_sources_newer_than_binary() -> bool:
    """Return True if any .zig source file is newer than the rxt binary."""
    bin_mtime = RXT_BIN.stat().st_mtime
    for src_dir in (ROOT / "rxt" / "src", ROOT / "rx" / "src"):
        for src in src_dir.rglob("*.zig"):
            if src.stat().st_mtime > bin_mtime:
                return True
    return False

def ensure_rxt() -> bool:
    """Build rxt (ReleaseFast) if binary is missing or sources are newer."""
    needs_build = not RXT_BIN.exists() or _zig_sources_newer_than_binary()
    if not needs_build:
        RUNNERS["rxt"] = [str(RXT_BIN)]
        return True
    reason = "not found" if not RXT_BIN.exists() else "sources changed"
    print(yellow(f"rxt binary {reason}, building with zig build -Doptimize=ReleaseFast…"))
    result = subprocess.run(
        ["zig", "build", "-Doptimize=ReleaseFast"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(red("zig build failed — .rxt benchmarks will be skipped."))
        print(dim(result.stderr.strip()))
        RUNNERS["rxt"] = None
        return False
    RUNNERS["rxt"] = [str(RXT_BIN)]
    return True

# ── timing ────────────────────────────────────────────────────────────────────

def run_once_ns(cmd: list[str]) -> int:
    """Run cmd and return wall time in nanoseconds."""
    import time
    start = time.perf_counter_ns()
    subprocess.run(cmd, capture_output=True, check=False)
    return time.perf_counter_ns() - start

def benchmark_file(file: Path, n: int, warmup: int) -> dict | None:
    ext = file.suffix.lstrip(".")
    runner = RUNNERS.get(ext)
    if runner is None:
        return None  # unsupported or deliberately disabled

    cmd = runner + [str(file)]

    # warmup
    for _ in range(warmup):
        subprocess.run(cmd, capture_output=True, check=False)

    samples_ns = [run_once_ns(cmd) for _ in range(n)]
    samples_ms = [t / 1_000_000 for t in samples_ns]

    return {
        "ext":    ext,
        "min":    min(samples_ms),
        "max":    max(samples_ms),
        "mean":   statistics.mean(samples_ms),
        "median": statistics.median(samples_ms),
        "stdev":  statistics.stdev(samples_ms) if len(samples_ms) > 1 else 0.0,
        "n":      n,
    }

# ── display ───────────────────────────────────────────────────────────────────

def fmt_ms(ms: float) -> str:
    return f"{ms:.2f}ms"

def print_result(r: dict) -> None:
    label = f".{r['ext']:<5}"
    print(
        f"  {dim(label)}"
        f"  min={green(fmt_ms(r['min']))}"
        f"  med={cyan(fmt_ms(r['median']))}"
        f"  avg={cyan(fmt_ms(r['mean']))}"
        f"  max={yellow(fmt_ms(r['max']))}"
        f"  σ={dim(fmt_ms(r['stdev']))}"
    )

# ── runner ────────────────────────────────────────────────────────────────────

def run_benchmark(bench_path: Path, n: int, warmup: int) -> None:
    name = bench_path.name
    print(f"\n{bold('▶ ' + name)}  {dim(f'({n} iters, {warmup} warmup)')}")

    files = sorted(f for f in bench_path.iterdir() if f.is_file())
    found = False
    for f in files:
        result = benchmark_file(f, n, warmup)
        if result is None:
            continue
        print_result(result)
        found = True

    if not found:
        print(f"  {red('No supported scripts found.')}")

# ── main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="Benchmark runner")
    parser.add_argument("benchmark", nargs="?", help="Name of benchmark to run (default: all)")
    parser.add_argument("-n", "--iterations", type=int, default=100, help="Number of iterations (default: 100)")
    parser.add_argument("-w", "--warmup",     type=int, default=5,   help="Warmup iterations (default: 5)")
    args = parser.parse_args()

    ensure_rxt()

    if args.benchmark:
        target = BENCH_DIR / args.benchmark
        if not target.is_dir():
            print(red(f"Benchmark '{args.benchmark}' not found in {BENCH_DIR}"))
            sys.exit(1)
        run_benchmark(target, args.iterations, args.warmup)
    else:
        benches = sorted(p for p in BENCH_DIR.iterdir() if p.is_dir())
        if not benches:
            print(yellow(f"No benchmarks found in {BENCH_DIR}"))
            sys.exit(0)
        for bench in benches:
            run_benchmark(bench, args.iterations, args.warmup)

    print(f"\n{bold('Done.')}\n")


if __name__ == "__main__":
    main()
