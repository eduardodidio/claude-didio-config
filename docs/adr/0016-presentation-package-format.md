# ADR-0016: Presentation Package Format

## Status

Accepted

**Date:** 2026-11-27
**Feature:** F38

## Context

The framework has shipped 37 features and needs a presentation package for
the architecture/leadership forum. The package must be version-controlled,
easy to update, and renderable without external services.

## Decision

### Marp-compatible Markdown slides

The slide deck is a single Markdown file with `---` separators and Marp
front matter (`marp: true`). This format:

1. Lives in git alongside the code it describes
2. Can be rendered to PDF/HTML via `marp-cli` or viewed as raw Markdown
3. Speaker notes are embedded as HTML comments (`<!-- -->`)
4. Code blocks render natively — no screenshot rot

### Separate demo script

The live demo script is a separate Markdown file with numbered steps, exact
commands, talking points, and contingency fallbacks. Separating the demo from
the slides allows the presenter to have both open simultaneously.

### docs/presentation/ directory

Presentation assets live in `docs/presentation/` rather than the repo root.
This keeps them discoverable but out of the way of daily development.

## Consequences

### Positive
- Version-controlled — diffs show exactly what changed between presentations
- No PowerPoint/Keynote vendor lock-in
- Speaker notes and demo commands are code-reviewable
- Can be rendered locally without network or SaaS

### Negative
- Marp rendering is optional — without it, the deck is plain Markdown
- No animations or transitions (Marp supports basic ones, but we don't use them)
- Images require file references (no embedded binary blobs in Markdown)
