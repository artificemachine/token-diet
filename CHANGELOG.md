# Changelog

All notable changes to token-diet will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [1.2.15] — 2026-04-06

### Added
- `tests/token-diet.bats`: 4 tests for `serena-gc` (clean state, list-only, `--force` kills, help text)

### Fixed
- `forks/serena` submodule pointer updated to include merged SIGTERM/SIGHUP fix — uvx now fetches the patched version
- `forks/serena/.project-hooks/pre-commit`: use `uv sync --extra dev` so pytest installs from optional-dependencies correctly

## [1.2.14] — 2026-04-06

### Added
- `token-diet serena-gc` — detect and kill orphaned Serena/LSP processes; SIGTERM → 2s wait → SIGKILL fallback (`--force` to apply)

### Fixed
- Serena fork (`forks/serena`): SIGTERM and SIGHUP now trigger graceful shutdown via `SystemExit`, ensuring `server_lifespan` finally-block runs and language-server children are cleaned up instead of orphaned

## [Unreleased]

### Added
- `docs/roadmap.md` — product roadmap: four-layer token optimization thesis and gap analysis

### Changed
- Added `__pycache__/` and `*.pyc` to `.gitignore`

## [Unreleased]

## [Unreleased] — 2026-04-02

### Changed

* `scripts/tkd` renamed to `scripts/token-diet` — binary is now `token-diet` (was `tkd`)
* `scripts/tkd-dashboard` renamed to `scripts/token-diet-dashboard`
* `install.sh` — `install_tkd()` renamed to `install_token_diet()`; writes `token-diet.md` to `~/.claude/` and `~/.codex/` and registers `@token-diet.md` in host instruction files
* `README.md` — Dashboard & CLI section and project structure updated to reflect `token-diet` binary name

### Added

* `~/.claude/token-diet.md` and `~/.codex/token-diet.md` — unified token-diet CLI reference injected into AI host configs on install
* `.project-hooks/pre-commit` — project-level pre-commit hook running `install.sh --dry-run`

## [1.1.2] - 2026-04-01

### Fixed

* `scripts/install.sh` — set `web_dashboard: false` in `~/.serena/serena_config.yml` to fully disable Serena's built-in pywebview app; on macOS each registered host spawned a native window even with `open_on_launch: false`

## [1.1.1] - 2026-04-01

### Fixed

* `scripts/install.sh` — patch `~/.serena/serena_config.yml` to set `web_dashboard_open_on_launch: false` after Serena registration, preventing multiple browser tabs from opening when Serena is registered in multiple AI hosts

## [1.1.0] - 2026-04-01

### Added

* `scripts/tkd` — global CLI dashboard: `tkd gain`, `tkd dashboard`, `tkd version`, `tkd verify`
* `scripts/tkd-dashboard` — stdlib-only Python browser dashboard (auto-refreshing, dark theme, RTK bar chart, host detection); installed to `~/.local/bin/tkd-dashboard`
* `scripts/install.sh` — `--dry-run` flag: previews all install steps without making changes
* `scripts/Install.ps1` — `-DryRun` switch: previews all install steps without making changes
* `README.md` — Dashboard & CLI section documenting `tkd` commands and browser dashboard

## [1.0.0] - 2026-04-01

### Added

* `CLAUDE.md` — project guidance for Claude Code sessions (structure, commands, conventions)
* `README.md` — project overview for the token-diet installer stack
* `README.md` — internal forge mirroring guide: staying in sync with `--mirror`, Forgejo/GitLab pull mirror tip
* `compliance/SBOM.json` — CycloneDX 1.5 bill of materials for all three components (rtk 0.34.3, tilth 0.5.7, serena-agent 0.1.4) with audit results and submodule commit pins
* `compliance/security-audit.md` — completed automated security audit pass (cargo audit, pip-audit, grep checks, Docker config)

### Fixed

* `install.sh` — OpenCode Serena integration now writes to `~/.opencode.json` instead of printing info-only
* `Install.ps1` — OpenCode Serena integration now writes to `%USERPROFILE%\.opencode.json` instead of manual-config warning
* Both scripts pass `--context=ide` to Serena for OpenCode (correct context for non-LSP agent hosts)

### Changed

