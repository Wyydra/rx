#!/usr/bin/env python3
"""bench_ci.py — Benchmark runner with JSON output for CI artifact storage.

Outputs a single JSON file (bench_results.json) with:
  - git commit SHA & timestamp
  - per-benchmark, per-language results (min/median/mean/max/stdev in ms)

Usage:
    python3 bench_ci.py
    python3 bench_ci.py --output results/bench_$(git rev-parse --short HEAD).json
    python3 bench_ci.py -n 50 -w 5
"""

import argparse
import json
import os
import statistics
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

# ── config ────────────────────────────────────────────────────────────────────

ROOT      = Path(__file__).parent.resolve()
BENCH_DIR = ROOT / "benchmarks"
RXT_BIN   = ROOT / "zig-out" / "bin" / "rxt"

RUNNERS: dict[str, list[str] | None] = {
    "rxt": None,   # filled in after build
    "lua": ["lua"],
    "py":  ["python3"],
    "js":  ["node"],
}

# ── git helpers ───────────────────────────────────────────────────────────────

def git_sha() -> str:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
        ).strip()
    except Exception:
        return "unknown"

def git_ref() -> str:
    """Return branch name or tag, e.g. 'main' or 'refs/tags/v1.0'."""
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=ROOT, text=True
        ).strip()
    except Exception:
        return "unknown"

# ── build ─────────────────────────────────────────────────────────────────────

def ensure_rxt() -> bool:
    needs_build = not RXT_BIN.exists()
    if not needs_build:
        bin_mtime = RXT_BIN.stat().st_mtime
        for src_dir in (ROOT / "rxt" / "src", ROOT / "rx" / "src"):
            for src in src_dir.rglob("*.zig"):
                if src.stat().st_mtime > bin_mtime:
                    needs_build = True
                    break

    if not needs_build:
        RUNNERS["rxt"] = [str(RXT_BIN)]
        return True

    print("[bench_ci] Building rxt (ReleaseFast)…", flush=True)
    result = subprocess.run(
        ["zig", "build", "-Doptimize=ReleaseFast"],
        cwd=ROOT,
        capture_output=False,   # show output in CI logs
    )
    if result.returncode != 0:
        print("[bench_ci] zig build failed — .rxt benchmarks will be skipped.")
        RUNNERS["rxt"] = None
        return False
    RUNNERS["rxt"] = [str(RXT_BIN)]
    return True

# ── timing ────────────────────────────────────────────────────────────────────

def run_once_ns(cmd: list[str]) -> int:
    start = time.perf_counter_ns()
    subprocess.run(cmd, capture_output=True, check=False)
    return time.perf_counter_ns() - start

def benchmark_file(file: Path, n: int, warmup: int) -> dict | None:
    ext    = file.suffix.lstrip(".")
    runner = RUNNERS.get(ext)
    if runner is None:
        return None

    cmd = runner + [str(file)]

    # warmup
    for _ in range(warmup):
        subprocess.run(cmd, capture_output=True, check=False)

    samples_ns = [run_once_ns(cmd) for _ in range(n)]
    samples_ms = [t / 1_000_000 for t in samples_ns]

    return {
        "language": ext,
        "iterations": n,
        "warmup": warmup,
        "min_ms":    round(min(samples_ms), 4),
        "max_ms":    round(max(samples_ms), 4),
        "mean_ms":   round(statistics.mean(samples_ms), 4),
        "median_ms": round(statistics.median(samples_ms), 4),
        "stdev_ms":  round(statistics.stdev(samples_ms) if len(samples_ms) > 1 else 0.0, 4),
    }

# ── main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="CI benchmark runner (JSON output)")
    parser.add_argument("benchmark",    nargs="?",      help="Run a single benchmark by name (default: all)")
    parser.add_argument("-n", "--iterations", type=int, default=100, help="Iterations (default: 100)")
    parser.add_argument("-w", "--warmup",     type=int, default=5,   help="Warmup iterations (default: 5)")
    parser.add_argument("-o", "--output",     default="bench_results.json", help="Output JSON file")
    args = parser.parse_args()

    ensure_rxt()

    # discover benchmarks
    if args.benchmark:
        target = BENCH_DIR / args.benchmark
        if not target.is_dir():
            print(f"[bench_ci] ERROR: benchmark '{args.benchmark}' not found in {BENCH_DIR}")
            sys.exit(1)
        bench_dirs = [target]
    else:
        bench_dirs = sorted(p for p in BENCH_DIR.iterdir() if p.is_dir())

    results: dict = {
        "commit":    git_sha(),
        "ref":       git_ref(),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "benchmarks": {},
    }

    for bench_dir in bench_dirs:
        name   = bench_dir.name
        files  = sorted(f for f in bench_dir.iterdir() if f.is_file())
        langs: list[dict] = []

        print(f"[bench_ci] ▶ {name}  ({args.iterations} iters, {args.warmup} warmup)")
        for f in files:
            r = benchmark_file(f, args.iterations, args.warmup)
            if r is None:
                continue
            langs.append(r)
            print(f"  .{r['language']:<5}  median={r['median_ms']}ms  mean={r['mean_ms']}ms  σ={r['stdev_ms']}ms")

        results["benchmarks"][name] = langs

    # write JSON
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(results, indent=2))
    print(f"\n[bench_ci] Results written to {out}")


if __name__ == "__main__":
    main()
