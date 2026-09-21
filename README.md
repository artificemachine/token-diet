# token-diet

[![Tests](https://github.com/artificemachine/token-diet/actions/workflows/test.yml/badge.svg)](https://github.com/artificemachine/token-diet/actions/workflows/test.yml)
[![Path Leak Guard](https://github.com/artificemachine/token-diet/actions/workflows/path-leak.yml/badge.svg)](https://github.com/artificemachine/token-diet/actions/workflows/path-leak.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20WSL-lightgrey.svg)](#requirements)

**Your AI coding agent guesses too much.** token-diet installs and wires three
tools that give it facts instead: symbol navigation, persistent memory, and
current library documentation.

One command installs the stack and registers it across every AI host you have:
Claude Code, Codex CLI, OpenCode, Copilot CLI, VS Code, Claude Desktop, and
Gemini CLI.

## What changed

RTK and tilth were removed from this stack. Independent benchmarks
([Quesma](https://quesma.com/blog/does-rtk-make-ai-coding-cheaper/), 1,740
attempts; [JetBrains SkillsBench](https://blog.jetbrains.com/ai/2026/07/rtk-claude-code-token-savings/))
found RTK's reported savings did not translate into real cost savings — its
`gain` metric counts removed output bytes, not billed tokens — and tilth's
claims were never independently validated. The evidence is recorded in
[docs/comparison.md](docs/comparison.md). No compression percentage is published
here anymore. If you installed an earlier version, the uninstallers still clean
the old tools up.

## Install

```bash
git clone --recursive https://github.com/artificemachine/token-diet.git
cd token-diet

bash scripts/install.sh --dry-run   # see exactly what it would touch
bash scripts/install.sh             # do it
token-diet status                   # verify
```

`--recursive` matters: the local components live in `forks/` as submodules. If
you already cloned without it, run `git submodule update --init --recursive`.

The installer detects which AI hosts you have and registers only those. Use
`--hosts claude,vscode` to narrow it, and `--dry-run` first if you want to see
the config files it will edit.

### Requirements

`bash`, `python3`, `git`, `jq`, `bc`. The default install fetches Rust and `uv`
if they're missing; `--local` builds from the pinned forks instead and needs no
network.

Optional: `poppler-utils` (better PDF extraction), `tiktoken` and `pdfplumber`
(exact token counts and richer PDF parsing). Everything degrades gracefully
without them.

## What the three tools do

| Tool | Job | Basis |
| :--- | :--- | :--- |
| **[Serena](https://github.com/oraios/serena)** | LSP navigation, so the agent jumps to a definition instead of reading to find it | Fewer prompt turns; not separately measured |
| **[ICM](https://github.com/artificemachine/icm)** | Persistent cross-session memory, so facts get recalled instead of re-derived | Recall replaces re-reading; not separately measured |
| **[Context7](https://github.com/upstash/context7)** | Current library docs, so the agent stops inventing renamed APIs | Not separately measured |

There is deliberately no headline "saves X%" number. None of the three has a
benchmark published in this repository, and inventing a figure would mean
publishing a guess. [docs/benchmarks.md](docs/benchmarks.md) explains what
would be required before a number appears there.

### Installed globally, scoped per project

All three install once. Serena and ICM run against whichever project directory
you're in; Context7 is a remote documentation service registered per host.
Prefer project-local MCP scope when only one repo needs a server. Per-project
token budgets live in a `.token-budget` file.

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
token-diet              # component + registration dashboard (default)
token-diet dashboard    # live browser UI
token-diet health       # quick check: tools + registrations
token-diet doctor       # deep diagnosis  [--json]
token-diet repair       # fix what doctor finds  [--dry-run]
```

<details>
<summary>Full command reference</summary>

| Command | Purpose |
| :--- | :--- |
| `token-diet status` | Component and registration dashboard. The default with no arguments. |
| `token-diet dashboard` | Live browser UI. `--no-open` to skip launching a browser. |
| `token-diet health` | Quick check: tools responding, MCP hosts registered. |
| `token-diet doctor` | Deep diagnosis of registrations and versions. `--json` for machine output. |
| `token-diet repair` | Fix stale-registration issues found by `doctor`. `--dry-run` to preview. |
| `token-diet version` | Installed component versions. |
| `token-diet mcp list` | Which AI hosts are currently wired up. `mcp install` to register. |
| `token-diet budget init` | Create a `.token-budget` for the current project. |
| `token-diet budget status` | Usage against the project budget (reports `untracked` when no usage counter is installed). |
| `token-diet budget hubs` | Register project roots (e.g. `~/Work`) for budget discovery. |
| `token-diet route <task>` | Suggest which tool fits a task. |
| `token-diet test-first <file>` | Suggest the test counterpart to read first. |
| `token-diet diff-reads <file>` | Suggest minimal line ranges based on recent git diff. |
| `token-diet extract <file>` | Extract a PDF/CSV/HTML/TXT document to a hash-cached plain-text file. |
| `token-diet strip <file>` | Strip comments from a source file to reduce tokens. `--stats` to preview. |
| `token-diet icm warmup` | One-time embedding-model download (~270 MB) for ICM semantic recall. Offline after. |
| `token-diet serena-gc` | Find and kill orphaned Serena/LSP processes. `--force` to kill. |
| `token-diet service` | Manage the always-on dashboard daemon: `install\|uninstall\|start\|stop\|status`. |
| `token-diet upstream` | Check the pinned forks against their upstreams: `setup\|check\|diff`. |
| `token-diet update` | Update the tools. `--fresh` for a clean reinstall. |
| `token-diet uninstall` | Remove all binaries, configs, and registrations. `--dry-run`, `--force`. |

</details>

### Budget discovery

`token-diet` finds `.token-budget` files from registered hubs and from the
current directory.

```bash
token-diet budget hubs add ~/Work
```

## Uninstall

```bash
token-diet uninstall --force     # binaries, configs, registrations
rm -rf ~/.serena                 # optional: Serena memories and logs
```

`--dry-run` shows what would be removed. `--include-data` also removes Serena
memories. The uninstallers keep a marked legacy cleanup region that removes RTK,
rtk-mcp, and tilth artifacts left by earlier versions.

## Platform support

macOS, Linux, and WSL are the supported platforms and are covered by CI.

**Windows (native) is experimental.** PowerShell scripts exist
(`scripts/Install.ps1`, `scripts/token-diet.ps1`) and there is a Pester suite,
but neither runs in CI, and the PowerShell CLI does not yet implement the
context hooks (`docextract`, `ctxwarn`), `serena-gc`, the Docker helpers, or
`budget hubs`. Treat it as unverified. WSL is the recommended path on Windows.

## Air-gapped install

`bash scripts/install.sh --local` builds from the pinned forks with no network
access. See the [Enterprise Guide](docs/enterprise.md) — note that Context7 is
the stack's one outbound registration, so skip it on isolated machines.

## Development

```bash
bats tests/*.bats && pytest tests/ -q
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, and
[docs/engineering-notes.md](docs/engineering-notes.md) for how this project is
tested and debugged.

## License

MIT. Serena is MIT-licensed, ICM is Apache-2.0, and Context7 is a remote
service (no code bundled). See [compliance/](compliance/) for the SBOM and
third-party license inventory.
