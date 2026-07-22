# Bulletproof Report — token-diet claim falsification

**SCOPE:** token-diet @ `main` `373edc8` (HEAD after #69). Falsify every "done / RESOLVED / single source of truth / symmetric / atomic / all N converted / PUBLIC-READY" claim in CLAUDE.md, README.md, docs/audits/2026-07-21-portfolio-ready.md, config/hosts-mcp.json, CHANGELOG.md, and code comments. Shape: bash (install.sh 82.5K, uninstall.sh 27.3K, token-diet 94.6K, lib/hosts.sh, lib/tdconfig.py) + python cores + 4 pinned submodule forks. Method: deterministic grep/AST at reproducible file:line. Tests confirmed live this session: **bats ~241 / 0 fail (exit 0)**, **pytest 72 passed / 18 skipped / 0 fail**.

---

## CLAIMS AUDITED

| # | Claim | Source file:line | Verdict | Evidence (file:line) |
|---|-------|------------------|---------|----------------------|
| 1 | `config/hosts-mcp.json` is the **single source of truth** for where host config files live | `config/hosts-mcp.json:3`; `uninstall.sh:22` | **VIOLATED** | codex `config.toml` hardcoded 4× at `install.sh:161,856,1249,1604`; opencode.json hardcoded 14× in `install.sh`; claude-desktop paths hardcoded at `install.sh:333-334,1616`. Registry only feeds claude-desktop (install) + claude-desktop/codex (uninstall). |
| 2 | HIGH #1 config-path drift → **RESOLVED**; install/uninstall/dashboard/CLI all converged, drift-prone paths registry-driven | `docs/audits/2026-07-21-portfolio-ready.md:318-322`; `CHANGELOG.md:726` | **VIOLATED** | codex config path is registry-driven ONLY in uninstall (`uninstall.sh:73`); `install.sh` never sources it — 4 hardcoded copies. `install.sh` writes to claude/opencode/gemini/icm via hardcoded literals throughout. |
| 3 | uninstall removes **exactly** what install writes (symmetric) | `docs/audits/2026-07-21-portfolio-ready.md:326-327`; `uninstall.sh:484` | **VIOLATED** | install writes Serena launcher `~/.local/bin/serena` (`install.sh:763,782,809`); uninstall removes rtk/tilth/icm (`uninstall.sh:464-466`) but **never** `~/.local/bin/serena`. Gemini target mismatch — see #10. |
| 4 | All config writes go through `tdconfig` (atomic); **no raw truncating write remains** | `docs/audits/2026-07-21-portfolio-ready.md:150` | **VIOLATED** | non-atomic `Path.write_text()` config writes: `install.sh:1610` (codex `config.toml`), `install.sh:1784` (claude/gemini `settings.json` hooks), `install.sh:1221,1290` (icm), `token-diet:2500` (icm `config.toml`). |
| 5 | #47 "**all 11 remaining config-write sites converted** to tdconfig" | `CHANGELOG.md:704` | **VIOLATED** | Same sites as #4. The doc's own full-depth Stage 5 already calls #47 "inaccurate" (`...:260`) yet CHANGELOG:704 still states it unqualified. |
| 6 | HIGH #2 floating install → **RESOLVED. All tools pinned**; single `SERENA_SRC` var dedups ~8 Serena refs | `docs/audits/2026-07-21-portfolio-ready.md:302,323-324` | **VIOLATED** | Serena OpenCode reg (`install.sh:967`→`981`) and Cowork reg (`install.sh:1033`→`1044`) pass bare `SERENA_REPO` (no `@rev`) → unpinned floating HEAD even inside a checkout. VS Code template (`install.sh:901`) hardcodes unpinned `git+https://github.com/artificemachine/serena`, bypassing `SERENA_SRC`. |
| 7 | `compat.json` copied so the version gate works post-install | `install.sh:1579`; `token-diet:96` | **VERIFIED** | copied `install.sh:1579`, read by CLI `token-diet:96`, removed by uninstall `uninstall.sh:458`. |
| 8 | #69: uninstall config removers now write **atomically** | `CHANGELOG.md:728` | **VERIFIED** | all 7 removers use `tempfile.mkstemp` + `os.replace` (`uninstall.sh:137-147,189-199,234-244,276-286,316-326,386-396,580-590`). |
| 9 | All 8 portfolio stages PASS / **PUBLIC-READY**; "only open item is a pre-existing LOW nit: the config **removers** rewrite in place" | `docs/audits/2026-07-21-portfolio-ready.md:342-349` | **VIOLATED (overstated)** | Names the removers (fixed by #69) as the sole open item while the install-side non-atomic writes (#4) — which the same doc flagged at line 260 — go unmentioned; HIGH #1 (#2) and HIGH #2 (#6) not actually fully closed. |
| 10 | Gemini MCP registrations cleaned symmetrically | `uninstall.sh:634-642` | **VIOLATED** | install registers via `gemini mcp add` (CLI); `install.sh:1363` comment says it lands in `~/.gemini/config/mcp_config.json`, but uninstall hand-edits `~/.gemini/settings.json` (`uninstall.sh:640-642`) and calls no `gemini mcp remove`. Contradictory targets; no guaranteed removal. |
| 11 | Tests green | `README.md:173` | **VERIFIED (test run) / drifted (count)** | bats/pytest pass, but README says "226 bats / 69 pytest" vs live 72 pytest + ~241 bats. |

---

## HONESTY SCORE

**Verified: 3 / 10 completion-claims (30%).** (Claims 7, 8, 11-run verified; claims 1,2,3,4,5,6,9,10 violated.)

Blunt line: the tests are real and green, but the headline architecture claims — "single source of truth," "symmetric uninstall," "all config writes atomic," "all tools pinned," "PUBLIC-READY" — are marketing, not fact. The audit doc contradicts itself (line 150 vs 260) and its final PUBLIC-READY verdict launders four still-open defects into "one LOW nit."

---

## VIOLATED FINDINGS (every one, with file:line)

**V1 — "single source of truth for host config paths" is false.**
- `config/hosts-mcp.json:3` claims it. Reality — hardcoded host config paths outside the registry:
  - codex `~/.codex/config.toml`: `install.sh:161, 856, 1249, 1604` (4 copies; install never reads the registry for codex)
  - opencode.json: 14 hardcoded refs in `install.sh` (`204, 921-927, 1299-1305, 1643, 1879-1880`, …)
  - claude `~/.claude/settings.json`: `install.sh:1616, 1811`
  - claude-desktop mac/linux: `install.sh:333-334` (as a "fallback" pair) and again `install.sh:1616`
- Registry is consulted only at `install.sh:322-327` (claude-desktop detection), `install.sh:376-377,430-431` (slug/label reporting), `uninstall.sh:59,73` (claude-desktop + codex removal). Every actual write path is a literal.

**V2 — HIGH #1 "RESOLVED" overstated.** Same evidence as V1. The audit's residual carve-out ("cleanup logic stays explicit by design") does not cover config *paths*, which it explicitly claims are registry-driven — codex's install path is not.

**V3 — uninstall not symmetric: Serena launcher orphaned.** `install.sh:763` `serena_launcher="$HOME/.local/bin/serena"`, written at `:782` (docker) / `:809` (uvx). `grep 'bin/serena' uninstall.sh` → no removal. A `token-diet uninstall` leaves an executable `~/.local/bin/serena` behind.

**V4 — non-atomic config writes remain.** `Path.write_text()` truncates identically to `open(p,"w")`:
- `install.sh:1610` `cfg.write_text(text + '\n[mcp_servers.token-diet]...')` — codex `config.toml`, a real MCP host config
- `install.sh:1784` `p.write_text(json.dumps(...))` — `~/.claude/settings.json` / `~/.gemini/settings.json` hook registration
- `install.sh:1221` `p.write_text(text)` — icm `config.toml`; `install.sh:1290` — VS Code icm template
- `token-diet:2500` `p.write_text(text)` — icm `config.toml` (via `icm warmup`)

**V5 — #47 "all 11 sites converted" still unqualified-false** at `CHANGELOG.md:704`, contradicted by V4 and by the audit's own `docs/audits/2026-07-21-portfolio-ready.md:260`.

**V6 — Serena not fully pinned; SERENA_SRC does not dedup all refs.**
- `install.sh:83` defines pinned `SERENA_SRC="git+${SERENA_REPO}${SERENA_REV:+@${SERENA_REV}}"`, used at `:813,834,846,881,1089,1100`.
- But `install.sh:967` and `:1033` pass bare `${SERENA_REPO}` (no rev) → python at `:981,:1044` builds `"git+" + repo` = unpinned. OpenCode and Cowork Serena registrations float to HEAD **inside** a checkout, not just outside.
- `install.sh:901` hardcodes `git+https://github.com/artificemachine/serena` literally — unpinned and not sourced from `SERENA_SRC`.

**V7 — PUBLIC-READY verdict overstated** (`docs/audits/2026-07-21-portfolio-ready.md:342-349`): declares the removers the "only open item" (since fixed by #69), silently dropping V4's install-side writers that the same document had flagged at line 260, and treating V2/V6 as closed.

**V10 — Gemini removal targets the wrong file.** install: `gemini mcp add --scope user` (`install.sh:1093,1099`), documented to write `~/.gemini/config/mcp_config.json` (`install.sh:1363`). uninstall: hand-edits `~/.gemini/settings.json` (`uninstall.sh:640-642`), no `gemini mcp remove`. If the CLI writes where its own comment says, uninstall removes nothing.

---

## DRIFT-CLASS FINDINGS

- **(a) doc-drift — stale code comment in the SoT loader.** `scripts/lib/hosts.sh:30-31`: "only the slugs/labels site in install.sh reads this; five other enumerations are still hardcoded and must be converted." Contradicts the "HIGH #1 RESOLVED / converged" claim; `TD_HOSTS_LIB_VERSION` still `"2"`.
- **(b) cross-doc SoT inconsistency — two divergent host enumerations.** `hosts.sh:35-43` `TD_HOSTS` = 7 hosts (incl. `copilot`, `cowork`; **no** claude-desktop). `config/hosts-mcp.json:7` `all_hosts` = 6 hosts (incl. `claude-desktop`; **no** copilot/cowork). Both are described as authoritative for "which hosts token-diet detects."
- **(c) unenforced invariant / dead guard.** CHANGELOG:704/728 advertise a bats guard asserting "no raw `open(p,"w")` remains." The guard greps the literal `open(...,"w")` and does **not** match `Path.write_text()`, so all of V4 evades it. Invariant stated, not enforced.
- **(d) count drift.** `README.md:173` "226 bats / 69 pytest" vs live 72 pytest, ~241 bats.

## Config-read vs authoritative-read classification

- `token-diet:96` (compat.json), `token-diet:152` + `token-diet-dashboard:117-127` (hosts-mcp.json), `install.sh:322` (claude-desktop paths): **config-read** — reading a shipped, installed config artifact. NOT a violation.
- The violations above are not "read the export as truth" cases; they are **write-path drift** (the code writes to hardcoded literals the registry claims to own) and **guard/atomicity gaps**.

---

## REMEDIATION

**Manifest / registry:**
1. Route codex/opencode/claude/gemini config paths through `td_host_config_paths` in `install.sh` the way claude-desktop already is, or drop the "single source of truth" wording from `config/hosts-mcp.json:3`.
2. Reconcile `hosts.sh:TD_HOSTS` with `hosts-mcp.json:all_hosts` (one host set, or explicit "detection labels" vs "config registry" naming).

**Symmetry:**
3. Add `remove_file "$HOME/.local/bin/serena"` to `uninstall.sh`.
4. Uninstall Gemini via `gemini mcp remove` (mirror the add), or fix `install.sh:1363` / `uninstall.sh:640` to agree on the real file.

**Atomicity + guards:**
5. Convert `install.sh:1221,1290,1610,1784` and `token-diet:2500` to `tdconfig.atomic_write_*`.
6. Extend the no-raw-write bats guard to also fail on `.write_text(` in config-writing python heredocs (negative-test it).

**Pinning:**
7. Pass a pinned ref (`${SERENA_REPO}${SERENA_REV:+@${SERENA_REV}}`) at `install.sh:967,1033` and template `:901`, or gate them behind the documented no-checkout fallback with a warning.

**Docs:**
8. Correct `hosts.sh:30-31`, `README.md:173`, and append a correction entry retracting CHANGELOG:704's "all 11 converted" and the audit's PUBLIC-READY "only open item" line.

---

## PROGRESS

Baseline report (no prior `bulletproof-report-*.md` on disk). The two prior audits referenced by this repo — `docs/audits/2026-07-20-portfolio-ready.md` and `docs/audits/2026-07-21-portfolio-ready.md` — are the falsification targets here; the second's PUBLIC-READY verdict is contradicted by V1–V10. Note the prompt's expectation held: the "#47 all 11 sites converted" claim, previously found false, **is still false and still stated unqualified** at `CHANGELOG.md:704`.