* Submodule forks (rtk, tilth, serena) point to security-patched versions with `## This Fork` documentation
* `.gitmodules` — removed `branch =` tracking lines; submodules pinned to exact commits for reproducible builds
* `.gitignore` — added `.serena/`, `.vscode/`, `dist/`, `excalidraw.log`

## [1.1.3] - 2026-04-02

### Changed

* `scripts/tkd` renamed to `scripts/token-diet` — binary is now `token-diet` (was `tkd`)
* `scripts/tkd-dashboard` renamed to `scripts/token-diet-dashboard`
* `install.sh` — `install_tkd()` renamed to `install_token_diet()`; writes `token-diet.md` to `~/.claude/` and `~/.codex/` and registers `@token-diet.md` in host instruction files
* `README.md` — Dashboard & CLI section and project structure updated to reflect `token-diet` binary name

### Added

* `~/.claude/token-diet.md` and `~/.codex/token-diet.md` — unified token-diet CLI reference injected into AI host configs on install
* `.project-hooks/pre-commit` — project-level pre-commit hook running `install.sh --dry-run`

## [Unreleased]

### Added

* `token-diet health` — lightweight health check subcommand: reports tool availability and MCP host registrations; exits 0 when all 3 tools healthy, exits 1 otherwise
* `scripts/uninstall.sh` — standalone bash uninstaller; reverses all install.sh writes across 15+ filesystem locations; supports `--dry-run`, `--force`, `--include-data`, `--include-docker`; preserves `~/.serena/memories` by default
* `tests/test_helper.bash` — shared bats fixtures: sandboxed `$HOME` and `$PATH` per test, `mock_cmd()`, `mock_cmd_with_gain()`, `mock_mcp_config()`, `mock_install_prereqs()`
* `tests/token-diet.bats` — bats tests for CLI dispatch: help, health (missing/all/MCP hosts), uninstall dispatch
* `tests/install.bats` — bats tests for `install.sh --dry-run`, `uninstall.sh --dry-run/--force/--include-data`
* `tests/conftest.py` — pytest fixtures: `dashboard_mod` (imports extension-less script via SourceFileLoader), `tmp_home` (sandboxed HOME)
* `tests/test_dashboard.py` — pytest tests for dashboard data layer: `collect()`, `rtk_stats()`, `tilth_stats()`, `_registered_hosts()`
* `.project-hooks/pre-commit` — updated to run `bats tests/*.bats` and `pytest tests/ -q` when available

### Changed

* `scripts/token-diet` — added `cmd_health()`, `cmd_uninstall()` dispatch, updated `cmd_help()`, hoisted `SCRIPT_DIR` to global, fixed `cmd_dashboard()` to reference `token-diet-dashboard`

### Added (Iteration 1 continued)

* `scripts/install.sh` — `--verbose` flag: shows full build output instead of `tail -5`; logs to `~/.local/share/token-diet/install.log` with 512 KB rotation via `show_output()` and `rotate_log()`
* `scripts/Install.ps1` — `-Verbose` switch: replaces `Select-Object -Last 5` with `Show-Output` helper; logs to `%LOCALAPPDATA%\Programs\token-diet\install.log`
* `scripts/Uninstall.ps1` — Windows uninstaller: mirrors `uninstall.sh` for all Windows paths; supports `-DryRun`, `-Force`, `-IncludeData`, `-IncludeDocker`
* `tests/Uninstall.Tests.ps1` — Pester v5 tests for Windows uninstaller (run on Windows/WSL)

## [Unreleased] — Iteration 2

### Added

* `token-diet breakdown` — top commands by tokens saved from RTK history; `--limit N` to cap rows
* `token-diet explain <cmd>` — per-command cost breakdown: tokens in/out/saved, efficiency bar
* `scripts/token-diet-dashboard` — `breakdown_stats()` added; `collect()` now includes `breakdown` key in `/api/stats`
* `tests/test_helper.bash` — `mock_cmd_with_history()` helper for breakdown/explain tests
* 8 new bats tests (cycles 6.1-6.4, 7.1-7.3) + 3 new pytest tests (cycles 8.1-8.2)

## [Unreleased] — Iteration 3

### Added

