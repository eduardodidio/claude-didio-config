#!/usr/bin/env python3
"""F03 benchmark — measures speedup from the mtime-based README cache in
didio-progress.py.

Methodology:
  - Creates a temp workspace with 6 fake features (each with a README and
    several .meta.json files).
  - Benchmarks two levels:
    a) _planned_tasks() directly — isolates the README cache effect.
    b) compute_feature() — end-to-end, includes agent iteration overhead.
  - For each, compares cache-cold (cache cleared each iteration) vs cache-warm.
  - Prints a comparison table and asserts cache-warm < 50% of cache-cold for
    _planned_tasks (the primary cache target).
"""
from __future__ import annotations

import importlib.util
import json
import os
import sys
import tempfile
import time
from pathlib import Path

# ─── Load module ──────────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
BIN_DIR = SCRIPT_DIR.parent / "bin"
PROGRESS_PY = BIN_DIR / "didio-progress.py"

spec = importlib.util.spec_from_file_location("didio_progress", PROGRESS_PY)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

# ─── Workspace setup ──────────────────────────────────────────────────────────

def make_workspace(tmp: str, n_features: int = 6, tasks_per: int = 40) -> None:
    """Create fake features, READMEs, and .meta.json files.

    tasks_per controls README size: larger values make the file-read cost
    more significant relative to Python overhead, giving a clearer cache
    benefit signal.
    """
    for i in range(1, n_features + 1):
        fid = f"F{i:02d}"
        name = f"feature-{i}"
        fdir = Path(tmp) / "tasks" / "features" / f"{fid}-{name}"
        fdir.mkdir(parents=True, exist_ok=True)

        readme = fdir / f"{fid}-README.md"
        task_ids = [f"{fid}-T{j:02d}" for j in range(1, tasks_per + 1)]
        # Spread tasks across several waves so the README has many lines.
        waves: list[str] = []
        chunk = 5
        for w, start in enumerate(range(0, len(task_ids), chunk)):
            chunk_ids = task_ids[start : start + chunk]
            waves.append(f"- **Wave {w}**: {', '.join(chunk_ids)}")

        lines = [
            f"# {fid} — {name}",
            "",
            "## Goal",
            f"This is a fake feature with {tasks_per} tasks for benchmarking.",
            "",
            "## Wave manifest",
            "",
        ] + waves
        readme.write_text("\n".join(lines))

        # Create a few .meta.json files
        log_dir = Path(tmp) / "logs" / "agents"
        log_dir.mkdir(parents=True, exist_ok=True)
        statuses = ["completed", "completed", "running", "planned", "planned"]
        # Only create meta for first 5 tasks to keep load_agents fast.
        for j, tid in enumerate(task_ids[:5]):
            meta = {
                "feature": fid,
                "task": tid,
                "status": statuses[j % len(statuses)],
                "started_at": f"2026-04-14T10:{j:02d}:00Z",
            }
            (log_dir / f"{fid}-{tid}.meta.json").write_text(json.dumps(meta))


# ─── Benchmark helpers ────────────────────────────────────────────────────────

def bench_planned_cold(root: str, feature: str, n: int = 200) -> float:
    """_planned_tasks, cache cleared each call — measures raw file-read cost."""
    t0 = time.perf_counter()
    for _ in range(n):
        mod._clear_readme_cache()
        mod._planned_tasks(root, feature)
    return time.perf_counter() - t0


def bench_planned_warm(root: str, feature: str, n: int = 200) -> float:
    """_planned_tasks, cache warm — measures cache-hit cost (mtime check only)."""
    # Pre-warm
    mod._clear_readme_cache()
    mod._planned_tasks(root, feature)
    t0 = time.perf_counter()
    for _ in range(n):
        mod._planned_tasks(root, feature)
    return time.perf_counter() - t0


def bench_compute_cold(root: str, feature: str, n: int = 100) -> float:
    """compute_feature, cache cleared each call — full overhead including agent iteration."""
    agents = mod.load_agents(root)
    t0 = time.perf_counter()
    for _ in range(n):
        mod._clear_readme_cache()
        mod.compute_feature(feature, root, agents)
    return time.perf_counter() - t0


def bench_compute_warm(root: str, feature: str, n: int = 100) -> float:
    """compute_feature with warm cache — README parse skipped."""
    agents = mod.load_agents(root)
    # Pre-warm
    mod._clear_readme_cache()
    mod.compute_feature(feature, root, agents)
    t0 = time.perf_counter()
    for _ in range(n):
        mod.compute_feature(feature, root, agents)
    return time.perf_counter() - t0


