# Changelog

All notable changes to token-diet will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

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
