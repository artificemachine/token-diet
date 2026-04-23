# Session Handoff — v1.7.1 (Hardened & Agent-Optimized)

## Executive Summary
This session successfully evolved **token-diet** from a user-facing dashboard into an active, **agent-aware optimization layer**. The stack has been converted into an MCP server, hardened via a 7-stage pipeline, and refined for cross-platform production use.

## 1. Core Evolution: The MCP Server (v1.7.0)
The project now acts as a "brain" for AI agents.
- **New Server**: `scripts/token-diet-mcp` (Zero-dependency Python).
- **Agent Tools**:
  - `token_diet_health`: Diagnostics and host checks.
  - `token_diet_savings`: Exact token efficiency metrics.
  - `token_diet_budget`: Project-specific usage tracking.
  - `token_diet_loops`: AI command repetition detection.
  - `token_diet_route`: Decision engine for tool selection (`tilth`/`Serena`/`RTK`).

## 2. Platform Parity & Maintenance (v1.7.1)
- **`token-diet upstream`**: New cross-platform command (Bash + PowerShell) to track and audit updates from original authors (`rtk-ai`, `jahala`, `oraios`) while preserving your security-patched forks.
- **Improved Serena Detection**: Distinguishes between Docker image presence, active container, and `uvx` runnability.
- **`token-diet serena-status`**: New command for deep runtime diagnostics.
- **Headless Mode**: All Serena registrations are now `--headless` by default to prevent desktop popups during AI coding sessions.

## 3. CLI & UX Refinements
- **Unified Interface**:
  - `token-diet hook [on|off]`: Replaces `no-rtk`/`use-rtk`.
  - `token-diet update --fresh`: Replaces `reinstall`.
  - `token-diet doctor`: Now includes `verify` logic and deep diagnostics.
- **1-Minute README**: Completely redesigned for immediate understanding.
- **Enterprise Guide**: New documentation for air-gapped/offline deployments (`docs/enterprise.md`).
- **Global vs. Project**: Clarified that tools are installed globally but operate with per-project context.

## 4. Hardening & Quality
- **Gauntlet Passed**: Successfully completed all 7 stages (Security, Threat Model, Code Quality, QA, UX, Simplify, Docker).
- **Security**: Passed full **ShipGuard** scan. Added Docker healthchecks for `serena`.
- **Testing**: 176 total tests (138 Bash, 38 PowerShell).
- **Performance**: Pre-commit hook optimized to skip slow PowerShell tests on macOS/Linux unless `RUN_SLOW_TESTS=1` is set.

## 5. Current State
- **Main Branch**: Clean, up-to-date, and pushed.
- **Tags**: `v1.7.1` is live and force-pushed to the final hardened commit.
- **Installers**: `install.sh` and `Install.ps1` are fully optimized and verified.

## Next Recommended Steps
1.  **Agent Prompting**: Remind your AI agent to run `token-diet route` when unsure which tool to use.
2.  **Auto-Repair**: Consider expanding the `doctor` command to automatically trigger `repair` for detected issues.
3.  **Docker Management**: Use `token-diet serena-status` if the Serena MCP tool ever feels sluggish.

Ready for production deployment.
