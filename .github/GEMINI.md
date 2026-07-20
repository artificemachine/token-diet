# token-diet — Gemini Context

token-diet is a unified installer and compliance kit for token optimization tools (RTK, tilth, Serena, ICM).

## 🎯 Project Overview
- **Purpose:** Orchestrate the installation and health of the token optimization stack.
- **Stack:** Bash, PowerShell, Python.

## 🛠 Building and Running

### Installation
- **Standard:** `bash scripts/install.sh`
- **Local (Air-gapped):** `bash scripts/install.sh --local`
- **Verify:** `bash scripts/install.sh --verify`

### Testing
- **Bash:** `bats tests/*.bats`
- **Python:** `pytest tests/ -q`
- **PowerShell:** `pwsh -NoProfile -Command "Import-Module Pester; Invoke-Pester tests/"`

## 📏 Operational Rules
- **Version Bump:** Increment `TD_VERSION` in both Bash and PowerShell entry points before shipping.
- **Submodules:** Forks are pinned via submodules; update intentionally.
- **Decoupling:** Binary must not depend on local repo path once installed.

## 🤝 Workspace Conventions
- **CHANGELOG.md:** Append-only, required per commit.
- **Task Lifecycle:** todo → plan_proposed → plan_approved → in_progress → report_ready → review_requested → review_passed → done.
- **Task Management:** Use `shux` for all task coordination.
- **Handoffs:** Write via `shux handoff-write`.
