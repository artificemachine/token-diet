# token-diet

[![Tests](https://github.com/artificemachine/token-diet/actions/workflows/test.yml/badge.svg)](https://github.com/artificemachine/token-diet/actions/workflows/test.yml)
[![Path Leak Guard](https://github.com/artificemachine/token-diet/actions/workflows/path-leak.yml/badge.svg)](https://github.com/artificemachine/token-diet/actions/workflows/path-leak.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20WSL-lightgrey.svg)](#requirements)

**Your AI coding agent reads too much.** token-diet installs and wires four
tools that sit between the agent and your machine, so it reads what it needs
instead of everything.

One command installs the stack and registers it across every AI host you have:
Claude Code, Codex CLI, OpenCode, Copilot CLI, VS Code, Claude Desktop, and
Gemini CLI.

```console
$ token-diet gain

RTK — command output compression (tracked)
──────────────────────────────────────────────────
  Commands filtered:     200194
  Tokens in:             110.2M
  Tokens saved:          92.5M  (83.9%)
  Exec time:             157h 2m
  Efficiency:  ████████████████░░░░  83.9%
  ✓  RTK 0.43.0 — active

tilth — AST-aware code reading (tree-sitter)
──────────────────────────────────────────────────
  MCP hosts:             claude-code,claude-desktop,opencode,codex,gemini
  ✓  tilth 0.9.0 — active
```

That 83.9% is one real machine's measured history over 200k commands, not a
marketing figure. Your number will differ. See
[docs/benchmarks.md](docs/benchmarks.md) for what is measured, what is
benchmarked, and what is neither.

## Install

```bash
git clone --recursive https://github.com/artificemachine/token-diet.git
cd token-diet

bash scripts/install.sh --dry-run   # see exactly what it would touch
bash scripts/install.sh             # do it
token-diet health                   # verify
```

`--recursive` matters: the four tools live in `forks/` as submodules. If you
already cloned without it, run `git submodule update --init --recursive`.

The installer detects which AI hosts you have and registers only those. Use
`--hosts claude,vscode` to narrow it, and `--dry-run` first if you want to see
the config files it will edit.

### Requirements

`bash`, `python3`, `git`, `jq`, `bc`. The default install fetches Rust and `uv`
if they're missing; `--local` builds everything from the pinned forks instead
and needs no network.

Optional: `poppler-utils` (better PDF extraction), `tiktoken` and `pdfplumber`
(exact token counts and richer PDF parsing). Everything degrades gracefully
without them.

## What the four tools do

| Tool | Job | Savings |
| :--- | :--- | :--- |
| **[RTK](https://github.com/rtk-ai/rtk)** | Compresses CLI output (builds, tests, logs) before the agent sees it | 60-90% output reduction, measured live from your own history |
| **[tilth](https://github.com/jahala/tilth)** | Reads code by AST, returning the symbols asked for instead of whole files | -38% to -44% cost per correct answer, [benchmarked](docs/benchmarks.md) |
| **[Serena](https://github.com/oraios/serena)** | LSP navigation, so the agent jumps to a definition instead of reading to find it | Fewer prompt turns; not separately measured |
| **[ICM](https://github.com/artificemachine/icm)** | Persistent cross-session memory, so facts get recalled instead of re-derived | Recall replaces re-reading; not separately measured |

There is deliberately no single headline "saves X%" number. Two of the four are
not separately measured, and inventing a combined figure would mean publishing
a guess. [docs/benchmarks.md](docs/benchmarks.md) explains the method for each.

### Installed globally, scoped per project

All four install once as global binaries. They operate on whichever project
directory you're in: RTK keeps per-project history, tilth and Serena scan the
current tree, and ICM persists across sessions and tools. Per-project token
budgets live in a `.token-budget` file.

## Optional: context hooks

`--with-context-hooks` registers two hooks that intercept live tool calls:

- **docextract** — when the agent reads a PDF, CSV, or HTML file, it gets a
  cached plain-text extraction instead of raw bytes.
- **ctxwarn** — warns once per session when the transcript crosses the
  `ctx_threshold` in your `.token-budget`.

```bash
bash scripts/install.sh --with-context-hooks
```

Off by default, because these are the only features that intercept a live tool
call. Real hooks are wired for Claude Code, Gemini CLI, and OpenCode. Codex CLI
and Copilot CLI have no hook API, so they get an instruction document instead.

## Commands

```bash
token-diet              # savings dashboard (default)
token-diet dashboard    # live browser UI
token-diet health       # quick check: tools + registrations
token-diet doctor       # deep diagnosis  [--json]
token-diet repair       # fix what doctor finds  [--dry-run]
```

<details>
<summary>Full command reference</summary>

| Command | Purpose |
| :--- | :--- |
| `token-diet gain` | Token savings dashboard. The default when run with no arguments. |
| `token-diet dashboard` | Live browser UI with daily history. `--no-open` to skip launching a browser. |
| `token-diet health` | Quick check: tools responding, MCP hosts registered. |
| `token-diet doctor` | Deep diagnosis of hooks, registrations, and versions. `--json` for machine output. |
| `token-diet repair` | Fix hook and stale-registration issues found by `doctor`. `--dry-run` to preview. |
| `token-diet version` | Installed versions of all four tools. |
| `token-diet mcp list` | Which AI hosts are currently wired up. `mcp install` to register. |
| `token-diet budget init` | Create a `.token-budget` for the current project. |
| `token-diet budget status` | Usage against the project budget. |
| `token-diet budget hubs` | Register project roots (e.g. `~/Work`) for budget discovery. |
| `token-diet breakdown` | Top commands by tokens saved. `--limit N`. |
| `token-diet explain <cmd>` | Cost breakdown for one command. |
| `token-diet loops` | Detect agent loop patterns (same command 3+ times). |
| `token-diet leaks` | Detect files read repeatedly in history. |
| `token-diet route <task>` | Suggest which of the four tools fits a task. |
| `token-diet test-first <file>` | Suggest the test counterpart to read first. |
| `token-diet diff-reads <file>` | Suggest minimal line ranges based on recent git diff. |
| `token-diet extract <file>` | Extract a PDF/CSV/HTML/TXT document to a hash-cached plain-text file. |
| `token-diet strip <file>` | Strip comments from a source file to reduce tokens. `--stats` to preview. |
| `token-diet icm warmup` | One-time embedding-model download (~270 MB) for ICM semantic recall. Offline after. |
| `token-diet clean` | Archive and reset RTK history, preserving daily totals. |
| `token-diet hook on\|off` | Toggle the RTK output filter. |
| `token-diet serena-gc` | Find and kill orphaned Serena/LSP processes. `--force` to kill. |
| `token-diet service` | Manage the always-on dashboard daemon: `install\|uninstall\|start\|stop\|status`. |
| `token-diet upstream` | Check the pinned forks against their upstreams: `setup\|check\|diff`. |
| `token-diet update` | Update the tools. `--fresh` for a clean reinstall. |
| `token-diet uninstall` | Remove all binaries, configs, and registrations. `--dry-run`, `--force`. |

</details>

### Budget discovery

`token-diet` finds `.token-budget` files three ways: from RTK history (every
project you've worked in), from registered hubs, and from the current directory.

```bash
token-diet budget hubs add ~/Work
```

## Uninstall

```bash
token-diet uninstall --force     # binaries, configs, registrations
rm -rf ~/.serena                 # optional: Serena memories and logs
```

`--dry-run` shows what would be removed. `--include-data` also removes Serena
memories.

## Platform support

macOS, Linux, and WSL are the supported platforms and are covered by CI.

**Windows (native) is experimental.** PowerShell scripts exist
(`scripts/Install.ps1`, `scripts/token-diet.ps1`) and there is a Pester suite,
but neither runs in CI, and the PowerShell CLI does not yet implement the
context hooks (`docextract`, `ctxwarn`), `serena-gc`, the Docker helpers, or
`budget hubs`. Treat it as unverified. WSL is the recommended path on Windows.

## Air-gapped install

`bash scripts/install.sh --local` builds everything from the pinned forks with
no network access. See the [Enterprise Guide](docs/enterprise.md).

## Development

```bash
bats tests/*.bats && pytest tests/ -q
```

197 bats tests and 61 pytest tests. See [CONTRIBUTING.md](CONTRIBUTING.md) for
setup, and [docs/engineering-notes.md](docs/engineering-notes.md) for how this
project is tested and debugged.

## License

MIT. All four upstream tools are MIT-licensed. See
[compliance/](compliance/) for the SBOM and third-party license inventory.
