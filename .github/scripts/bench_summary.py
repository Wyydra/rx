#!/usr/bin/env python3
"""bench_summary.py — Convert bench_results.json to a GitHub Markdown summary.

Usage:
    python3 .github/scripts/bench_summary.py bench_results/results.json >> $GITHUB_STEP_SUMMARY
"""

import json
import sys
from pathlib import Path


def ms(val: float) -> str:
    return f"`{val:.2f}ms`"


def main() -> None:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("bench_results/results.json")
    data = json.loads(path.read_text())

    commit = data.get("commit", "?")[:8]
    ref    = data.get("ref", "?")
    ts     = data.get("timestamp", "?")

    print(f"## 📊 Benchmark Results")
    print(f"")
    print(f"| | |")
    print(f"|---|---|")
    print(f"| **Commit** | `{commit}` |")
    print(f"| **Branch** | `{ref}` |")
    print(f"| **Time** | {ts} |")
    print()

    benchmarks: dict = data.get("benchmarks", {})
    for bench_name, langs in benchmarks.items():
        if not langs:
            continue
        print(f"### `{bench_name}`")
        print()
        print("| Language | Min | Median | Mean | Max | σ |")
        print("|----------|-----|--------|------|-----|---|")
        for r in langs:
            lang = r.get("language", "?")
            print(
                f"| `.{lang}` "
                f"| {ms(r['min_ms'])} "
                f"| {ms(r['median_ms'])} "
                f"| {ms(r['mean_ms'])} "
                f"| {ms(r['max_ms'])} "
                f"| {ms(r['stdev_ms'])} |"
            )
        print()


if __name__ == "__main__":
    main()
