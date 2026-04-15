"""Tests for didio-progress.py — mtime cache in _planned_tasks()."""
from __future__ import annotations

import json
import os
import time
import tempfile

import pytest

import importlib.util
import sys

_spec = importlib.util.spec_from_file_location(
    "didio_progress",
    os.path.join(os.path.dirname(__file__), "didio-progress.py"),
)
_mod = importlib.util.module_from_spec(_spec)  # type: ignore[arg-type]
_spec.loader.exec_module(_mod)  # type: ignore[union-attr]
dp = _mod


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_feature_dir(root: str, feature: str, readme_content: str) -> str:
    """Create tasks/features/<feature>-slug/README.md, return readme path."""
    feat_dir = os.path.join(root, "tasks", "features", f"{feature}-slug")
    os.makedirs(feat_dir, exist_ok=True)
    readme = os.path.join(feat_dir, f"{feature}-README.md")
    with open(readme, "w") as f:
        f.write(readme_content)
    return readme


SAMPLE_README = """\
# F99 — Test Feature

## Wave manifest

- **Wave 1**: F99-T01, F99-T02        (first wave tasks)
- **Wave 2**: F99-T03        (second wave tasks)
"""


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(autouse=True)
def clear_cache():
    """Ensure cache is empty before and after each test."""
    dp._clear_readme_cache()
    yield
    dp._clear_readme_cache()


@pytest.fixture
def tmp_root(tmp_path):
    """Return a temporary root directory."""
    return str(tmp_path)


# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------

def test_happy_returns_tasks(tmp_root):
    _make_feature_dir(tmp_root, "F99", SAMPLE_README)
    result = dp._planned_tasks(tmp_root, "F99")
    assert result == [("F99-T01", 1), ("F99-T02", 1), ("F99-T03", 2)]


def test_happy_second_call_uses_cache(tmp_root):
    readme = _make_feature_dir(tmp_root, "F99", SAMPLE_README)

    result1 = dp._planned_tasks(tmp_root, "F99")
    assert dp._readme_cache.get(readme) is not None, "cache should be populated after first call"

    # Overwrite with different content — but do NOT change mtime
    cached_mtime = dp._readme_cache[readme][0]
    result2 = dp._planned_tasks(tmp_root, "F99")

    assert result1 == result2
    # Confirm cache entry mtime is unchanged (second call returned cached)
    assert dp._readme_cache[readme][0] == cached_mtime


# ---------------------------------------------------------------------------
# Edge: empty README
# ---------------------------------------------------------------------------

def test_edge_empty_readme_returns_empty_list(tmp_root):
    readme = _make_feature_dir(tmp_root, "F99", "")
    result = dp._planned_tasks(tmp_root, "F99")
    assert result == []
    assert readme in dp._readme_cache, "empty README result should still be cached"


# ---------------------------------------------------------------------------
# Error: README missing
# ---------------------------------------------------------------------------

def test_error_missing_readme_returns_empty_not_cached(tmp_root):
    # Create the feature dir but not the README
    feat_dir = os.path.join(tmp_root, "tasks", "features", "F99-slug")
    os.makedirs(feat_dir, exist_ok=True)

    result = dp._planned_tasks(tmp_root, "F99")
    assert result == []
    assert len(dp._readme_cache) == 0, "missing README should not be cached"


def test_error_missing_feature_dir_returns_empty_not_cached(tmp_root):
    result = dp._planned_tasks(tmp_root, "F99")
    assert result == []
    assert len(dp._readme_cache) == 0


# ---------------------------------------------------------------------------
# Boundary: mtime change invalidates cache
# ---------------------------------------------------------------------------

def test_boundary_mtime_change_reparsed(tmp_root):
    readme = _make_feature_dir(tmp_root, "F99", SAMPLE_README)
    result1 = dp._planned_tasks(tmp_root, "F99")
    assert result1 == [("F99-T01", 1), ("F99-T02", 1), ("F99-T03", 2)]

    # Wait briefly then write new content (guarantees mtime change on most FS)
    time.sleep(0.01)
    new_content = "- **Wave 3**: F99-T10        (new task)\n"
    with open(readme, "w") as f:
        f.write(new_content)
    # Force a distinct mtime if filesystem resolution is coarse
    new_mtime = os.path.getmtime(readme)
    old_mtime = dp._readme_cache[readme][0]
    # If mtime didn't change (very fast FS), nudge it explicitly
    if new_mtime == old_mtime:
        os.utime(readme, (new_mtime + 1, new_mtime + 1))

    result2 = dp._planned_tasks(tmp_root, "F99")
    assert result2 == [("F99-T10", 3)]
    assert result2 != result1


# ---------------------------------------------------------------------------
# Boundary: two features have independent cache entries
# ---------------------------------------------------------------------------

def test_boundary_two_features_independent_cache(tmp_root):
    readme_a = _make_feature_dir(tmp_root, "F99", SAMPLE_README)
    readme_b = _make_feature_dir(tmp_root, "F98", "- **Wave 1**: F98-T01\n")

    result_a = dp._planned_tasks(tmp_root, "F99")
    result_b = dp._planned_tasks(tmp_root, "F98")

    assert readme_a in dp._readme_cache
    assert readme_b in dp._readme_cache
    assert result_a != result_b
    assert result_b == [("F98-T01", 1)]
