# Session Handoff — 2026-04-22

## What was done

Converted `token-diet` into a full-fledged MCP (Model Context Protocol) server to provide AI agents with self-observability and budget awareness.

### 1. New MCP Server
- Created `scripts/token-diet-mcp`: A zero-dependency Python MCP server communicating over `stdio`.
- Implemented 5 specialized tools for agents:
    - `token_diet_health`: Diagnoses the health of the entire stack (RTK, tilth, Serena).
    - `token_diet_savings`: Reports exact token efficiency and savings metrics.
    - `token_diet_budget`: Checks project-specific usage against `.token-budget` thresholds.
    - `token_diet_loops`: Detects inefficient agent command repetition patterns.
    - `token_diet_route`: Recommends the optimal tool (`tilth`/`Serena`/`RTK`) for a given task.

### 2. TDD & Infrastructure
- Followed a strict 5-iteration TDD plan (documented in `docs/token-diet-mcp-conversion-plan.md`).
- Added `tests/test_token_diet_mcp.py` for automated MCP handshake and tool call verification.
- Updated `scripts/install.sh` and `scripts/Install.ps1` to:
    - Install the new `token-diet-mcp` binary.
    - **Auto-register** the server in `claude_desktop_config.json`, `.opencode.json`, `.claude/settings.json`, and `.codex/config.toml`.
- Updated `scripts/uninstall.sh`, `scripts/Uninstall.ps1`, and `tests/install.bats` to ensure clean lifecycle management.

## Key framing

By making `token-diet` an MCP server, we have shifted from **user-facing reporting** to **agent-driven optimization**. Agents can now "see" their own token costs and self-correct their behavior (e.g., breaking loops or staying within budget) without human intervention.

## Recommended next moves

1. **Agent Instructions:** Update `token-diet.md` instructions to explicitly tell agents to call `token_diet_route` when starting complex tasks.
2. **Auto-Repair:** Enhance the `token_diet_health` tool to allow agents to trigger `token-diet repair` if it detects a broken hook or stale registration.
3. **Budget Governance:** Implement an "auto-stop" mode where the MCP server returns errors or warnings if the `hard` budget is exceeded, forcing the agent to stop and ask for permission.

## Notes
- All tests passed: `pytest tests/test_token_diet_mcp.py` and `bats tests/install.bats`.
- Full analysis available in `docs/token-diet-mcp-conversion-analysis.md`.
