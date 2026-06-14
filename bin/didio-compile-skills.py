#!/usr/bin/env python3
"""didio-compile-skills.py — compile skills/*.md into provider artifacts.

See skills/SPEC.md for the neutral skill format. Implements both the Claude
target (F01-T09) and the Codex target (F01-T10): command/role-prompt skills
that target codex are written to ~/.codex/prompts/<name>.md, role-prompts
plus the project's CLAUDE.md are aggregated into AGENTS.md (Codex's CLAUDE.md
analogue), and subagent skills have no Codex analogue so they are skipped
with a logged note.
"""
import argparse
import os
import re
import sys
import tempfile

VALID_KINDS = {"command", "role-prompt", "subagent"}
VALID_TARGETS = {"claude", "codex"}
CLI_TARGETS = {"claude", "codex", "all"}

GENERATED_HEADER_TMPL = (
    "<!-- GENERATED FILE — DO NOT EDIT.\n"
    "     Source: skills/{filename}\n"
    "     Regenerate with: didio compile-skills\n"
    "-->\n"
)

AGENTS_MD_HEADER = (
    "<!-- GENERATED FILE — DO NOT EDIT.\n"
    "     Source: CLAUDE.md + skills/*.md (role-prompt, targets: [codex])\n"
    "     Regenerate with: didio compile-skills --target codex\n"
    "     This is the Codex analogue of CLAUDE.md: project instructions\n"
    "     followed by the role prompts used by didio spawn-agent.\n"
    "-->\n"
)

BLOCK_OPEN_RE = re.compile(r"<!--\s*didio:(claude|codex)\s*-->")
BLOCK_CLOSE_RE = re.compile(r"<!--\s*/didio:(claude|codex)\s*-->")

DROP_KEYS_COMMAND = {"name", "kind", "targets", "role-bindings"}


class SkillError(Exception):
    pass


def parse_front_matter(text, filename):
    """Return (meta, body) or (None, text) if the file has no front-matter."""
    if not text.startswith("---\n"):
        return None, text

    lines = text.splitlines(keepends=True)
    fm_lines = []
    i = 1
    while i < len(lines) and lines[i].rstrip("\n") != "---":
        fm_lines.append(lines[i])
        i += 1
    if i >= len(lines):
        raise SkillError(f"{filename}: unterminated front-matter (missing closing '---')")

    body = "".join(lines[i + 1:])
    meta = parse_simple_yaml(fm_lines, filename)
    return meta, body


def parse_simple_yaml(lines, filename):
    meta = {}
    order = []
    for raw in lines:
        line = raw.rstrip("\n")
        if not line.strip():
            continue
        m = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", line)
        if not m:
            raise SkillError(f"{filename}: malformed front-matter line: {line!r}")
        key, val = m.group(1), m.group(2).strip()
        if val.startswith("[") and val.endswith("]"):
            inner = val[1:-1].strip()
            meta[key] = [v.strip() for v in inner.split(",")] if inner else []
        else:
            meta[key] = val
        order.append(key)
    meta["_order"] = order
    return meta


def validate(meta, filename):
    for req in ("name", "description", "kind", "targets"):
        if req not in meta:
            raise SkillError(f"{filename}: missing required front-matter field '{req}'")
    if meta["kind"] not in VALID_KINDS:
        raise SkillError(
            f"{filename}: invalid kind '{meta['kind']}' (must be one of {sorted(VALID_KINDS)})"
        )
    targets = meta["targets"]
    if not isinstance(targets, list) or not targets:
        raise SkillError(f"{filename}: 'targets' must be a non-empty list")
    for t in targets:
        if t not in VALID_TARGETS:
            raise SkillError(f"{filename}: invalid target '{t}' (must be one of {sorted(VALID_TARGETS)})")


