# BUG: ICM SessionStart hook survives token-diet uninstall

**Date:** 2026-09-22  
**Status:** Confirmed  
**Tracker:** Not created; this report is the required local residue.

## Problem

`scripts/uninstall.sh --force` removes ICM MCP registrations but leaves the Claude
Code `SessionStart` hook `icm hook start 2>/dev/null || true` in the user settings.
That command relies on `icm` being on the non-interactive hook `PATH`. It is not,
and `|| true` suppresses the failure on every session start.

## Evidence

- `icm doctor` reports: `[Claude Code] SessionStart ✗ icm (missing)`.
- The user settings retain the `SessionStart` command above.
- `scripts/uninstall.sh` removes only the token-diet `PreToolUse` and `PostToolUse`
  hook entries. It has no removal for the ICM `SessionStart` entry.
- The uninstaller's ICM selection logic can classify a hook command containing
  `icm`; the missing operation is the `SessionStart` removal itself.

## Expected behavior

Uninstalling the `icm` component removes only ICM-owned `SessionStart` hook entries
while preserving unrelated entries. A completed uninstall leaves no silently failing
ICM hook behind.

## Acceptance

1. Add a sandboxed regression test with an ICM `SessionStart` entry and an unrelated
   entry in the same config.
2. After `uninstall.sh --only icm --force`, the ICM entry is absent and the unrelated
   entry remains.
3. `icm doctor` no longer reports a missing ICM hook after the uninstall.

## Scope boundary

This does not configure ICM for Codex. Registering ICM as a Codex MCP server and
restarting a Codex session are separate setup actions.

## Build outcome — 2026-09-22

- Implemented: acceptance criteria 1 and 2. `scripts/uninstall.sh` now calls the existing `remove_hook_entry "$HOME/.claude/settings.json" "SessionStart" "icm hook start 2>/dev/null || true"` in the Claude Code section (after the `remove_json_key` calls); the helper already gates itself through `td_component_of` (`*icm*` → `icm`), so `--only`/`--skip` are honoured. Two new tests in `tests/install.bats`: removal with an unrelated SessionStart entry preserved, and preservation when `icm` is out of scope.
- Validation: RED observed first (`AssertionError: ICM SessionStart hook survived uninstall: ['echo unrelated', 'icm hook start 2>/dev/null || true']`), then GREEN. `BATS_TMPDIR=/tmp TMPDIR=/tmp bats tests/*.bats` → exit 0, 261 tests (was 259). `python3 -m pytest tests/ -q` → 67 passed, 15 skipped. `bash .github/scripts/path-leak-scan.sh --full-tree` → clean. `bash -n scripts/uninstall.sh` → OK.
- Acceptance criterion 3 (`icm doctor` no longer reports the missing hook) is NOT verified: it needs a real uninstall against the live machine, which would remove the stack reinstalled earlier the same day. Verify with `bash scripts/uninstall.sh --only icm --force` followed by `icm doctor`; the live `~/.claude/settings.json` still carries the hook until then.
- Commits: none — not authorized. Diff left uncommitted on branch `fix/icm-sessionstart-hook-uninstall` (`scripts/uninstall.sh` +8, `tests/install.bats` +60). No CHANGELOG line, since that is part of the commit.
- Deviations from plan: `plan_check.py` returns `PASS-0 [authored-invalid] plan: no `#### Iteration N — title` blocks found` — this artifact is a bug report with an Acceptance list, not a plan-format document, so the checker's structural pass cannot apply. Implementation proceeded on the operator's explicit instruction naming this file, treating the Acceptance list as the specification.
- Learned: the hook is not written by anything in this repo (`grep -rn "icm hook"` matches only this document) — `icm` itself registers it, so cleanup has to be by exact command string. `remove_hook_entry` matches commands by exact equality; a machine that wrote `icm hook start` without the `2>/dev/null || true` suffix would not be cleaned. Same-class entries left in place deliberately, outside this document's scope: `$HOME/.claude/hooks/icm-transcript-hook.sh` under both `Stop` and `UserPromptSubmit`.

## Acceptance #3 verified on the live machine — 2026-09-22

- Before: `icm doctor` reported `[Claude Code] SessionStart ✗ icm (missing)` and `1 of 1 ICM hook entries point at a missing binary.`
- Ran: `bash scripts/uninstall.sh --only icm --force` against the live configuration.
- After: Claude Code `SessionStart` entries went 8 -> 7 and the ICM command is absent; `icm doctor` reports `No ICM hooks found. Run 'icm init --mode hook' to install them.` — no missing-binary error. Acceptance 3 satisfied.
- Scope honoured: `--only icm` removed only the `icm` MCP registration; `serena`, `context7`, `persona`, `obsidian-semantic` and `hablatone-rs` remained in the Claude Code global server map. Restored with `bash scripts/install.sh --icm-only`; `scripts/token-diet doctor` then reported `All checks passed — stack is healthy`.
- Restore caveat: token-diet's installer never ran `icm init --mode hook`, so it does not re-register ICM's own SessionStart hook. Run `icm init --mode hook --force` to bring that hook back.
- Still present, out of this document's scope: `$HOME/.claude/hooks/icm-transcript-hook.sh` under both `Stop` and `UserPromptSubmit`.