def bench_all_cold(root: str, n: int = 20) -> float:
    """All features × N iters, cache cleared each outer iteration."""
    agents = mod.load_agents(root)
    features = mod.known_features(root, agents)
    t0 = time.perf_counter()
    for _ in range(n):
        mod._clear_readme_cache()
        for f in features:
            mod.compute_feature(f, root, agents)
    return time.perf_counter() - t0


def bench_all_warm(root: str, n: int = 20) -> float:
    """All features × N iters, cache persists — typical long-running watcher."""
    agents = mod.load_agents(root)
    features = mod.known_features(root, agents)
    # Pre-warm all features
    mod._clear_readme_cache()
    for f in features:
        mod.compute_feature(f, root, agents)
    t0 = time.perf_counter()
    for _ in range(n):
        for f in features:
            mod.compute_feature(f, root, agents)
    return time.perf_counter() - t0


# ─── Main ─────────────────────────────────────────────────────────────────────

def main() -> int:
    N_PLANNED = 200   # _planned_tasks iterations
    N_SINGLE = 100    # compute_feature single-feature iterations
    N_ALL = 20        # all-features outer iterations
    TASKS_PER = 40    # tasks per README (controls file size / parse cost)

    all_pass = True

    with tempfile.TemporaryDirectory() as tmp:
        make_workspace(tmp, n_features=6, tasks_per=TASKS_PER)

        agents = mod.load_agents(tmp)
        features = mod.known_features(tmp, agents)
        print(
            f"Workspace: {len(features)} features, {TASKS_PER} tasks/feature"
        )
        print(
            f"Iterations: _planned_tasks N={N_PLANNED}, "
            f"compute_feature N={N_SINGLE}, all-features N={N_ALL}"
        )
        print()

        # ── 1. _planned_tasks benchmarks ──────────────────────────────────────
        print(f"1. _planned_tasks benchmarks (N={N_PLANNED})")
        print(f"   The cache eliminates the README file-read on repeat calls.")
        print(f"   {'Feature':<8} {'Cold (ms)':<14} {'Warm (ms)':<14} {'Ratio':<10} {'Pass?'}")
        print("   " + "-" * 56)

        for feat in features:
            cold_s = bench_planned_cold(tmp, feat, N_PLANNED)
            warm_s = bench_planned_warm(tmp, feat, N_PLANNED)
            ratio = warm_s / cold_s if cold_s > 0 else 0.0
            ok = ratio < 0.50
            if not ok:
                all_pass = False
            print(
                f"   {feat:<8} {cold_s * 1000:<14.2f} {warm_s * 1000:<14.2f}"
                f" {ratio:<10.3f} {'OK' if ok else 'FAIL (>50%)'}"
            )

        print()

        # ── 2. compute_feature benchmarks ─────────────────────────────────────
        print(f"2. compute_feature benchmarks (N={N_SINGLE})")
        print(f"   Includes agent iteration overhead — absolute ratio is higher.")
        print(f"   {'Feature':<8} {'Cold (ms)':<14} {'Warm (ms)':<14} {'Ratio':<10}")
        print("   " + "-" * 48)

        for feat in features:
            cold_s = bench_compute_cold(tmp, feat, N_SINGLE)
            warm_s = bench_compute_warm(tmp, feat, N_SINGLE)
            ratio = warm_s / cold_s if cold_s > 0 else 0.0
            print(
                f"   {feat:<8} {cold_s * 1000:<14.2f} {warm_s * 1000:<14.2f}"
                f" {ratio:<10.3f}"
            )

        print()

        # ── 3. All-features benchmarks ─────────────────────────────────────────
        print(
            f"3. All-features benchmarks ({len(features)} features × {N_ALL} outer iters)"
        )
        all_cold_s = bench_all_cold(tmp, N_ALL)
        all_warm_s = bench_all_warm(tmp, N_ALL)
        all_ratio = all_warm_s / all_cold_s if all_cold_s > 0 else 0.0
        print(f"   Cold total: {all_cold_s * 1000:.2f} ms")
        print(f"   Warm total: {all_warm_s * 1000:.2f} ms")
        print(f"   Ratio:      {all_ratio:.3f}")
        print()

    if all_pass:
        print("BENCHMARK PASS: _planned_tasks cache-warm loops < 50% of cache-cold.")
        return 0
    else:
        print("BENCHMARK FAIL: _planned_tasks did not achieve >= 2× speedup.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
