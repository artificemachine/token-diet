# docextract / ctxwarn — Document Intercept & Context Warning (no-hook harnesses)

This harness has no `PreToolUse`/`PostToolUse` hook support wired for `token-diet`
(or its schema is unverified — see PLAN-docextract-ctxwarn.md OQ-2/OQ-3), so
these two checks run manually instead of automatically.

## Rule 1 — Extract documents before reading them

Before reading a `.pdf`, `.csv`, `.html`, `.htm`, `.txt`, or `.md` file, run:

```bash
token-diet extract <file>
```

It prints a hash-cached plain-text path — read that instead of the original.
Exit codes: `2` no extractor for this type (binary — read it raw, nothing to do
here), `3` needs `markitdown` (not installed — read it raw), `4` missing file.

## Rule 2 — Check context size periodically

```bash
token-diet budget --check --transcript <session-transcript.jsonl>
```

Prints a warning once per threshold band when the estimate crosses
`.token-budget`'s `ctx_threshold` (default 100000 tokens); silent otherwise.
Always exits 0. Run this occasionally during long sessions, not every turn.