* `token-diet budget init` — creates `.token-budget` in cwd with default warn (50K) and hard (100K) thresholds
* `token-diet budget status` — shows token usage vs thresholds; exits 0 (OK), 2 (WARN), 3 (HARD STOP)
* `token-diet loops` — detects agent loop patterns (commands run ≥3 times in RTK history); exits 1 with flagged commands
* `scripts/token-diet-dashboard` — `budget_stats()` added; `collect()` now includes `budget` key in `/api/stats`
* `tests/test_helper.bash` — `mock_cmd_no_loops()` helper for clean-history loop detection tests
* 9 new bats tests (cycles 9.1-9.4, 10.1-10.3 + budget init/status) + 3 new pytest tests (cycles 11.1-11.2)

## [Unreleased] — Iteration 4

### Added

* `token-diet strip <file>` — strips single-line comments from Python, bash, and JS/TS source files to reduce prompt token count; `--stats` flag prints line/reduction summary
* `token-diet diff-reads <file>` — parses `git diff HEAD` and staged diffs for a file and prints changed line ranges with `Read` offset/limit hints for targeted reading
* 10 new bats tests (cycles 12.1-12.4, 13.1-13.3)

## [Unreleased] — Iteration 5

### Added

* `token-diet route <task>` — keyword router that suggests tilth (read/search), Serena (rename/refactor), or RTK (run/build/test) based on task description
* `token-diet leaks` — detects files read multiple times in RTK command history; exits 1 with flagged file paths and token waste estimate
* `token-diet test-first <file>` — suggests conventional test file counterpart for Python, Rust, TypeScript, Go, and JS source files; encourages reading tests before implementation
* 12 new bats tests (cycles 14.1-14.4, 15.1-15.3, 16.1-16.3); 77 tests total passing

## [1.2.0] — 2026-04-02

### Added

* **`token-diet health`** — lightweight diagnostic: checks RTK/tilth/Serena presence and MCP host registrations
* **`token-diet uninstall`** — clean removal of all token-diet components (binaries, MCP entries, hooks, doc files); `--dry-run`, `--force`, `--include-data`
* **`token-diet breakdown`** — top commands by tokens saved from RTK history; `--limit N`
* **`token-diet explain <cmd>`** — per-command token cost: tokens in/out/saved, efficiency bar
* **`token-diet budget init/status`** — per-project `.token-budget` with warn/hard thresholds; exits 0 (OK), 2 (WARN), 3 (HARD STOP)
* **`token-diet loops`** — detects agent loop patterns (commands run ≥3 times in RTK history)
* **`token-diet strip <file>`** — strips single-line comments from Python/bash/JS/TS files to reduce prompt size; `--stats` flag
* **`token-diet diff-reads <file>`** — parses git diff hunks and prints changed line ranges with Read offset/limit hints
* **`token-diet route <task>`** — keyword router: suggests tilth (read/search), Serena (rename/refactor), or RTK (run/build/test)
* **`token-diet leaks`** — detects files read multiple times in RTK history; exits 1 with flagged paths
* **`token-diet test-first <file>`** — suggests conventional test file counterpart for Python, Rust, TypeScript, Go, JS
* **`scripts/uninstall.sh`** — standalone bash uninstaller (macOS/Linux)
* **`scripts/Uninstall.ps1`** — PowerShell uninstaller (Windows); `-DryRun`, `-Force`, `-IncludeData`
* **`scripts/install.sh --verbose`** — full build output instead of `tail -5`; logs to `~/.local/share/token-diet/install.log`
* **Test suite** — 61 bats tests + 16 pytest tests; pre-commit hook runs full suite on every commit

## [1.2.1] — 2026-04-02

### Added
* **Dashboard — budget card** with progress bar and warn/hard threshold markers
* **Dashboard — breakdown card** showing top commands by tokens saved
* **Dashboard — loop/leak alerts** — banner warnings when loops (≥3 repeats) or file-read leaks are detected
* **Dashboard — weekly token projection** metric in the summary bar
* **Dashboard — missing-host hints** on tilth/Serena cards showing unregistered MCP hosts

### Fixed
* `breakdown_stats()` / `loops_stats()` / `leaks_stats()` now use correct RTK flag (`-H --format json`); return `None` gracefully when `commands` key is absent
* Dashboard JS `outerHTML` replacement now preserves element `id`, preventing null-reference on subsequent refreshes
* `budget_stats()` test isolation: stray `.token-budget` in project root no longer pollutes test sandbox

## [1.2.2] — 2026-04-02

