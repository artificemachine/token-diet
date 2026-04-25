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

### Global vs. Per-Project?
All three tools are installed **Globally** as binaries, but they operate with **Project-Level** context.

| Tool | Installation | Scope of Work |
| :--- | :--- | :--- |
| **RTK** | **Global** (`~/.local/bin`) | **Per-Project History**: RTK stores command history in `~/.rtk/history.json`. `token-diet` allows you to define per-project `.token-budget` files to govern costs. |
| **tilth** | **Global** (`~/.local/bin`) | **Per-Project Scanning**: When an agent calls tilth, it scans the files in your **current project directory**. It doesn't store permanent state between projects. |
| **Serena** | **Global** (uvx/Docker) | **Per-Project Memories**: Serena's "Memories" (learned code patterns) are project-specific. It reads from and learns your active project directory. |

**In short:** You install them once (Global), but your AI agent uses them to optimize whichever project folder you currently have open (Per-Project).

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
Once installed, your AI agent (Claude Code, Codex, Gemini CLI, VS Code, etc.) will automatically use the optimized tools. You can monitor your diet via the CLI or dashboard:

```bash
token-diet           # See your total token savings
token-diet dashboard # Open the live browser stats
```

---

## Main Commands

| Command | Purpose |
| :--- | :--- |
| `token-diet gain` | **Status**: See how many tokens you've saved today. |
| `token-diet dashboard` | **Live UI**: Open the browser dashboard with persistent daily history. |
| `token-diet health` | **Check**: Quick health check of tools and registrations. |
| `token-diet mcp list` | **Hosts**: See which AI hosts (Gemini, Claude, etc.) are currently optimized. |
| `token-diet budget hubs` | **Discovery**: Register "Project Hubs" (e.g. `~/Projects`) for automatic discovery. |
| `token-diet budget status` | **Governance**: Check usage against your project budget. |
| `token-diet doctor` | **Debug**: Run deep diagnostics on your setup. |
| `token-diet repair` | **Fix**: Automatically fix hook and registration issues. |
| `token-diet clean` | **Archive**: Reset RTK history while preserving daily totals. |
| `token-diet hook off` | **Toggle**: Temporarily disable the RTK output filter. |
| `token-diet breakdown` | **Analytics**: Show top commands by token savings. |
| `token-diet explain` | **Inspect**: Break down costs for a specific command. |
| `token-diet loops` | **Safety**: Detect and flag agent loop patterns. |
| `token-diet route` | **Advisory**: Suggest which tool fits a specific task. |
| `token-diet leaks` | **Audit**: Detect redundant file reads in history. |
| `token-diet test-first` | **Strategy**: Suggest test files to read before implementation. |
| `token-diet diff-reads` | **Context**: Suggest minimal line ranges to read based on git diff. |
| `token-diet uninstall` | **Remove**: Cleanly remove all binaries and registrations. |

---

## Smart Discovery
`token-diet` automatically finds your `.token-budget` files using a hybrid logic:
1.  **RTK History**: It remembers every project you've ever worked in.
2.  **Project Hubs**: It scans your registered code roots (e.g., `~/Dev`).
3.  **Local Context**: It always checks your current folder and its neighbors.

Register a new hub to see all its project budgets on the dashboard:
```bash
token-diet budget hubs add ~/Work
```

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
