# token-diet v1.7.1 Handoff

## Release Overview
The **token-diet v1.7.1** release is now live. This version solidifies the MCP server transformation (v1.7.0) by integrating crucial runtime diagnostics and installation fixes.

## Key Changes
- **MCP Server Conversion**: The entire stack is now an MCP server, providing AI agents with first-class observability into their token consumption.
- **`token-diet upstream`**: A new cross-platform command to track and audit changes from original tool authors while preserving your audited security patches.
- **Serena Runtime Diagnostics**: 
  - New `serena-status` command for deep detection of uvx vs. Docker modes.
  - Visual status indicators in the dashboard.
- **Installer Fix**: modifier-only flags (e.g., `install.sh --verbose`) now correctly default to installing the full stack.

## Documentation
- **1-Minute README**: Redesigned for immediate understanding of the stack's value.
- **Enterprise Guide**: New dedicated documentation for air-gapped deployments.

## Testing & Quality
- **Bash/Bats**: 110 tests passing.
- **Python/Pytest**: 5 tests passing (100% coverage on MCP server).
- **PowerShell/Pester**: 38 tests passing (Verified on macOS and Windows).
- **Security**: Passed full ShipGuard scan.

## Current State
- **Branch**: `main` is up to date with `origin/main`.
- **Tag**: `v1.7.1` is pushed and points to the latest commit.

Ready for deployment.
EOF

## Update (v1.7.1 Final Refinements)
- **Headless Serena**: All Serena MCP registrations now include the `--headless` flag by default. This ensures the native Serena dashboard does not pop up automatically during AI coding sessions.
- **Improved Host Tracking**: Fixed `token-diet doctor` and `token-diet mcp list` to correctly detect Serena registrations in both global (`$HOME/.claude.json`) and local settings.
- **Clarified Scope**: README now includes a "Global vs. Per-Project" section explaining that tools are installed once but work contextually.
