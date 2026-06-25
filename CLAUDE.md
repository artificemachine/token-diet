# token-diet

Token optimization stack installer and compliance kit for RTK + tilth + Serena + ICM.

## Identity

- **What:** Unified installer, CLI dashboard, and compliance kit that wires RTK, tilth, Serena, and ICM together to reduce AI agent token costs by 40–90%.
- **Stack:** Bash (CLI entry point), PowerShell (Windows CLI), Python (dashboard, tests), Rust (RTK + tilth + ICM submodule forks), Docker (Serena container)
- **Version:** `TD_VERSION` in `scripts/token-diet` and `$script:TD_VERSION` in `scripts/token-diet.ps1` (current: 1.10.4)
- **Status:** active

## Guardrails

- Never edit `.env`, credentials, or secrets.
- Never push directly to `main` — always use a feature/fix branch and PR.
- Run the full test suite before any commit: `bats tests/*.bats && pytest tests/ -q`.
- `CHANGELOG.md` is append-only — never edit or reorder existing entries.
- Bump `TD_VERSION` in both `scripts/token-diet` AND `scripts/token-diet.ps1` before every release commit. The pre-commit hook warns when the version matches the latest git tag.
- Never let installed binaries depend on the local repo path for execution. All installed paths must use `~/.local/bin`, `~/.config`, or other standard system paths.
- Submodule forks in `forks/` are pinned — never update them automatically.
- Regenerate `compliance/SBOM.template.json` on each release.

## Project structure

```
token-diet/
├── forks/                    # Git submodules — audited forks
│   ├── rtk/                  # celstnblacc/rtk (Rust CLI proxy)
│   ├── tilth/                # celstnblacc/tilth (Rust MCP server)
│   ├── serena/               # celstnblacc/serena (Python MCP server)
│   └── icm/                  # celstnblacc/icm (Rust MCP server — Infinite Context Memory)
├── scripts/
│   ├── install.sh            # macOS/Linux installer (--local for air-gapped, --verbose for full output)
│   ├── Install.ps1           # Windows installer (-Verbose for full output)
│   ├── uninstall.sh          # macOS/Linux uninstaller (--dry-run, --force, --include-data)
│   ├── Uninstall.ps1         # Windows uninstaller (-DryRun, -Force, -IncludeData)
│   ├── token-diet            # CLI entry point — macOS/Linux (bash)
│   ├── token-diet.ps1        # CLI entry point — Windows (PowerShell)
│   ├── token-diet-dashboard  # stdlib-only Python browser dashboard
│   ├── token-diet-mcp        # MCP server entry point
│   ├── lib/                  # Shared shell helpers sourced by the CLI
│   ├── playbook.yml          # Ansible playbook
│   ├── release.sh            # Release automation (tag, SBOM, GitHub release)
│   └── build.sh              # Build from forks (no internet)
├── tests/
│   ├── test_helper.bash      # Shared bats fixtures (sandboxed HOME/PATH, mock helpers)
│   ├── token-diet.bats       # CLI tests (dispatch, health, uninstall)
│   ├── install.bats          # Installer + uninstaller tests
│   ├── token-diet.Tests.ps1  # Pester v5 tests for Windows CLI (token-diet.ps1)
│   ├── Uninstall.Tests.ps1   # Pester v5 tests for Windows uninstaller
│   ├── conftest.py           # pytest fixtures (dashboard_mod, tmp_home)
│   └── test_dashboard.py     # Dashboard data layer tests
├── docker/
│   ├── Dockerfile.serena     # Multi-stage, non-root, network_mode: none
│   └── compose.yml
├── config/
│   └── serena-dedup.template.yml
├── compliance/
│   ├── SBOM.template.json    # CycloneDX 1.5
│   ├── LICENSE-THIRD-PARTY.md
│   └── security-audit.md
└── docs/
    ├── roadmap.md            # 5-iteration improvement roadmap
    └── comparison.md
```

## Key CLI commands (post-install)

```bash
token-diet gain          # Token savings dashboard (default)
token-diet health        # Quick health check: tools + MCP hosts
token-diet dashboard     # Live browser stats UI
token-diet mcp list      # Which AI hosts are currently optimized
token-diet budget status # Check usage against project budget
token-diet doctor        # Deep diagnostics
token-diet repair        # Auto-fix hook and registration issues
token-diet hook off/on   # Temporarily disable/re-enable RTK output filter
token-diet breakdown     # Top commands by token savings
token-diet loops         # Detect agent loop patterns
token-diet leaks         # Detect redundant file reads in history
token-diet route <task>  # Suggest which tool fits a task
token-diet diff-reads    # Suggest minimal line ranges based on git diff
token-diet test-first    # Suggest test files to read before implementation
token-diet icm warmup    # One-time embedding-model download for ICM recall
token-diet icm status    # ICM integration state
token-diet version       # Versions of all four tools
```

## Build commands

```bash
# Build all tools from local forks (no internet)
bash scripts/build.sh --release

# Build Serena Docker image only
docker build -f docker/Dockerfile.serena -t serena:local .
```

## Test commands

```bash
# Bash tests (requires bats-core: brew install bats-core)
bats tests/*.bats

# Python tests (requires pytest)
pytest tests/ -q

# PowerShell tests (requires pwsh + Pester v5)
pwsh -NoProfile -Command "Import-Module Pester -Force; Invoke-Pester tests/ -Output Minimal"

# Full suite
bats tests/*.bats && pytest tests/ -q && pwsh -NoProfile -Command "Import-Module Pester -Force; Invoke-Pester tests/ -Output Minimal"
```

## Install commands

```bash
# Install from upstream (internet required)
bash scripts/install.sh

# Install from local forks/ submodules (air-gapped, builds from source)
bash scripts/install.sh --local

# Verify installation
bash scripts/install.sh --verify

# Full output + log to ~/.local/share/token-diet/install.log
bash scripts/install.sh --verbose
```

## Uninstall commands

```bash
# Preview what would be removed (no changes)
bash scripts/uninstall.sh --dry-run

# Remove everything (prompts for confirmation)
bash scripts/uninstall.sh

# Remove without prompts
bash scripts/uninstall.sh --force

# Also remove ~/.serena/memories
bash scripts/uninstall.sh --force --include-data
```

## Submodule workflow

```bash
git submodule update --init --recursive   # first checkout
git submodule update --remote             # pull latest from forks
```

## Conventions

- All four forks are pinned via submodules — never update automatically.
- Security audit checklist: compliance/security-audit.md
- SBOM must be regenerated on each release: compliance/SBOM.template.json
- CHANGELOG.md is append-only — never edit existing entries.
- **Version bump rule**: before every commit that ships a new feature or fix, increment `TD_VERSION` in `scripts/token-diet` AND `$script:TD_VERSION` in `scripts/token-diet.ps1`. The pre-commit hook warns when the version matches the latest git tag. Patch = bug fix, Minor = new command/feature, Major = breaking change.

## Strict Installation Decoupling

Once installed (e.g., to ~/.local/bin), the project binary must NEVER depend on the local repository path for execution, configuration, or data. All paths must be relative to the installation root or use standard system config paths (~/.config).
