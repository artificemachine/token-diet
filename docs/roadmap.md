# token-diet Roadmap

## The Thesis

RTK, tilth, and Serena cover three layers of token optimization:

| Layer | Tool | Mechanism | Savings |
|-------|------|-----------|---------|
| Output compression | RTK | CLI proxy, regex/truncate | 60-90% (tracked) |
| Code reading | tilth | AST-aware tree-sitter | 38-44% (structural) |
| Symbol navigation | Serena | LSP-based navigation | fewer turns (structural) |

**What's missing: a fourth layer — observation and control.**

No budgets. No loop detection. No cross-session memory. No per-project attribution. No cross-tool routing. That layer is where the next 20-30% savings live, on top of what the three tools already deliver.

---

## Current Gaps

### Operational
- No `token-diet health` — lightweight diagnostic (currently requires full re-install via `--verify`)
- No `token-diet uninstall` — no clean removal path
- No test suite for the installer or CLI
- No `--verbose` / `--debug` flag for install.sh
- No per-project `token-diet init` command

### Measurement
- RTK tracks exact savings; tilth/Serena savings are "structural estimates" with no data
- All stats are global — no per-project or per-tool breakdown
- No cost explainer ("why did this command cost 87K tokens?")
- No session-level attribution

### Control
- No token budget enforcement (proactive)
- No loop detection (agents retrying the same thing 5x)
- No cross-tool routing (agents pick wrong tool, waste tokens on overlap)

### Efficiency
- No comment/noise stripping on code reads (~30% of file content is comments)
- No incremental diff patching ("read only what changed" vs full re-read)
- No cross-session dedup persistence (tilth forgets between sessions)
- No test-first read strategy suggestion

---

## Roadmap by Iteration

### Iteration 1 — Foundation (operational gaps)

**Goal:** Make the existing stack testable, diagnosable, and reversible.

| Feature | What | Why |
|---------|------|-----|
| `token-diet health` | Lightweight check: 3 tools responding, MCP registered, hosts detected | `--verify` re-runs the entire installer — too slow for daily use |
| `token-diet uninstall` | Remove binaries, MCP entries, config files, injected references | No removal path exists; users must clean up manually |
| Test suite | Bash tests for install.sh (dry-run assertions), Python tests for dashboard API | Zero automated tests today; any refactor is blind |
| `--verbose` flag | Full build/install output instead of `tail -5` | Errors are currently hidden; debugging requires re-running commands |

### Iteration 2 — Measurement (visibility gaps)

**Goal:** Give users and agents visibility into where tokens go.

| Feature | What | Why |
|---------|------|-----|
| Per-project breakdown | `token-diet breakdown --by project` | All stats are global; no way to compare projects |
| Per-tool breakdown | `token-diet breakdown --by tool` | Can't tell if RTK, tilth, or Serena drives savings |
| Token explainer | `token-diet explain 'cargo test'` | Users don't know which commands are expensive or why |
| Dashboard v2 | Add breakdown charts, session history, project selector | Current dashboard shows only RTK global totals |

### Iteration 3 — Control (proactive savings)

**Goal:** Prevent token waste before it happens.

| Feature | What | Why |
|---------|------|-----|
| Token budget | `.token-budget` per project with warn/hard-stop thresholds | No proactive control — only reactive measurement |
| Loop detection | Semantic fingerprinting to catch agents retrying the same read/edit cycle | Most expensive waste pattern — agents stuck in loops burn 5x tokens |
| Budget burn-down | Dashboard shows remaining budget as a burn-down chart | Current dashboard only shows cumulative totals |

### Iteration 4 — Efficiency (deeper savings)

**Goal:** Extract 20-30% more savings from code reading patterns.

| Feature | What | Why |
|---------|------|-----|
| Comment stripping | `--clean` mode in tilth: strip non-doc comments, license headers, blank lines | ~30% of file content is noise for the agent |
| Incremental diff reads | `tilth diff --suggest-reads`: read only changed ranges + minimal context | Agents re-read entire files after small changes — ~25% waste |
| Dependency-ordered reads | `tilth deps --suggest-read-order`: read files in impact order | Alphabetical reading misses the critical path |

### Iteration 5 — Integration (cross-tool orchestration)

**Goal:** Make the three tools work as one unified system.

| Feature | What | Why |
|---------|------|-----|
| Cross-tool router | Meta-MCP server: dispatches to tilth (fast reads), Serena (deep refactors), RTK (CLI output) | Agents waste tokens deciding which tool to use |
| Session dedup persistence | Persist tilth's file-read cache across sessions via Serena memory | Same utility files re-read every session |
| Context leakage detector | MCP tool that flags redundant reads and suggests alternatives | "You read auth.rs 3 times in 10 turns — 2.4K tokens wasted" |
| Test-first strategy | tilth suggests reading tests before implementation | Reduces trial-and-error rereads by 15-20% |

---

## Estimated Impact

| Iteration | Savings | Type |
|-----------|---------|------|
| 1 — Foundation | 0% direct | Enables everything else |
| 2 — Measurement | 0% direct | Visibility drives behavior change |
| 3 — Control | ~15% | Prevents budget blowouts and loops |
| 4 — Efficiency | ~25% | Comment stripping + incremental reads |
| 5 — Integration | ~10% | Routing + dedup + leakage detection |
| **Cumulative** | **~50% additional** | On top of existing RTK/tilth/Serena savings |
