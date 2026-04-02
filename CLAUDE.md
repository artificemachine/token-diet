# token-diet

Token optimization stack installer and compliance kit for RTK + tilth + Serena.

## Project structure

```
token-diet/
├── forks/                    # Git submodules — audited forks
│   ├── rtk/                  # celstnblacc/rtk (Rust CLI proxy)
│   ├── tilth/                # celstnblacc/tilth (Rust MCP server)
│   └── serena/               # celstnblacc/serena (Python MCP server)
├── scripts/
│   ├── install.sh            # macOS/Linux installer (--local for air-gapped, --verbose for full output)
│   ├── Install.ps1           # Windows installer (-Verbose for full output)
│   ├── uninstall.sh          # macOS/Linux uninstaller (--dry-run, --force, --include-data)
│   ├── Uninstall.ps1         # Windows uninstaller (-DryRun, -Force, -IncludeData)
│   ├── token-diet            # CLI entry point — macOS/Linux (bash)
│   ├── token-diet.ps1        # CLI entry point — Windows (PowerShell)
│   ├── token-diet-dashboard  # stdlib-only Python browser dashboard
│   ├── playbook.yml          # Ansible playbook
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

- All three forks are pinned via submodules — never update automatically.
- Security audit checklist: compliance/security-audit.md
- SBOM must be regenerated on each release: compliance/SBOM.template.json
- CHANGELOG.md is append-only — never edit existing entries.