### Fixed
* `token-diet verify` no longer crashes when run from `~/.local/bin` (inline fallback when `install.sh` is absent)
* `scripts/install.sh` now copies itself as `token-diet-install.sh` to `~/.local/bin` so future verify calls can delegate to it
* `test_budget_stats_returns_none_when_no_budget_file` now mocks `Path.cwd()` to prevent a stray `.token-budget` in the project root from breaking test isolation

## [1.2.3] — 2026-04-02

### Added
* `.vscode/mcp.json` — add Serena MCP server for GitHub Copilot / VS Code

## [1.2.4] — 2026-04-02

### Added
* `scripts/token-diet.ps1` — Windows PowerShell equivalent of the bash CLI; all 15 commands (gain, health, breakdown, explain, budget, loops, route, leaks, test-first, strip, diff-reads, dashboard, version, verify, uninstall)
* `tests/token-diet.Tests.ps1` — 23 Pester v5 tests for the Windows CLI; full cross-platform test parity
* `.project-hooks/pre-commit` — Pester runner block: runs `token-diet.Tests.ps1` when `pwsh` and Pester are available
* `README.md` — Windows CLI usage note in Dashboard & CLI section

## [1.2.5] — 2026-04-02

### Fixed
* `scripts/install.sh` — rename `token-diet_file` local variable (hyphen not valid in bash variable names; caused install to abort at host-doc step)

## [1.2.6] — 2026-04-02

### Changed
* `token-diet budget init` — auto-adds `.token-budget` to `.gitignore` (appends if file exists, creates if in a git repo with no `.gitignore`, skips if no git repo found)

## [1.2.7] — 2026-04-02

### Changed
* `token-diet budget` — `hard: 0` in `.token-budget` is now treated as unlimited (no hard stop); displays "unlimited" for hard stop and remaining
* `token-diet budget status` — warn message corrected to "approaching warn threshold"

### Fixed
* `tests/test_dashboard.py` — mock `Path.cwd()` in budget threshold test to prevent stray `.token-budget` from leaking into test

## [1.2.8] — 2026-04-02

### Changed
* `.gitignore` — add `.token-budget` entry

## [1.2.9] — 2026-04-03

### Added
* `scripts/token-diet` — `health` now detects stale Codex tilth MCP registrations: parses `~/.codex/config.toml` and warns if the configured command path no longer exists
* `scripts/install.sh` — `--verify` likewise warns on stale Codex tilth MCP command path
* `tests/token-diet.bats` — 2 new tests covering stale Codex path detection in `health`
* `tests/install.bats` — 1 new test covering `--verify` stale Codex path warning
* `tests/test_tilth_benchmark_paths.py` — regression tests: tilth benchmark resolves binary from `TILTH_BIN`/PATH, uses repo-local results dir

### Fixed
* `forks/tilth/benchmark/` — hardcoded `/Users/flysikring/.cargo/bin/tilth` and workspace results path replaced with env-var/PATH resolution and repo-local fallback

## [1.2.10] — 2026-04-03

### Fixed
* `scripts/token-diet` + `scripts/install.sh` — TOML parser now handles single-quoted command values (`command = 'tilth'`); previously single-quoted entries were silently ignored
* `scripts/token-diet` — `verify` inline fallback now exits 1 when tools or MCP registrations have issues (was always exiting 0)

### Added
* `.dockerignore` — excludes secrets, tests, docs, and unused forks from Docker build context (build context is repo root; previously everything was sent to the daemon)
* `tests/token-diet.bats` — 3 regression tests: single-quote TOML detection, stale single-quoted path warning, verify inline fallback exit code
* `tests/install.bats` — 1 regression test: stale single-quoted TOML path in `--verify`

## [1.2.11] — 2026-04-03

### Added
* `scripts/token-diet.ps1` — `health` now detects stale Codex tilth MCP registrations (parses `~\.codex\config.toml`); handles both double- and single-quoted TOML command values
* `scripts/token-diet.ps1` — `verify` now detects stale Codex tilth MCP registrations and exits 1 when issues found (was always exiting 0)
* `scripts/Install.ps1` — `Verify-Stack` / `-VerifyOnly` likewise warns on stale Codex tilth MCP command path
* `tests/token-diet.Tests.ps1` — 4 Pester tests: stale double-quoted path (health + verify), stale single-quoted path, single-quoted command detected as registered

