# rtk_init_bug

Date: 2026-04-07

## Problem

`token-diet` install is expected to wire RTK hooks automatically, but users still see:

`[rtk] /!\ No hook installed — run rtk init -g for automatic token savings`

Observed state from `rtk init -g --show`:

- Hook: not found
- `settings.json`: exists but RTK hook not configured
- Global `~/.claude/CLAUDE.md`: old RTK block (migration warning)

## Root cause

Installer host integration used:

- `rtk init -g`
- `rtk init -g --opencode`

These calls do not guarantee hook patching on current RTK behavior unless auto-patch is enabled.

## Patch

Updated `scripts/Install.ps1` host integration commands to include `--auto-patch`:

- `rtk init -g --auto-patch`
- `rtk init -g --opencode --auto-patch`

Dry-run output strings were updated to match.

## Additional hardening

Installer now includes a submodule worktree repair step after `git submodule update --init --recursive`.

- If `forks/rtk`, `forks/tilth`, or `forks/serena` exists but contains only `.git` (empty worktree), install will run:
  - `git submodule update --init --force -- <submodule>`
- This addresses cases where a submodule directory was externally wiped and appears as mass deletions.

## Expected outcome

After install, RTK global hook/settings patching should complete in one pass, reducing cases where users must run manual follow-up init commands.
