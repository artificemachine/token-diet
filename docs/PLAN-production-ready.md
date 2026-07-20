# PLAN — token-diet to production-ready / job-ready

**Source:** `docs/audits/2026-07-20-job-ready.md` (verdict: NOT READY, 8 stages, 32 findings)
**Created:** 2026-07-20
**Status:** not started

Every phase is independently shippable, has its own tests, and ends green.
Designed to be resumable across sessions and executable with `/plan-implement`.

Phases 1 to 4 get to **job-ready**. Phase 5 is what makes it genuinely
**production-ready** and is the strongest senior signal. Phase 6 is cosmetic.

Do not reorder 1 and 2. Phase 1 closes a public-data gate; phase 2 fixes a
data-loss bug. Everything after is improvement, not remediation.

---

## Phase 1 — Close the gate, fix the 90-second read
**Goal:** NOT READY becomes NEEDS POLISH. Highest leverage per hour in the plan.

### 1.1 Remove personal data from public HEAD (hard gate)
- `HANDOFF.md` at HEAD carries 6 occurrences of local username + home paths (lines 91, 103, 118, 134, 161, 306).
- Decision to make: delete `HANDOFF.md` from the repo entirely, or move to `docs/handoffs/` with paths scrubbed. Recommend **delete from repo, keep locally untracked** — it is an agent working file, not a project artifact.
- Do **not** rewrite git history. That call was already made and is correct (`HANDOFF.md:306`).
- Add `HANDOFF.md` to `.gitignore` so it cannot regress.
- **Test:** `git grep -c airm2max HEAD` returns 0. Add to `.github/workflows/path-leak.yml` a full-tree scan (not just PR diff) so this cannot come back.

### 1.2 Root directory triage
- Keep `CLAUDE.md` and `AGENTS.md` (both are recognized conventions now, not smells).
- Move `GEMINI.md` into `.github/` or merge into `AGENTS.md`.
- Result: root shows README, LICENSE, CHANGELOG, CONTRIBUTING, SECURITY, plus two recognized agent configs.

### 1.3 README rewrite (above the fold)
- Line 1-15 must answer: what it does, proof it works, how to install.
- Add demo: asciinema cast or GIF of `token-diet gain`. Repo currently has **zero** images.
- Add badges: CI status, license, version, platform.
- Move the Global-vs-Per-Project table (`README.md:20-30`) below Quickstart.
- Add a Prerequisites section: `jq`, `bc`, `poppler-utils`, `tiktoken`, `pdfplumber`.
- Document `git clone --recursive` / `git submodule update --init` (currently absent; `--local` install fails without it).

### 1.4 Fix claims (do this or drop the numbers)
- Replace unsourced "40-90%" / "60-90%" with the measured tilth figure and link `forks/tilth/benchmark/README.md`.
- Reconcile README, `CLAUDE.md:7`, and the GitHub description to one number.
- Remove or substantiate "Fit 5x more information" (`README.md:22`).
- **Test:** a `docs/benchmarks.md` exists and every quantitative claim in README links to it.

### 1.5 README/CLI drift
- Document the 6 missing commands: `strip`, `serena-gc`, `service`, `update`, `upstream`, `version`.
- Fix `budget` documented three ways (README vs `--help` vs usage string at `:1148`).
- Fix `scripts/token-diet:2469`: literal `\n` mangles `--help` output.
- **Test:** extend the existing project pre-commit doc-sync check into a bats test asserting every dispatch case appears in README.

### 1.6 Community files
- Add `SECURITY.md`, `CODE_OF_CONDUCT.md`, `.github/ISSUE_TEMPLATE/`, PR template.
- Soften `CONTRIBUTING.md:9` ("PRs without an issue will not be reviewed").

### 1.7 docs/ reorganization
- 19 files, 6 dated session handoffs, stale `PLAN-*` and bug reports, no index.
- Archive session-era docs to `docs/archive/`, add `docs/README.md` index.
- Write `docs/engineering-notes.md`: the CI-caught-real-bugs story, the clean-container reproduction method, the tilth dead-code root-cause chase. **This is the most persuasive artifact available and currently does not exist.**

**Phase 1 exit:** 186 bats + 46 pytest green, `git grep airm2max HEAD` = 0, README renders with demo + badges.

---

## Phase 2 — Correctness and safety (the "production" in production-ready)
**Goal:** the installer cannot silently destroy user config.

### 2.1 H1 — silent truncation (data loss, verified)
`scripts/install.sh:1456-1467`: `open(cfg,"w")` truncates before dump, wrapped in `except Exception: pass`. A mid-write failure empties the user's `~/.claude/settings.json` with no message and no backup. Also silently no-ops on malformed JSON, contradicting 7 sibling blocks that abort loudly.
- **RED:** test that a write failure mid-dump leaves the original file intact.
- **GREEN:** write to temp + `os.replace`; on exception, restore and report.
- **REFACTOR:** collapse the 7 copy-pasted malformed-JSON-abort blocks into one helper.

### 2.2 H2 — non-atomic writes, systemic
Exactly 1 of ~15 mutation sites uses `os.replace` (`token-diet:1900`). Everything else is `open(w)` or `write_text()`, including `merge_hook_entry` (`install.sh:1168`) and all MCP registration.
- Single `atomic_write_json()` helper, used everywhere.
- Pre-mutation backup on the success path, not only when input is already corrupt.
- **Test:** parametrized test asserting every config-mutation entry point is atomic and pre-backs-up.

