# Implementation Plan — docextract + ctxwarn as token-diet modules

## 1. Scope summary

Add two token-optimization filters to the existing `token-diet` stack, alongside RTK/tilth/Serena/ICM: `docextract` (extract PDF/csv/html/txt to plain text before it enters an LLM context — the RTK analogue for documents) and `ctxwarn` (estimate a session transcript's token size and warn when it crosses a threshold — the runtime warn-arm of the existing `.token-budget` subsystem). Both are Python cores in `scripts/lib/`, invoked by new bash subcommands (`token-diet extract`, and a `--check` arm on `token-diet budget`), and registered as cross-harness hooks by extending `scripts/install.sh`'s existing per-harness block. What's explicitly NOT being built: a standalone repo (rejected — these belong in token-diet), docx/pptx/xlsx/epub extraction (needs `markitdown`, deferred to v2), OCR, auto-`/compact`, and any new installer (reuse `install.sh`).

**Smallest possible v1:** Iteration 1 alone — `token-diet extract <file.pdf>` prints a cached text path. Usable by hand with no hook wiring.

**Source design doc:** `docs/GUIDE-context-warning-and-pdf-intercept-hooks.md` (copied into this repo).

## 2. Prerequisites

**Dependencies (all confirmed present):** Python 3.11.6, `pdfplumber`, `pdftotext` (`/opt/homebrew/bin`), `tiktoken`. Stdlib `csv`/`html.parser` for csv/html. Test harness: `bats` (bash) + `pytest` (python) already used in `tests/`.

**Existing code areas the work touches (all in-repo, confirmed):**
- `scripts/token-diet` — bash CLI, `cmd_*` functions + dispatch case block (`gain)`/`hook)`/`budget)` at ~line 2509). New `cmd_extract` and a `budget --check` arm insert here.
- `scripts/lib/` — currently holds `opencode-rules.md`; new Python cores land here.
- `scripts/install.sh` — cross-harness hook registration block (Claude Code `~/.claude/settings.json` at ~line 1436; Gemini via `rtk init --gemini` at ~544; Cowork awareness-doc at ~485; Copilot shares CC). This is the machinery both hooks reuse.
- `scripts/uninstall.sh` — must unregister the new hooks symmetrically.
- `tests/token-diet.bats`, `tests/install.bats`, `tests/conftest.py` — existing test homes.
- `cmd_budget` (line 1036) + helpers `find_budget_file` (1006), `ensure_global_budget` (1018) — ctxwarn reuses the `.token-budget` discovery.

**Risks that could block the plan:**
- `scripts/token-diet` defines `cmd_hook()` **twice** (lines 611 and 666); the second shadows the first. Extending hook logic risks editing the dead copy. Mitigation: Iteration 3 must confirm which definition the dispatch actually reaches before editing, and flag the duplicate for a separate fix (not fixed here to keep scope tight) — OQ-1.
- Binary PDF test fixtures would trip global pre-commit check 1f. Mitigation: fixtures generated at test runtime into `tmp_path`, never committed (baked into every iteration).
- Gemini `PreToolUse` support for a *non-RTK* hook is unverified; install.sh currently wires Gemini only via `rtk init --gemini`. Mitigation: Iteration 3 probes; if unsupported, Gemini falls back to the awareness-doc (soft rule) path install.sh already uses for Cowork — OQ-2.

## 3. Iterations

#### Iteration 1 — `docextract` core + `token-diet extract` subcommand

**Goal:** `token-diet extract <file>` extracts a supported document to a hash-keyed cache and prints the cache path, with a clear exit-code contract for unsupported/binary/missing inputs.

**Shippable on its own?** Yes — usable by hand immediately, no hook wiring.

**Source references:**
- `docs/GUIDE-context-warning-and-pdf-intercept-hooks.md` — the EXTRACT/NATIVE/NEEDS_MARKITDOWN extension split this core implements. Read first to keep the sets identical to the documented design.
- `scripts/token-diet` (lines ~209 `cmd_gain`, ~2509 dispatch case) — the `cmd_*` + dispatch idiom the new subcommand must match. Read before adding `cmd_extract`.

**Files touched:**
- `scripts/lib/docextract.py` (modified — shipped commit `70cc457`; the Python core)
- `scripts/lib/tdcache.py` (modified — shipped commit `70cc457`; hash-keyed cache-path helper, shared with ctxwarn in Iteration 2)
- `scripts/token-diet` (modified — add `cmd_extract()` and an `extract)` dispatch arm)
- `tests/test_docextract.py` (modified — shipped commit `70cc457`; pytest for the Python core)
- `tests/conftest.py` (modified — add runtime fixture generators: minimal PDF bytes, csv, html; no committed binaries)
- `tests/token-diet.bats` (modified — add a `token-diet extract --help` smoke case)
- `CHANGELOG.md` (modified — append entry)

**Commit message:**
`feat(extract): add docextract document-to-text core and token-diet extract subcommand`

**TDD cycle:**
- RED (failing tests to write first):
  - `tests/test_docextract.py::test_extract_pdf_returns_cache_path_with_text` — a generated one-page PDF containing "HELLO PLAN" extracts to a `.md` cache file containing "HELLO PLAN"; the core prints that path.
  - `tests/test_docextract.py::test_extract_csv_to_markdown_table` — a csv fixture extracts to a markdown table.
  - `tests/test_docextract.py::test_extract_html_strips_tags` — an html fixture extracts to tag-free text.
  - `tests/test_docextract.py::test_txt_passthrough` — a `.txt` input returns unchanged.
  - `tests/test_docextract.py::test_binary_input_exits_2` — a `.zip` input exits 2, prints "no text extractor".
  - `tests/test_docextract.py::test_needs_markitdown_exits_3` — a `.docx` input exits 3, prints an install-markitdown hint.
  - `tests/test_docextract.py::test_cache_hit_skips_reextraction` — a repeat call on an unchanged file returns the same path without rewrite.
  - `tests/test_docextract.py::test_missing_file_exits_4` — a nonexistent path exits 4.
- GREEN (minimal implementation):
  - `EXTRACT={".pdf",".csv",".html",".htm",".txt",".md"}`, `NATIVE={".png",".jpg",".jpeg",".gif",".webp"}`, `NEEDS_MARKITDOWN={".docx",".pptx",".xlsx",".epub",".odt",".rtf"}`.
  - `extract(path)->str`: dispatch by suffix. PDF via `pdfplumber.open`; on exception fall back to `subprocess pdftotext -`. csv via stdlib `csv`→markdown table. html via a minimal `html.parser` stripper. txt/md read-through.
  - `scripts/lib/tdcache.py::cache_path(src)->Path`: `~/.cache/token-diet/extract/<sha256(abspath+mtime)>.md`.
  - `main(argv)`: missing→4; suffix in NEEDS_MARKITDOWN→3+hint; NATIVE or unknown-binary→2; else extract (or reuse cache), write, print path, exit 0.
  - `cmd_extract()` (bash): `python3 "$SCRIPT_DIR/lib/docextract.py" "$@"`; add `extract) shift; cmd_extract "$@" ;;` to dispatch.
- REFACTOR (cleanup after GREEN):
  - Extract the per-format branches into a `_EXTRACTORS: dict[str, Callable]` dispatch table in `docextract.py`.

**Test pyramid for this iteration:**
- Smoke: `token-diet extract --help` exits 0 (bats).
- Unit: 8 — one per format/branch/exit-code; file `tests/test_docextract.py`.
- Integration: N/A — single module + stdlib, no cross-component boundary yet.
- State machine: N/A — no FSM.
- Contract: 1 — exit-code contract (0/2/3/4) asserted as a table test.
- Regression: N/A — new module, no prior bug.
- Chaos: 1 — a zero-byte/corrupt PDF falls back to `pdftotext` then exits cleanly, no crash.
- E2E: N/A — closes no full user path until hooked (Iteration 3).
- Performance: N/A — not a v1 acceptance criterion.
- TDD Parity: 100% — `extract`, `cache_path`, `main` each directly tested.
- Coverage: docextract.py + tdcache.py fully covered by test_docextract.py; no repo-wide `fail_under` change (token-diet has no Python coverage gate today — note only, do not add one).

**Acceptance criteria (binary):**
- [ ] `token-diet extract <one-page-pdf>` prints a `.md` cache path whose file contains the PDF text.
- [ ] `token-diet extract <file.zip>` exits 2 with "no text extractor".
- [ ] `token-diet extract <file.docx>` exits 3 with an install-markitdown hint.
- [ ] A repeat call on an unchanged file returns the identical cache path without rewriting.
- [ ] `pytest tests/test_docextract.py` green; no binary fixture committed.

**Estimated effort:** M

**Blocked by:** None

**Side-effect fence:** Repo tree + `~/.cache/token-diet/` only. No live config, service, or global home touched this iteration.

---

#### Iteration 2 — `ctxwarn` core + `token-diet budget --check` arm

**Goal:** A `ctxwarn` core that estimates a transcript JSONL's token size and warns over a threshold, exposed through a new `--check` arm on the existing `token-diet budget` command, reusing `.token-budget` discovery.

**Shippable on its own?** Yes — `token-diet budget --check --transcript <f>` runs by hand against any JSONL.

**Source references:**
- `docs/GUIDE-context-warning-and-pdf-intercept-hooks.md` — the threshold (~100k, matching global Gate 15) and debounce design.
- `scripts/token-diet` (lines 1006 `find_budget_file`, 1018 `ensure_global_budget`, 1036 `cmd_budget`) — the `.token-budget` discovery and budget-command structure ctxwarn plugs into. Read and **verify these signatures before calling** — the budget command may have changed shape.

**Files touched:**
- `scripts/lib/ctxwarn.py` (modified — shipped commit `eb6ea74`; the Python core)
- `scripts/token-diet` (modified — add a `--check` arm inside `cmd_budget` that calls `ctxwarn.py`)
- `tests/test_ctxwarn.py` (modified — shipped commit `eb6ea74`; pytest for the core)
- `tests/token-diet.bats` (modified — add a `budget --check` smoke case)
- `CHANGELOG.md` (modified — append entry)

**Commit message:**
`feat(budget): add ctxwarn transcript token estimator as budget --check arm`

**TDD cycle:**
- RED (failing tests to write first):
  - `tests/test_ctxwarn.py::test_estimate_tokens_tiktoken_path` — a JSONL fixture yields a tiktoken count within 5% of a precomputed value.
  - `tests/test_ctxwarn.py::test_estimate_falls_back_to_chars_div_4` — with tiktoken monkeypatched to raise, estimate equals `total_chars // 4`.
  - `tests/test_ctxwarn.py::test_below_threshold_prints_nothing` — under threshold → empty stdout, exit 0.
  - `tests/test_ctxwarn.py::test_above_threshold_prints_warning` — over threshold → stdout contains "Context" and a k-token figure.
  - `tests/test_ctxwarn.py::test_threshold_from_token_budget_file` — a `.token-budget` with a `ctx_threshold` value lowers the trip point (reuse `find_budget_file`).
  - `tests/test_ctxwarn.py::test_debounce_suppresses_second_warning` — two calls in the same size band warn once; state recorded via `tdcache.py`.
  - `tests/test_ctxwarn.py::test_missing_transcript_exits_0_silently` — nonexistent transcript → exit 0, no output.
  - `tests/test_ctxwarn.py::test_malformed_jsonl_line_skipped` — a bad JSON line is skipped, estimate still returns.
- GREEN (minimal implementation):
  - `estimate_tokens(jsonl_path)->int`: stream lines, sum text fields; try `tiktoken.get_encoding("cl100k_base")`, except → `chars // 4`; skip unparseable lines.
  - `should_warn(estimate, threshold, state_path)->bool`: true when `estimate >= threshold` and last-warned band differs; write band to `state_path` (reuse `tdcache.py`'s cache-dir helper — verify its signature first, Iteration 1's REFACTOR may have moved it).
  - `main(argv)`: read `--transcript`; missing→exit 0 silent; read threshold from `.token-budget` (`ctx_threshold`) via `find_budget_file`, default 100000; if `should_warn`, print `⚠️ Context ~{k}k tokens. Consider /compact or a fresh session.`; **always exit 0**.
  - bash: inside `cmd_budget`, add `--check)` branch → `python3 "$SCRIPT_DIR/lib/ctxwarn.py" "$@"`.
- REFACTOR (cleanup after GREEN):
  - Extract the JSONL text-field walk into a `_iter_text(jsonl_path)` generator in `ctxwarn.py`.

**Test pyramid for this iteration:**
- Smoke: `token-diet budget --check --help` exits 0 (bats).
- Unit: 6 — estimation (2), threshold-below/above (2), env/budget-file threshold (1), debounce (1); file `tests/test_ctxwarn.py`.
- Integration: 1 — `ctxwarn` reads a real multi-line JSONL fixture end-to-end and warns; plus threshold sourced from a real `.token-budget` fixture.
- State machine: N/A — debounce is a two-state latch, covered by the debounce unit test.
- Contract: 1 — **always exits 0** (a warn arm must never fail a turn) asserted for below/above/missing/malformed.
- Regression: N/A — new core.
- Chaos: 1 — malformed JSONL line is non-fatal (covered by `test_malformed_jsonl_line_skipped`).
- E2E: N/A — until hooked (Iteration 3).
- Performance: N/A.
- TDD Parity: 100% — `estimate_tokens`, `should_warn`, `main` each directly tested.
- Coverage: ctxwarn.py fully covered by test_ctxwarn.py; no repo-wide gate change.

**Acceptance criteria (binary):**
- [ ] `token-diet budget --check --transcript <big.jsonl>` prints a warning with a k-token figure.
- [ ] `token-diet budget --check --transcript <small.jsonl>` prints nothing, exits 0.
- [ ] A missing transcript exits 0 silently.
- [ ] A `.token-budget` `ctx_threshold` overrides the default.
- [ ] A second call in the same band prints nothing (debounce).
- [ ] `pytest tests/test_ctxwarn.py` green.

**Estimated effort:** M

**Blocked by:** Iteration 1 (reuses `scripts/lib/tdcache.py`)

**Side-effect fence:** Repo tree + `~/.cache/token-diet/` only. `.token-budget` is read, never written, by ctxwarn. No global home or service touched.

---

#### Iteration 3 (REVISED 2026-07-19) — cross-harness hook registration via install.sh

**Why revised:** The original Iteration 3 assumed `install.sh` already contains reusable "merge one hook entry into a settings.json preserving existing hooks" machinery, citing lines ~479/485/544/1436 as the template. Verified false before writing any code (plan-implement Step 2a): none of those four blocks write `PreToolUse`/`PostToolUse` JSON — they are an RTK CLI invocation, a Cowork awareness-doc writer, a `rtk init --gemini` call, and MCP-server JSON registration, respectively. The real hook-merge logic ("Creates hooks.PreToolUse structure if missing, preserves existing hooks") lives entirely inside the pinned Rust submodule `forks/rtk/src/hooks/init.rs` (~1000+ lines) — off-limits per this project's "submodules are pinned, never updated automatically" rule, and not callable from bash as a library. `~/.claude/settings.json`'s live hooks block was inspected directly and contains zero RTK entries, confirming RTK's registration is a separate, unexported code path. This iteration is rewritten to design that machinery for real instead of citing machinery that doesn't exist.

**Goal:** Register `docextract` as a document-read intercept and `ctxwarn` as a post-turn context check for the one harness whose hook JSON schema is empirically verified (Claude Code), behind an explicit opt-in flag, with an awareness-doc fallback everywhere else — and symmetric removal in `uninstall.sh`.

**Design decisions (locked, not open questions):**
1. **Opt-in, not automatic.** New `install.sh --with-context-hooks` flag. Without it, install behaves exactly as before (no hook writes). Rationale: this is the first token-diet feature that intercepts a live tool call (`Read`) and rewrites Claude's behavior on every future session — a materially higher blast radius than a passive CLI subcommand. Defaulting it on was never actually decided by the original plan; it just fell out of "reuse existing machinery" framing. Making it opt-in is the corrected default; flip to auto-on later as a one-line change if the operator wants that.
2. **Claude Code only for real hook wiring this iteration.** Schema verified against a live `~/.claude/settings.json`: `hooks.<Event>` is an array of `{"matcher": <string>, "hooks": [{"type": "command", "command": <string>, "timeout": <int>}]}`. `PreToolUse` exit code 2 blocks the tool call and feeds stderr back to Claude as the reason; exit 0 lets the tool call proceed. This is the same contract `docs/GUIDE-context-warning-and-pdf-intercept-hooks.md` describes and is stable, documented Claude Code behavior.
3. **Copilot CLI excluded, not assumed-covered.** The existing RTK comment ("Copilot CLI uses the same hooks as Claude Code", `install.sh:481`) is about RTK's own binary-managed hook, not about `~/.claude/settings.json` specifically — `forks/rtk/src/hooks/init.rs:3872` notes Copilot may use a *different* key casing (`preToolUse` vs `PreToolUse`) in what its comment calls "the same file, both hosts" (VS Code + Copilot CLI, not Claude Code). Unverified for this project's purposes → left out of scope this iteration (OQ-3, below), same conservative treatment as Gemini.
4. **Everyone else gets the awareness-doc fallback.** Codex CLI, Gemini CLI, OpenCode, Cowork, and Copilot (until OQ-3 resolves) all receive `awareness-docextract.md`, extending the existing Cowork-awareness-doc pattern (`install.sh:488-542`) to a shared doc referenced from each host's instruction file the same way `token-diet.md` already is. Gemini's original OQ-2 ("does Gemini accept a non-RTK hook?") is *not* resolved empirically in this rewrite — guessing wrong on a live hook write is exactly the failure mode this rewrite exists to avoid. Gemini stays on the awareness-doc path until someone verifies its hook schema out-of-band and that becomes its own follow-up.
5. **Installed-path decoupling (this project's own hard rule, missed by the original plan).** CLAUDE.md: "installed binaries must NEVER depend on the local repository path." The original Iteration 3 wrote hook `command` fields without specifying whether they'd point at `$SCRIPT_DIR/lib/hooks/...` (the dev checkout) or an installed copy — a real gap. Fixed here: `install.sh` copies both shims to `~/.local/bin/token-diet-hooks/*.sh` (mirroring how `token-diet`/`token-diet-mcp` are already installed to `~/.local/bin`), and the hook `command` field points at the installed copy. The shims themselves call the installed `token-diet` CLI (already on PATH post-install), never a repo-relative path.
6. **Idempotency key = exact command string.** `merge_hook_entry()` (new bash helper) skips adding an entry if a hook with that literal `command` already exists anywhere under that event — simple, matches how the rest of `install.sh` does idempotency (e.g. the MCP-registration loop's `if '[mcp_servers.token-diet]' not in text` check), and gives `uninstall.sh` the same string to match on for removal.
7. **Never partial-write.** If `~/.claude/settings.json` fails to parse as JSON, abort that host's hook registration with a warning and leave the file untouched — do not attempt a merge into a config we can't safely round-trip. Back up the file once per install run before the first write (`settings.json.bak-token-diet-hooks-<timestamp>`), not once per hook (two hooks would double-backup the already-modified file otherwise).
8. **docextract hook only intercepts what it can actually extract.** `docextract-pre-read.sh` only calls `token-diet extract` for suffixes in `EXTRACT` (`.pdf .csv .html .htm .txt .md`); everything else (images, `NEEDS_MARKITDOWN`, unknown binaries) passes through untouched — never block a `Read` without a usable replacement already in hand. On `token-diet extract` exit 0, block with exit 2 and a stderr message pointing at the cache path. On any other outcome (extract exited 2/3/4, or `token-diet`/`python3` missing), exit 0 passthrough.
9. **ctxwarn hook always passes through cleanly.** `ctxwarn-post.sh` reads `.transcript_path` from the `PostToolUse` stdin JSON, calls `token-diet budget --check --transcript <path>` (which already always exits 0 and already debounces — no new logic needed in the shim), forwards its stdout verbatim, and itself always exits 0 even if `token-diet` is missing or errors (guard with `|| true`).

**Source references:**
- `~/.claude/settings.json` (live file, read directly, not committed) — the actual hooks JSON schema this iteration targets. Re-verify its shape before writing the Python merge code; schemas can drift between Claude Code versions.
- `scripts/install.sh` lines ~1389 (`bin_dir="$HOME/.local/bin"`, existing binary-install pattern) and ~1436 (MCP JSON-merge loop) — not hook machinery, but the closest existing precedent for "install a file to `~/.local/bin`" and "python3-heredoc JSON merge, preserve existing keys" respectively. Follow their style, not their content.
- `scripts/install.sh` lines ~1674-1692 (top-level flag-parsing `case` block in `main()`) — where `--with-context-hooks` is added, following the existing modifier-flag style (`--verbose`, `--dry-run`).
- `scripts/uninstall.sh` — read fully before adding removal logic; mirror whatever idempotency/lookup style it already uses for RTK/tilth/Serena/ICM entries.
- `scripts/token-diet` lines 611 and 666 (the two `cmd_hook()` definitions) — **OQ-1, unchanged from the original plan**: confirm bash resolves to the second (line 666) definition before this iteration touches any hook-related state, and leave a one-line note if so (do not fix the duplicate itself — still out of scope, see Section 6).
- `docs/GUIDE-context-warning-and-pdf-intercept-hooks.md` — the exit-code contract (`exit 2` = block + stderr reason) this design implements.

**Files touched:**
- `scripts/install.sh` (modified — add `--with-context-hooks` flag; add `install_context_hooks()`: copies both shims to `~/.local/bin/token-diet-hooks/`, backs up and merges hook entries into `$HOME/.claude/settings.json` via `merge_hook_entry()` when `$HAS_CLAUDE`, writes `awareness-docextract.md` for every other detected harness)
- `scripts/uninstall.sh` (modified — remove both hook entries from `settings.json` by command-string match when present, delete `~/.local/bin/token-diet-hooks/`, delete `awareness-docextract.md` from each host config dir)
- `scripts/lib/hooks/docextract-pre-read.sh` (new — dev-repo copy; installed to `~/.local/bin/token-diet-hooks/docextract-pre-read.sh`)
- `scripts/lib/hooks/ctxwarn-post.sh` (new — dev-repo copy; installed to `~/.local/bin/token-diet-hooks/ctxwarn-post.sh`)
- `scripts/lib/awareness-docextract.md` (new — soft-rule instruction text for no-hook harnesses, same voice as the existing RTK awareness doc)
- `tests/install.bats` (modified — new cases below)
- `README.md` (modified — document `--with-context-hooks` as opt-in; do not imply it's default behavior)
- `CHANGELOG.md` (modified — append entry)

**Commit message:**
`feat(install): add opt-in docextract/ctxwarn hook registration for Claude Code, awareness-doc fallback elsewhere`

**TDD cycle:**
- RED (failing tests to write first):
  - `tests/install.bats::"context hooks: not installed without --with-context-hooks"` — a plain `install.sh` run against `HOME=<tmp>` leaves `<tmp>/.claude/settings.json` (if present) with no `token-diet-hooks` entries and does not create `~/.local/bin/token-diet-hooks/`.
  - `tests/install.bats::"context hooks: --with-context-hooks registers both hooks into claude settings"` — with the flag, `<tmp>/.claude/settings.json` gains a `PreToolUse` entry (matcher `Read`) and a `PostToolUse` entry (matcher `*`), both pointing at `<tmp>/.local/bin/token-diet-hooks/*.sh`, and every pre-existing hook entry in a seeded `settings.json` survives byte-for-byte apart from the addition.
  - `tests/install.bats::"context hooks: shims are copied to ~/.local/bin/token-diet-hooks"` — both `.sh` files exist there, executable, and neither contains the dev checkout's absolute path.
  - `tests/install.bats::"context hooks: idempotent — running install twice does not duplicate entries"` — two consecutive `--with-context-hooks` runs leave exactly one `PreToolUse` and one `PostToolUse` entry for token-diet.
  - `tests/install.bats::"context hooks: malformed settings.json aborts that host's registration without writing"` — a seeded unparseable `settings.json` is byte-for-byte unchanged after install, and install still exits 0 (a broken settings.json must not fail the whole install).
  - `tests/install.bats::"context hooks: non-claude harness gets awareness-docextract.md"` — with only `$HAS_CODEX` true (no `$HAS_CLAUDE`), `awareness-docextract.md` is written under the Codex config dir and no `settings.json` is touched.
  - `tests/install.bats::"context hooks: uninstall removes both hook entries and leaves unrelated hooks intact"` — seed a `settings.json` with one unrelated `PreToolUse` entry plus the two token-diet entries; after `uninstall.sh`, only the unrelated entry remains.
- GREEN (minimal implementation):
  - `merge_hook_entry()` bash helper (python3-heredoc, matches the existing MCP-merge style): loads JSON, `hooks.setdefault(event, [])`, skips append if the exact `command` string is already present anywhere under that event, else appends `{"matcher": ..., "hooks": [{"type": "command", "command": ..., "timeout": ...}]}`, writes back with `indent=2`. Exits 1 (not silent) on unparseable JSON, letting the caller decide to warn-and-skip rather than crash the whole install.
  - `install_context_hooks()`: guarded by `$WITH_CONTEXT_HOOKS`. Installs both shims to `~/.local/bin/token-diet-hooks/` (mkdir -p, `install -m755`). If `$HAS_CLAUDE`: back up `~/.claude/settings.json` once, call `merge_hook_entry` twice (PreToolUse/Read → docextract shim, PostToolUse/* → ctxwarn shim). For every other detected harness (`$HAS_CODEX`, `$HAS_GEMINI`, `$HAS_OPENCODE`, `$HAS_COWORK`, `$HAS_COPILOT`): write `awareness-docextract.md` into that harness's config dir (same directory-resolution helpers `install.sh` already uses for `token-diet.md`).
  - `docextract-pre-read.sh`: `python3 -c` parses stdin JSON for `.tool_input.file_path`; bail (exit 0) if suffix not in the extractable set; run `token-diet extract "$file_path"`; on exit 0 print `Extracted to <path> — read that file instead of the original.` to stderr and exit 2; on any other exit, exit 0.
  - `ctxwarn-post.sh`: `python3 -c` parses stdin JSON for `.transcript_path`; `token-diet budget --check --transcript "$path" 2>/dev/null || true`; always exit 0.
  - `uninstall.sh`: a matching `remove_hook_entry()` (same command-string match) removes both entries from `~/.claude/settings.json` if present; `rm -rf ~/.local/bin/token-diet-hooks`; delete `awareness-docextract.md` from each host config dir it could have been written to.
- REFACTOR (cleanup after GREEN):
  - Nothing to extract — `merge_hook_entry()`/`remove_hook_entry()` are written as reusable helpers from the start in this revision (GREEN already targets the corrected design; no extra pass needed since Iteration 1/2's "write inline first" approach isn't applicable when there's no prior inline version to extract from).

**Test pyramid for this iteration:**
- Smoke: `install.sh --with-context-hooks --dry-run` against a tmp HOME exits 0, no writes (bats).
- Unit: 2 — `merge_hook_entry()` sourced and tested in isolation: `"merge helper preserves an unrelated existing hook"`, `"merge helper is idempotent on repeat calls with the same command"`. File: `tests/install.bats`.
- Integration: 6 — the RED bats cases above.
- State machine: N/A.
- Contract: 2 — the emitted `PreToolUse`/`PostToolUse` JSON shape matches Claude Code's schema (`matcher`/`hooks[].type`/`command`/`timeout` keys present, correct types); `docextract-pre-read.sh` exits 2 only on successful extraction, 0 otherwise (table test over supported/unsupported/missing-file cases).
- Regression: 1 — "preserve pre-existing hook block" (unrelated hooks byte-for-byte unchanged apart from the addition).
- Chaos: 1 — malformed `settings.json` aborts that host's registration without a partial write, install still exits 0 overall.
- E2E: 1 — manual, env-gated, run by the operator only (never CI): `install.sh --with-context-hooks` against the real `HOME`, then in a live Claude Code session `Read` a real PDF and confirm the cache path is what gets read; grow a session past `ctx_threshold` and confirm the warning line appears once. Record the outcome in the CHANGELOG entry, same as Iteration 1's cache-hit check was manually spot-verified.
- Performance: N/A.
- TDD Parity: 85% — `merge_hook_entry()`/`remove_hook_entry()` are directly unit-tested; the two `.sh` shims remain thin and integration/contract-covered rather than unit-tested (parsing stdin JSON and shelling out is exactly what the integration bats cases already exercise end-to-end).
- Coverage: +0% Python (shell wiring, not counted by Python coverage); no repo-wide gate change.

**Acceptance criteria (binary):**
- [ ] Plain `install.sh` (no flag) never touches `settings.json` or writes `token-diet-hooks/`.
- [ ] `install.sh --with-context-hooks` against a tmp HOME with `$HAS_CLAUDE` registers both hooks, preserving every pre-existing hook entry.
- [ ] Both shims are installed to `~/.local/bin/token-diet-hooks/`, executable, containing no dev-checkout path.
- [ ] Running `install.sh --with-context-hooks` twice produces no duplicate entries.
- [ ] A malformed `settings.json` is left byte-for-byte unchanged; install still exits 0.
- [ ] A harness without `$HAS_CLAUDE` gets `awareness-docextract.md`; its config file (if any) is untouched.
- [ ] `uninstall.sh` removes both hook entries and the installed shim directory, leaving unrelated hooks intact.
- [ ] OQ-1 confirmed (which `cmd_hook()` definition is live) before this iteration edits any hook-adjacent state.
- [ ] `bats tests/install.bats` green.

**Estimated effort:** L

**Blocked by:** Iteration 2

**Side-effect fence:** Tests run install/uninstall only against `HOME=<tmp_path>` — never the real `~/.claude`, `~/.gemini`, or `~/.config/opencode`. The only live-system touch is the operator running `token-diet` install by hand with `--with-context-hooks` explicitly passed, which backs up `settings.json` first and is opt-in specifically so it can never happen as a side effect of an unrelated `install.sh` run.

## 4. Test inventory summary

| Iter | Smoke | Unit | Integration | State machine | Contract | Regression | Chaos | E2E | Performance | TDD Parity | Coverage Δ |
|------|-------|------|-------------|---------------|----------|------------|-------|-----|-------------|------------|------------|
| 1    | 1     | 8    | 0           | 0             | 1        | 0          | 1     | 0   | 0           | 100%       | new cores fully covered |
| 2    | 1     | 6    | 1           | 0             | 1        | 0          | 1     | 0   | 0           | 100%       | new core fully covered |
| 3    | 1     | 2    | 6           | 0             | 2        | 1          | 1     | 1   | 0           | 85%        | +0% Python (shell) |

## 5. End-to-end definition of done

**Deduplicated acceptance criteria:**
- `docextract` extracts PDF/csv/html/txt to a hash-cached text file; exits 2 on binaries, 3 on markitdown-needing docs, 4 on missing, 0 on success; commits no binary fixture.
- `ctxwarn` warns above a `.token-budget`-configurable threshold, is silent below/missing/malformed, always exits 0, debounces repeats.
- `install.sh --with-context-hooks` registers both hooks for Claude Code without clobbering existing hooks, is idempotent, writes an awareness doc for every other harness, and `uninstall.sh` removes the hooks symmetrically; plain `install.sh` (no flag) never touches hook state at all.
- The live `cmd_hook` duplicate is identified (OQ-1). Gemini's hook path (OQ-2) and Copilot's hook schema (OQ-3) are deliberately deferred, not guessed at — both stay on the awareness-doc fallback this iteration.

**Single end-to-end manual test (demo script):**
1. `bash scripts/install.sh --with-context-hooks` (real HOME, operator-run only).
2. Fresh Claude Code session: `Read` a sample PDF → confirm the session reads a `~/.cache/token-diet/extract/*.md` path, not raw bytes.
3. Grow the session past the threshold → confirm the warning line appears once.
4. Codex CLI (no hook): confirm its instruction file / awareness doc tells it to run `token-diet extract` first.
5. `token-diet gain` → confirm the extract/ctxwarn activity is visible in savings accounting.
6. Plain `bash scripts/install.sh` (no flag), fresh tmp HOME: confirm `settings.json` and `token-diet-hooks/` are untouched — the opt-in gate actually gates.

**Exact command that must return green at the end:**
```
pytest tests/test_docextract.py tests/test_ctxwarn.py && bats tests/token-diet.bats tests/install.bats
```

## 6. Out of scope

- **docx/pptx/xlsx/epub/odt/rtf extraction** — requires `markitdown` (absent); v2 adds it behind the exit-3 hint already emitted. Reason: extra dependency; PDF covers the dominant case.
- **OCR / scanned-PDF image text** — heavy dependency (tesseract). Reason: uncertain demand.
- **Auto-`/compact` on threshold** — ctxwarn only warns. Reason: acting on context automatically is risky and harness-specific.
- **Fixing the duplicate `cmd_hook`** — identified here (OQ-1) but fixed separately to keep this scope tight. Reason: pre-existing bug, orthogonal to the feature.
- **`token-diet gain` accounting schema changes** — v1 surfaces activity through the existing accounting; a dedicated savings metric for extract/ctxwarn is deferred. Reason: needs a measurement design of its own.
- **Gemini and Copilot hook wiring** — both stay on the awareness-doc fallback this iteration (see OQ-2, OQ-3). Reason: their hook JSON schemas are unverified against a live config, and this iteration's whole rewrite exists to stop wiring live hooks on unverified assumptions.
- **Defaulting `--with-context-hooks` on** — ships opt-in only. Reason: first token-diet feature that rewrites live tool-call behavior; earning default-on status is a separate, later decision once the opt-in path has real usage.

## 7. Open questions

- **OQ-1:** `scripts/token-diet` defines `cmd_hook()` twice (lines 611, 666). Which does the dispatch at ~line 2516 actually reach? Iteration 3 must confirm before editing hook state; the duplicate itself is fixed separately (out of scope). (Unresolved as of the 2026-07-19 revision — both definitions are functionally identical, so it doesn't block Iteration 3, but still needs a one-line confirmation in the implementation.)
- **OQ-2:** Does Gemini CLI accept a non-RTK `PreToolUse`/`PostToolUse` hook, or only the `rtk init --gemini` shell hook? **Deferred, not resolved this iteration** (2026-07-19 revision) — Gemini gets the awareness-doc fallback unconditionally. Resolving this is a follow-up once someone can verify Gemini's hook schema against a live config, the same way Claude Code's was verified here.
- **OQ-3 (new, 2026-07-19):** Does Copilot CLI read hooks from `~/.claude/settings.json`, a separate file, or a different key casing (`preToolUse` per `forks/rtk/src/hooks/init.rs:3872`)? Unverified — Copilot gets the awareness-doc fallback unconditionally this iteration, same treatment as Gemini.

## Revision log

- **2026-07-19:** Iteration 3 rewritten. `/plan-implement` hard-stopped mid-execution (Iterations 1-2 already shipped, commits `70cc457`/`eb6ea74`) after verifying the original Iteration 3's core premise — that `install.sh` already has reusable settings.json hook-merge machinery to extend — was false. That machinery exists only inside the pinned Rust submodule `forks/rtk/src/hooks/init.rs`, which this project cannot modify or call as a library. Rewrote Iteration 3 from scratch: real JSON schema (verified against a live `~/.claude/settings.json`), an explicit `--with-context-hooks` opt-in gate (the original plan implied default-on, never actually decided), installed-path decoupling for the two hook shims (a gap the original plan missed entirely), and scoped the actual hook wiring to Claude Code only — Gemini (OQ-2) and Copilot (new OQ-3) stay on the awareness-doc fallback rather than guessing at unverified hook schemas.

## Build outcome — 2026-07-19

- **Shipped:** All 3 iterations, branch `feat/docextract-ctxwarn`.
  - `70cc457` — Iteration 1: `docextract` core + `tdcache` + `token-diet extract` subcommand
  - `eb6ea74` — Iteration 2: `ctxwarn` core + `token-diet budget --check` arm
  - `9608379` — Iteration 3 (revised): opt-in `install.sh --with-context-hooks`, `merge_hook_entry`/`remove_hook_entry` helpers, two hook shims, `awareness-docextract.md` fallback
- **Deviations from plan:** Iteration 3 was fully rewritten mid-execution — see the Revision log above for why and what changed. Iterations 1-2 shipped materially as specified; two build-time-only fixes: the PDF test fixture used a hand-rolled minimal-PDF byte generator (`tests/conftest.py::make_minimal_pdf`) instead of a PDF-writing library, since none (`reportlab`/`fpdf`/`pypdf`) is installed in this repo's Python env; the `budget --check` bats fixture had to use ~12000x a real sentence rather than a repeated single character, because real `tiktoken` (unmocked in a bats subprocess) collapses repeated-character runs far below chars/4, undershooting the 100000-token default threshold.
  Iteration 3's `install_context_hooks()` also creates `~/.claude/settings.json` with `{}` if it doesn't exist yet, rather than skipping registration — a refinement over the plan's original "skip if missing" wording, needed because the file only comes into existence after Claude Code's own first run.
- **Learned:** Before citing existing code as "reusable machinery" in a plan, read it — a plan can pass its own internal consistency checker (structural pass) while still being unimplementable because the referenced code doesn't do what the plan claims. This project's actual `PreToolUse`/`PostToolUse` hook-merge logic lives entirely inside the pinned Rust submodule `forks/rtk/src/hooks/init.rs`, invisible to a bash-only read of `install.sh`. Real-machine host detection (`command -v claude`, `codex`, `opencode`, `gemini`, `code`) finds genuinely-installed binaries even inside bats' sandboxed `PATH`, because the test harness only *prepends* `$TMP_BIN` rather than isolating `PATH` — any test asserting on a single harness must pass `--hosts <name>` explicitly (the pattern the rest of this test suite already uses) or it will silently pick up every real CLI on the developer's machine.
- **Verified:** `pytest tests/test_docextract.py tests/test_ctxwarn.py` (20 passed) and `bats tests/token-diet.bats tests/install.bats` (169 passed, 0 failed) green at each commit; full pre-commit hook (SAST, doc-sync, path-leak, CHANGELOG-append) passed on all three.