def process_blocks(body, target, filename):
    """Strip/unwrap <!-- didio:X --> override blocks for the given target."""
    lines = body.splitlines(keepends=True)
    out = []
    i = 0
    while i < len(lines):
        line = lines[i]
        m = BLOCK_OPEN_RE.search(line)
        if m:
            block_target = m.group(1)
            j = i + 1
            while j < len(lines) and not BLOCK_CLOSE_RE.search(lines[j]):
                j += 1
            if j >= len(lines):
                raise SkillError(
                    f"{filename}: unbalanced override block '<!-- didio:{block_target} -->' "
                    "(no matching close)"
                )
            if block_target == target:
                out.extend(lines[i + 1:j])
            i = j + 1
            continue
        if BLOCK_CLOSE_RE.search(line):
            raise SkillError(f"{filename}: unmatched closing override marker: {line.strip()}")
        out.append(line)
        i += 1
    return "".join(out)


def output_path(meta, target, output_root, codex_prompts_dir):
    name = meta["name"]
    kind = meta["kind"]
    if target == "claude":
        if kind == "command":
            return os.path.join(output_root, ".claude", "commands", f"{name}.md")
        if kind == "subagent":
            return os.path.join(output_root, ".claude", "agents", f"{name}.md")
        if kind == "role-prompt":
            return os.path.join(output_root, "agents", "prompts", f"{name}.md")
    if target == "codex":
        if kind in ("command", "role-prompt"):
            return os.path.join(codex_prompts_dir, f"{name}.md")
        if kind == "subagent":
            return None  # no Codex analogue — caller logs a skip note
    raise SkillError(f"unsupported target/kind combination: {target}/{kind}")


def render_front_matter(meta, kind, target):
    if target == "codex":
        # Codex prompts are plain markdown bodies, no YAML front-matter.
        return ""
    if kind == "role-prompt":
        return ""
    if kind == "subagent":
        keys = [k for k in ("name", "description") if k in meta]
    else:  # command
        keys = [k for k in meta["_order"] if k not in DROP_KEYS_COMMAND]
    out = ["---\n"]
    for k in keys:
        v = meta[k]
        if isinstance(v, list):
            out.append(f"{k}: [{', '.join(v)}]\n")
        else:
            out.append(f"{k}: {v}\n")
    out.append("---\n")
    return "".join(out)


def compile_for_target(meta, body, target, src_filename):
    kind = meta["kind"]
    processed_body = process_blocks(body, target, src_filename)
    front = render_front_matter(meta, kind, target)
    header = GENERATED_HEADER_TMPL.format(filename=src_filename)
    if front:
        content = front + "\n" + header + "\n" + processed_body.lstrip("\n")
    else:
        content = header + "\n" + processed_body.lstrip("\n")
    return content


def write_atomic(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".compile-skills-")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(content)
        os.replace(tmp_path, path)
    except Exception:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise


def discover_skill_files(skills_dir):
    """Return sorted list of .md files in skills_dir that start with front-matter."""
    result = []
    for fname in sorted(os.listdir(skills_dir)):
        if not fname.endswith(".md"):
            continue
        path = os.path.join(skills_dir, fname)
        with open(path, "r") as f:
            head = f.read(4)
        if head == "---\n":
            result.append(fname)
    return result


def build_agents_md(role_prompts, output_root):
    """Aggregate CLAUDE.md + Codex role-prompt bodies into AGENTS.md content."""
    sections = []
    toc = []

    claude_md = os.path.join(output_root, "CLAUDE.md")
    if os.path.exists(claude_md):
        with open(claude_md, "r") as f:
            project_instructions = f.read().strip("\n")
        toc.append("- [Project Instructions](#project-instructions)")
        sections.append("## Project Instructions\n\n" + project_instructions + "\n")

    for fname, name, body in role_prompts:
        anchor = name.lower()
        toc.append(f"- [{name}](#{anchor})")
        sections.append(f"## {name}\n\n" + body.strip("\n") + "\n")

    parts = [AGENTS_MD_HEADER, "\n# AGENTS.md\n"]
    if toc:
        parts.append("\n## Contents\n\n" + "\n".join(toc) + "\n")
    parts.extend("\n" + s for s in sections)
    return "".join(parts)


