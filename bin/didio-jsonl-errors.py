#!/usr/bin/env python3
"""Count tool_result events with is_error=true in a JSONL log file.

Usage: didio-jsonl-errors.py <log_file>
Prints a single integer: the count of tool errors found.
Always exits 0 — parse errors are swallowed per line.
"""
import json
import sys


def count_tool_errors(path: str) -> int:
    n = 0
    try:
        with open(path) as f:
            for line in f:
                try:
                    ev = json.loads(line)
                except Exception:
                    continue
                msg = ev.get("message") or {}
                content = msg.get("content")
                if not isinstance(content, list):
                    continue
                for c in content:
                    if (
                        isinstance(c, dict)
                        and c.get("type") == "tool_result"
                        and c.get("is_error")
                    ):
                        n += 1
    except Exception:
        pass
    return n


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(0)
        sys.exit(0)
    print(count_tool_errors(sys.argv[1]))
