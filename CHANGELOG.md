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
