# Changelog

All notable changes to token-diet will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [1.11.4] — 2026-07-14

### Fixed
- **Docker double-invocation bug**: `docker/Dockerfile.serena` had both `ENTRYPOINT ["serena", "start-mcp-server"]` AND the v1.11.3 launcher wrapper supplying `serena start-mcp-server`. Result: container ran `serena start-mcp-server serena start-mcp-server --context=...` and exited with `Error: Got unexpected extra argument (start-mcp-server)`. The bug would silently break any LOCAL-mode install using the v1.11.3 wrapper. Removed the Dockerfile's ENTRYPOINT/CMD so the wrapper at `~/.local/bin/serena` is the single source of truth for the serena CLI invocation. Direct docker users must now pass the full command (documented in Dockerfile comment).
- **Rebuilt `token-diet/serena:latest` image** against current serena fork (`48d5b27d`, ahead of the previous `1.5.3` label — now `1.5.4.dev0`). MCP round-trip verified: Serena v1.27.0, project auto-detection works (`/workspace` mount resolves to host cwd), all 52 tools load. Local users can rebuild with `bash scripts/install.sh --serena-only --local` or directly via `docker build -f docker/Dockerfile.serena -t token-diet/serena:latest .`.

### Notes
- v1.11.3 users hitting `Error: Got unexpected extra argument (start-mcp-server)` from their Serena MCP after upgrading to v1.11.4 need to rebuild the Docker image as above.
- Bumps `TD_VERSION` 1.11.3 → 1.11.4 in `scripts/token-diet` + `scripts/token-diet.ps1`.

## [1.11.3] — 2026-07-14

### Fixed
- **Strict Installation Decoupling (CLAUDE.md):** the macOS/Linux installer's OpenCode MCP registration no longer writes absolute `$PROJECT_ROOT/forks/...` paths into `~/.config/opencode/opencode.json`. After this fix, MCP registrations for `serena` and `tilth` use bare commands resolvable through `~/.local/bin`, the same pattern ICM already uses. Concretely: replacing the broken local-mode fallback with a launcher-wrapped bare command. Also fixed a latent bug in the same registration where `serena-mcp-server` was used as a literal binary name — Serena's entry point is `serena start-mcp-server` (no separate MCP binary exists). And fixed the `tilth` MCP subcommand: it is `tilth --mcp`, not `tilth mcp`. Mirrored in `Install.ps1`. New `install.bats` regression: asserts no MCP config written by `install.sh` contains a `forks/` path, the `serena-mcp-server` string, or a bare `mcp` arg in the tilth entry. Manual repair on already-affected systems: `ln -sf "$REPO/forks/serena/.venv/bin/serena" ~/.local/bin/serena` and edit `~/.config/opencode/opencode.json` `mcp.serena.command` to `["serena","start-mcp-server","--context=ide","--open-web-dashboard","false","--project-from-cwd"]`, `mcp.tilth.command` to `["tilth","--mcp"]`. `install_serena()` now provisions `~/.local/bin/serena` as a Docker (LOCAL) or uvx (online) wrapper script so the bare-command registration works in both modes.

## [1.10.7] — 2026-07-06

### Fixed
- Correction: the `[1.10.6]` entry below was tagged and merged under a version number that collided with a pre-existing `v1.10.6` git tag from 2026-06-05 (a leftover from earlier release drift where the tag was cut one version ahead of the code). No functional change from 1.10.6 — this release simply re-tags the same installer fix under the next actually-unused version number, 1.10.7.

## [1.10.6] — 2026-07-06

### Fixed
- Installer: config writers no longer reset a malformed existing config to `{}` and overwrite it with a stub. On a JSON parse error the installer now backs the file up to a timestamped `.corrupt-<ts>` copy and aborts (exit 3) instead of destroying it. Combined `FileNotFoundError`/`JSONDecodeError` handlers were split so a genuinely missing config still starts fresh. Covers the OpenCode, Cowork/Claude Desktop, and VS Code MCP config writers. Updated install.bats cycles 5.2/5.3 to assert the abort-and-preserve contract.

## [1.7.9] — 2026-05-14

### Fixed
- Dashboard: "Top days by tokens saved" now ranks by savings efficiency % (min 10 commands) instead of absolute saved tokens. This prevents single outlier days from permanently dominating the list and ensures recent active days are always represented fairly.
- Dashboard: Added `--no-open` / `--no-browser` to skip automatic browser launch.
- Dashboard services: macOS launchd, Linux systemd, and Windows Task Scheduler now disable browser auto-open by default.
- Windows budget: `token-diet budget status` now resolves the global budget path through the cross-platform home helper instead of `$env:USERPROFILE`, fixing null-path failures in PowerShell-on-macOS test environments.

## [1.7.8] — 2026-05-02

### Fixed
- Dashboard: Added `--no-open` / `--no-browser` to skip automatic browser launch.
- Dashboard services: macOS launchd, Linux systemd, and Windows Task Scheduler now disable browser auto-open by default.
- Windows budget: `token-diet budget status` now resolves the global budget path through the cross-platform home helper instead of `$env:USERPROFILE`, fixing null-path failures in PowerShell-on-macOS test environments.

## [1.7.1] — 2026-04-22

### Fixed
- `scripts/install.sh`: Fix modifier-only logic to correctly default to all tools when no specific tool flag is provided (e.g. `install.sh --verbose`).
- Serena Runtime: Added `--headless` flag to all registrations by default to prevent unwanted dashboard popups.
- Serena Runtime: Improved detection logic to validate actual `uvx` runnability and distinguish between Docker image presence and active container.
- CLI: Fixed `token-diet mcp list` to show both tilth and serena hosts and return 0 even when diagnostics find issues.
- Diagnostics: Fixed `token-diet doctor --json` to include `serena_mcp` registration data.
- Hook: Optimized pre-commit to skip slow Pester tests on non-Windows by default (use `RUN_SLOW_TESTS=1` to run).
- README: Added "Global vs. Per-Project" section and refined "Full Reset" instructions.

### Added
- `token-diet serena-status`: New command (Bash + PowerShell) for deep Serena runtime diagnostics.
- Dashboard: Added visual indicators for Serena status (Image vs. Container vs. uvx).

## [1.7.0] — 2026-04-22

### Added
- `scripts/token-diet-mcp`: Zero-dependency Python MCP server providing agent-accessible observability.
- MCP Tools: `token_diet_health`, `token_diet_savings`, `token_diet_budget`, `token_diet_loops`, and `token_diet_route`.
- `tests/test_token_diet_mcp.py`: Automated test suite for MCP server handshake and tool calls.
- Auto-registration of `token-diet` MCP server in `install.sh` and `Install.ps1` across all supported AI hosts.
- Analysis and TDD documentation for the MCP conversion in `docs/`.
- `token-diet mcp` command: New dedicated command for managing server registrations.
- `token-diet upstream` command: New command to manage and verify original repository updates for audited forks.
- `token-diet hook` command: Unified toggle for RTK optimization (replacing `no-rtk`/`use-rtk`).
- `docs/enterprise.md`: New guide for air-gapped and enterprise deployments.

### Changed
- `README.md`: Major rewrite for clarity; explains the stack in under 60 seconds.
- `scripts/install.sh` & `scripts/Install.ps1`: Now installs `token-diet-mcp` and configures MCP host registrations.
- `scripts/uninstall.sh` & `scripts/Uninstall.ps1`: Now removes `token-diet-mcp` binary.
- `tests/install.bats`: Updated to verify lifecycle management of the new MCP binary.
- `token-diet update`: Added `--fresh` flag for clean reinstalls (deprecates `reinstall`).
- `token-diet verify`: Now an alias for `doctor`, providing deep diagnostics.
- AI Instructions: Refined `token-diet.md` with explicit tool selection and self-monitoring guidelines for agents.
- Windows: Fixed duplicate dispatch block in `token-diet.ps1` that broke Pester tests.


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

- 2026-07-21: docs: align CODE_OF_CONDUCT.md with concise 5-line CoC (replaces Contributor Covenant boilerplate with internal style)
### Added
- `docs/roadmap.md` — product roadmap: four-layer token optimization thesis and gap analysis

### Changed
- Added `__pycache__/` and `*.pyc` to `.gitignore`

## [Unreleased]

## [Unreleased] — 2026-04-02

### Changed

* `scripts/tkd` renamed to `scripts/token-diet` — binary is now `token-diet` (was `tkd`)
* `scripts/tkd-dashboard` renamed to `scripts/token-diet-dashboard`
* `install.sh` — `install_tkd()` renamed to `install_token_diet()`; writes `token-diet.md` to `$HOME/.claude/` and `$HOME/.codex/` and registers `@token-diet.md` in host instruction files
* `README.md` — Dashboard & CLI section and project structure updated to reflect `token-diet` binary name

### Added

* `$HOME/.claude/token-diet.md` and `$HOME/.codex/token-diet.md` — unified token-diet CLI reference injected into AI host configs on install
* `.project-hooks/pre-commit` — project-level pre-commit hook running `install.sh --dry-run`

## [1.1.2] - 2026-04-01

### Fixed

* `scripts/install.sh` — set `web_dashboard: false` in `$HOME/.serena/serena_config.yml` to fully disable Serena's built-in pywebview app; on macOS each registered host spawned a native window even with `open_on_launch: false`

## [1.1.1] - 2026-04-01

### Fixed

* `scripts/install.sh` — patch `$HOME/.serena/serena_config.yml` to set `web_dashboard_open_on_launch: false` after Serena registration, preventing multiple browser tabs from opening when Serena is registered in multiple AI hosts

## [1.1.0] - 2026-04-01

### Added

* `scripts/tkd` — global CLI dashboard: `tkd gain`, `tkd dashboard`, `tkd version`, `tkd verify`
* `scripts/tkd-dashboard` — stdlib-only Python browser dashboard (auto-refreshing, dark theme, RTK bar chart, host detection); installed to `$HOME/.local/bin/tkd-dashboard`
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

* `install.sh` — OpenCode Serena integration now writes to `$HOME/.opencode.json` instead of printing info-only
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
* `install.sh` — `install_tkd()` renamed to `install_token_diet()`; writes `token-diet.md` to `$HOME/.claude/` and `$HOME/.codex/` and registers `@token-diet.md` in host instruction files
* `README.md` — Dashboard & CLI section and project structure updated to reflect `token-diet` binary name

### Added

* `$HOME/.claude/token-diet.md` and `$HOME/.codex/token-diet.md` — unified token-diet CLI reference injected into AI host configs on install
* `.project-hooks/pre-commit` — project-level pre-commit hook running `install.sh --dry-run`

## [Unreleased]

### Added

* `token-diet health` — lightweight health check subcommand: reports tool availability and MCP host registrations; exits 0 when all 3 tools healthy, exits 1 otherwise
* `scripts/uninstall.sh` — standalone bash uninstaller; reverses all install.sh writes across 15+ filesystem locations; supports `--dry-run`, `--force`, `--include-data`, `--include-docker`; preserves `$HOME/.serena/memories` by default
* `tests/test_helper.bash` — shared bats fixtures: sandboxed `$HOME` and `$PATH` per test, `mock_cmd()`, `mock_cmd_with_gain()`, `mock_mcp_config()`, `mock_install_prereqs()`
* `tests/token-diet.bats` — bats tests for CLI dispatch: help, health (missing/all/MCP hosts), uninstall dispatch
* `tests/install.bats` — bats tests for `install.sh --dry-run`, `uninstall.sh --dry-run/--force/--include-data`
* `tests/conftest.py` — pytest fixtures: `dashboard_mod` (imports extension-less script via SourceFileLoader), `tmp_home` (sandboxed HOME)
* `tests/test_dashboard.py` — pytest tests for dashboard data layer: `collect()`, `rtk_stats()`, `tilth_stats()`, `_registered_hosts()`
* `.project-hooks/pre-commit` — updated to run `bats tests/*.bats` and `pytest tests/ -q` when available

### Changed

* `scripts/token-diet` — added `cmd_health()`, `cmd_uninstall()` dispatch, updated `cmd_help()`, hoisted `SCRIPT_DIR` to global, fixed `cmd_dashboard()` to reference `token-diet-dashboard`

### Added (Iteration 1 continued)

* `scripts/install.sh` — `--verbose` flag: shows full build output instead of `tail -5`; logs to `$HOME/.local/share/token-diet/install.log` with 512 KB rotation via `show_output()` and `rotate_log()`
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
* **`scripts/install.sh --verbose`** — full build output instead of `tail -5`; logs to `$HOME/.local/share/token-diet/install.log`
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
* `token-diet verify` no longer crashes when run from `$HOME/.local/bin` (inline fallback when `install.sh` is absent)
* `scripts/install.sh` now copies itself as `token-diet-install.sh` to `$HOME/.local/bin` so future verify calls can delegate to it
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
* `scripts/token-diet` — `health` now detects stale Codex tilth MCP registrations: parses `$HOME/.codex/config.toml` and warns if the configured command path no longer exists
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
* `scripts/install.sh` — Cowork (Claude Desktop) support: auto-detected via `$HOME/Library/Application Support/Claude/claude_desktop_config.json`
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
* `scripts/token-diet` — `no-rtk` command: temporarily disables the RTK Claude Code hook via a sentinel file (`$HOME/.config/token-diet/rtk-disabled`); patches the hook to respect it (idempotent)
* `scripts/token-diet` — `use-rtk` command: removes the sentinel file and re-enables RTK filtering
* `tests/token-diet.bats` — 6 tests covering `no-rtk`/`use-rtk` toggle behaviour

