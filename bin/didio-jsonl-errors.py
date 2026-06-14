#!/usr/bin/env python3
"""Count tool-level errors in a per-provider JSONL log file.

Usage: didio-jsonl-errors.py <log_file> [provider]
Prints a single integer: the count of tool errors found.
Always exits 0 — parse errors are swallowed per line.

Provider is read from the sibling `<log>.meta.json` ("provider" field) when
not given explicitly; defaults to "claude". Counting is delegated to
didio-events-lib.py so the logic stays in one place across error-detection
and rate-limit classification.
"""
import importlib.util
import os
import sys

_LIB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "didio-events-lib.py")
_spec = importlib.util.spec_from_file_location("didio_events_lib", _LIB_PATH)
_events_lib = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_events_lib)

count_tool_errors = _events_lib.count_tool_errors
get_provider_for_log = _events_lib.get_provider_for_log


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(0)
        sys.exit(0)

    log_path = sys.argv[1]
    provider = sys.argv[2] if len(sys.argv) > 2 else get_provider_for_log(log_path)
    print(count_tool_errors(log_path, provider))
