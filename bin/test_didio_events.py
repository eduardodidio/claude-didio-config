#!/usr/bin/env python3
"""Unit tests for didio-events-lib.py (F01-T11).

Run: python3 bin/test_didio_events.py
"""
import importlib.util
import json
import os
import sys
import tempfile
import unittest

_BIN_DIR = os.path.dirname(os.path.abspath(__file__))
_FIXTURES_DIR = os.path.join(_BIN_DIR, "..", "tests", "fixtures")

_spec = importlib.util.spec_from_file_location(
    "didio_events_lib", os.path.join(_BIN_DIR, "didio-events-lib.py")
)
events_lib = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(events_lib)


def fixture(name: str) -> str:
    return os.path.join(_FIXTURES_DIR, name)


class TestClaudeMapper(unittest.TestCase):
    def test_golden_assistant_text(self):
        ev = events_lib.normalize_event(
            {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": "hi"}]}},
            "claude",
        )
        self.assertEqual(ev["kind"], "assistant")
        self.assertFalse(ev["is_error"])

    def test_tool_result_error_maps_to_error(self):
        ev = events_lib.normalize_event(
            {
                "type": "assistant",
                "message": {
                    "role": "assistant",
                    "content": [{"type": "tool_result", "tool_use_id": "t2", "is_error": True}],
                },
            },
            "claude",
        )
        self.assertEqual(ev["kind"], "error")
        self.assertTrue(ev["is_error"])
        self.assertEqual(len(ev["tool_errors"]), 1)

    def test_result_success(self):
        ev = events_lib.normalize_event(
            {"type": "result", "is_error": False, "result": "done"}, "claude"
        )
        self.assertEqual(ev["kind"], "result")
        self.assertFalse(ev["is_error"])

    def test_result_rate_limit(self):
        ev = events_lib.normalize_event(
            {"type": "result", "is_error": True, "result": "You have hit your limit", "api_error_status": "429"},
            "claude",
        )
        self.assertEqual(ev["kind"], "rate_limit")

    def test_result_real_error(self):
        ev = events_lib.normalize_event(
            {"type": "result", "is_error": True, "result": "boom"}, "claude"
        )
        self.assertEqual(ev["kind"], "error")

    def test_unknown_event_degrades_to_raw(self):
        ev = events_lib.normalize_event({"type": "system", "subtype": "init"}, "claude")
        self.assertEqual(ev["kind"], "raw")


class TestCodexMapper(unittest.TestCase):
    def test_agent_message_maps_to_assistant(self):
        ev = events_lib.normalize_event(
            {"id": "1", "msg": {"type": "agent_message", "message": "hi"}}, "codex"
        )
        self.assertEqual(ev["kind"], "assistant")
        self.assertEqual(ev["text"], "hi")
        self.assertFalse(ev["is_error"])

    def test_error_event_maps_to_error(self):
        ev = events_lib.normalize_event(
            {"id": "2", "msg": {"type": "error", "message": "boom"}}, "codex"
        )
        self.assertEqual(ev["kind"], "error")
        self.assertTrue(ev["is_error"])

    def test_error_with_rate_limit_text_maps_to_rate_limit(self):
        ev = events_lib.normalize_event(
            {"id": "2", "msg": {"type": "error", "message": "You have hit your usage rate limit (429)"}},
            "codex",
        )
        self.assertEqual(ev["kind"], "rate_limit")
        self.assertEqual(ev["api_error_status"], "429")

    def test_exec_command_end_success_and_failure(self):
        ok = events_lib.normalize_event(
            {"id": "3", "msg": {"type": "exec_command_end", "exit_code": 0}}, "codex"
        )
        self.assertEqual(ok["kind"], "tool")
        self.assertFalse(ok["is_error"])

        bad = events_lib.normalize_event(
            {"id": "4", "msg": {"type": "exec_command_end", "exit_code": 1}}, "codex"
        )
        self.assertEqual(bad["kind"], "error")
        self.assertTrue(bad["is_error"])

    def test_unsupported_event_degrades_to_raw(self):
        ev = events_lib.normalize_event({"id": "5", "msg": {"type": "some_new_event"}}, "codex")
        self.assertEqual(ev["kind"], "raw")

    def test_event_without_msg_degrades_to_raw(self):
        ev = events_lib.normalize_event({"id": "6", "no_msg": True}, "codex")
        self.assertEqual(ev["kind"], "raw")


class TestFixtures(unittest.TestCase):
    def test_claude_fixture_golden_tool_error_count(self):
        # claude-stream.jsonl has exactly one tool_result with is_error=true.
        self.assertEqual(events_lib.count_tool_errors(fixture("claude-stream.jsonl"), "claude"), 1)

    def test_claude_fixture_classify_success(self):
        self.assertEqual(events_lib.classify_result(fixture("claude-stream.jsonl"), "claude"), "success")

    def test_codex_fixture_tool_error_count(self):
        # codex-json.jsonl has exactly one exec_command_end with exit_code=1.
        self.assertEqual(events_lib.count_tool_errors(fixture("codex-json.jsonl"), "codex"), 1)

    def test_codex_fixture_classify_success(self):
        self.assertEqual(events_lib.classify_result(fixture("codex-json.jsonl"), "codex"), "success")

    def test_codex_rate_limit_fixture_classify(self):
        self.assertEqual(
            events_lib.classify_result(fixture("codex-json-rate-limit.jsonl"), "codex"), "rate_limit"
        )


class TestToleranceAndDegradation(unittest.TestCase):
    def test_empty_log_returns_unknown_and_zero_errors(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".jsonl", delete=False) as f:
            path = f.name
        try:
            self.assertEqual(events_lib.count_tool_errors(path, "claude"), 0)
            self.assertEqual(events_lib.classify_result(path, "claude"), "unknown")
        finally:
            os.remove(path)

    def test_truncated_last_line_is_skipped_not_crashed(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".jsonl", delete=False) as f:
            f.write(json.dumps({"type": "result", "is_error": False, "result": "done"}) + "\n")
            f.write('{"type": "result", "is_error": fal')  # truncated, no trailing newline
            path = f.name
        try:
            self.assertEqual(events_lib.classify_result(path, "claude"), "success")
            self.assertEqual(events_lib.count_tool_errors(path, "claude"), 0)
        finally:
            os.remove(path)

    def test_missing_file_does_not_crash(self):
        self.assertEqual(events_lib.count_tool_errors("/nonexistent/path.jsonl", "claude"), 0)
        self.assertEqual(events_lib.classify_result("/nonexistent/path.jsonl", "claude"), "unknown")

    def test_get_provider_for_log_defaults_to_claude(self):
        self.assertEqual(events_lib.get_provider_for_log("/nonexistent/run.jsonl"), "claude")

    def test_get_provider_for_log_reads_meta(self):
        with tempfile.TemporaryDirectory() as d:
            log_path = os.path.join(d, "run.jsonl")
            meta_path = os.path.join(d, "run.meta.json")
            with open(meta_path, "w") as f:
                json.dump({"provider": "codex"}, f)
            self.assertEqual(events_lib.get_provider_for_log(log_path), "codex")


if __name__ == "__main__":
    unittest.main()
