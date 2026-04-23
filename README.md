# token-diet

**Put your AI coding sessions on a diet.** Orchestrate RTK, tilth, and Serena to slash token costs by 40-90%.

## 1-Minute Overview

### What is it?
`token-diet` is a unified installer and dashboard for the ultimate token optimization stack. It wires together three specialized tools that act as a "filter" between your AI agent and your code:

1.  **[RTK](https://github.com/rtk-ai/rtk)**: Compresses huge CLI outputs (builds, tests, logs) before the agent sees them.
2.  **[tilth](https://github.com/jahala/tilth)**: Uses AST (tree-sitter) to read only the code symbols the agent actually needs.
3.  **[Serena](https://github.com/oraios/serena)**: Provides IDE-grade navigation (LSP) so agents stop reading whole files just to find a definition.

### Why use it?
- **Slash Costs**: Save up to 90% on command output and 40% on code reading.
- **Bigger Context**: Fit 5x more information into the same context window.
- **Faster Agents**: Fewer tokens mean faster responses and fewer "out of context" errors.

---

## Quick Start

### 1. Install (macOS / Linux / WSL)
```bash
# Preview what will happen
bash scripts/install.sh --dry-run

# Install everything
bash scripts/install.sh
```
*(Windows users: run `.\scripts\Install.ps1`)*

### 2. Verify
```bash
token-diet health
```

### 3. Use
Once installed, your AI agent (Claude Code, Codex, VS Code, etc.) will automatically use the optimized tools. You can monitor your diet via the CLI or dashboard:

```bash
token-diet           # See your total token savings
token-diet dashboard # Open the live browser stats
```

---

## Main Commands

| Command | Purpose |
| :--- | :--- |
| `token-diet gain` | **Dashboard**: See how many tokens you've saved today. |
| `token-diet mcp list` | **Status**: See which AI hosts are currently optimized. |
| `token-diet hook off` | **Toggle**: Temporarily disable optimization for raw output. |
| `token-diet budget status` | **Governance**: Check usage against your project budget. |
| `token-diet doctor` | **Debug**: Run deep diagnostics on your setup. |

---

## Full Reset / Uninstall

If you need to start from a clean slate or remove the stack entirely:

```bash
# 1. Remove all binaries (including RTK and tilth), configs, and MCP registrations
token-diet uninstall --force

# 2. (Optional) Remove Serena memories and logs
rm -rf ~/.serena
```

On Windows: `.\token-diet.ps1 uninstall -Force`

---

## Enterprise / Air-Gapped
`token-diet` supports fully offline installation from local forks. See the [Enterprise Guide](docs/enterprise.md) for details.

## License
MIT — all upstream tools are MIT-licensed.
