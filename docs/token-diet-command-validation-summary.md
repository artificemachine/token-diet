# token-diet command validation summary

Date: 2026-04-07

## Scope

- Validated `token-diet *` command dispatch paths for the Windows PowerShell entrypoint.
- Fixed command/runtime issues observed during interactive smoke testing.
- Added an automated smoke suite to keep these command paths stable.

## Code changes

### `scripts/token-diet.ps1`

- Added robust capture of trailing subcommand args via `ValueFromRemainingArguments`.
- Added explicit `dashboard --help` handling to return usage text immediately.
- Fixed parser/runtime stability issues in several command handlers by normalizing inline script blocks.
- Fixed Serena counters to handle single-item directories safely using `@(Get-ChildItem ...).Count`.

### `scripts/Install.ps1`

- Installer now copies `Uninstall.ps1` into the installed bin directory.
- Dry-run output now includes the uninstaller copy step.

### `scripts/token-diet-dashboard`

- Replaced a Unicode arrow in startup output with ASCII (`->`) to avoid cp1252 console encoding failures on Windows.

### `tests/test_token_diet_ps1_smoke.py`

- Added a pytest smoke matrix that invokes `scripts/token-diet.ps1` in fresh `pwsh` processes.
- Covers help, gain, health, breakdown, explain, budget, loops, route, leaks, test-first, strip, diff-reads, dashboard, service, version, verify, uninstall.
- Uses environment-tolerant assertions for state-dependent commands (e.g., missing RTK history/tools).

## Validation

- Executed:

  - `python -m pytest tests/test_token_diet_ps1_smoke.py`

- Result:

  - `18 passed`

## Notes

- Existing unrelated workspace changes were intentionally left untouched (e.g., `.vscode/mcp.json`, `forks/tilth`, `nul`).
