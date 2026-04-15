#!/usr/bin/env python3
"""Persistent watcher loop for didio-log-watcher.sh.

Runs every 1 s, aggregates logs/agents/*.meta.json into state.json.
No-op guard: skips os.replace when agents+features payload is identical
to the previous tick.  generated_at is only updated on real changes.
"""
from __future__ import annotations

import importlib.util
import json
import os
import sys
import time
from datetime import datetime, timezone


def _load_progress(progress_py: str):
    spec = importlib.util.spec_from_file_location("didio_progress", progress_py)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main() -> None:
    if len(sys.argv) < 3:
        print(
            "Usage: didio-log-watcher-loop.py <state_file> <project_root> [<progress_py>]",
            file=sys.stderr,
        )
        sys.exit(1)

    state_file = sys.argv[1]
    root = sys.argv[2]

    # Prefer explicit progress_py arg; fall back to sibling script.
    if len(sys.argv) >= 4:
        progress_py = sys.argv[3]
    else:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        progress_py = os.path.join(script_dir, "didio-progress.py")

    progress = _load_progress(progress_py)

    # In-memory string of previous agents+features payload (excludes
    # generated_at).  None on first tick → always writes.
    prev_payload: str | None = None

    while True:
        try:
            agents = progress.load_agents(root)
            features = [
                progress.compute_feature(f, root, agents)
                for f in progress.known_features(root, agents)
            ]

            # Canonical JSON for comparison (sort_keys for determinism).
            state_core = {"agents": agents, "features": features}
            payload_str = json.dumps(state_core, sort_keys=True)

            # Write only when payload changed or state.json was deleted.
            if payload_str != prev_payload or not os.path.exists(state_file):
                state = {
                    "generated_at": datetime.now(timezone.utc).strftime(
                        "%Y-%m-%dT%H:%M:%SZ"
                    ),
                    **state_core,
                }
                tmp = state_file + ".tmp"
                with open(tmp, "w") as fh:
                    json.dump(state, fh, indent=2)
                os.replace(tmp, state_file)
                prev_payload = payload_str

        except Exception as exc:
            # Keep running on transient errors (e.g. partial meta.json write).
            print(f"[watcher] tick error: {exc}", file=sys.stderr)

        time.sleep(1)


if __name__ == "__main__":
    main()
