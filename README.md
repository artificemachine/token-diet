# token-diet

Put your AI coding sessions on a diet. Three tools, three layers, zero overlap.

## What is this?

`token-diet` is an installer, build system, and compliance kit for a complete token optimization stack. It wires together three complementary tools — with support for both open-source and enterprise (air-gapped) deployment.

| Tool | Layer | What it does |
|---|---|---|
| [RTK](https://github.com/rtk-ai/rtk) | Command output | Filters `git log`, `cargo test`, `npm install` — 60-90% savings |
| [tilth](https://github.com/jahala/tilth) | Code reading | AST-aware file reading + symbol search — 38-44% cost reduction |
| [Serena](https://github.com/oraios/serena) | Code understanding | LSP-powered symbol navigation, rename, diagnostics |

```
+-----------------------------------------------------------+
|  Claude Code / Codex / OpenCode / Copilot CLI / VS Code   |
+-----------------------------------------------------------+
         |                |                |
    Code reading     Refactoring     Command output
         |                |                |
    +--------+      +---------+      +--------+
    | tilth  |      | Serena  |      |  RTK   |
    | (fast) |      |  (deep) |      | (filter)|
    +--------+      +---------+      +--------+
    tree-sitter        LSP           regex/truncate
```

## Supported AI Hosts

Auto-detected and configured for:

| Host | RTK | tilth | Serena |
|---|---|---|---|
| **Claude Code** | Hook (settings.json) | MCP server | MCP server |
| **Codex CLI** (OpenAI) | AGENTS.md + RTK.md | MCP server | MCP via config.toml |
| **OpenCode** | Plugin | MCP server | MCP server |
| **Copilot CLI** | Shared hooks | MCP server | Shared with VS Code |
| **VS Code** | — | MCP server | MCP via .vscode/mcp.json |

## Quick Start (Open Source)

Install from upstream repositories (requires internet):

```bash
# macOS / Linux — install all
bash scripts/install.sh

# Install specific tool
bash scripts/install.sh --rtk-only

# Preview what would be installed (no changes made)
bash scripts/install.sh --dry-run

# Check status
bash scripts/install.sh --verify
```

```powershell
# Windows
.\scripts\Install.ps1
.\scripts\Install.ps1 -Tool RTK
.\scripts\Install.ps1 -DryRun        # preview, no changes made
.\scripts\Install.ps1 -VerifyOnly
```

```bash
# Ansible
ansible-playbook scripts/playbook.yml
ansible-playbook scripts/playbook.yml -e "tools=rtk,tilth"
```

## Dashboard & CLI

After installation, `token-diet` is available globally:

```bash
token-diet                  # token savings summary (RTK + tilth + Serena)
token-diet health           # quick health check: tools + MCP host registrations
token-diet breakdown        # top commands by tokens saved  [--limit N]
token-diet explain <cmd>    # per-command cost: tokens in/out/saved, efficiency
token-diet budget init      # create .token-budget with warn/hard thresholds
token-diet budget status    # usage vs budget (exits 0=OK, 2=WARN, 3=HARD STOP)
token-diet loops            # detect agent loop patterns (commands run 3+ times)
token-diet strip <file>     # strip comments from source file to reduce prompt tokens  [--stats]
token-diet diff-reads <file> # suggest line ranges to read based on recent git diff
token-diet route <task>     # suggest which tool (tilth/Serena/RTK) best fits the task
token-diet leaks            # detect files read multiple times (context waste)
token-diet test-first <file> # suggest test file counterpart before reading implementation
token-diet dashboard        # live browser dashboard at http://127.0.0.1:7384
token-diet dashboard --port 8080
token-diet version          # show installed versions
token-diet verify           # re-run installation verification
token-diet uninstall        # remove all token-diet components
token-diet uninstall --dry-run   # preview what would be removed
```

The browser dashboard auto-refreshes every 30 s and shows cumulative RTK savings, a 14-day savings bar chart, weekly token projection, budget usage vs warn/hard thresholds, top-commands breakdown, loop and leak alerts, tilth/Serena status, and registered MCP hosts with missing-host hints.

## Enterprise / Air-Gapped Deployment

Build from audited local forks — no internet required at install time.

### 1. Fork upstream repos to your internal Git server

```bash
# Clone upstream, push to internal Gitea/Forgejo/GitLab
git clone https://github.com/rtk-ai/rtk.git
cd rtk && git remote add internal https://gitea.internal/token-diet/rtk.git
git push internal main
# Repeat for tilth and serena
```

The repo must exist on the forge first (create it empty, no README). You now have two remotes: `origin` (GitHub) and `internal` (your forge). Verify with `git remote -v`.

**Staying in sync** — pull upstream changes and re-push:

```bash
git fetch origin && git push internal --mirror
```

`--mirror` syncs all branches, tags, and refs — not just `main`. Run this as a cron job or CI task to keep the mirror current.

> **Tip:** Forgejo, GitLab, and Gitea all support *pull mirrors* from the UI — point them at the GitHub URL and they auto-sync on a schedule without any manual script.

### 2. Update submodule URLs

Edit `.gitmodules` to point to your internal server, then:

```bash
git submodule update --init --recursive
```

### 3. Verify the forks build and pass tests

```bash
# Build + test + audit all forks (CI verification)
bash scripts/build.sh --release
```

### 4. Install from local forks

```bash
# Build and install directly from forks/ — no crates.io, no PyPI, no GitHub
bash scripts/install.sh --local
```

### 5. Distribute to team

Each team member clones token-diet, runs `git submodule update --init --recursive`,
then `bash scripts/install.sh --local`. Rust toolchain is auto-installed by the
script if missing.

## Project Structure

```
token-diet/
├── forks/                    # Git submodules (audited forks)
│   ├── rtk/
│   ├── tilth/
│   └── serena/
├── docker/
│   ├── Dockerfile.serena     # Air-gapped Serena image
│   └── compose.yml           # Local Docker compose
├── scripts/
│   ├── install.sh            # macOS/Linux installer (--local for air-gapped)
│   ├── Install.ps1           # Windows installer
│   ├── token-diet            # CLI dashboard (installed to ~/.local/bin/token-diet)
│   ├── token-diet-dashboard  # Browser dashboard server (Python stdlib)
│   ├── playbook.yml          # Ansible playbook
│   └── build.sh              # Build from forks (no internet)
├── config/
│   └── serena-dedup.template.yml  # Overlap fix config
├── compliance/
│   ├── SBOM.template.json    # CycloneDX bill of materials
│   ├── LICENSE-THIRD-PARTY.md
│   └── security-audit.md     # Per-tool security checklist
├── docs/
│   └── comparison.md         # RTK vs tilth vs Serena analysis
├── scripts/build.sh          # Build + test + audit all forks (CI verification)
├── .gitmodules               # Submodule config
└── .gitignore
```

## Overlap Fix

tilth and Serena both do code navigation. The installer configures Serena to defer fast operations (file reading, symbol search, outlines) to tilth, keeping Serena for LSP-only operations (rename, references, diagnostics).

Applied per project:

```bash
cp ~/.config/serena/project.local.template.yml /path/to/project/project.local.yml
```

See [docs/comparison.md](docs/comparison.md) for the full analysis.

## Security Model

| Concern | Solution |
|---|---|
| Supply chain | Build from audited forks, no upstream at runtime |
| Telemetry | Strip in fork (RTK analytics, Serena tiktoken) |
| Network isolation | Serena Docker: `network_mode: none` |
| Reproducibility | Pinned submodules + Cargo.lock + Docker base |
| Compliance | SBOM, license tracking, audit checklist |

See [compliance/security-audit.md](compliance/security-audit.md) for the full checklist.

## Prerequisites

**Open source mode:**
- git, curl, Rust toolchain (auto-installed), uv (auto-installed)

**Enterprise mode:**
- git, Rust toolchain, Docker
- Internal Git server (Gitea/Forgejo recommended)

## License

MIT — all three upstream tools are MIT-licensed.
