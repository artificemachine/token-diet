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

## Current Progress (v1.7.6)

### ✓ Foundation (Iteration 1)
- [x] `token-diet health` — Lightweight diagnostics.
- [x] `token-diet uninstall` — Clean removal path.
- [x] Automated Test Suite — 140+ bats/pytest tests.
- [x] `--verbose` installer flag.

### ✓ Measurement & Visibility (Iteration 2)
- [x] Per-project breakdown (`token-diet budget status`).
- [x] Token explainer (`token-diet explain`).
- [x] Dashboard v2 — Sparklines, Top Days, and Project Hubs.
- [x] **Persistent Daily History** — Stats survive history cleanup.

### ✓ Control (Iteration 3)
- [x] Token budget enforcement (`.token-budget` with warn/hard stop).
- [x] Loop detection (`token-diet loops`).
- [x] **Zero-Config Discovery** — Automatic project budget detection.

---

## Next Steps

### Iteration 4 — Efficiency (deeper savings)

**Goal:** Extract 20-30% more savings from code reading patterns.

| Feature | What | Why |
|---------|------|-----|
| Comment stripping | `token-diet strip`: strip non-doc comments, license headers, blank lines | ~30% of file content is noise for the agent |
| Incremental diff reads | `token-diet diff-reads`: suggest reading only changed ranges | Agents re-read entire files after small changes — ~25% waste |
| Dependency-ordered reads | `tilth deps --suggest-read-order`: read files in impact order | Alphabetical reading misses the critical path |

### Iteration 5 — Integration (cross-tool orchestration)

**Goal:** Make the three tools work as one unified system.

| Feature | What | Why |
|---------|------|-----|
| Cross-tool router | `token-diet route`: suggests tilth (fast reads), Serena (deep refactors), RTK (CLI output) | Agents waste tokens deciding which tool to use |
| Session dedup persistence | Persist tilth's file-read cache across sessions via Serena memory | Same utility files re-read every session |
| Context leakage detector | `token-diet leaks`: flags redundant reads in RTK history | "You read auth.rs 3 times in 10 turns — 2.4K tokens wasted" |
| Test-first strategy | `token-diet test-first`: suggests reading tests before implementation | Reduces trial-and-error rereads by 15-20% |

---

## Estimated Impact

| Iteration | Savings | Type | Status |
|-----------|---------|------|--------|
| 1 — Foundation | 0% direct | Enables everything else | **DONE** |
| 2 — Measurement | 0% direct | Visibility drives behavior change | **DONE** |
| 3 — Control | ~15% | Prevents budget blowouts and loops | **DONE** |
| 4 — Efficiency | ~25% | Comment stripping + incremental reads | **IN PROGRESS** |
| 5 — Integration | ~10% | Routing + dedup + leakage detection | **IN PROGRESS** |
| **Cumulative** | **~50% additional** | On top of existing RTK/tilth/Serena savings | |