### Changed
* `scripts/token-diet.ps1` — Codex registration in `Get-HostsRegistered` now uses TOML section parsing instead of plain-text grep (matches bash parity)
* `scripts/token-diet.ps1` — `health` exit message updated from "tool(s) missing" to "issue(s) found — reinstall tools or repair MCP registrations"

## [1.2.12] — 2026-04-03

### Added
* `scripts/token-diet` — `--version` flag prints self-version (`token-diet 1.2.12`)
* `scripts/token-diet-dashboard` — dashboard header now displays the token-diet version on load
* `scripts/token-diet-dashboard` — `token_diet_version()` data function collects self-version via `token-diet --version`
* `tests/test_dashboard.py` — 3 pytest tests: version string parsing, None when not installed, `collect()` includes `version` key
* `tests/token-diet.bats` — `--version` bats test (72 bats total)
* `README.md` — `token-diet --version` documented in commands table

## [1.2.13] — 2026-04-05

### Fixed
* `scripts/token-diet` — `explain` with no argument crashed with `unbound variable`; fixed with `${1:-}`
* `scripts/token-diet` — `breakdown --limit` with no value crashed with `unbound variable`; fixed with `${2:-$limit}`
* `scripts/token-diet` — `service` with no argument exited 0 instead of 1
* `scripts/token-diet-dashboard` — port-in-use showed raw Python traceback; now prints a friendly message and exits 1

### Security
* `docker/Dockerfile.serena` — base images pinned to SHA256 digests (`python:3.12-slim`, `uv`)
* `docker/Dockerfile.serena` — removed `2>/dev/null` suppression on `npm install` so build errors are visible
* `tests/test_helper.bash` — replaced `printf` JSON construction with `jq` (SHELL-005)

### Changed
* `scripts/token-diet` — reduced python3 subprocess count: 5→1 in `cmd_gain`, 3→1 in `_print_budget_section`, 2→1 in `cmd_budget status`
* `scripts/token-diet-dashboard` — reduced RTK subprocess count: 4→1 per `collect()` cycle via `_get_rtk_daily()` helper
* `scripts/token-diet.ps1` — hoisted `$rtkSummary` in `Show-BudgetSection` to eliminate redundant `Get-RtkSummary` call
* `scripts/token-diet` — removed dead `BLUE` color variable and unused `comment_char` local

### Added
* `tests/test_dashboard.py` — 3 pytest tests: `loops_stats()`/`leaks_stats()` return None, `collect()` includes `loops`/`leaks` keys
* `tests/token-diet.bats` — test: `explain` exits 1 with usage when no arg given

## [1.3.0] — 2026-04-07

### Added
* `scripts/install.sh` — Cowork (Claude Desktop) support: auto-detected via `~/Library/Application Support/Claude/claude_desktop_config.json`
* `scripts/install.sh` — RTK awareness doc written to Claude Desktop config dir (LLM instructed to prefix commands with `rtk`; no hook mechanism available)
* `scripts/install.sh` — Serena + tilth MCP entries injected into `claude_desktop_config.json` (stdlib `python3`, supports both normal and `--local` Docker mode)
* `scripts/install.sh` — `token-diet.md` written to Claude Desktop config dir for Cowork sessions
* `scripts/install.sh` — Cowork shown as 6th host in `verify_stack` output and architecture banner

## [1.3.1] — 2026-04-07

### Fixed
* `scripts/Install.ps1` — removed `-Verbose` reserved parameter conflict; replaced with `-FullOutput` switch
* `scripts/Install.ps1` — repaired broken RTK detection (`if (Test-Cmd...); $LASTEXITCODE` semicolon bug)
* `scripts/Install.ps1` — path resolution uses `$script:ProjectRoot` consistently (fixes submodule and config source paths)
* `scripts/Install.ps1` — `--VerifyOnly` now runs `Detect-Hosts` before `Verify-Stack`

