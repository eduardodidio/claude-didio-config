#!/usr/bin/env python3
"""Per-provider JSONL/event normalization (F01-T11).

Maps raw NDJSON events from Claude `stream-json` or Codex `exec --json` into
a common internal shape so error-detection (didio-jsonl-errors.py) and
rate-limit classification (didio-rate-limit-lib.sh) work for both providers.

Common event shape:
    {
        "kind": "assistant" | "tool" | "result" | "error" | "rate_limit"
                | "usage" | "raw",
        "raw": <original parsed JSON object>,
        "is_error": bool,            # present on result/error/rate_limit/tool kinds
        "text": str,                 # best-effort human-readable text, if any
        "tool_errors": [...],        # list of tool_result content blocks with is_error
        "api_error_status": str,     # e.g. "429", if known
    }

The `claude` mapper is a thin pass that preserves today's behavior exactly
(see count_tool_errors / classify_result, which match the pre-existing
didio-jsonl-errors.py / didio-rate-limit-lib.sh logic byte-for-byte for the
claude provider). The `codex` mapper translates Codex `exec --json` events
(keyed off `msg.type`) and degrades unknown event types to kind "raw" rather
than raising — Codex has no analogue for some Claude-only fields (e.g. the
rate-limit reset timestamp embedded in the result text), and consumers must
tolerate that gap (AC4).
"""
import json


def get_provider_for_log(log_path: str) -> str:
    """Read `provider` from the sibling `<log>.meta.json`; default "claude"."""
    if log_path.endswith(".jsonl"):
        meta_path = log_path[: -len(".jsonl")] + ".meta.json"
    else:
        meta_path = log_path + ".meta.json"
    try:
        with open(meta_path) as f:
            meta = json.load(f)
        return meta.get("provider", "claude") or "claude"
    except Exception:
        return "claude"


def _extract_tool_errors(obj: dict) -> list:
    """Return tool_result content blocks with is_error=true (Claude shape)."""
    msg = obj.get("message") or {}
    content = msg.get("content")
    errors = []
    if isinstance(content, list):
        for c in content:
            if (
                isinstance(c, dict)
                and c.get("type") == "tool_result"
                and c.get("is_error")
            ):
                errors.append(c)
    return errors


def _map_claude_event(obj: dict) -> dict:
    t = obj.get("type")
    tool_errors = _extract_tool_errors(obj)

    if t == "result":
        is_error = bool(obj.get("is_error"))
        result_text = str(obj.get("result", ""))
        api_status = str(obj.get("api_error_status", ""))
        kind = "result"
        if is_error:
            if (
                "hit your limit" in result_text
                or "rate_limit" in result_text
                or api_status == "429"
            ):
                kind = "rate_limit"
            else:
                kind = "error"
        return {
            "kind": kind,
            "raw": obj,
            "is_error": is_error,
            "text": result_text,
            "api_error_status": api_status,
            "tool_errors": tool_errors,
        }

    if t == "assistant":
        return {
            "kind": "error" if tool_errors else "assistant",
            "raw": obj,
            "is_error": bool(tool_errors),
            "tool_errors": tool_errors,
        }

    if t == "usage":
        return {"kind": "usage", "raw": obj}

    return {"kind": "raw", "raw": obj, "tool_errors": tool_errors}


def _map_codex_event(obj: dict) -> dict:
    msg = obj.get("msg")
    if not isinstance(msg, dict):
        return {"kind": "raw", "raw": obj}

    mtype = msg.get("type", "")

    if mtype == "agent_message":
        return {
            "kind": "assistant",
            "raw": obj,
            "is_error": False,
            "text": str(msg.get("message", "")),
        }

    if mtype == "error":
        text = str(msg.get("message", ""))
        is_rate_limit = "rate limit" in text.lower() or "429" in text
        return {
            "kind": "rate_limit" if is_rate_limit else "error",
            "raw": obj,
            "is_error": True,
            "text": text,
            "api_error_status": "429" if is_rate_limit else "",
        }

    if mtype == "exec_command_end":
        exit_code = msg.get("exit_code")
        is_error = bool(exit_code)
        return {"kind": "error" if is_error else "tool", "raw": obj, "is_error": is_error}

    if mtype == "token_count":
        return {"kind": "usage", "raw": obj}

    if mtype == "task_complete":
        return {"kind": "result", "raw": obj, "is_error": False, "text": ""}

    # Unknown/unsupported Codex event type — degrade to "raw" (AC4).
    return {"kind": "raw", "raw": obj}


def normalize_event(obj: dict, provider: str = "claude") -> dict:
    """Map one parsed JSONL object to the common internal event shape."""
    if provider == "codex":
        return _map_codex_event(obj)
    return _map_claude_event(obj)


def iter_events(path: str, provider: str = "claude"):
    """Yield normalized events from a JSONL log, tolerating truncated lines."""
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                yield normalize_event(obj, provider)
    except Exception:
        return


def count_tool_errors(path: str, provider: str = "claude") -> int:
    """Count tool-level errors in a JSONL log.

    For `claude`, this matches the original didio-jsonl-errors.py logic
    exactly: count of tool_result content blocks with is_error=true.
    For `codex`, count normalized "error"-kind events (degraded — no
    per-content-block granularity available).
    """
    if provider == "claude":
        n = 0
        try:
            with open(path) as f:
                for line in f:
                    try:
                        obj = json.loads(line)
                    except Exception:
                        continue
                    n += len(_extract_tool_errors(obj))
        except Exception:
            pass
        return n

    n = 0
    for ev in iter_events(path, provider):
        if ev.get("kind") == "error":
            n += 1
    return n


def classify_result(path: str, provider: str = "claude") -> str:
    """Classify the final outcome of a run: rate_limit|real_error|success|unknown.

    Mirrors didio_rl_classify_jsonl: looks at the last result-like event.
    """
    last = None
    for ev in iter_events(path, provider):
        if ev.get("kind") in ("result", "error", "rate_limit"):
            last = ev

    if last is None:
        return "unknown"
    if not last.get("is_error"):
        return "success"
    if last.get("kind") == "rate_limit":
        return "rate_limit"
    return "real_error"


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print(0)
        sys.exit(0)

    log_path = sys.argv[1]
    provider = sys.argv[2] if len(sys.argv) > 2 else get_provider_for_log(log_path)
    print(count_tool_errors(log_path, provider))
