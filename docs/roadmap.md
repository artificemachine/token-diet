# token-diet Roadmap

## The Thesis

Three tools cover three layers that text search and full-file reads cannot:

| Layer | Tool | Mechanism | Savings |
|-------|------|-----------|---------|
| Symbol navigation | Serena | LSP-based definitions, references, renames | fewer turns (structural) |
| Persistent memory | ICM | Cross-session recall of decisions and errors | recall replaces re-reading (structural) |
| Library documentation | Context7 | Current docs for the library in use | fewer hallucinated APIs (structural) |

**None of these is an output filter.** RTK and tilth were removed from the stack
after independent benchmarks disproved the compression-savings claim; the
evidence is recorded in [comparison.md](comparison.md). The retired tracked
compression figure is not published anywhere in this project.

## Where the project stands (v1.10.4)

### Shipped

- [x] **Installer** — detects hosts, registers components, `--dry-run`, `--local` air-gapped build.
- [x] **Component set** — Serena + ICM + Context7, each individually selectable (`--serena-only`, `--icm-only`, `--context7-only`).
- [x] **CLI** — `status`, `health`, `doctor`, `repair`, `route`, `budget`, `mcp list`.
- [x] **Context hooks** (`--with-context-hooks`) — docextract + ctxwarn, off by default.
- [x] **Uninstall symmetry** — removes exactly what install writes, plus a legacy region that cleans pre-removal RTK/tilth installs.
- [x] **Test suite** — bats + pytest + Pester, run in CI.

### Removed

- [x] RTK, rtk-mcp, tilth: code, forks, docs, tests, and the tracked savings metric. See [comparison.md](comparison.md).

## Next Steps

### Iteration — Measurement honesty

**Goal:** replace the removed vanity metric with claims that can be defended.

| Feature | What | Why |
|---------|------|-----|
| Per-tool usage counter | Count Serena/ICM/Context7 tool calls per session, from host transcripts | Gives a real denominator without inventing a savings percentage |
| Cost-basis harness | Script a small task set, record billed tokens and pass/fail, publish method + N | The Quesma methodology is the bar; anything less stays unquantified |
| Budget accounting | Make `budget status` account for usage from a source that actually exists | It currently reports `untracked` because no usage counter is installed |

### Iteration — Integration

**Goal:** make the three tools cooperate instead of competing for the agent's attention.

| Feature | What | Why |
|---------|------|-----|
| Cross-tool router | `token-diet route` already suggests a tool; extend it with the library-docs arm for Context7 | Agents waste turns deciding where to look |
| Memory hygiene | Surface ICM topics that have grown stale or contradictory | Recall quality decays as memory grows |
| Doc-freshness hints | Flag when Context7 returns docs that disagree with a pinned dependency version | Prevents confident wrong APIs |

### Iteration — Footprint

**Goal:** keep the stack cheap enough that its structural benefits are not eaten
by its own runtime cost.

| Feature | What | Why |
|---------|------|-----|
| Serena process GC | `serena-gc` exists; add a scheduled check | LSP servers are the heaviest component in the stack |
| Host-scoped registration | Encourage project-local MCP scope over global | Global servers spawn a process tree per session |
| Startup audit | Report what each host actually loads at session start | Users should see the cost they are paying |

## Estimated Impact

This project no longer publishes a cumulative savings figure. The previous
roadmap carried a "~50% additional" line inherited from the removed tools'
claims; it was never measured and has been deleted rather than restated.

Impact claims will be added here only with the method, the run count, and a
cost basis — see [benchmarks.md](benchmarks.md).