### Added
* `scripts/Install.ps1` — Copilot CLI, VS Code, and Cowork (Claude Desktop) host detection and integration
* `scripts/Install.ps1` — `-Local` flag for air-gapped installs: builds RTK/tilth from `forks\` submodules, Serena via Docker
* `scripts/Install.ps1` — `-SkipTests` flag to skip clippy + cargo test in local mode
* `scripts/Install.ps1` — `Install-TokenDiet` function: copies `token-diet.ps1`, creates `.cmd` shim, manages PATH, writes `token-diet.md` to `~\.claude\` and `~\.codex\`
* `scripts/Install.ps1` — RTK awareness doc written to `%APPDATA%\Claude\` for Cowork sessions
* `scripts/Install.ps1` — Serena + tilth MCP entries injected into `claude_desktop_config.json` for Cowork
* `scripts/Install.ps1` — log rotation (512 KB cap on `install.log`)
* `scripts/Install.ps1` — interactive wizard gains local-mode prompt

## [1.3.2] — 2026-04-07

### Fixed
* `.vscode/mcp.json` — replaced hardcoded absolute path `/Users/…/.local/bin/tilth` with plain `tilth` (portable across machines)

### Added
* `AGENTS.md`, `SOUL.md` — superharness project scaffolding

## [1.3.3] — 2026-04-07

### Added
* `scripts/token-diet` — `no-rtk` command: temporarily disables the RTK Claude Code hook via a sentinel file (`~/.config/token-diet/rtk-disabled`); patches the hook to respect it (idempotent)
* `scripts/token-diet` — `use-rtk` command: removes the sentinel file and re-enables RTK filtering
* `tests/token-diet.bats` — 6 tests covering `no-rtk`/`use-rtk` toggle behaviour

## [1.3.4] - 2026-04-07

### Fixed
* `scripts/install.sh` — copy `uninstall.sh` to `~/.local/bin/` during installation so `token-diet uninstall` works from the installed binary
* `scripts/token-diet` — `cmd_uninstall()` now falls back gracefully to sibling `uninstall.sh` rather than hard-failing when the script isn't on PATH; emits a clear reinstall hint on missing file

## [1.3.5] - 2026-04-07

### Fixed
* `scripts/token-diet` — `breakdown`, `loops`, `leaks`, `explain`: replaced JSON parsing (which relied on a non-existent `commands` array in `rtk gain --format json`) with regex parsing of the human-readable "By Command" table from `rtk gain`; all four commands now work correctly with the current RTK binary
* `tests/test_helper.bash` — updated `mock_cmd_with_history` and `mock_cmd_no_loops` to emit text table output for plain `gain` calls; inline mocks in `token-diet.bats` updated to match

## [1.3.6] - 2026-04-07

### Fixed
* `scripts/Install.ps1` — `rtk init -g` now called with `--auto-patch` to ensure RTK hooks are wired during install without requiring a manual follow-up step
* `scripts/Install.ps1` — added `Repair-SubmoduleWorktree` to recover empty submodule worktrees after external wipes
* `scripts/Install.ps1` — copies `Uninstall.ps1` to bin dir (mirrors macOS fix from v1.3.4)
* `scripts/token-diet.ps1` — parser stability fixes: here-string assignments, `$(...)`/`@(...)` subexpressions, `ValueFromRemainingArguments` for `$SubArgs`
* `scripts/token-diet.ps1` — `dashboard --help` handler; Serena counter fix for single-item directories
* `scripts/token-diet-dashboard` — replaced Unicode arrow `→` with ASCII `->` to avoid cp1252 encoding failures on Windows consoles
* `.vscode/mcp.json` — reverted hardcoded absolute tilth path to plain `tilth`

### Security
* `forks/tilth` — bump submodule to `v0.5.7-security.1`: path traversal guards (P-1 HIGH) added to all three MCP entry points; pager injection prevention (P-2 MEDIUM) added to `$PAGER` handling

### Tests
* `tests/test_token_diet_ps1_smoke.py` — new Windows-only pytest smoke suite covering 18 PS1 command dispatch paths

## [1.3.7] - 2026-04-07

### Added
* `scripts/install.sh` — `--hosts LIST` flag: comma-separated list of AI hosts to wire integrations for (e.g. `--hosts "claude,vscode"`); prompts interactively when multiple hosts are detected and no flag is given
* `scripts/Install.ps1` — `-Hosts` parameter: same semantics as `--hosts` on macOS/Linux; interactive numbered prompt when multiple hosts are detected and no flag is given

## [1.4.0] - 2026-04-13

### Added
* `config/compat.json` — new cross-tool version compatibility manifest: schema-1 with `min`/`tested` versions for RTK, tilth, and Serena
* `scripts/token-diet` — `cmd_version`: shows per-tool compat status (OK / WARN below minimum) using `_compat_min()` + `_semver_ok()` helpers
* `scripts/token-diet` — `cmd_doctor [--json]`: compat block added to JSON output with per-tool status; MCP registration section delegates to `tilth doctor --json` (covers all 22 hosts vs 4 previously)
* `forks/tilth` — bump submodule to v0.6.0: adds `tilth doctor [--json]` subcommand; checks tilth registration across all 22 MCP hosts; reports `healthy`, `registered_hosts`, and per-host `command`/`command_ok` status

### Fixed
* `scripts/install.sh` — malformed JSON recovery: 4 remaining `json.load` sites now catch `json.JSONDecodeError` and back up the corrupt file before starting fresh, preventing crash under `set -euo pipefail`

### Tests
* `tests/token-diet.bats` — 6 new tests (Cycle 16): compat version OK/WARN, doctor compat block, doctor exits 1 on below-min tool
* `tests/install.bats` — 5 new tests (Cycles 5.1–5.4): opencode/cowork malformed JSON recovery, idempotent re-install, uninstall idempotency

## [1.4.1] - 2026-04-13

### Changed
* `config/compat.json` — update serena tested version to `0.1.5` (fork version scheme); bump rtk tested to `0.34.4`; lower serena minimum to `0.1.0` (fork epoch)
* `forks/serena` — bump submodule to v0.1.5: SEC-003 atomic writes, SEC-002 extended metachar guard + `--no-shell` flag, SEC-004 LS pre-flight binary validation, `serena doctor [--json]` CLI subcommand; 36 security tests passing
* `scripts/token-diet` — version bump 1.4.0 → 1.4.1
* `scripts/token-diet.ps1` — version bump 1.4.0 → 1.4.1

## [1.4.2] - 2026-04-13

### Changed
* `forks/rtk` — bump submodule to v0.34.5: clippy clean on Rust 1.94 (7 lint fixes)
* `forks/tilth` — bump submodule to v0.6.1: clippy clean on Rust 1.94 (9 lint fixes)
* `config/compat.json` — rtk tested→0.34.5, tilth tested→0.6.1
* `scripts/install.sh` — symlink RTK and tilth from `~/.cargo/bin/` into `~/.local/bin/` instead of copying; macOS security policy (SIGKILL) kills copied Rust binaries in `~/.local/bin` but honours symlinks
* `scripts/token-diet` + `scripts/token-diet.ps1` — version bump 1.4.1 → 1.4.2

## [1.4.3] - 2026-04-13

### Fixed
* `docker/Dockerfile.serena` — add `nodejs npm` to builder stage; `python:3.12-slim` has no Node.js, causing `npm install -g typescript-language-server typescript` to silently no-op and `COPY --from=builder /usr/local/bin/tsserver` to fail. Image now builds and runs correctly.

## [1.4.4] - 2026-04-14

### Added
* `scripts/token-diet-dashboard` — RTK and Serena cards now show their installed version numbers alongside the active/badge label (RTK via `rtk --version`; Serena docker via `org.opencontainers.image.version` label; Serena uvx via `uvx serena --version`).
* `docker/Dockerfile.serena` — add `LABEL org.opencontainers.image.version="0.1.5"` to runtime stage so `docker inspect` reports the bundled version. Rebuild the image to pick this up.

## [1.4.5] - 2026-04-14

### Fixed
* `scripts/token-diet-dashboard` — use `docker image inspect` (consistent with existing `has_docker` check) instead of bare `docker inspect` for reading the version label.
* `scripts/token-diet-dashboard` — `token_diet_version()` fallback for Windows: if `token-diet` subprocess fails, parse `TD_VERSION` from the sibling bash or PS1 script file (first 50 lines).

## [1.4.6] - 2026-04-14

### Fixed
* `tests/Uninstall.Tests.ps1` — set `$env:CARGO_HOME` to the test temp dir in `BeforeAll` so that `cargo uninstall rtk/tilth` never touches the host cargo registry. Previously, Pester `-Force` tests called the real `cargo uninstall` against the actual cargo registry, wiping the installed RTK and tilth binaries after each test run.
