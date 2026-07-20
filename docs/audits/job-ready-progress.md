# /job-ready progress

Stage-by-stage verdict log. `/job-ready continue` resumes from the first stage
not marked complete. Append one block per stage; never rewrite prior entries.

---

## Run: 2026-07-20 — commit 2877862 (main)
Mode: default (audit-only). Full report: `docs/audits/2026-07-20-job-ready.md`

| # | Stage | Verdict | Blockers | Complete |
|---|-------|---------|----------|----------|
| 1 | Recruiter first impression | FAIL | 4 | yes |
| 2 | Git history & releases | FAIL | 3 | yes |
| 3 | README + docs | FAIL | 6 | yes |
| 4 | Fresh clone + deps | FAIL | 3 | yes |
| 5 | Gauntlet (security/quality) | PASS (3 HIGH) | 3 | yes* |
| 6 | Architecture | FAIL | 6 | yes* |
| 7 | CI governance | FAIL | 4 | yes* |
| 8 | Claims vs reality | FAIL | 3 | yes* |
| 9 | Final scorecard | done | — | yes |

**Overall verdict: NOT READY** — hard gate tripped by personal data (local
username + home paths, 6 occurrences) in `HANDOFF.md` at committed HEAD.
No secrets/keys/tokens found in tree or history; `/rotate-secret` not required.

### Method deviation (recorded so a later run can compare like-for-like)

`*` Stages 5, 6, 7, 8 and the docs half of stage 3 were executed as **parallel
general-purpose subagents**, not by invoking the named skills the spec calls for
(`/gauntlet`, `/arch-audit`, `/ci-gate`, `/bulletproof`, `/readme-audit`,
`/docs-organize`). Reason: the session was already ~160k tokens deep and those
six skills run sequentially would have exhausted the context before stage 9.

Coverage is substantively equivalent for stages 6, 7, 8 (single-pass audits
either way). **Stage 5 is thinner than a true `/gauntlet` run**, which would
itself have driven 7 loop sub-commands (`/loop-security`, `/loop-threat-model`,
`/loop-senior-reviewer`, `/loop-production-ready`, `/loop-user-reviewer`,
`/loop-simplify`, `/loop-docker-audit`). Treat stage 5's PASS as
"no blocking findings in a single hardening pass," not as a full gauntlet.

To close this properly, re-run stage 5 alone: `/gauntlet`.

### Evidence notes
- Fresh-clone test suite: **PASS** (`bats tests/*.bats` from a clean clone of
  the public remote, exit 0, 0 failures).
- ShipGuard: 0 findings / 93 files.
- Stage 5 finding H1 (silent `settings.json` truncation, `install.sh:1456-1467`)
  was independently verified in the main thread, not taken on the subagent's word.
- Stage 2 cleanup plan was produced but **nothing was executed** — all branch,
  tag, and release operations await per-operation approval.

### Next actions (none executed)
1. Close the NOT-READY gate: relocate `HANDOFF.md` + agent-instruction files out
   of repo root (also the highest first-impression win).
2. Add demo GIF + badges above the fold in README.
3. Replace the unsourced "40-90%" headline with the measured tilth benchmark.
4. Fix the H1/H2 non-atomic config-write paths.
5. Resolve Windows: CI it, or demote to experimental.

---

## Run: 2026-07-20 — `--fix` mode (working tree, uncommitted)

Fix pass against the findings from the audit run above. No re-audit: the repo
was unchanged at the time, so the existing findings were executed against
directly. Stage 2 executed nothing, per spec (`--fix` does not run branch, tag,
or release operations).

### Hard gates — all now passing

| Gate | Before | After |
|---|---|---|
| Personal data in tracked files | 6 occurrences in `HANDOFF.md` | **0** |
| Full-tree path-leak scan | did not exist | **passes**, and fails on planted input |
| LICENSE | present | present |
| Community files | 2 of 6 | **6 of 6** |
| Tests | 186 bats / 46 pytest | **199 bats / 61 pytest**, 0 failures |
| shellcheck errors | 1 (SC2259) | **0** |

**Verdict: NOT READY is lifted.** Remaining findings are NEEDS POLISH class.

### Phase 1 completed

- **P1.1** `HANDOFF.md` and `.vscode/mcp.json` untracked and gitignored. Path-leak
  guard gained full-tree mode, now runs on push and PR, with 11 regressions that
  assert it *fails* on planted leaks.
- **P1.2** `SECURITY.md`, `CODE_OF_CONDUCT.md`, issue templates, PR template added.
  `CONTRIBUTING.md` rewritten. `GEMINI.md` moved to `.github/`.
- **P1.3** README rewritten: badges, real sample output, prerequisites,
  `--recursive`, Windows demoted to experimental. Claims reconciled to
  `docs/benchmarks.md`.
- **P1.4** `--help` literal `\n` fixed; "all three tools" corrected to four;
  6 undocumented commands added to the reference.
- **P1.5** 13 stale documents archived, `docs/README.md` index added,
  `docs/engineering-notes.md` written.

### Phase 2 completed

- **P2.1** `scripts/lib/tdconfig.py` — atomic write, backup-on-success, loud
  failure. Replaces both `open(cfg,"w")` + `except Exception: pass` sites.
  15 pytest regressions.
- **P2.2** Remaining write sites reviewed: all abort loudly on malformed input
  already. See "carried forward" below.
- **P2.3** `ERR` trap reporting which files were mutated before a failure.
  SC2259 fixed (see below).

### Found during the fix pass, not in the original audit

1. **`gain` under-reported savings by ~95%.** Same stdin-collision class as
   SC2259: the heredoc supplied stdin to `python3 -`, so the piped rtk JSON was
   discarded, `json.load(sys.stdin)` parsed the Python source, hit a bare
   `except`, and zeroed live values. Displayed 153,114 commands / 4.8M saved;
   true figures were 200,194 / 92.5M (83.9%). Two regressions added.
2. **The first full-tree guard implementation could not fail.** `grep -qP` with
   `2>/dev/null`: BSD grep has no `-P`, so it silently matched nothing on macOS
   while working in CI. Caught only by testing the negative case. Rewritten in
   python3.
3. **`.vscode/mcp.json` had five prior symptom-fix commits.** Cause was
   `install.sh` calling `tilth install <host>`, whose installer writes its
   absolute binary path back into the invoking repo. Untracking is the first
   durable fix.

### Carried forward (not blockers)

- **Demo asset.** Still no GIF or asciinema cast; real `gain` output is embedded
  as a console block instead. Requires a human to record. Highest remaining
  first-impression item.
- **Atomic writes at the other 11 sites.** They abort loudly on malformed input,
  so no silent data loss remains, but they are still non-atomic. Convert to
  `tdconfig.atomic_write_json` incrementally.
- **Phase 3** (dependabot, SAST in CI, pinned Python deps, release automation),
  **Phase 4** (Windows: CI it or keep it demoted), **Phase 5** (the `lib/hosts.sh`
  registry refactor), **Phase 6** (branch/tag housekeeping) all untouched.
- Codex `config.toml` still mutated by blind `cat >>` without parsing.
- `curl | sh` for rustup and uv on the default path.

### State

Nothing committed or pushed. All changes are in the working tree, tests green,
ready for review as a PR.
