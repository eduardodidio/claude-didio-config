#!/usr/bin/env python3
"""didio-poc-pipeline.py — meeting-to-POC orchestrator.

Imports:
    poc_codegen  (T06: mock_gen, ui_gen, app_rewrite)
    poc_finalize (T07: style_step, smoke_step)

Usage: see didio-poc-from-minutes.sh.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

# T06 / T07 modules — present in same dir as this script
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import poc_codegen  # noqa: E402
import poc_finalize  # noqa: E402

import jsonschema  # framework dep

PROJECT_ROOT = Path.cwd()
SCHEMA_PATH = PROJECT_ROOT / "tasks/features/F16-meeting-to-poc/manifest.schema.json"
TEMPLATE_DIR = PROJECT_ROOT / "templates/poc-vite-react"
SPAWN_AGENT = PROJECT_ROOT / "bin/didio-spawn-agent.sh"

EXIT_OK, EXIT_USAGE, EXIT_ATA, EXIT_MANIFEST, \
EXIT_INSTALL, EXIT_SMOKE, EXIT_GIT = 0, 2, 3, 4, 5, 6, 7

STEP_ORDER = ["parse", "scaffold", "mock_gen", "ui_gen",
              "style", "install_smoke", "git"]


def log_step(dest: Path, step: str, ok: bool, msg: str) -> None:
    log_path = dest / "_pipeline" / "log.jsonl"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    entry = {
        "step": step, "ok": ok, "msg": msg,
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    with log_path.open("a") as f:
        f.write(json.dumps(entry) + "\n")


def derive_default_name(ata: Path) -> str:
    text = ata.read_text(errors="replace")
    for line in text.splitlines():
        m = re.match(r"^#\s+(.+?)\s*$", line)
        if m:
            slug = re.sub(r"[^a-z0-9-]+", "-", m.group(1).lower()).strip("-")
            if slug:
                return slug[:50]
    return "poc-" + datetime.now().strftime("%Y%m%d-%H%M%S")


def parse_step(ata: Path, dest: Path) -> dict:
    """Spawn meeting-parser; return parsed manifest dict."""
    manifest_path = dest / "_pipeline" / "manifest.json"
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["POC_MANIFEST_PATH"] = str(manifest_path.resolve())
    cmd = [str(SPAWN_AGENT), "meeting-parser", "F16-poc", str(ata.resolve())]
    proc = subprocess.run(cmd, env=env, cwd=PROJECT_ROOT)
    if proc.returncode != 0 or not manifest_path.exists():
        log_step(dest, "parse", False, "meeting-parser failed or manifest not written")
        raise SystemExit(EXIT_MANIFEST)
    manifest = json.loads(manifest_path.read_text())
    schema = json.loads(SCHEMA_PATH.read_text())
    try:
        jsonschema.validate(manifest, schema)
    except jsonschema.ValidationError as e:
        log_step(dest, "parse", False, f"schema validation failed: {e.message}")
        raise SystemExit(EXIT_MANIFEST)
    # Cross-ref check: data_shape must reference an existing entity
    entity_names = {e["name"] for e in manifest["entities"]}
    for s in manifest["screens"]:
        ds = s.get("data_shape")
        if ds and ds not in entity_names:
            log_step(dest, "parse", False, f"unknown data_shape: {ds}")
            raise SystemExit(EXIT_MANIFEST)
    log_step(dest, "parse", True,
             f"manifest: {len(manifest['screens'])} screens, "
             f"{len(manifest['entities'])} entities")
    return manifest


def scaffold_step(manifest: dict, dest: Path) -> None:
    """Copy template-base, render .tmpl files with {{POC_NAME}}."""
    if not TEMPLATE_DIR.exists():
        log_step(dest, "scaffold", False, f"template dir not found: {TEMPLATE_DIR}")
        raise SystemExit(EXIT_USAGE)
    # Copy everything from template, preserving _pipeline/ (already created)
    for item in TEMPLATE_DIR.iterdir():
        target = dest / item.name
        if item.is_dir():
            shutil.copytree(item, target, dirs_exist_ok=True)
        else:
            shutil.copy2(item, target)
    # Render .tmpl files
    name = manifest["name"]
    for tmpl in dest.rglob("*.tmpl"):
        rendered = tmpl.read_text().replace("{{POC_NAME}}", name)
        out_path = Path(str(tmpl)[:-len(".tmpl")])
        out_path.write_text(rendered)
        tmpl.unlink()
    log_step(dest, "scaffold", True, f"copied template, name={name}")


def git_init_step(dest: Path, manifest: dict) -> None:
    slug = manifest["name"]
    msg = f"scaffold from meeting {slug}"
    cmds = [
        ["git", "init", "-q"],
        ["git", "add", "-A"],
        ["git",
         "-c", "user.name=didio poc-from-minutes",
         "-c", "user.email=poc@didio.local",
         "commit", "-q", "-m", msg],
    ]
    for c in cmds:
        r = subprocess.run(c, cwd=dest, capture_output=True, text=True)
        if r.returncode != 0:
            log_step(dest, "git", False,
                     f"{c[1]} failed: {r.stderr.strip()}")
            raise SystemExit(EXIT_GIT)
    log_step(dest, "git", True, f"committed: {msg}")


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--ata", required=True)
    p.add_argument("--name", default=None)
    p.add_argument("--dest", default=None)
    p.add_argument("--style-ref", default=None)
    p.add_argument("--no-smoke", action="store_true")
    p.add_argument("--stop-after", default=None,
                   choices=STEP_ORDER + [None])
    args = p.parse_args()

    ata = Path(args.ata).resolve()
    if not ata.is_file() or ata.stat().st_size == 0:
        print(f"[didio-poc] ata not found or empty: {ata}", file=sys.stderr)
        return EXIT_ATA

    name = args.name or derive_default_name(ata)
    dest = Path(args.dest or (Path.home() / "Projects" / name)).resolve()
    dest.mkdir(parents=True, exist_ok=True)

    style_ref = args.style_ref
    if style_ref is None:
        cfg = json.loads((PROJECT_ROOT / "didio.config.json").read_text())
        style_ref = cfg.get("poc", {}).get("default_style_ref")

    print(f"[didio-poc] ata={ata}", file=sys.stderr)
    print(f"[didio-poc] dest={dest}", file=sys.stderr)
    print(f"[didio-poc] name={name}", file=sys.stderr)
    print(f"[didio-poc] style_ref={style_ref}", file=sys.stderr)

    def stop(after: str) -> bool:
        return args.stop_after == after

    manifest = parse_step(ata, dest)
    if stop("parse"): return EXIT_OK
    scaffold_step(manifest, dest)
    if stop("scaffold"): return EXIT_OK
    poc_codegen.mock_gen(manifest, dest, log_step)
    if stop("mock_gen"): return EXIT_OK
    poc_codegen.ui_gen(manifest, dest, log_step)
    if stop("ui_gen"): return EXIT_OK
    poc_finalize.style_step(manifest, dest, style_ref, log_step)
    if stop("style"): return EXIT_OK
    if not args.no_smoke:
        cfg = json.loads((PROJECT_ROOT / "didio.config.json").read_text())
        poc_cfg = cfg.get("poc", {})
        poc_finalize.install_and_smoke(
            dest,
            poc_cfg.get("smoke_timeout_secs", 30),
            log_step,
            install_timeout=poc_cfg.get("install_timeout_secs", 180),
            build_timeout=poc_cfg.get("build_timeout_secs", 60),
        )
    else:
        cfg = json.loads((PROJECT_ROOT / "didio.config.json").read_text())
        install_timeout = cfg.get("poc", {}).get("install_timeout_secs", 180)
        # still need npm install for AC2 even with --no-smoke
        poc_finalize.install_only(dest, log_step, install_timeout=install_timeout)
    if stop("install_smoke"): return EXIT_OK
    git_init_step(dest, manifest)

    print(f"[didio-poc] done: {dest}", file=sys.stderr)
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