def compile_target(target, skill_files, skills_dir, output_root, codex_prompts_dir, dry_run):
    """Compile all skill_files for one target. Returns (changed, role_prompts_for_agents)."""
    changed = []
    role_prompts = []  # (fname, name, processed_body) — codex role-prompts, for AGENTS.md

    for fname in skill_files:
        src_path = os.path.join(skills_dir, fname)
        with open(src_path, "r") as f:
            text = f.read()

        meta, body = parse_front_matter(text, fname)
        if meta is None:
            continue
        validate(meta, fname)
        if target not in meta["targets"]:
            continue

        kind = meta["kind"]

        if target == "codex" and kind == "subagent":
            print(f"[compile-skills] skip codex: {meta['name']} (subagent)")
            continue

        content = compile_for_target(meta, body, target, fname)
        out_path = output_path(meta, target, output_root, codex_prompts_dir)

        if target == "codex" and kind == "role-prompt":
            processed_body = process_blocks(body, target, fname)
            role_prompts.append((fname, meta["name"], processed_body))

        existing = None
        if os.path.exists(out_path):
            with open(out_path, "r") as f:
                existing = f.read()

        if existing == content:
            continue

        changed.append(out_path)
        if dry_run:
            action = "update" if existing is not None else "create"
            print(f"[compile-skills] would {action}: {rel(out_path, output_root, codex_prompts_dir)}")
        else:
            write_atomic(out_path, content)
            print(f"[compile-skills] wrote: {rel(out_path, output_root, codex_prompts_dir)}")

    return changed, role_prompts


def rel(path, output_root, codex_prompts_dir):
    for base in (output_root, codex_prompts_dir):
        try:
            r = os.path.relpath(path, base)
        except ValueError:
            continue
        if not r.startswith(".."):
            return r
    return path


def main(argv):
    parser = argparse.ArgumentParser(description="Compile skills/*.md into provider artifacts")
    parser.add_argument("--skills-dir", default=None, help="Path to skills/ directory")
    parser.add_argument("--output-root", default=None, help="Root to write compiled artifacts under")
    parser.add_argument("--target", default="claude", choices=sorted(CLI_TARGETS),
                         help="Target provider to compile for (default: claude)")
    parser.add_argument("--out-codex", default=None,
                         help="Directory for Codex prompt files (default: ${CODEX_HOME:-$HOME/.codex}/prompts)")
    parser.add_argument("--dry-run", action="store_true", help="Print what would change, write nothing")
    args = parser.parse_args(argv)

    didio_home = os.environ.get("DIDIO_HOME", os.path.expanduser("~/.claude-didio-config"))
    skills_dir = args.skills_dir or os.path.join(didio_home, "skills")
    output_root = args.output_root or didio_home

    codex_home = os.environ.get("CODEX_HOME", os.path.expanduser("~/.codex"))
    codex_prompts_dir = args.out_codex or os.path.join(codex_home, "prompts")

    targets = ["claude", "codex"] if args.target == "all" else [args.target]

    try:
        skill_files = discover_skill_files(skills_dir)
    except OSError as e:
        print(f"[compile-skills] error: {e}", file=sys.stderr)
        return 1

    changed = []
    for target in targets:
        try:
            target_changed, role_prompts = compile_target(
                target, skill_files, skills_dir, output_root, codex_prompts_dir, args.dry_run
            )
        except SkillError as e:
            print(f"[compile-skills] error: {e}", file=sys.stderr)
            return 1
        except OSError as e:
            print(f"[compile-skills] error: {e}", file=sys.stderr)
            return 1

        changed.extend(target_changed)

        if target == "codex":
            try:
                agents_content = build_agents_md(role_prompts, output_root)
                agents_path = os.path.join(output_root, "AGENTS.md")

                existing = None
                if os.path.exists(agents_path):
                    with open(agents_path, "r") as f:
                        existing = f.read()

                if existing != agents_content:
                    changed.append(agents_path)
                    if args.dry_run:
                        action = "update" if existing is not None else "create"
                        print(f"[compile-skills] would {action}: {os.path.relpath(agents_path, output_root)}")
                    else:
                        write_atomic(agents_path, agents_content)
                        print(f"[compile-skills] wrote: {os.path.relpath(agents_path, output_root)}")
            except OSError as e:
                print(f"[compile-skills] error: {e}", file=sys.stderr)
                return 1

    if not changed:
        print("[compile-skills] up to date (no changes)")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
