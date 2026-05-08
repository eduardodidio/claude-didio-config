"""POC finalization: style customization, npm install, build, and smoke run."""
from __future__ import annotations

import re
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

DEFAULT_PRIMARY = "265 70% 65%"  # mellon-magic-maker purple
DEFAULT_FONT = "Inter"

# Anchored to :root block to avoid picking up .dark overrides.
PRIMARY_RE = re.compile(
    r":root\s*\{[^}]*?--primary:\s*([0-9.]+\s+[0-9.]+%\s+[0-9.]+%)\s*;",
    re.DOTALL,
)
FONT_RE = re.compile(r"sans:\s*\[\s*['\"]([^'\"]+)['\"]")


def _extract_style(style_ref: Path) -> tuple[str, str]:
    primary = DEFAULT_PRIMARY
    font = DEFAULT_FONT
    css = style_ref / "src" / "index.css"
    cfg = style_ref / "tailwind.config.ts"
    if css.is_file():
        m = PRIMARY_RE.search(css.read_text())
        if m:
            primary = m.group(1).strip()
    if cfg.is_file():
        m = FONT_RE.search(cfg.read_text())
        if m:
            font = m.group(1).strip()
    return primary, font


def style_step(manifest: dict, dest: Path, style_ref: str | None, log_fn) -> None:
    if not style_ref:
        log_fn(dest, "style", True, "no style_ref; using template defaults")
        return
    sr = Path(style_ref).expanduser()
    if not sr.is_dir():
        log_fn(dest, "style", True,
               f"style_ref not found: {sr}; using template defaults")
        return
    primary, font = _extract_style(sr)
    css_path = dest / "src" / "index.css"
    if css_path.is_file():
        css = css_path.read_text()
        new_css = re.sub(
            r"(--primary:\s*)[0-9.]+\s+[0-9.]+%\s+[0-9.]+%(\s*;)",
            rf"\g<1>{primary}\g<2>", css, count=1,
        )
        css_path.write_text(new_css)
    cfg_path = dest / "tailwind.config.ts"
    if cfg_path.is_file():
        tw = cfg_path.read_text()
        new_tw = re.sub(
            r"(sans:\s*\[\s*)['\"][^'\"]+['\"]",
            rf"\g<1>'{font}'", tw, count=1,
        )
        cfg_path.write_text(new_tw)
    log_fn(dest, "style", True, f"primary={primary}, font={font}")


def install_only(dest: Path, log_fn, install_timeout: int = 180) -> None:
    r = subprocess.run(
        ["npm", "install", "--no-fund", "--no-audit"],
        cwd=dest, capture_output=True, text=True, timeout=install_timeout,
    )
    if r.returncode != 0:
        log_fn(dest, "install", False, f"npm install failed: {r.stderr[:500]}")
        raise SystemExit(5)
    log_fn(dest, "install", True, "npm install completed")


def install_and_smoke(
    dest: Path, timeout_secs: int, log_fn,
    install_timeout: int = 180, build_timeout: int = 60,
) -> None:
    install_only(dest, log_fn, install_timeout=install_timeout)
    r = subprocess.run(
        ["npm", "run", "build"],
        cwd=dest, capture_output=True, text=True, timeout=build_timeout,
    )
    if r.returncode != 0:
        log_fn(dest, "build", False, f"vite build failed: {r.stderr[:500]}")
        raise SystemExit(5)
    log_fn(dest, "build", True, "vite build OK")
    dev_log_path = dest / "_pipeline" / "dev.log"
    dev_log_path.parent.mkdir(parents=True, exist_ok=True)
    dev_log = open(dev_log_path, "w")
    dev_proc = subprocess.Popen(
        ["npm", "run", "dev", "--", "--port", "5173", "--host", "127.0.0.1"],
        cwd=dest, stdout=dev_log, stderr=subprocess.STDOUT,
    )
    try:
        url = "http://127.0.0.1:5173/"
        deadline = time.time() + timeout_secs
        ok = False
        while time.time() < deadline:
            try:
                with urllib.request.urlopen(url, timeout=1) as resp:
                    if 200 <= resp.status < 300:
                        ok = True
                        break
            except Exception:
                pass
            time.sleep(1)
        if not ok:
            log_fn(dest, "smoke", False,
                   f"HTTP not 200 within {timeout_secs}s "
                   f"(see {dev_log_path})")
            raise SystemExit(6)
        log_fn(dest, "smoke", True,
               f"HTTP 200 in <={timeout_secs}s on {url}")
    finally:
        dev_proc.terminate()
        try:
            dev_proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            dev_proc.kill()
        dev_log.close()
