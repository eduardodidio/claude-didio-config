# ADR-0018: Black Hawk Delta Security Agent

## Status

Accepted

**Date:** 2026-11-27
**Feature:** F40

## Context

As agents write more code autonomously, security scanning becomes critical.
The CLAUDE.md guardrails tell agents what NOT to do, but there's no automated
verification that guardrails are followed and no detection of secrets or
dangerous patterns in the codebase.

## Decision

### Follow the Bravo/Charlie scanner pattern

Delta uses the same 4-scanner architecture. This completes the core squad:
Alpha (strategy), Bravo (CI/CD), Charlie (monitoring), Delta (security).

### Four security scanners

1. **Secrets**: file patterns (.env, .pem, .key) + content patterns (API keys, tokens, private keys) with directory skip list
2. **Shell patterns**: dangerous commands in .sh files (eval, rm -rf, curl|bash, chmod 777, --no-verify, force push, reset --hard) — skips test files and comments
3. **Guardrails**: validates CLAUDE.md contains required guardrail keywords
4. **Permissions**: checks .claude/settings.json for overly permissive modes

### Skip test files in shell scanner

Test files may legitimately contain dangerous patterns for testing. The shell
scanner skips any file under `tests/` to avoid false positives.

## Consequences

### Positive
- Automated security scanning without external tools (no Snyk, no Trivy)
- Catches common agent mistakes (committing secrets, dangerous shell patterns)
- Validates guardrails are actually present in CLAUDE.md
- 11 E2E tests with synthetic fixtures

### Negative
- Pattern-based detection has false positives (legitimate uses of eval, etc.)
- No dependency vulnerability scanning (would require package manager integration)
- Content pattern matching is regex-based, not AST-based