## [1.3.4] - 2026-04-07

### Fixed
* `scripts/install.sh` — copy `uninstall.sh` to `$HOME/.local/bin/` during installation so `token-diet uninstall` works from the installed binary
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
* `scripts/install.sh` — symlink RTK and tilth from `$HOME/.cargo/bin/` into `$HOME/.local/bin/` instead of copying; macOS security policy (SIGKILL) kills copied Rust binaries in `$HOME/.local/bin` but honours symlinks
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

## [1.5.0] - 2026-04-19

### Added
* `token-diet update` — re-runs the installer to update RTK + tilth + Serena. Locates `install.sh` via `$TD_INSTALLER`, the script's own dir (repo checkout or installed `token-diet-install.sh`), or as a last resort clones `celstnblacc/token-diet` (depth 1) to a tempdir and runs it from there. All extra args are passed through to the installer (`--local`, `--verbose`, etc.).
* `token-diet reinstall` — runs `uninstall --force` then `update`. Useful when the install is broken or out of sync.
* PowerShell parity: `token-diet update` and `token-diet reinstall` mirror the same resolution order using `Install.ps1` / `token-diet-install.ps1`.

## [1.5.1] - 2026-04-19

### Added
* `LICENSE` — MIT, matching the upstream forks (`celstnblacc/rtk`, `tilth`, `serena`). The installer pulls the repo via `git clone`, so the repo needed an explicit license for users building from source.

### Changed
* `.gitignore` — ignore local scan/coverage artifacts (`.coverage`, `shipguard.txt`) that were showing up as untracked after test and ShipGuard runs.

## [1.6.0] - 2026-04-20

### Added
* OpenCode prompt rule injection — `install.sh` now writes the token-diet + RTK + tilth + Serena usage rules into `$HOME/.config/opencode/opencode.json` under `mode.build.prompt` and `mode.plan.prompt`, wrapped in `<!-- token-diet:begin -->` / `<!-- token-diet:end -->` markers. Previously binaries and MCP servers installed fine for OpenCode, but the usage rules never reached the model because OpenCode does not read `@file.md` include syntax or `$HOME/.claude/CLAUDE.md`. Rules live at `scripts/lib/opencode-rules.md` and are re-usable for any other non-Claude prompt-string host.
* `uninstall.sh` strips the token-diet block from OpenCode prompts, preserving user-authored text outside the markers.
* 4 bats tests covering injection, idempotency, user-text preservation, and clean removal.

## [1.6.1] - 2026-04-20

### Fixed