### 2.3 Codex TOML blind append
`install.sh:751,759,1134` mutate `config.toml` via `cat >>`, never parsed or validated, grep-guarded, no backup. Parse, validate, write atomically.

### 2.4 SC2259 — likely live bug
`scripts/token-diet:226`: `read <<<` plus heredoc on the same command; the redirect overrides piped input. Probably a real parsing bug in `gain`. Reproduce, fix, regression-test.

### 2.5 H3 — `curl | sh` on the default path
`install.sh:222,238` pipe rustup and uv installers unpinned, no checksum, on the default path, in a project that ships an SBOM and an air-gap mode. Pin + verify checksum, or require explicit opt-in.

### 2.6 Partial-failure recovery
`set -euo pipefail` with no `ERR`/`EXIT` trap. Failure at host 5 of 7 leaves 5 hosts mutated, no rollback, no resume. Add a trap that reports exactly what was mutated and how to revert.

**Phase 2 exit:** interrupted-write and partial-install tests exist and pass. This is the phase that earns the word "production."

---

## Phase 3 — Supply chain and CI governance
**Goal:** close the 7-of-9 gate gap. Anything enforced only locally is unenforced for fork PRs and any `--no-verify`.

- 3.1 `.github/dependabot.yml` (github-actions + pip).
- 3.2 `security.yml`: ShipGuard + gitleaks on PR, hard-fail.
- 3.3 Pin Python deps. `tiktoken`/`pdfplumber` currently declared only inside `test.yml:32`, unpinned, installed at CI runtime. Add `requirements-dev.txt`.
- 3.4 Port CHANGELOG append-only and README doc-sync checks into CI.
- 3.5 `release.yml` wrapping `scripts/release.sh` (currently referenced by no workflow; 5 releases shipped by hand today).
- 3.6 Mark `test.yml` and `path-leak.yml` as required status checks on `main`.
- 3.7 Refresh `compliance/security-audit.md` (dated 2026-04-01, stale).

---

## Phase 4 — Resolve Windows
**Goal:** stop shipping 46 tests that execute nowhere.

Pick one and commit to it:
- **(a)** Add `windows-latest` CI job running Pester + ps1 smoke, then close the parity gap (`grep -c "ctxwarn\|docextract" scripts/token-diet.ps1` = 0; `serena-gc`, `docker-*`, `budget hubs` also missing).
- **(b)** Demote Windows to "experimental, untested in CI" in README, remove the Pester claim from `CLAUDE.md`'s "full suite".

**(b) is honest and takes an hour. (a) is the right answer if Windows users matter.** Do not leave it as-is; the current state is the only *false* claim the audit found.

---

## Phase 5 — Architecture (the senior-signal phase)
**Goal:** the codebase reads as designed, not accreted. Do this as one deliberate documented refactor, not a scramble.

### 5.1 The single highest-leverage change in the repo
Extract `lib/hosts.sh`: one host registry (slug, label, detect-fn, register-fn, check-fn), sourced by both entry points. This alone kills three findings:
- `scripts/lib/` is documented as "sourced by the CLI" and is **never sourced** (only `source` in 4,555 lines is `install.sh:224` for cargo env).
- `codex_mcp_command()` and `mcp_command_exists()` are byte-identical across `install.sh` and `token-diet`, including a duplicated embedded Python TOML parser.
- The 7-host list is declared **six times in one file** (`install.sh:276,289,298,304,318,332`) with parallel arrays that desync silently, plus 77 `HAS_*` refs.

**Test first:** add a bats test asserting the host list is defined exactly once. It fails today; that is the RED.

### 5.2 Config schema and migration
No state namespace, no versioning. `.token-budget` unversioned. `config/compat.json` has `"schema": 1` but omits ICM. There is no answer to "user upgrades v1.2 to v1.14, what happens to their config?" Add a schema version and a migration path.

### 5.3 Fork strategy honesty
`compat.json` says tilth tested `0.6.1`, pinned at `v0.9.0-85`; rtk tested `0.34.5`, pinned `v0.34.7-669`. All four forks are hundreds of commits past their last tag. Either refresh compat on every pin bump (CI check) or document the fork strategy as deliberate ownership.

### 5.4 Decompose god functions
`cmd_doctor()` 388 lines, `install_icm()` 226, `cmd_budget()` 170, `install_token_diet()` 169.

---

## Phase 6 — Housekeeping (cosmetic, do last or never)
- 6.1 Branch cleanup: 27 remote safe-deletes verified via `git cherry` (0 unique commits), 10 local merged, 3 needing per-branch review. Full commands in the audit's Cleanup Plan.
- 6.2 Reconcile 12 releases against the documented 10-tag threshold.
- 6.3 Leave the 59 release-less tags alone. Deleting tags someone may have pinned is user-hostile.
- 6.4 Enforce squash-merge as repo default.

---

## Sequencing note

Phase 1 is half a day and moves the verdict. Phase 2 is the one that makes the
project genuinely trustworthy and is worth doing even if job hunting stops.
Phase 5 is the most impressive to a senior reviewer but also the easiest to get
wrong under time pressure. Do not start phase 5 in a long session.

Suggested cadence: one phase per session, fresh context each time, green tests
at every phase boundary.
