#!/usr/bin/env python3
"""Shared feature-progress computation used by didio-progress-lib.sh and
didio-log-watcher.sh. Reads the feature README for the planned task list
and logs/agents/*.meta.json for per-task status.

CLI:
  didio-progress.py --root <root> --feature <F01> [--line]
  didio-progress.py --root <root> --all

With --line, prints a single compact status line to stdout; otherwise
prints JSON.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys

_readme_cache: dict[str, tuple[float, list[tuple[str, int]]]] = {}


def _clear_readme_cache() -> None:
    """Clear the module-level README mtime cache (for tests)."""
    _readme_cache.clear()


STATUS_COMPLETED = "completed"
STATUS_RUNNING = "running"
STATUS_FAILED = "failed"
STATUS_PLANNED = "planned"

WAVE_RE = re.compile(r"wave\s*(\d+)", re.IGNORECASE)
GLYPH = {
    STATUS_COMPLETED: "✓",
    STATUS_RUNNING: "▶",
    STATUS_FAILED: "✗",
    STATUS_PLANNED: "·",
}


def load_agents(root: str) -> list[dict]:
    agents = []
    for path in sorted(glob.glob(os.path.join(root, "logs/agents/*.meta.json"))):
        try:
            with open(path) as f:
                agents.append(json.load(f))
        except Exception:
            continue
    return agents


def _planned_tasks(root: str, feature: str) -> list[tuple[str, int]]:
    matches = sorted(glob.glob(os.path.join(root, "tasks/features", f"{feature}-*")))
    if not matches:
        return []
    readme = os.path.join(matches[0], f"{feature}-README.md")
    if not os.path.isfile(readme):
        return []
    mtime = os.path.getmtime(readme)
    cached = _readme_cache.get(readme)
    if cached and cached[0] == mtime:
        return cached[1]
    task_re = re.compile(rf"{feature}-T\d+")
    seen: set[str] = set()
    planned: list[tuple[str, int]] = []
    with open(readme) as f:
        for line in f:
            wm = WAVE_RE.search(line)
            if not wm:
                continue
            wave = int(wm.group(1))
            for tid in task_re.findall(line):
                if tid not in seen:
                    seen.add(tid)
                    planned.append((tid, wave))
    _readme_cache[readme] = (mtime, planned)
    return planned


def compute_feature(feature: str, root: str, agents: list[dict] | None = None) -> dict:
    if agents is None:
        agents = load_agents(root)
    planned = _planned_tasks(root, feature)
    task_wave = {tid: wave for tid, wave in planned}

    latest: dict[str, dict] = {}
    for m in agents:
        if m.get("feature") != feature:
            continue
        tid = m.get("task")
        prev = latest.get(tid)
        if not prev or m.get("started_at", "") > prev.get("started_at", ""):
            latest[tid] = m

    trail: list[dict] = []
    counts = {STATUS_COMPLETED: 0, STATUS_RUNNING: 0, STATUS_FAILED: 0}

    def push(tid: str, wave: int | None, status: str) -> None:
        trail.append({"task": tid, "wave": wave, "status": status})
        if status in counts:
            counts[status] += 1

    for tid, wave in planned:
        meta = latest.get(tid)
        push(tid, wave, meta["status"] if meta else STATUS_PLANNED)
    for tid, meta in latest.items():
        if tid not in task_wave:
            push(tid, None, meta.get("status", STATUS_PLANNED))

    total = len(trail)
    completed = counts[STATUS_COMPLETED]
    percent = int(round(completed / total * 100)) if total else 0

    current_task = current_wave = None
    for priority in (STATUS_RUNNING, STATUS_PLANNED):
        for it in trail:
            if it["status"] == priority:
                current_task, current_wave = it["task"], it["wave"]
                break
        if current_task:
            break

    return {
        "feature": feature,
        "total": total,
        "completed": completed,
        "running": counts[STATUS_RUNNING],
        "failed": counts[STATUS_FAILED],
        "percent": percent,
        "current_wave": current_wave,
        "current_task": current_task,
        "trail": trail,
    }


def known_features(root: str, agents: list[dict]) -> list[str]:
    seen = sorted({a.get("feature") for a in agents if a.get("feature")})
    for d in sorted(glob.glob(os.path.join(root, "tasks/features", "F*-*"))):
        base = os.path.basename(d).split("-", 1)[0]
        if base and base not in seen:
            seen.append(base)
    return seen


def format_line(p: dict) -> str:
    def short(tid: str) -> str:
        return tid.split("-")[-1] if "-" in tid else tid

    chips = [f"{GLYPH.get(i['status'], '?')}{short(i['task'])}" for i in p["trail"]]
    if len(chips) > 12:
        chips = chips[:12] + ["…"]
    wave = f"Wave {p['current_wave']}" if p["current_wave"] is not None else "—"
    cur = f"{p['current_task']} ▶" if p["current_task"] else "done"
    return (
        f"[{p['feature']}] {wave} · {cur} · "
        f"{p['completed']}/{p['total']} done ({p['percent']}%) · "
        + " ".join(chips)
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--feature")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--line", action="store_true", help="print compact line instead of JSON")
    args = ap.parse_args()

    agents = load_agents(args.root)
    if args.all:
        out = [compute_feature(f, args.root, agents) for f in known_features(args.root, agents)]
        print(json.dumps(out))
        return 0
    if not args.feature:
        ap.error("--feature or --all required")
    p = compute_feature(args.feature, args.root, agents)
    print(format_line(p) if args.line else json.dumps(p))
    return 0


if __name__ == "__main__":
    sys.exit(main())