* `install.sh` modifier-only invocations (e.g. `--skip-tests`, `--verbose`, `--dry-run`, `--local`, `--hosts X`) used to set `has_args=true` and then silently no-op because no `do_*` intent was configured. Result: the `token-diet` CLI binary got updated but RTK/tilth/Serena installation and Serena MCP registration (including v1.6.0's OpenCode prompt injection) never ran. Intent flags (`--all`, `--rtk-only`, `--tilth-only`, `--serena-only`, `--verify`) are now the only flags that gate the wizard; modifier-only invocations default to install-all. Closes #38.
* `install.sh` wizard's final `Proceed? [Y/n]` prompt used `[[ … ]] && echo && exit 0`, which under `set -e` caused the whole function to return non-zero when the user answered "y", aborting main(). Rewritten as a proper `if … then … fi` block. Latent since the wizard path was never test-covered before v1.6.1 (all existing tests passed explicit `--serena-only`/`--all` and skipped the wizard).

### Added

* New bats test: `install.sh --skip-tests (modifier-only) still triggers Serena MCP + opencode rules`. Proves the fix by driving the wizard with canned stdin (`install-all=y, dedup=y, local=n, proceed=y`) and asserting the token-diet begin marker lands in `opencode.json`. Total 138 bats tests, 0 failures.

## [1.7.1] — 2026-04-23
### Fixed
- CLI: Improved `token-diet mcp list` to show both Tilth and Serena hosts.
- README: Added "Global vs. Per-Project" scope explanation.
- README: Clarified that `uninstall --force` removes Tilth and RTK.
- Serena: Added `--headless` flag to all MCP registrations for silent operation.
- Diagnostics: Fixed `token-diet doctor --json` to include `serena_mcp` data.
- Diagnostics: Added `$HOME/.claude.json` to Serena registration checks.

## [1.7.2] - 2026-04-23
### Fixed
- Dashboard: `budget_stats()` infinite-loop under launchd when CWD is `/` (parent-of-root is root, so the walk-up loop never terminated and the HTTP server wedged). Replaced `while d.parts` with an explicit `parent == d` fixed-point guard.
- Dashboard: `main()` now prints the serving URL and a clear error (with the PID holding the port) on `OSError`, auto-opens the browser (`webbrowser` was imported but never called), and handles Ctrl+C cleanly instead of exiting silently with code 1.
- Dashboard: Added a 30s timeout to the auto-rotate `subprocess.run(["token-diet", "clean"])` call so a hanging clean cannot wedge `/api/stats`.

### Restored
- Dashboard UI: Sparkline bars for the last 14 days, avg-efficiency bar, weekly-projection metric, "tools active N/3" summary, per-tool tooltips (`data-tip`), serena mode/memories/log_days rows, budget progress bar with warn-line marker, top-days breakdown table, and missing-host hints. These were dropped by the v1.7.1 MCP rewrite.
- `_budget_entry()` now emits `unlimited`, `installed_at`, and `~`-relative paths consumed by the restored UI.
- `projection_stats()` now includes `avg_daily_saved`, `avg_pct`, and `days_sampled`.

## [1.7.3] - 2026-04-24
### Added
- Windows parity: `Invoke-Gain` in `scripts/token-diet.ps1` now reads `~/.config/token-diet/archived_stats.json` and sums archived totals with live RTK totals, matching the bash `cmd_gain` behavior shipped earlier. This closes the UX gap where Windows users saw only post-rotation totals after running `token-diet clean`.
- Windows parity: `Invoke-Clean` in `scripts/token-diet.ps1` archives RTK history (`~/.rtk/history.json` and OS-specific `history.db` under the Rust dirs::data_dir convention: `%APPDATA%\rtk` on Windows, `~/Library/Application Support/rtk` on macOS, `$XDG_DATA_HOME/rtk` on Linux) and carries cumulative totals forward into `archived_stats.json`. Added to the `clean` dispatch and `help` text.
- Version bump to 1.7.3 in both `scripts/token-diet` and `scripts/token-diet.ps1` (PS1 was stale at 1.6.1 — this is the first coordinated bump since v1.6.1 on Windows).

### Fixed
- `tests/token-diet.Tests.ps1` mock rtk/tilth scripts now use `ValueFromRemainingArguments` so `--format` and `--version` reach the script body instead of being silently bound as named parameters by PowerShell. Pre-existing bug that hid any test coverage of `rtk gain --format json` via the mock.
- `tests/token-diet.Tests.ps1` PATH concatenation now uses `[System.IO.Path]::PathSeparator` so the MockBin directory actually lands on PATH on macOS/Linux (the hardcoded `;` only worked on Windows).

## [1.7.4] - 2026-04-24
### Fixed
- `scripts/install.sh` Codex CLI Serena registration used a fragile `grep -q "serena"` idempotency check that false-matched on any line containing the substring "serena" — including vestigial orphan arrays from bad pastes. This caused the installer to log "already configured" and silently skip writing the real `[mcp_servers.serena]` block. Changed to `grep -Eq '^\[mcp_servers\.serena\]'` so the check requires the anchored TOML table header. Two new regression tests in `tests/install.bats` cover both the bug (stray substring present -> must still register) and the correct no-op behavior (real header present -> no duplicate block).

## [1.7.5] — 2026-04-25

### Added
- **Budget Discovery Hubs**: New logic to automatically discover .token-budget files across all your projects without a slow full-disk scan. Uses a hybrid of RTK history, local siblings, and explicit "Project Hubs".
- \`token-diet budget hubs <list|add <path>>\`: New CLI command to manage your project scan roots.
- \`scripts/install.sh\`: Added an interactive prompt during installation to seed your first Project Hubs.
- **Gemini CLI Support**: Added \`rtk init -g --gemini\` support to register TILTH/SERENA and install the RTK \`beforeTool\` hook in \`~/.gemini/settings.json\`.

### Fixed
- Dashboard: \`_registered_hosts\` now walks up the directory tree to find \`.vscode/mcp.json\`, ensuring VS Code registration is detected even when started from a subfolder.
- Dashboard: Support for the \`"servers"\` key in MCP JSON configurations (common in VS Code settings).
- Dashboard: Visual highlight (ACTIVE badge + green border) for the specific budget file currently being enforced for your workspace.
- Dashboard: Improved path visibility to distinguish between global, group, and project-specific budgets.

## [1.7.6] — 2026-04-25

### Added
- **Persistent Daily History**: \`token-diet clean\` now preserves a 30-day daily breakdown in the archive.
- **Dashboard History Merging**: The dashboard now automatically merges archived and live daily stats for accurate "Top Days" tracking.
- **Context-Aware Discovery**: The dashboard now uses the last recorded RTK project as context for budget highlighting and VS Code registration detection.

### Fixed
- Dashboard: Reverted budget filtering to show all discovered budgets (Global, Group, and Project) while maintaining the ACTIVE highlight.
- Dashboard: Simplifed Serena card by removing redundant Mode/Status lines and fixing version detection.
- Dashboard: Dynamic versioning now correctly pulls from the \`token-diet\` binary.
- 2026-04-25: v1.7.7 — fix pre-commit doc-sync regex; add 11 missing subcommands to README quick-reference table
- 2026-04-27: fix(doctor): fallback MCP registration checks when tilth doctor is unavailable; replace deprecated serena --headless flags with --open-web-dashboard false in installers
- 2026-05-04: v1.7.10 — fix(install): use correct OpenCode XDG path (~/.config/opencode/opencode.json), lowercase mcp key, and {type, command[], enabled} entry shape; also register tilth and detect Windows venv binary path
- 2026-05-04: v1.7.11 — fix(install): make Claude Code Serena MCP registration idempotent (check 'claude mcp get serena' before add; report 'already configured' instead of false-positive 'setup failed' warning)
- 2026-05-07: feat(install): add keylogger-mcp-wrapper injection — transparent MCP proxy logging for all registered servers (KEYLOGGER_MCP env var controls, default on)
- 2026-05-08: feat!(install): drop KEYLOGGER_MCP coupling. Remove `_keylogger_wrap_json_cmd`, `_keylogger_wrap_claude_cmd` (dead-code helpers — never called) and `_apply_keylogger_wrapper` (config rewrite that wrapped every registered MCP). token-diet no longer touches keylogger. Migration: install keylogger-mcp v0.2.0+ and run `keylogger-mcp wrap <host> <server>` per server you want logged. Reversible via `keylogger-mcp unwrap`. See `keylogger-mcp status`. Aligns with tilth v0.7.0 (same coupling removal).
- 2026-05-08: chore(release): bump TD_VERSION literal in scripts/token-diet from 1.7.11 to 1.9.0. The bash script's hardcoded version had drifted through v1.7.x → v1.8.0 → v1.9.0 tags without ever being bumped — `token-diet --version` reported 1.7.11 even after tag v1.9.0 shipped.

## [1.10.0] - 2026-05-29

### Added
- **ICM (Infinite Context Memory) as the 4th token-diet tool** alongside RTK, tilth, and Serena. ICM is a cross-tool persistent-memory MCP server (`icm serve --compact`), built from the audited fork `celstnblacc/icm` pinned to tag `icm-v0.10.50` (Apache-2.0; Rust virtual workspace, bin crate `crates/icm-cli`). Registered into the same hosts as Serena/tilth (Claude Code, Codex, OpenCode, VS Code, Cowork/Claude Desktop) using bare-path `icm serve --compact` invocations — never an embedded `forks/` path, and never via `icm init` (which would bake absolute `current_exe()` paths into host configs, an install-decoupling violation).
- **One-time-warmup embeddings policy (honest air-gap)**: `--local` builds use `--no-default-features --features tui`, so `fastembed` is never compiled and the binary physically cannot fetch a model (keyword-only). Online installs compile embeddings but ship them disabled via `~/.config/icm/config.toml` `[embeddings] enabled=false`; `token-diet icm warmup` flips that flag, runs `icm recall` once to fetch the ~270 MB model (intfloat/multilingual-e5-base), after which ICM runs offline.
- `doctor` JSON now emits `icm_mcp.registered_hosts` (mirrors `serena_mcp`).
- Compliance: ICM added to `compliance/SBOM.template.json` (upstream scheme) and `compliance/SBOM.json` (fork scheme, in `dependencies[0].dependsOn`); `compliance/LICENSE-THIRD-PARTY.md` updated for MIT + ICM Apache-2.0 with attribution checklist item; `compliance/security-audit.md` gained an `### ICM` section, network-isolation/supply-chain rows, and a 2026-05-29 audit-history entry.

### Changed
- Reconciled version drift across the three independently-owned version literals to **1.10.0**: `scripts/token-diet` `TD_VERSION` (was 1.9.0), `scripts/token-diet.ps1` `$script:TD_VERSION` (was 1.7.11), and `scripts/token-diet-dashboard` fallback literal (was 1.7.5).

### Fixed
- Windows `mcp list` contract fix so the PowerShell CLI reports the same registered-host set as the bash CLI.
- 2026-05-29: feat(uninstall): add ICM teardown to uninstall.sh + Uninstall.ps1 — `cargo uninstall icm`, remove ~/.local/bin/icm (plus orphaned rtk/tilth symlinks), strip icm MCP key from Claude Code/Desktop (mac+linux)/OpenCode/Cowork configs and the VS Code servers.* template, extend the Codex stale-table regex to (tilth|serena|icm), and remove ~/.config/icm/config.toml only under --include-data/-IncludeData.
- 2026-05-29: fix(forks/icm): re-pin forks/icm from tag icm-v0.10.50 to fork commit e6c1da3, which carries a NoEmbedder shim so the keyword-only build (`--no-default-features --features tui`) compiles. Upstream icm-v0.10.50 cfg-gated only some embedder sites, so the air-gapped `--local` ICM build failed (E0277/E0599); verified via `cargo tree` that fastembed is absent from the keyword-only dependency graph. SBOM submodule-commit updated to the patched SHA.
- 2026-05-29: feat(hosts): add Gemini CLI as the 7th token-diet host — wire RTK (rtk init --gemini), tilth, Serena, and ICM into Gemini CLI using gemini mcp add --scope user; write token-diet.md into ~/.gemini and reference from GEMINI.md; detect_hosts/hosts_registered/_doctor_check_mcp_gemini added; mock_gemini helper in tests; bats 153/0, pytest 20 passed.
- 2026-05-29: fix(token-diet): replace undefined info() calls in cmd_icm warmup with echo — info is an install.sh helper not available in the CLI script
- 2026-05-29: fix(token-diet): hosts_registered now checks ~/.claude.json (where claude mcp add --scope user writes) in addition to ~/.claude/settings.json — claude-code host was not showing in icm status/mcp list
- 2026-05-29: fix(token-diet): hosts_registered and cmd_doctor now detect tools in ~/.config/opencode/opencode.json (XDG path) and handle configs with both mcpServers and mcp keys — opencode was showing serena but not icm/tilth because the XDG config was missed and the mcp key was shadowed by mcpServers
- 2026-05-29: chore(release): bump to v1.10.1 — patch fixes: warmup info() crash, hosts_registered missing ~/.claude.json and opencode XDG path, mixed mcpServers/mcp key handling
- 2026-05-30: fix(token-diet): restore opencode config paths in hosts_registered array — ~/.opencode.json and ~/.config/opencode/opencode.json were accidentally dropped during dedup refactor, causing opencode to not appear in icm status display
- 2026-05-30: chore(release): bump to v1.10.2 — fix hosts_registered missing opencode configs
- 2026-05-30: fix(install): write token-diet-mcp to mcp key (not mcpServers) in OpenCode configs — mcpServers is Claude/Cowork format; OpenCode 1.x only recognizes mcp, and a foreign mcpServers key triggers ConfigInvalidError on startup. Also added remove_opencode_mcp_key helper to uninstall.sh and bumped to v1.10.3.
- 2026-05-30: fix(token-diet): doctor validation improvements — tilth new-format JSON parsing, serena/icm claude-code double-check false positive, gemini config-file detection (replaces gemini mcp list blocking call), _doctor_check_mcp_json silent_miss flag; bump v1.10.4
- 2026-06-05: docs: name ICM across all doctrine (CLAUDE.md, AGENTS.md, GEMINI.md, README.md, SBOM description) — the stack shipped four tools (RTK + tilth + Serena + ICM) but docs still described three; closes bulletproof doc-roster drift. Also commits the previously-uncommitted CLAUDE.md/AGENTS.md doctrine expansion that was sitting in the working tree
- 2026-06-05: fix(token-diet): cmd_upstream guards against running outside a source checkout (clear error instead of confusing per-tool git failures once installed to ~/.local/bin) and configures ICM's upstream remote; diff usage lists icm
- 2026-06-05: chore(compliance): bump SBOM application component version 1.0.0 → 1.10.4 to track the project (component list already carried icm@0.10.50)
- 2026-06-05: chore(release): bump to v1.10.5
- 2026-06-05: chore(gitignore): ignore local tool artifacts (.gemini/, .hablatone, .ship-check-passed, .shipguard/) so per-machine tool output never gets committed
- 2026-06-05: chore(submodule): bump forks/serena pin e5c8fd5 → da07972 to include the vendored MCP stdio EOF patch (server survives transient client disconnects; modelcontextprotocol/python-sdk#2549)
- 2026-06-11: ci(path-leak): add server-side Path Leak Guard workflow + scanner (.github/) that fails PRs introducing hardcoded local-machine paths (/Users/<name>, C:\\Users\\<name>, ...) in added diff lines — the server-side mirror of pre-commit check 1d, which never runs on fork PRs or API-side merges (the path that let the roym hardcoded path into #68). Uses on: pull_request (read-only, no secrets). Mark "Path Leak Guard" as a required status check to block merges.
- 2026-06-11: ci(path-leak): set explicit job name "Path Leak Guard" so the GitHub check name is deliberate (was the job id "scan") — this is the exact string to register as a required status check in branch protection.
- 2026-06-25: chore: remove personal workspace path from tracked files
- 2026-07-09: ci(upstream-check): add scheduled workflow (.github/workflows/upstream-check.yml + .github/scripts/upstream-check.sh) that checks forks/{rtk,tilth,serena,icm} against their original-author repos weekly and opens/updates a GitHub issue on drift — detection only, no auto-merge, keeps the manual `token-diet upstream diff <tool>` review gate intact. Bump TD_VERSION 1.10.7 → 1.10.8.
- 2026-07-09: chore(compliance): regenerate SBOM.template.json for 1.10.8 release — bump rtk 0.34.3→0.34.5, tilth 0.5.7→0.6.1, serena 0.1.4→0.1.5 to match current pinned submodule versions; icm unchanged at 0.10.50.
- 2026-07-10: fix(rtk): landed 4-commit permission-engine security fix (PR celstnblacc/rtk#9, merge commit 8ffb4f1) on forks/rtk master ahead of the full sync plan — closes the live compound-command allow-bypass and the `>&file` redirect bypass, unifies hook decision flow, adds unattestable-construct deferral. See PLAN-fork-upstream-sync.md.
- 2026-07-10: chore(rtk-sync): iteration 1 — pushed backup/pre-sync-2026-07-10 (= master @ 8ffb4f1) and sync/upstream-v0.43.0 (= upstream tag v0.43.0 @ 5a7880d) to celstnblacc/rtk. Triaged 23 fork-only commits: KEEP d9c22d5 (token-diet hook integration), 8ce33a1 + 8d95f93 (stdin-null hardening #897), ff52520 (telemetry-off policy, partial), 91a9bee, cd4f07c (.shipguard.yml); DROP the rest (superseded by native upstream, local dev-tooling noise, or moot version/CI bookkeeping). Per PLAN-fork-upstream-sync.md iteration 1.
- 2026-07-10: chore(rtk-sync): iterations 2-3 — re-applied token-diet integration patches (rtk-disabled sentinel on the native `rtk hook claude` path, telemetry-off verified) on sync/upstream-v0.43.0 (PR celstnblacc/rtk#9 fix commits, PR celstnblacc/rtk#10 landed the full sync onto master). Fixed a test-suite bug found along the way: running `cargo test` inside a git hook leaks `GIT_DIR`/`GIT_INDEX_FILE` into the test binary, redirecting isolated `git -C <tempdir>` test operations onto the real outer repo (`.cargo/config.toml` runner override fixes it). Re-wired `rtk doctor` after the tree merge dropped its CLI registration; removed orphaned `mvn-build.toml`. Bump forks/rtk pin to master @ v0.43.0, SBOM rtk 0.34.5→0.43.0, TD_VERSION 1.10.8→1.10.9. rtk portion of PLAN-fork-upstream-sync.md (iterations 1-3) complete; tilth and serena (iterations 4-8) remain.
- 2026-07-10: chore(tilth-sync): iterations 4-5 — full sync celstnblacc/tilth v0.6.1 to upstream v0.9.0 (PR celstnblacc/tilth#10). Re-applied the pager-injection guard as standalone src/pager_guard.rs (P-1 path-traversal guard deliberately skipped — upstream's own mcp::tools containment system supersedes it with its own test coverage; doctor.rs deferred — its install.rs dependencies were rewritten upstream). Removed 6 orphaned pre-sync files the tree merge left behind, one a real module-path conflict (src/mcp.rs vs new src/mcp/mod.rs) blocking compilation. Same git-hook-environment test fix as rtk (GIT_DIR/GIT_INDEX_FILE leak, plus a GIT_CONFIG_GLOBAL fix for fixtures that commit directly to throwaway repos). Bump forks/tilth pin to main @ v0.9.0, SBOM tilth 0.6.1→0.9.0, TD_VERSION 1.10.9→1.10.10. tilth portion of PLAN-fork-upstream-sync.md (iterations 4-5) complete; serena (iterations 6-8) remains.
- 2026-07-10: chore(serena-sync): iterations 6-8 — full sync celstnblacc/serena v0.1.6 to upstream v1.5.3 (PR celstnblacc/serena#7 for the patch commit, PR celstnblacc/serena#8 for the tree-merge landing onto main). Re-applied S-1 (shell metacharacter guard), S-2 (memory path-traversal guard, additive to upstream's own lexical ".." check for symlink-escape coverage), and a new SIGTERM/SIGHUP graceful-shutdown handler. Deferred `--no-shell` trust mode, `serena doctor`, and the vendored MCP stdio EOF patch — `cli.py` was rewritten substantially upstream. Removed 5 orphaned pre-sync files (4 docs pages superseded by upstream's restructured docs tree, 1 test for a removed `set_modes()` API). CHANGELOG.md needed the same multi-pass append-only restoration technique as rtk's. Fixed two local-environment issues: a global pre-commit hook `python3 -m pytest` invocation was resolving imports against an unrelated stray local serena checkout (fixed via pyproject.toml `pythonpath` + a repo-scoped `.project-hooks/pre-commit` that runs `uv run pytest`), and docker/Dockerfile.serena's LSP-server COPY referenced a `tsserver` binary that no longer exists in current npm typescript packages (fixed to copy `typescript-language-server` + `tsc` instead). Verified: 153 bats + 113 pytest (fast suite) + full serena test suite (571 passed, 6 pre-existing Go/Nix-toolchain failures unrelated to this fork) all green; Docker image builds and serves a live MCP initialize + tools/list round-trip. Bump forks/serena pin to main @ v1.5.3, SBOM final pass (rtk 0.43.0, tilth 0.9.0, serena 1.5.3, icm 0.10.50), TD_VERSION 1.10.10→1.11.0. PLAN-fork-upstream-sync.md complete — all 8 iterations landed.
- 2026-07-10: fix(fork-drift): `token-diet upstream check/diff` and the weekly drift-detection workflow both compare via `git log HEAD..upstream/branch` (ancestry-based). The `--strategy=ours` tree-merge landing technique used for rtk/tilth/serena's syncs never records true git ancestry with upstream even though content matches — so this check reported the entire pre-sync history as "new" for all three forks. Fixed by recording a synthetic no-op ancestor merge (`git merge -s ours --allow-unrelated-histories <upstream-tag>`) on each fork's default branch: rtk (celstnblacc/rtk master, now ba84820, ancestor v0.43.0), tilth (celstnblacc/tilth main, now 9c59d4b, ancestor v0.9.0). serena needed no fix — its sync branch already carried real ancestry to v1.5.3 from iteration 7. Verified: `HEAD..upstream/branch` now reports only genuinely new upstream commits (rtk: 0, tilth: 64 real new commits since v0.9.0, serena: 147 real new commits since v1.5.3) instead of the whole pre-sync backlog. Bump forks/rtk and forks/tilth pins.
- 2026-07-11: fix(org-transfer): `celstnblacc/{rtk,tilth,serena,icm}` were transferred into the `artificemachine` GitHub org at some point during the fork-sync work — the old `celstnblacc/*` URLs still resolve today only via GitHub's 301 redirect, which is fragile (breaks if anyone ever creates a new repo at the old name). Repointed every live reference to `artificemachine/*`: `.gitmodules`, all four `forks/*` submodules' `origin` remote, `scripts/token-diet`(.ps1) self-update clone source + serena uvx fallback, `scripts/install.sh`/`Install.ps1` repo constants + generated MCP config, `scripts/playbook.yml`, `README.md`, `.shipguard.yml` comment. `celstnblacc/token-diet` is a separate, real repo (not a transfer) — left untouched where it isn't this project's own canonical URL. Also fixed a real, unrelated bug surfaced by the same audit: `cmd_upstream`'s icm_url and `.github/scripts/upstream-check.sh`'s icm entry both pointed at `celstnblacc/icm` (our own fork) instead of icm's true upstream `rtk-ai/icm` — icm's drift check had always been comparing HEAD against itself and trivially reporting "up to date". Fixed to `rtk-ai/icm.git` and corrected `forks/icm`'s `upstream` remote to match; icm is actually 76 commits behind rtk-ai/icm, now correctly surfaced. CLAUDE.md's `forks/` comment block still references `celstnblacc/*` — left alone per the protected-instruction-files rule (edit only when explicitly named).
- 2026-07-11: chore(icm-sync): first real sync, upstream rtk-ai/icm v0.10.34 to v0.10.57 (383 commits, artificemachine/icm PR #1). main had zero prior fork divergence — the previously "up to date" status was because the drift check compared against our own fork (see the org-transfer fix above), and the only fork-specific work (the NoEmbedder shim, e6c1da3) was sitting unmerged on a side branch — a clean merge (not a tree-merge) landed this one. Dropped the NoEmbedder shim: upstream independently added an equivalent `DisabledEmbedder` (issue #301 Store-enum backend split) solving the same `--no-default-features` compile problem. Kept `.project-hooks/pre-commit` (build-guard hook) but had to fix its lean-build invocation: upstream's backend split now requires an explicit `backend-*` feature alongside `tui` — `--features tui` alone leaves the `Store` enum with zero variants, failing to compile (E0004, non-exhaustive `&Store` match). This same stale flag set was baked into token-diet's own installer in four places — fixed `scripts/install.sh`, `scripts/Install.ps1`, `scripts/build.sh`, `scripts/playbook.yml` from `--features tui` to `--features tui,backend-sqlite`, matching upstream's own documented lean-build recommendation in Cargo.toml. Verified end-to-end: `bash scripts/install.sh --local --icm-only` rebuilds and installs `icm 0.10.57` cleanly (previously failed with "the package 'icm-cli' does not contain this feature: backend-sqlite" using the old flags against the new source). CLAUDE.md forks/ comment block fixed (celstnblacc/* → artificemachine/*, explicitly authorized this time). Bump forks/icm pin to main @ v0.10.57, SBOM icm 0.10.50→0.10.57, TD_VERSION 1.11.0→1.11.1.
- 2026-07-11: chore(tilth-serena-incremental-sync): incremental resync of forks/tilth (64 commits, v0.9.0 to e7ef464) and forks/serena (147 commits, v1.5.3 to 065df5ea), both artificemachine PRs (tilth#11, serena#9). Both merged cleanly as normal 3-way merges — no tree-merge needed, no orphaned files — because the earlier ancestry fix (rtk/tilth) and serena's already-real ancestry made each fork's tagged sync point a true git ancestor of its current main. tilth: 2 trivial conflicts (.gitignore additive entries, src/lib.rs auto-resolved); src/pager_guard.rs untouched. serena: a real security/feature tradeoff — upstream added its own memory-path containment check (`_resolve_memory_path`, commit 310a01c1) deliberately lexical (no symlink resolution) to support a new feature, symlinked memory directories for monorepo sharing; this is incompatible with S-2's stricter symlink-escape rejection. Adopted upstream's version per explicit user decision; test_security.py's symlink test now asserts the new supported behavior instead of rejection. S-1 and the graceful-shutdown handler merged clean. Neither fork cut a new release tag (both synced to unreleased upstream main), so SBOM component versions are unchanged. TD_VERSION 1.11.1→1.11.2.
- 2026-07-11: fix(upstream-diff): `token-diet upstream diff <tool>` had a shell-grouping bug — `A 2>/dev/null || cd "$dir" && B` parses as `(A || cd) && B` (bash `||`/`&&` share precedence, left-to-right), so B (`git diff HEAD..upstream/master`) always ran regardless of whether A (`git diff HEAD..upstream/main`) succeeded. For tools using "main" as their default branch (tilth, serena, icm — 3 of 4), this meant every `diff` invocation printed the correct diff from A, immediately followed by a `fatal: ambiguous argument 'upstream/master': unknown revision` from the spurious B. rtk (which genuinely uses "master") masked the bug by accident — A failed as expected and B happened to be the real diff. The error went unnoticed in this session's own testing because `2>&1 > file` redirect ordering sent stderr to the terminal, not the saved file. Fixed by checking which ref actually exists (`git rev-parse --verify --quiet upstream/main`) before choosing which single diff to run, in both `scripts/token-diet` and `scripts/token-diet.ps1` (which additionally had no master fallback at all, and its usage string listed only "rtk|tilth|serena", missing icm — both fixed to match). Verified: `token-diet upstream diff <tool>` now exits 0 cleanly for all four.
- 2026-07-19: feat(extract): add docextract document-to-text core (scripts/lib/docextract.py + tdcache.py) and `token-diet extract <file>` subcommand — hash-cached PDF/csv/html/txt extraction with exit codes 2 (no extractor), 3 (needs markitdown, deferred to v2), 4 (missing file). Test fixtures (PDF included) generated at pytest runtime — no binaries committed. Iteration 1 of PLAN-docextract-ctxwarn.md. TD_VERSION 1.11.4 -> 1.12.0.
- 2026-07-19: feat(budget): add ctxwarn transcript token estimator (scripts/lib/ctxwarn.py, shares tdcache.py with docextract) as a `token-diet budget --check --transcript <file>` arm — estimates a JSONL transcript's token size via tiktoken (chars/4 fallback), warns once per `.token-budget` `ctx_threshold` band (default 100000), debounces repeat calls in the same band, always exits 0. Iteration 2 of PLAN-docextract-ctxwarn.md. TD_VERSION 1.12.0 -> 1.13.0.
- 2026-07-19: feat(install): add opt-in `install.sh --with-context-hooks` — registers docextract (PreToolUse/Read intercept, cached-extraction swap) and ctxwarn (PostToolUse transcript check) hooks into Claude Code's `~/.claude/settings.json` via a new idempotent `merge_hook_entry()` helper (command-string dedup key, backs up before writing, never partial-writes a malformed config); every other detected harness gets `awareness-docextract.md` instead, since their hook schemas are unverified (Gemini OQ-2, new Copilot OQ-3 — both deliberately deferred rather than guessed at). Hook shims install to `~/.local/bin/token-diet-hooks/` per this project's installed-path decoupling rule. `uninstall.sh` removes both hook entries and the shim directory symmetrically. Rewrite of the original Iteration 3 plan (docs/PLAN-docextract-ctxwarn.md revision log, 2026-07-19): the original assumed install.sh already had reusable settings.json hook-merge machinery to extend — verified false (that logic lives only in the pinned Rust submodule forks/rtk, unreachable from bash) before any code was written. OQ-1 confirmed: `cmd_hook()`'s two definitions (scripts/token-diet:611,666) are functionally identical, so dispatch resolving to the second is a no-op duplicate, not a bug affecting this feature. Iteration 3 of PLAN-docextract-ctxwarn.md, revised. TD_VERSION 1.13.0 -> 1.14.0.
- 2026-07-19: docs(plan): append build-outcome block to PLAN-docextract-ctxwarn.md — all 3 iterations shipped (70cc457, eb6ea74, 9608379), deviations and learnings recorded.
- 2026-07-19: fix(install): `install_token_diet()` never copied `scripts/lib/{docextract,tdcache,ctxwarn}.py` to `~/.local/bin/lib/` — `cmd_extract`/`cmd_budget --check` shell out to `$SCRIPT_DIR/lib/<name>.py`, and once installed the running copy's `$SCRIPT_DIR` is `~/.local/bin`, not the repo checkout. Every test in this repo (and every prior manual verification) ran `token-diet` from the dev checkout, where `scripts/lib/` is a sibling directory, so the bug was invisible until a real `install.sh --with-context-hooks` run against a live HOME (v1.14.0 already shipped with this broken — `extract`/`budget --check` failed post-install for every user, not just `--with-context-hooks` users). Fixed: `install_token_diet()` now copies the three Python cores to `$bin_dir/lib/`; `uninstall.sh` removes them symmetrically. New regression tests run the INSTALLED binary (not `$SCRIPTS_DIR/token-diet`) end-to-end for both subcommands — the exact gap that let this ship. TD_VERSION 1.14.0 -> 1.14.1.
- 2026-07-19: fix(docextract-hook): the PreToolUse shim at `scripts/lib/hooks/docextract-pre-read.sh` intercepted `.md` and `.txt` reads, causing two problems. (1) `.md` infinite loop: docextract's cache format is always `.md` (`tdcache.cache_path` default suffix), so reading a `.md` source → extracted to a `.md` cache → the cache's own Read re-triggered the same hook → never terminates. This was caught live on this machine while writing the prior session handoff: Read on `HANDOFF.md` became effectively broken for the entire repo checkout as long as the hook was registered. (2) `.txt` pointless extraction: already plain text, extracting only adds a round trip. Fixed: shim's intercepted-suffix set is now `{pdf,csv,html,htm}` — `.md`/`.txt` exit 0 (passthrough). Comment block in the shim documents the loop bug for future readers. The standalone `token-diet extract somefile.md` CLI still works (the core module's EXTRACT set is unchanged — shim interception policy and core extraction capability are intentionally separate concerns). New bats regression in `tests/install.bats` cycle 6.1 covers all three cases (`.md` passthrough, `.txt` passthrough, `.pdf` still blocks). `mock_token_diet_extract` helper added to `tests/test_helper.bash` simulates a successful extract returning a `.md` cache path — without it, the shim falls through to passthrough when extract fails and the bug stays hidden. TD_VERSION 1.14.1 -> 1.14.2.

- 2026-07-19: chore(refactor): delete duplicate `cmd_hook()` and `cmd_mcp()` from `scripts/token-diet` (OQ-1). Two definitions of each existed (cmd_hook at old lines 611 + 666, cmd_mcp at old lines 574 + 629) — bash function shadowing meant dispatch always reached the second definition, making the first pure dead code. `cmd_hook` duplicates differed only in color codes (first used ${RED}/${GREEN}, second was bare); `cmd_mcp` duplicates were byte-identical. Discovered `cmd_mcp` was ALSO duplicated while doing this cleanup (HANDOFF only flagged `cmd_hook`); both deleted together since the fix is identical. 4 new bats regressions (cycle 17.1): two assert exactly one definition of each function exists in source (catches future re-introduction at test time), two smoke tests confirm `hook` and `mcp` dispatch behavior is unchanged post-deletion. Net diff: -54 lines deleted, +47 lines added (regressions). TD_VERSION 1.14.2 -> 1.14.3.

- 2026-07-19: fix(ctxwarn): debounce state file now keys on abspath alone (was: mtime). scripts/lib/tdcache.cache_path() gained a key_by_mtime: bool = True parameter; scripts/lib/ctxwarn.py opts out with key_by_mtime=False. Root cause: the debounce state file cache key was sha256(abspath:mtime_ns). Real Claude Code sessions append to the transcript JSONL on every tool use, which updates mtime_ns, so every PostToolUse call hashed to a fresh state file, the recorded band reset to 0, and the warning re-fired every time the threshold was exceeded (effectively no debounce). Caught live: 154 stale .band files all containing 1 had accumulated under ~/.cache/token-diet/ctxwarn/ across prior sessions; this session alone produced a 5th-band file for the 535k-token transcript that proves the per-band semantic works once the key is fixed. 2 new pytest regressions in tests/test_ctxwarn.py: test_debounce_holds_across_transcript_appends (asserts the warning does NOT re-fire across transcript appends that keep the estimate within the same band) and test_band_transitions_still_warn (asserts the warning DOES re-fire when the estimate crosses into a new band, proving the fix preserves once-per-band, not just once-ever). TD_VERSION 1.14.3 -> 1.14.4.
- 2026-07-19: feat(install): wire docextract + ctxwarn hooks for OpenCode and Copilot CLI. New TS plugin at scripts/lib/hooks-plugins/opencode.ts installs to ~/.config/opencode/plugins/token-diet-hooks.ts (mode 644) and registers in opencode.json plugin array via idempotent merge (preserves pre-existing plugin entries, never duplicates). Plugin uses tool.execute.before to substitute args.filePath with the docextract cache for the read tool (mirrors rtk.ts command-rewrite pattern), and tool.execute.after to estimate session tokens via client.session.messages and warn once per band (state keyed by sessionID only, no mtime — same lesson as v1.14.4's Claude Code fix). Plugin also reads .token-budget for ctx_threshold by walking up from cwd to HOME, mirrors ctxwarn.py exactly. Copilot CLI (OQ-3): verified via README that v0.0.377 has no hook surface (only custom agents / LSP / MCP) — awareness doc fallback at ~/.copilot/awareness-docextract.md now installed (previously skipped entirely). 3 new bats regressions in tests/install.bats cycle 6.2: OpenCode plugin installs + registers + idempotent on second run, Copilot awareness doc written when --hosts copilot, source-level check that shipped plugin wires both handlers. install.sh dry-run branch updated to describe new paths. TD_VERSION 1.14.4 -> 1.14.5.
- 2026-07-19: fix(install): Copilot CLI detector accepts both `github-copilot-cli` (legacy Homebrew) and `copilot` (current npm @github/copilot). The v1.14.5 commit only checked the legacy name, silently missing npm-installed users (including this machine). Caught during live-install validation per the v1.14.4 lesson. New bats regression in tests/install.bats mocks the legacy `github-copilot-cli` binary and confirms awareness doc is written — together with the existing `copilot`-mocked test, both detection paths are now covered. No version bump (fix to v1.14.5, not a new feature).

- 2026-07-19: feat(install): wire real hooks to Gemini CLI (OQ-2 resolved). Gemini CLI v0.49.0 has a `gemini hooks migrate --from-claude` subcommand (verified by extracting the migrate implementation from bundled JS in `gemini-APNDCIQH.js`). The hooks schema is identical to Claude Code's `~/.claude/settings.json` JSON format with one difference: tool names are mapped (Read->read_file, Bash->run_shell_command, Edit->replace, etc.) via TOOL_NAME_MAPPING. Same merge_hook_entry helper now writes to `~/.gemini/settings.json` with matcher `read_file` (docextract) and `*` (ctxwarn). Awareness doc still written as courtesy fallback. OQ-2 confirmed-closed. 3 new bats regressions in tests/install.bats cycle 6.3. TD_VERSION 1.14.5 -> 1.14.6.
- 2026-07-20: chore(ci): add missing test workflow + harden path-leak.yml. New `.github/workflows/test.yml` runs bats+pytest on every push/PR to main — previously the test suite was only enforced by the local pre-commit hook, so a fork PR or a `--no-verify` bypass could land untested. `.github/workflows/path-leak.yml`: pinned `actions/checkout` to a commit SHA (was mutable `@v4` tag) and replaced `fetch-depth: 0` (full-history clone on a `pull_request`-triggered workflow) with `fetch-depth: 1` plus a targeted `git fetch --depth=1` of just the PR's base and head SHAs — same diff capability, smaller blast radius. Also pruned GitHub releases to the 10-tag retention threshold (deleted v1.10.8, v1.11.0) and cleared 2 stale `.band` debounce files under `~/.cache/token-diet/ctxwarn/`. TD_VERSION 1.14.6 -> 1.14.7.
- 2026-07-20: fix(doctor): serena/icm registration miss under-reported when claude-code only has settings.json. `_doctor_check_mcp_json()`'s cc_global (`~/.claude.json`) fallback check silently treated a missing file as "host not installed" even when `~/.claude/settings.json` already proved claude-code was installed, so a genuinely-missing serena/icm registration went unreported. Caught by the very first run of the new CI test workflow (added earlier this session): `doctor: exits 1 when serena not registered in claude-code` failed on a clean Ubuntu runner but passed locally only because this dev machine has a real `gemini` binary on PATH that `_doctor_check_mcp_gemini` picked up and flagged instead (masking the real bug). Fix: new `assume_installed` 6th param on `_doctor_check_mcp_json()`, passed by the serena/icm call sites when `cc_cfg` exists — a missing `cc_global` in that case is now correctly reported as "not registered" rather than silently skipped. Also installed the CI workflow's missing optional test dependencies surfaced by the same first run: `jq`, `poppler-utils` (pdftotext), `tiktoken`, `pdfplumber`. Verified green in a from-scratch Ubuntu 24.04 container (186 bats, 46 pytest) matching CI exactly, plus local macOS re-run. No version bump (fix to the same unreleased v1.14.7).
- 2026-07-20: test(ci): fix remaining test-isolation gaps surfaced by the new CI workflow's second run. Several bats tests only mocked a subset of the real-world CLIs they exercised (`uv` but not `uvx`; no `codex` mock at all), so they passed locally only because this dev machine happens to have `uvx` and `codex` genuinely installed on PATH — masking the gap the same way the `gemini` leak did in the doctor fix above. Fixed: added `mock_cmd uvx` to the single-quoted-TOML health test, added `mock_cmd codex` to both codex-stray-substring install.sh tests. Also replaced 5 test assertions that called the real `rtk`/`tilth` CLI directly (`rtk diff`, `rtk grep -q`) with plain `diff`/`grep` — those tests were meant to check file content, not exercise RTK, and would `command not found` (status 127) on any machine without RTK installed, including CI. Also added `bc` to the CI workflow's apt-get install list — `cmd_budget`'s K-formatted output silently produced `0.0K` for every field without it (no error surfaced, just wrong numbers), breaking one budget-status test's substring check. Verified green end-to-end in a from-scratch Ubuntu 24.04 container: 186 bats + 46 pytest, exit 0. No version bump (test-only, same unreleased v1.14.7).
- 2026-07-20: fix(doctor): tilth MCP registration false-negative from an unwired `doctor` subcommand. Found via live-install validation on this machine (`bash scripts/install.sh --local`): `token-diet doctor` reported "tilth: not registered in any MCP host" even though tilth was genuinely registered everywhere. Root cause: the installed `tilth` binary has no `doctor` subcommand wired into its CLI at all — `forks/tilth/src/doctor.rs` exists (403 lines, fully implemented, has its own unit tests) but was never declared in `lib.rs`'s `pub mod` list, so it isn't compiled into the binary or reachable from `main.rs`'s dispatcher. `tilth doctor --json` therefore parsed `doctor` as tilth's `[QUERY]` search argument instead, returning real-but-unrelated search-result JSON that `cmd_doctor()` misread as an unhealthy report. Fixed in `scripts/token-diet` (not the pinned fork, which stays untouched per project convention): validate the JSON actually has a `hosts` or `checks` key before trusting it as a doctor report; when it doesn't, fall through to the same direct MCP-config-file check already used for older tilth versions. That fallback path had its own pre-existing bug — checking both `claude-code`'s settings.json and .claude.json unconditionally produced a contradictory double-print (one ✗, one ✓) for the same host — fixed with the same silent-first / assume_installed pattern already applied to the serena/icm checks earlier this session. Confirmed fixed live: `doctor` now reports "All checks passed — stack is healthy" on this machine. 186 bats + 46 pytest still green. TD_VERSION 1.14.7 -> 1.14.8.
- 2026-07-20: fix(install): harden `confirm_hosts()` `--hosts` filter + tighten test isolation, from a proactive env-coupling audit. `confirm_hosts()` in `scripts/install.sh` previously returned early ("nothing to choose from") whenever 0 or 1 hosts were auto-detected, *before* checking whether `--hosts` was explicitly supplied — meaning an explicit `--hosts` filter silently had no effect on any machine with 0-1 real host binaries on PATH. Reordered so the `--hosts` filter check runs first and always applies regardless of detected-host count; the early-return now only gates the interactive multi-choice prompt, which is the only thing that actually needs 2+ candidates. Also scoped 6 context-hook tests in `tests/install.bats` (`--icm-only --with-context-hooks` invocations that previously passed no `--hosts` flag) to explicit `--hosts claude` / `--hosts claude,opencode`, matching the pattern an earlier fix in this session already used for one sibling test (`context hooks: non-claude harness gets awareness-docextract.md`) — these tests only mocked `claude` (and `opencode` for one of them) but this machine's real `codex`/`opencode`/`gemini`/`copilot` binaries were still leaking through as additional "detected" hosts, causing the installer to silently do extra per-host work the tests never asserted on. No test currently failed from this (assertions didn't diverge), but it meant local runs exercised different code paths than a clean CI box without that difference being visible — the same env-coupling risk class already found and fixed 3 times earlier this session, caught this time by a proactive audit rather than a CI failure. 186 bats + 46 pytest, verified in a from-scratch Ubuntu 24.04 container and locally on macOS. TD_VERSION 1.14.8 -> 1.14.9.
- 2026-07-20: feat(ctxwarn): print the threshold-crossing warning in red. `scripts/lib/ctxwarn.py`'s warning line (`Context ~Nk tokens. Consider /compact or a fresh session.`) now wraps in ANSI red (`\033[0;31m` / `\033[0m`), unconditionally rather than gated on `sys.stdout.isatty()` — a TTY-gated version was tried first but verified to resolve to no-op in the actual hook-firing context (Claude Code invokes the hook as a piped subprocess, `isatty()` is always `False` there), which would have made the color invisible exactly where the warning is meant to be seen. Confirmed via `subprocess.run(capture_output=True)` (the same invocation shape as the real hook) that the escape codes are present in stdout regardless of piping. No existing test asserted the exact warning string, so nothing needed updating. 186 bats + 46 pytest still green. TD_VERSION 1.14.9 -> 1.14.10.
- 2026-07-20: chore(deps): bump `forks/tilth` submodule pin to pick up removal of dead `doctor.rs`. Root-caused and fixed upstream in [artificemachine/tilth#12](https://github.com/artificemachine/tilth/pull/12): `doctor.rs` was added in a single commit at v0.8.0 but never declared in `lib.rs`'s `pub mod` list (so `tilth doctor` never worked as a real subcommand), and later bit-rotted further when `install.rs` was refactored down to a single public function — `doctor.rs`'s host-probing code no longer even compiled against current `install.rs`. Rather than rebuild that logic (real feature work in a separate repo), removed the dead file upstream instead; token-diet's own workaround (shipped earlier this session in v1.14.8) already handles the practical symptom via the JSON-shape-validation fallback, which continues to work correctly now that `tilth doctor --json` cleanly fails to produce a report (rather than returning a misleading search-result JSON). Rebuilt and reinstalled tilth from the updated fork source; `token-diet doctor` confirmed still healthy. 186 bats + 46 pytest green. No `TD_VERSION` bump — submodule pointer change only, no token-diet code changed.
- 2026-07-20: fix(gain): live rtk totals were silently dropped, under-reporting savings by ~95%. `cmd_gain` piped the live rtk JSON into `python3 - "$arch" << 'PY'`, but `python3 -` reads its program from stdin, which the heredoc already supplies, so the pipe was discarded (shellcheck SC2259, the only shellcheck *error* in the codebase). `json.load(sys.stdin)` therefore parsed the Python source itself, hit the bare `except`, and set every live value to zero — `gain` displayed archived totals alone. On the machine where this was found it reported 153,114 commands and 4.8M tokens saved; the true figures including live history were 200,194 commands and 92.5M tokens saved (83.9%). Fix: pass the JSON as `argv[2]` instead of piping, and narrow the bare `except` to `except Exception`. Two bats regressions added: one asserts live totals appear at all, one asserts live and archived totals are summed (10 live + 90 archived must render 100, not 90). README sample output corrected to the accurate figures.
- 2026-07-20: fix(install): config mutation is now atomic and loud. New `scripts/lib/tdconfig.py` provides `atomic_write_json` / `update_json` / `load_json`: serialize fully before touching the target, write to a same-directory temp file, fsync, then `os.replace` (atomic on POSIX and Windows), preserving the original file mode and taking a backup on the success path. Replaces two blocks in `install.sh` that did `open(cfg,"w")` — which truncates before serializing — inside `except Exception: pass`, so a mid-write failure left the user's `~/.claude/settings.json` empty with no message, and a malformed input was silently skipped while seven sibling blocks aborted loudly on the same condition. Both call sites now report the skip and continue. `tdconfig.py` added to the installed Python cores (omitting a new core from that manifest is how `cmd_extract` shipped broken in v1.14.0). 15 pytest regressions covering truncation, temp-file cleanup, mode preservation, backup-on-success, and malformed-input handling.
- 2026-07-20: fix(install): report what was already modified when an install fails partway. `install.sh` ran under `set -euo pipefail` with no `ERR` trap, so a failure at host five of seven exited silently with five hosts mutated and no record of which. Adds a `TD_MUTATED` accumulator, `td_record_mutation`, and an `ERR` trap that lists every file touched before the failure, points at the timestamped backups, and states that re-running is safe because registration is idempotent.
- 2026-07-20: security(ci): path-leak guard gains a full-tree mode and now runs on push as well as pull_request. Diff mode only matched home paths under a known subdirectory (`Documents|Desktop|Downloads|Library|.local`), so `/Users/<name>/Projects/...` passed straight through — which is how a home path came to sit in a committed file while the guard was green on every PR. Full-tree mode scans every tracked file. Implemented in python3, not `grep -qP`: the negative lookahead needs PCRE, BSD grep on macOS has no `-P`, and the first implementation paired that with `2>/dev/null`, producing a guard that silently matched nothing locally while working in CI. 11 bats regressions, each asserting the guard *fails* on planted input rather than only that it passes on clean input.
- 2026-07-20: chore(repo): untrack `HANDOFF.md` and `.vscode/mcp.json`, both now gitignored. `HANDOFF.md` was agent session-log working state carrying machine-local absolute paths into the public tree. `.vscode/mcp.json` had its portable `"command": "tilth"` rewritten to an absolute binary path on every install, because `install.sh` calls `tilth install <host>` and tilth's installer writes the absolute path back into the invoking project's config — a symptom previously patched in five separate commits (`4751685`, `43eebaa`, `2495d6a`, `1e9a92c`, `f408b4f`) without addressing the cause. The portable template still installs to `~/.config/token-diet/vscode-mcp.template.json`.
- 2026-07-20: docs: honest claims, community files, and reorganization. Replaced the unsourced "40-90%" / "60-90%" headline (three different figures across README, CLAUDE.md, and the repo description) with per-tool figures and their methods in new `docs/benchmarks.md`: tilth's -38%/-44% cost-per-correct-answer is genuinely benchmarked over 160 runs and was previously uncited; RTK's 60-90% is measured live from the user's own history; Serena and ICM are explicitly labelled unmeasured, and no combined stack-wide percentage is published. Fixed a literal `\n` mangling the `clean` line of `--help` output, and `version`'s "all three tools" (there are four). Added `SECURITY.md`, `CODE_OF_CONDUCT.md`, issue templates, and a PR template; rewrote `CONTRIBUTING.md` to drop the "PRs without an issue will not be reviewed" gate and document `--recursive` plus prerequisites. Moved `GEMINI.md` to `.github/`, archived 13 stale session/plan documents to `docs/archive/`, and added `docs/README.md` as an index. New `docs/engineering-notes.md` records the debugging methodology and the bugs behind it. Windows is now labelled experimental and untested in CI, which is accurate: 46 Pester tests run in no workflow and the PowerShell CLI lacks the context hooks entirely.
- 2026-07-20: chore(release): TD_VERSION 1.14.10 -> 1.15.0. Minor rather than patch: alongside the fixes above this adds new capability (full-tree mode for the path-leak guard, the `scripts/lib/tdconfig.py` atomic-config module, and partial-failure reporting via an ERR trap in install.sh). Tests: 199 bats, 61 pytest, 0 failures.
- 2026-07-20: fix(docs): scrub a local username re-introduced by the audit and plan documents. The production-readiness pass closed a personal-data gate by untracking HANDOFF.md, then re-introduced the same username in three places inside `docs/PLAN-production-ready.md` and `docs/audits/2026-07-20-job-ready.md` — twice as a literal in a documented `git grep <username> HEAD` verification command, once inside a quoted prior decision. The full-tree path-leak scanner did not catch it because it matches `/Users/<name>/`-shaped paths, not a bare username used as a search term. Replaced with `$(id -un)` and a generic description. Note: the scanner cannot generically detect bare usernames without embedding the username it is looking for, which would defeat the purpose; the durable control is not writing them down. One historical occurrence of a different username remains in this CHANGELOG (entry dated 2026-06-11) and is deliberately left alone, since this file is append-only.
- 2026-07-20: fix(release): `scripts/release.sh` could never complete a run, and would have tagged the wrong version if it had. Two independent defects, both invisible because the script was never successfully executed end-to-end. (1) Under `set -euo pipefail`, `record_ok`/`record_warn` incremented counters with `(( PASS++ ))` / `(( WARN++ ))`. Bash post-increment evaluates to the *old* value, so the first increment from `0` returns `0`, which arithmetic evaluation reports as a failed command, and `set -e` aborted the script. The gate therefore died at whichever check first passed or warned — in practice the very first preflight check — which is why every release in this project's history was tagged by hand. Replaced all 8 sites with `X=$((X + 1))`. (2) `VERSION` was hardcoded to `1.2.0` while `TD_VERSION` was `1.15.0`, thirteen minor versions stale; the gate would have created a `v1.2.0` tag on a 1.15.0 tree. `VERSION` is now derived by parsing `TD_VERSION` out of `scripts/token-diet`, with a hard failure if that parse yields nothing. 3 bats regressions assert no literal version is reintroduced, that the derived value matches `TD_VERSION`, and that bash and PowerShell versions stay in lockstep; the literal-version guard was negative-tested against planted input rather than only confirmed green on a clean tree. TD_VERSION 1.15.0 -> 1.15.1.
- 2026-07-20: feat(release): automatic GitHub release retention, and a tracked policy to enforce it against. The "10-tag threshold" this project was documented as violating existed only in `HANDOFF.md` — untracked and gitignored since the prior session — while an archived handoff stated a conflicting number ("keep latest 5"), so the rule was unavailable to any reader or check. New `docs/release-policy.md` is the single source of truth and makes the tag/release distinction explicit: **tags are permanent history and are never pruned; GitHub releases are a curated surface capped at 10**. That reframes the 62 tags without a release page as intended rather than as debt. `scripts/release.sh` gained `RELEASE_RETENTION` (default 10, env-overridable) and a `prune_releases` step that deletes the release only and never the tag, skips with a notice when `gh` is missing or unauthenticated, and reports without acting under `--dry-run`. Gated on `$DO_TAG || $DRY_RUN` so `--test-only` and `--sign-only` cannot delete a release as a side effect of running checks. Pruned the 3 oldest releases (v1.11.4, v1.14.0, v1.14.1) back to 10, retaining all three tags. 3 further bats regressions cover the retention constant, the tag-deletion invariant (negative-tested with a planted `git tag -d`), and the policy doc's existence.
- 2026-07-20: chore(repo): delete 27 merged remote branches, each verified to carry 0 unique commits via `git cherry main`. Three branches were deliberately retained because they do carry unique commits: `fix/path-leak-guard` and `fix/opencode-mcp-registration` are superseded in substance (the path-leak workflow is on `main` and was hardened further; the latter bumps to 1.7.10 against a 1.15.x tree), but `fix/dashboard-projection-and-efficiency` contains genuinely unmerged work — `projection_stats` on `main` still computes the weekly projection as a naive 7-day mean with no volume filter, so a day with 2 commands weighs the same as a day with 5,000; the branch adds a `commands >= 10` qualification plus a 30-day average. Left in place pending a decision rather than deleted. Note the branch count had drifted to 30 by fetch time, not the 27 the prior audit recorded, so the deletion set was recomputed from `git cherry` rather than taken from the audit.
- 2026-07-20: fix(release): move release retention enforcement into `.github/workflows/release.yml`, where it actually runs. The retention prune shipped in v1.15.1 lived only in `scripts/release.sh`, and nothing invokes that script on the tag path — so the first real run of the new `release.yml` created the v1.15.1 release and put the count at 11, one over the documented limit of 10, within seconds of the policy being introduced. Enforcement that lives somewhere which never executes is not enforcement; this is the same shape as the release gate that could not complete a run (v1.15.1) and the path-leak guard that could not fail (v1.15.0), and it was caught only because the tag was pushed without hand-creating the release first, which exercised the automation for real rather than assuming it worked. `release.yml` now prunes immediately after creating a release, deleting the GitHub release only and never the tag. Pruned v1.14.2's release to return to 10; its tag is retained and `git checkout v1.14.2` still works. 2 bats regressions assert the workflow carries a retention step and that it never deletes a tag. `docs/release-policy.md` now documents both enforcement points and why the workflow one is the one that matters. TD_VERSION 1.15.1 -> 1.15.2.
- 2026-07-20: fix(dashboard): exclude low-volume days from the weekly projection, and report a 30-day baseline alongside the 7-day trend. `projection_stats` averaged raw daily entries with no volume weighting, so a day the machine was barely used counted as much as a full working day. Measured on a three-day sample where two days had 500 commands and one had 2, the single near-idle day dragged the weekly projection from 70,000 down to 46,690 — a 33% understatement driven entirely by a day that carried no meaningful signal. Days below `MIN_DAILY_COMMANDS` (10) are now excluded before averaging. The filter deliberately degrades to a no-op when the data carries no `commands` field at all: treating a missing field as zero volume would drop every day and turn an absent field into "no data", which the first version of this change did and which the pre-existing `test_projection_stats` caught. When volume data does exist and nothing qualifies, the function returns None rather than reporting a projection built from noise. Also surfaces `weekly_proj_30d`, `days_qualified`, and `days_total`; the dashboard renders the 30-day average under the headline number so an unrepresentative week is visible instead of silently becoming "the" figure. 4 new pytest regressions, including one asserting the no-volume-data no-op and one asserting the None case. Origin: this work sat unmerged on `fix/dashboard-projection-and-efficiency` for 9 weeks and was found during the branch cleanup that deleted 27 other branches; it was re-applied onto current main rather than merged, since the stale branch conflicted. TD_VERSION 1.15.2 -> 1.15.3.
- 2026-07-20: fix(install): convert all 11 remaining config-write sites to `tdconfig`, and fix a live data-loss bug found while doing it. `install.sh`'s OpenCode plugin registration read the config with `except Exception: cfg = {}` — a malformed `opencode.json` was treated as EMPTY and then written back containing only the `plugin` key, silently destroying every other setting the user had. That is the same truncate-or-swallow shape as the two sites fixed in v1.15.0; this third one survived that pass because it swallowed on *read* rather than truncating on *write*, so it did not match the pattern being searched for. It now aborts and preserves the original. New `tdconfig.quarantine()` provides the abort path the 10 `install.sh` sites needed: it copies an ALREADY-BROKEN file aside as `<name>.corrupt-<stamp>`, distinct from `backup()` which preserves a currently-GOOD file before mutation — conflating the two would either lose the corrupt original or litter `.corrupt-` files on healthy configs. `quarantine()` never raises, since it runs on an error path and a failure to preserve must not mask the corruption itself. Sites converted: `install.sh` 226, 886, 917, 955, 979, 1002, 1244, 1271, 1796, 2077 and `scripts/token-diet:1009` plus the hand-rolled tmp+`os.replace` block at `token-diet:1904` (already atomic but lacking fsync, mode preservation, backup, and malformed-input handling). Verified live end-to-end: a good config keeps every unrelated key through a mutation, and a malformed config exits 3 with the original byte-identical and a `.corrupt-` copy written. 4 new pytest regressions for `quarantine` (copies not moves, returns None when absent, never raises on an unwritable directory, does not collide with `backup`) and 2 new bats guards asserting no raw `open(p,"w")` and no bare `except Exception:` config read remain — both negative-tested against planted input. 60 install.bats tests pass unchanged. TD_VERSION 1.15.3 -> 1.15.4.
- 2026-07-20: fix(release): derive every value in `release.sh`'s git tag message, and drop an unverified security claim from permanent history. The template hardcoded all of it and every single field had drifted false: it printed token-diet's own `$VERSION` as RTK's version (1.15.3 vs the real 0.43.0), claimed `tilth 0.5.7` (actually 0.9.0) and `serena-agent 0.1.4` (actually 1.5.4.dev0), listed three stale submodule SHAs, and omitted `forks/icm` entirely — there are four forks, not three. It also asserted `0 vulnerabilities (164 deps)` on every tag, while no audit runs at tag time; that was an unverified security claim baked into immutable git history, so it was removed rather than derived. Run `cargo audit` separately and record real results in release notes if the claim is wanted. Tool versions now come from `<tool> --version`, serena's from its `pyproject.toml`, and submodule SHAs from `git submodule status`. 2 bats regressions assert no literal 40-char SHA and no literal fork semver appear in the template, and that no vulnerability language remains; both negative-tested against planted input. Same defect class as the `VERSION="1.2.0"` bug fixed in v1.15.1, and invisible for the same reason: the script had never completed a run, so nobody ever read its output.
- 2026-07-20: chore(deps): merge dependabot batch — `actions/setup-python` 5.6.0 -> 7.0.0 (#41), `pdfplumber` 0.11.9 -> 0.11.10 (#43), `pytest` 9.0.3 -> 9.1.1 (#44), `actions/checkout` 4.3.1 -> 7.0.1 (#42). #42 spans three majors and was reviewed rather than taken on green CI alone: v5 moves the runtime to node24 (supported on `ubuntu-latest`), v6 relocates credential persistence to a separate file (the only consumer of git credentials here is `path-leak.yml`'s `git fetch --depth=1`, which passes), and v7 blocks fork checkout for `pull_request_target`/`workflow_run` — every workflow in this repo uses plain `pull_request`, so that change is a security improvement with no behavioral impact. All four required a branch update before merging, since `main` enforces `strict: true` status checks as of this session.
- 2026-07-20: docs: replace rotted coordinates with grep recipes, and guard against their return. Stale line numbers in `docs/PLAN-production-ready.md` and `docs/audits/2026-07-20-job-ready.md` caused a correct finding to be reported as FALSE: an agent grepped the six cited `install.sh` lines, found a `PATH` export and a comment, and concluded the claim was wrong — when only the address had drifted, not the substance. A correct finding was nearly discarded because its coordinates had moved. Re-verified: the audit is substantively right, and the 7-host list IS enumerated six times in `install.sh` (`HAS_*` init, detection, reporting, slug->bool accessor, slug->disable, parallel `slugs`/`labels` arrays). All coordinates in the plan are now grep recipes that re-derive on read, and five findings are marked RESOLVED with a verification command (H1 truncation, H2 non-atomic writes, Codex TOML append, SC2259, unpinned Python deps — all fixed across v1.15.0-v1.15.4). One audit claim was genuinely overstated and is corrected: the duplication across the two entry points is near-identical, NOT byte-identical — `codex_mcp_command()` and `mcp_command_exists()` diverge on the helper they call (`check_command` vs `check_cmd`), so a naive copy-paste dedup silently breaks one caller. `CLAUDE.md` no longer describes `scripts/lib/` as "Shared shell helpers sourced by the CLI"; it contains no shell files and nothing sources it. 2 new bats guards (the actionable plan cites no literal source line numbers; `CLAUDE.md` cannot reinstate the shell-helpers claim while `scripts/lib/` holds no `.sh` files), both negative-tested against planted input. The guard is scoped to the PLAN deliberately, not the audit: a dated audit is a historical record, and "the bug was at `install.sh:1456`" is legitimate for a record to say — acting on a stale coordinate causes harm, preserving one does not. Also adds `docs/PLAN-phase5-host-registry.md`, 9 independently shippable iterations, surfacing the design decision the original audit never raises: Strict Installation Decoupling means the installed `token-diet` cannot source from the repo, so a shared shell lib must install to `~/.local/bin/lib/` and version-sync like the Python cores — the exact omission that shipped `cmd_extract` broken in v1.14.0. No version bump: docs and tests only, no shipped behavior change.
- 2026-07-20: feat(install): ship shared shell libs with the installed binary. Phase 5 Iteration 1, plumbing only, no consumers yet. `scripts/lib/hosts.sh` lands with a version marker and a no-op, and `install.sh` now copies `scripts/lib/*.sh` to `$bin_dir/lib/` alongside the Python cores. Strict Installation Decoupling means the installed `token-diet` runs from `~/.local/bin` and cannot source from the repo checkout, so any shared lib must be copied there or every consumer breaks post-install while passing every test from the dev checkout, exactly how `cmd_extract` shipped broken in v1.14.0. The copy is deliberately a glob, not a manifest: that v1.14.0 break was a hardcoded list forgetting a newly-added file, so adding a lib must require no installer edit. 3 bats regressions, all run against the INSTALLED binary path rather than `$SCRIPTS_DIR`: `hosts.sh` present after install, absent after uninstall, and a negative test that plants an unknown `.sh` in `scripts/lib/` and asserts it is installed anyway (a hardcoded manifest fails it). The prior "scripts/lib holds no .sh files" tripwire fired as designed and is superseded by a guard on the invariant that actually matters, that the glob loop must exist, also negative-tested against a planted hardcoded manifest. `install.sh --dry-run` output byte-identical to the pre-change baseline, captured twice for determinism. Iterations 2-9 (the registry itself) deliberately NOT started; ship this alone first.
- 2026-07-21: fix(release): `release.sh` exited 1 silently whenever the working tree was clean, so nothing past preflight had ever executed. The unstaged-count pipeline began with `grep -v`, which exits 1 when it selects no lines; a clean tree feeds it nothing, and under `set -euo pipefail` that failure propagated to the bare assignment where `set -e` killed the script with no message. A clean tree is the PRECONDITION for tagging a release, so every real invocation hit this and every casual dev run did not. Same mechanism as the v1.15.x defect family: code never executed in the condition it was written for. This is the eighth instance. Counting now uses `grep -cvE` with `|| true`, which prints 0 rather than failing the pipeline. Also fixes the submodule preflight loop, which checked `rtk tilth serena` and omitted `icm`, the same four-forks-not-three omission the v1.15.4 tag-message fix corrected elsewhere. 2 bats regressions: `release.sh --dry-run` exits 0 under a forced clean tree, and the preflight loop names all four forks. The clean-tree condition is forced with a `git status --porcelain` shim rather than asserted against the real checkout, because the test edit itself dirties the tree; it exercises the real script, not a copy of its logic. Verified end to end: `release.sh --dry-run --sign-only` now reaches its summary and exits 0, reporting `forks/icm initialized` and `READY WITH WARNINGS`. The full `--dry-run` including `cargo clippy`/`test` on both Rust forks runs past preflight but was not watched to completion (over 10 minutes), so the Rust test stages remain unverified. No release was ever tagged for 1.15.5; this bump supersedes it.
- 2026-07-21: fix(test): make the release.sh clean-tree regression hermetic. The first version shimmed `git status --porcelain` against the dev checkout and passed locally, then failed in CI: `actions/checkout` runs without `submodules`, so `forks/*` are empty and preflight legitimately aborts on "fork is empty" before ever reaching the line under test. The test asserted exit 0, which only held where submodules happened to exist. Rewritten to build a throwaway git repo under the sandboxed HOME with stub fork directories, a stub `scripts/token-diet` carrying a parseable TD_VERSION, and a real commit, so `release.sh` (which derives ROOT from its own location) runs against a genuinely clean tree with no shim, no submodules, and no dependence on the state of the developer checkout. The clean-tree precondition is now asserted rather than assumed. Commits in the throwaway repo use `-c core.hooksPath=/dev/null`, since the machine-global pre-commit hook blocks commits to main and has no business governing a test fixture. Negative-tested: reverting `release.sh` to the original failing pipeline makes the test fail again, restoring it makes it pass. No behavior change to shipped code; 218 bats / 0 fail.
- 2026-07-21: refactor(install): Phase 5 Iteration 2. The 7-host list is enumerated six times in `install.sh` and desyncs silently. This defines it once in `scripts/lib/hosts.sh` as `TD_HOSTS` (slug|label pairs, plain indexed array because macOS ships bash 3.2 and nothing in this repo uses `declare -A`), exposed via `td_host_slugs`/`td_host_labels`, and converts ONLY the `slugs`/`labels` array site to read from it. The other five enumerations (`HAS_*` init, detection, found/not-found reporting, slug->bool accessor, slug->disable) stay hardcoded until their own iterations; converting all six at once is how a silent desync becomes a silent break. `install.sh` sources the lib from the repo at install time while the installed `token-diet` sources its own copy at runtime. Critically `install.sh` is ITSELF installed as `token-diet-install.sh`, so its `source $SCRIPT_DIR/lib/hosts.sh` resolves against the INSTALLED lib, the exact v1.14.0 trap: a new test runs the installed `token-diet-install.sh --verify` and asserts the registry populates to 7, and is negative-tested by breaking Iteration 1 glob copy (installed installer then dies at its first source line). 4 registry tests plus the installed-installer test, the hardcode-removal guard negative-tested against a planted array. `install.sh --dry-run` byte-identical to the pre-change baseline, captured twice for determinism. 223 bats / 0 fail. No behavior change; internal deduplication only. Iterations 3-9 not started.
- 2026-07-21: fix(build): a failing forks test no longer aborts the builds of the forks after it. `build.sh --rtk --tilth --release` built ONLY rtk: each fork block ran `cargo test ... | tail -5` bare, and under `set -euo pipefail` a failing `cargo test` (RTK fails on two dead-code lints under `-D warnings`) made the pipeline non-zero, so `set -e` killed the whole script before the tilth block ever ran. A fork whose tests fail silently aborted every fork queued after it. Line 136 `ok "RTK tests passed"` was also unconditional, a claim of success the code never checked. Fixed all three fork blocks (rtk, tilth, icm): `cargo test` is wrapped in `if ...; then ok; else warn "tests failed (non-fatal for build)"; fi`, so a fork test failure is non-fatal to the build and reported honestly. New `tests/build.bats`, hermetic via a stubbed `cargo` (creates `target/release/<fork>` on `build`, fails `test` for forks named in `$FAIL_TEST_FORKS`) and stub fork manifests, so it needs no Rust toolchain and no submodules and survives CI. 2 tests, both negative-tested: the abort guard fails if the fix is reverted, the honesty guard fails if tests are made non-fatal while keeping the unconditional "passed" line. Verified on the REAL forks: `build.sh --rtk --tilth --release` now exits 0 and builds both (rtk 0.43.0, tilth 0.9.0), printing the non-fatal warning for each. 225 bats / 0 fail. Note the underlying fork test failures (RTK dead-code lints, 13 real tilth unit-test failures) are unaddressed and tracked separately; this fix stops them from silently truncating a multi-fork build, it does not fix them.
- 2026-07-21: fix(build,release): run each fork test suite from the fork own directory, not via `--manifest-path` from the repo root. `build.sh` and `release.sh` both ran `cargo test --manifest-path "$FORKS/<fork>/Cargo.toml"` from the token-diet root. Many fork tests use relative fixture paths, so this reported PHANTOM failures: tilth showed `598 passed; 13 failed` from the repo root but `611 passed; 0 failed` run from its own directory, same commit, same test binary, only cwd differs (proven: 3 isolated runs plus a cd A/B, all reproduced). This directly falsifies a claim made earlier this session that tilth has 13 real test failures; it has none, the harness invoked them wrong. Fixed by wrapping every fork test step in `( cd "$FORKS/<fork>" && cargo test ... )` in both scripts (rtk, tilth, icm in build.sh; rtk, tilth in release.sh). New `tests/build.bats` case records the cwd the stub cargo runs in and asserts it is the fork directory, not the repo root; the stub now derives the fork from cwd when no `--manifest-path` is passed. Verified on real forks: `build.sh --tilth --release` now reports 0 tilth failures. NOT fixed (correctly, and now reported honestly as a non-fatal warning): RTK test build fails to compile under `-D warnings` on two dead-code lints (`FILTERS_TOML`, `load()`), which is cwd-independent, lives in the pinned RTK fork own lint config, and does not affect the release binary (rtk 0.43.0 builds and runs). 226 bats / 0 fail, 69 pytest / 18 skip. Version 1.15.8 to 1.15.9.
- 2026-07-21: docs(readme,audit): correct stale README test counts (197 bats / 61 pytest to the actual 226 / 69, the suite grew and the literals drifted) and add a `--budget` job-ready portfolio audit under `docs/audits/2026-07-21-job-ready.md` (verdict NEEDS POLISH, 0 hard-gate fails; findings: GitHub description published a combined 60-90% claim the project guardrail forbids [fixed separately via repo metadata], no demo GIF above the README fold [needs a human], releases lag the manifest by 5 versions, 3 stale remote branches of unverifiable merge status left for human judgment). No version bump: docs only.
- 2026-07-21: docs(readme): add a terminal-cast SVG demo (`docs/assets/demo-gain.svg`) above the README fold, replacing the plain text `token-diet gain` console block. Resolves the job-ready audit finding that the repo had no visual demo above the fold (the single biggest "student vs engineer" first-impression signal). SVG is text (commits clean, no binary-guard trip), self-contained (no external refs or scripts, renders on GitHub), and faithful to real measured output (83.9% over 200194 commands). Column alignment preserved via `xml:space="preserve"`. Descriptive alt text carries the numbers for accessibility. No version bump: docs only.
- 2026-07-21: docs(audit): append post-fix update to the job-ready audit. All MEDIUM findings resolved this session: GitHub description overclaim rewritten, terminal-cast SVG demo added above the README fold (#55), v1.15.9 tagged and released (release lag closed), README test counts corrected (#54), and the home path the audit doc itself introduced scrubbed before push. Remaining items are all LOW and either immutable (home path in old history) or out-of-repo (RTK dead-code lint in the pinned fork). Verdict stays NEEDS POLISH: capped only by Stages 5-8 having run [condensed] under --budget, which cannot certify absence. No repo defect above LOW remains; full skill reruns would re-certify, not change the repo. No version bump: docs only.
- 2026-07-21: fix(install): copy `config/compat.json` to the install root so the version-compat gate is not a dead no-op post-install. `scripts/token-diet` reads `$SCRIPT_DIR/../config/compat.json`; installed, `$SCRIPT_DIR` is `~/.local/bin`, so it looked for `~/.local/config/compat.json`, which the installer never created. `_compat_min` therefore fell back to `"0.0.0"` on every installed system and the whole gate silently passed everything, only ever working from the dev checkout. Same decoupling-omission class as `cmd_extract` (v1.14.0) and the `release.sh` clean-tree crash: a feature that runs only in the condition it is NOT deployed in. Surfaced by a full-depth architecture audit (job-ready Stage 6). Fix: `install.sh` copies compat.json to `$bin_dir/../config/`, `uninstall.sh` removes it, both tested against the INSTALLED path not the checkout. Also adds the missing fourth tool ICM to compat.json (was rtk/tilth/serena only) and refreshes the stale `tested` versions to the real installed ones (rtk 0.43.0, tilth 0.9.0, serena 1.5.4, icm 0.10.57). 228 bats / 0 fail. Version 1.15.9 to 1.15.10.
- 2026-07-21: docs(audit): record full-depth Stage 5-8 re-audit results and final verdict in the job-ready audit. Four parallel deep audits lifted the [condensed] cap: Stage 5 (security) PASS, Stage 7 (CI governance) PASS, Stage 8 (claims) PASS, Stage 6 (architecture) NEEDS WORK with 2 HIGH findings the condensed pass missed (config-path drift = the remaining Phase 5 iters 3-9; default-install submodule non-pinning = a design decision). The MED dead compat gate was fixed in #57. Final verdict NEEDS WORK: 7/8 stages PASS, but 2 Stage-6 HIGH remain, both deliberately not fixed here (one violates the Phase 5 plans no-long-session guardrail, the other is an operator design decision). No version bump: docs only.
- 2026-07-21: fix(install): pin the default (network) install to the audited fork revisions instead of floating to upstream HEAD (job-ready Stage 6 HIGH #2, operator-approved). The default path ran `cargo install --git <repo> --force` and `uvx --from git+<repo>` with no revision, so a non-local install did not match the pinned/audited `forks/` submodules or `compat.json` tested versions and was non-reproducible. Now each tool pins to the exact revision its submodule gitlink records (single source of truth via `git rev-parse HEAD:forks/<tool>`, never duplicated): rtk/tilth/icm get `--rev <sha>`, Serena gets `git+<repo>@<sha>` through a new single `SERENA_SRC` var that also deduplicates the ~8 previously hand-copied Serena refs across every launcher and MCP-registration site. Falls back to floating HEAD with a warning only outside a git checkout. 2 bats regressions assert the dry-run emits the pinned rev matching the live gitlink SHA for all four tools. 230 bats / 0 fail. Version 1.15.10 to 1.15.11.
- 2026-07-21: refactor(dashboard): Phase 5 Iteration 3 — converge the dashboard onto a canonical MCP-host registry (job-ready Stage 6 HIGH #1, first consumer). The dashboard carried its OWN independent copy of every host config path, the mcpServers/mcp/servers key dialect, the all-hosts list, and per-host presence checks, in Python that structurally cannot source the bash `scripts/lib/hosts.sh` — so it drifted silently from the installer. New `config/hosts-mcp.json` is the single source of truth (paths + dialect order + host list + presence base), and `token-diet-dashboard` `_registered_hosts`/`_missing_hosts` now read it, with `_ALL_HOSTS` removed. Strict Installation Decoupling preserved: `install.sh` copies the registry to `~/.local/config/` and `uninstall.sh` removes it, exactly mirroring compat.json; the dashboard resolves the file from both the repo (dev) and the installed path. Behavior preserved exactly (the or-chain dialect semantics, the vscode walk-up, the project-vs-home presence split). 3 pytest + 2 bats regressions, RED-then-GREEN. install.sh/uninstall.sh/token-diet bash consumers are LATER iterations (one site per iteration). 232 bats / 0 fail, 72 pytest / 18 skip. Version 1.15.11 to 1.15.12.
- 2026-07-21: refactor(install): Phase 5 Iteration 4 — derive the Cowork (Claude Desktop) config path from the canonical host registry instead of hardcoding it. Adds `td_host_config_paths <registry> <host>` to `scripts/lib/hosts.sh` (prints a host `home_configs` paths in registry order via python3, returns non-zero with no output on any failure so callers fall back cleanly), and `resolve_cowork_cfg()` in install.sh now derives its macOS/Linux Claude Desktop paths from `config/hosts-mcp.json`, falling back to the exact original literals when the registry does not yield exactly 2 paths (preserves curl|sh bare-script behavior). The registry path is passed IN by the caller, never assumed by the lib, keeping it decoupled. `install.sh --dry-run` output byte-identical before and after (verified independently). 4 bats regressions incl. negative tests (absent registry, host with no entries). One consumer only: `uninstall.sh` MCP-removal and `token-diet` `hosts_registered()` remain for later iterations (the latter is a live-HOME runtime scan not coverable by the dry-run harness, so its conversion needs a different verification). 76 install.bats / 0 fail. Version 1.15.12 to 1.15.13.
- 2026-07-21: refactor(install): Phase 5 Iteration 5 — drive the found/not-found host REPORTING from the registry instead of 7 hardcoded `if $HAS_* ...` lines. `detect_hosts` now loops `td_host_slugs`/`td_host_labels` + the existing `_host_is_set` accessor. The dotted alignment is one uniform rule (dots = 16 - label length, framed by a space each side), which reproduces every label including the zero-dot two-space `Cowork (Desktop)  found` with no special-casing. `install.sh --dry-run` byte-identical before/after (verified independently). 2 bats regressions assert the exact reporting block for all-seven-found and partial-not-found host sets; genuine RED demonstrated (a no-dots intermediate failed both). One site only: HAS_* init, detection, accessor, disable remain for iters 6-9. 78 install.bats / 0 fail. Version 1.15.13 to 1.15.14.
- 2026-07-21: fix(cli): Phase 5 Iteration 6 — converge `token-diet` `hosts_registered()` onto the canonical registry `config/hosts-mcp.json`, eliminating its hardcoded config-path list + inline MCP-key dialect (the HARD half of architecture-audit HIGH #1: it scans live $HOME, so it is NOT --dry-run coverable). Now reads the registry home_configs + mcp_key_dialect via python3, resolving `$SCRIPT_DIR/../config/hosts-mcp.json` (installed to ~/.local/config, repo checkout to repo/config) exactly like `_compat_min` reads compat.json, with a fallback to the historical hardcoded paths if the registry is unreadable. A source-guard (`[ "${BASH_SOURCE[0]}" != "${0}" ] && return`) was added at EOF so the script is sourceable for isolated `hosts_registered` testing; normal CLI dispatch is unaffected (verified). Verification is by 24 fixture-$HOME characterization tests (planted configs across dialects, TOML codex, malformed/empty, substring match, opencode dedup, full-stack ordering) — RED against a deliberately-broken intermediate, GREEN on the refactor. DELIBERATE DOCUMENTED BEHAVIOR DELTA (not byte-identical): a JSON config using ONLY the `servers` dialect key, previously IGNORED (old bash merged only mcpServers+mcp), is now detected, because true convergence adopts the registry full dialect [mcpServers, mcp, servers] — which the dashboard already honors. Pure superset: no previously-detected host is lost, and bash now AGREES with the dashboard (closing the exact drift HIGH #1 targets). Left for later: the registry omits the XDG opencode path + VS Code home path that bash still scans as explicit code, and the .config/Claude Linux no-op is a latent detection bug — residual drift, preserved not fixed. 24 hosts-registered + 146 token-diet bats / 0 fail, 72 pytest. Version 1.15.14 to 1.15.15.
- 2026-07-21: refactor(uninstall): Phase 5 Iteration 7 — drive the SAFE SUBSET of uninstall.sh MCP-removal paths from the canonical registry config/hosts-mcp.json, keeping every removal helper (remove_json_key, remove_opencode_mcp_key, remove_vscode_template_server, codex TOML regex, strip_opencode_rules) unchanged. uninstall now sources scripts/lib/hosts.sh and reads config paths via the existing td_host_config_paths helper (honoring TD_HOSTS_MCP_REGISTRY). Dispatch is by HOST, not format (format alone mis-routes: opencode is json but needs remove_opencode_mcp_key). uninstall.sh --dry-run --force byte-identical before/after against a fixture $HOME triggering every removal branch (verified independently). 3 bats regressions RED-then-GREEN incl. a guard that .claude.json and gemini are never newly cleaned. KEY FINDING (documented in-code, NOT forced): the registry and uninstall path set diverge in BOTH directions, so only claude-desktop + codex could be registry-driven safely — registry lists 2 claude-code paths but uninstall only cleaned settings.json (expansion risk); registry omits opencode XDG .config/opencode/opencode.json that uninstall must clean (shrink risk); registry vscode is project-scoped .vscode/* while uninstall cleans home Code settings (disjoint); gemini in registry but never cleaned by uninstall. Fully collapsing uninstall into one registry loop needs REGISTRY COMPLETENESS + install/uninstall asymmetry DECISIONS that also affect the dashboard (Iter 3) and hosts_registered (Iter 6) consumers — a coordinated behavior decision, out of scope for a behavior-preserving refactor. 81 install.bats / 0 fail. Version 1.15.15 to 1.15.16.
- 2026-07-21: fix(uninstall): Phase 5 FINAL, close architecture-audit HIGH #1 (config-path drift) via registry completeness + install/uninstall symmetry (both operator-approved). DECISION 1: config/hosts-mcp.json now lists every config path the code touches, adding opencode XDG `.config/opencode/opencode.json` and VS Code home `.config/Code/User/settings.json`. The dashboard consequently gains (documented superset) detection of XDG-opencode and home-VS-Code installs it previously missed; it never detects less. token-diet hosts_registered stays byte-identical (24/24 + 146/146). DECISION 2: uninstall now removes EXACTLY what install writes, per host (previously it left several behind, the audit/Iter-7 asymmetry). BEHAVIOR CHANGE, what uninstall now additionally cleans: gemini (mcpServers.{tilth,serena,icm}, the two context hooks, ~/.gemini/token-diet.md, the @token-diet.md line in GEMINI.md), which was never cleaned; claude-code ~/.claude.json {tilth,serena,icm} plus token-diet from ~/.claude/settings.json; the token-diet MCP server everywhere it was registered (claude settings, both Claude Desktop paths, both opencode paths, codex); opencode plugin de-registration (plugins/token-diet-hooks.ts removed from the plugin array plus file deleted); VS Code template now strips serena and tilth not just icm; Claude Desktop dir docs (rtk-awareness.md, token-diet.md, awareness-docextract.md). The codex remover replaced a buggy regex (which orphaned args array lines and never removed the token-diet block) with a line-based TOML-block remover keyed on table headers; user tables preserved verbatim (independently verified: a config with a user [mcp_servers.my_own_tool] plus [other_user_setting] keeps both, drops only token-diet blocks). 5 install-to-uninstall ROUND-TRIP tests (RED before, GREEN after) assert each host config is restored to its pre-install state with unrelated user content preserved, via parsed-structure deep-equality. Testing note found and fixed: bats exempts negated-grep pipelines from set -e (the assertion silently never fails), so all decisive assertions were consolidated into single python blocks after one falsely-passing test was caught. Residual (documented, not forced): uninstall per-host path lists stay explicit (only claude-desktop and codex registry-driven) because each host carries cleanup beyond a flat path list; the registry source of truth is complete, which is the drift closure. 85 install.bats + 24 hosts-registered + 146 token-diet + 11 path-leak / 0 fail, 72 pytest. Version 1.15.16 to 1.15.17.
- 2026-07-21: docs(audit): final job-ready scorecard, verdict HIRE-READY. Independent arch re-audit confirms both prior HIGH findings RESOLVED with code evidence (config-path drift closed across Iters 3 through FINAL / PRs #61-#66; floating install pinned #60), the uninstall symmetry expansion has no over-removal risk (all removers key-scoped, round-trip-proven), all 8 stages PASS at full depth, findings LOW-only. One pre-existing LOW follow-up noted: config removers rewrite in place rather than atomically. No version bump: docs only.
- 2026-07-22: docs(audit): rename the job-ready audit artifacts to portfolio-ready and change the verdict term HIRE-READY to PUBLIC-READY, matching the renamed /portfolio-ready command (formerly /job-ready) whose top grade is now PUBLIC-READY. git mv of docs/audits/{2026-07-20,2026-07-21}-job-ready.md and job-ready-progress.md to their portfolio-ready equivalents (history preserved), with titles, internal path references, and the PLAN-production-ready.md source reference updated. The grade itself is unchanged (PUBLIC-READY is the old HIRE-READY: every stage PASS at full depth, findings LOW-only); only the label vocabulary changed. No code touched, no version bump: docs only.
- 2026-07-22: fix(uninstall): make the config removers write atomically (closes the one LOW follow-up from the portfolio-ready arch re-audit). All 7 python3 remover blocks in uninstall.sh (remove_opencode_mcp_key, remove_opencode_plugin, remove_json_key, remove_vscode_template_server, strip_opencode_rules, the codex TOML remover, and remove_hook_entry) rewrote config files in place with `open(cfg,"w")`, so a crash or disk-full mid-write could truncate a user config. Each now serializes fully in memory, writes to a `tempfile.mkstemp` in the SAME directory, flush + os.fsync, preserves the original mode via os.chmod, then os.replace(tmp, cfg); on any exception the temp is unlinked and the error re-raised so the target is never left partial. This is the exact tdconfig.py pattern, inlined per heredoc (they must not depend on the repo path). Behavior byte-identical (json.dumps(indent=2)+newline == the old json.dump+write). The existing no-raw-open(w) guard is extended with a sibling asserting uninstall.sh has none, plus a negative-control proving the guard fires on a planted raw `open(cfg,"w")` and stays silent on the atomic `os.fdopen(fd,"w")` form. 85 install.bats + 148 token-diet.bats (+2 guards) / 0 fail, 72 pytest. Version 1.15.17 to 1.15.18.
- 2026-07-22: fix(install): fix broken Serena Docker-mode MCP registration for Claude Code, Gemini CLI, and Cowork/Claude Desktop. All three wrote a literal `"$(pwd):/workspace:ro"` docker volume-mount arg into MCP stdio configs; those hosts exec the configured command as argv directly with no shell, so the command-substitution syntax never expanded and was passed to `docker` verbatim, causing an immediate "invalid characters for a local volume name" failure and Serena never connecting. Replaced with `.` (matching the already-correct Codex CLI registration in the same file): docker resolves a relative `-v` path against its own invocation cwd, which is inherited from the host's spawn of the MCP subprocess, with no shell substitution required. Found live via a real `claude mcp get serena` failure investigation on this machine; the standalone editable-clone MCP registration that had been masking this bug was also repointed to token-diet's own pinned uvx source. No test coverage existed for this path (docker-mode registration strings aren't asserted in install.bats); `bash -n` and a `--local --dry-run` run confirm no remaining `$(pwd)` in any live codepath. Version 1.15.18 to 1.15.19.
- 2026-07-22: fix(uninstall): remove the orphaned Serena launcher on uninstall, and add test coverage for the three fixes bundled into the previous commit's diff but never documented or tested there. `install.sh` writes a Serena launcher to `$HOME/.local/bin/serena`; `uninstall.sh` removed the rtk/tilth/icm launchers but never this one, leaving it orphaned post-uninstall — now removed alongside them. The previous commit (1.15.19) also silently carried three unrelated fixes from a `/bulletproof` self-audit (honesty score 3/10 on the prior session's "PUBLIC-READY" claim, see `docs/bulletproof-report-2026-07-22.md`, now committed): the VS Code/OpenCode/Cowork Serena registrations were pinned to `SERENA_SRC` instead of floating to upstream HEAD; 8 `write_text()`/`write_bytes()` config writes across install.sh and token-diet were converted to atomic mkstemp+fsync+chmod+os.replace; and the gemini-symmetry install.sh comment was corrected against an empirical `gemini mcp add --scope user` v0.49.0 test (writes `~/.gemini/settings.json`, the same file uninstall.sh cleans — no code change needed there, comment only). This commit adds the missing regression tests for all of it: a round-trip test planting the Serena launcher exactly as install writes it (RED without the uninstall.sh fix, GREEN with it); an install --serena-only test asserting every emitted Serena `--from` ref is pinned (`git+<repo>@<real SHA>`), with zero bare `git+...serena` refs left in install.sh; a sibling atomic-write guard covering `.write_text()`/`.write_bytes()` (the prior guard only caught raw `open(path,"w")`) plus a negative control; two byte-identical-content tests for the converted writes; and the existing raw-open guard's regex fixed to not false-flag the new `os.fdopen(fd,"w")` atomic pattern. 277 bats / 72 pytest (18 skipped), 0 fail. Version 1.15.19 to 1.15.20.
- 2026-07-22: test(install): fix a Linux-only CI failure in the SERENA_SRC pinning test added above. `resolve_cowork_cfg()` checks the macOS Claude-Desktop config path's existence before the Linux path, unconditional on `uname`; the test planted BOTH platform paths so install.sh always picked the macOS path while the test's own read side switched to the Linux path on non-Darwin, a mismatch invisible on macOS (where both point at the same path) and fatal on Linux CI (`KeyError: 'serena'`, the untouched file never got the key). Reproduced with a local Docker `ubuntu:24.04` run matching the GitHub Actions runner. Fixed by planting only the OS-appropriate path, matching the existing "malformed cowork config" test's pattern in the same file. Verified in the same Ubuntu container (0 fail) and locally on macOS (277 bats / 72 pytest, 0 fail). No version bump: test-only.
