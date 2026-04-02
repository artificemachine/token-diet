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
