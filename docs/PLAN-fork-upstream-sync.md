# PLAN: Fork Full-Sync with Upstream (rtk, tilth, serena)

## 1. Scope summary

Bring all three drifted fork submodules (`forks/rtk`, `forks/tilth`, `forks/serena`) up to their upstream authors' latest stable release, without losing any fork-local security patch and without force-pushing any `main`. Per tool: create an immutable backup branch of the current fork state, build a `sync/` branch starting from the upstream stable tag, re-apply the fork's keeper patches on that tree, prove tests green, then land the sync tree on the fork's `main` via a regular merge commit (tree of the merge equals the sync branch, history preserved, no force-push). After each tool lands, update token-diet: submodule pin bump, SBOM regeneration, version bump, full test suite, local rebuild verification. `forks/icm` is explicitly NOT in scope (already up to date, self-authored upstream). Adding new upstream features to token-diet's CLI surface is NOT in scope; this is a sync, not a feature adoption pass.

Smallest possible v1: iterations 1-3 only (rtk synced to v0.43.0, tilth and serena untouched).

Source design discussion: this conversation (audit of 2026-07-10, three parallel agent audits of rtk/tilth/serena drift; tracking issue artificemachine/token-diet#5).

## 2. Prerequisites

- Dependencies: git with `upstream` remotes already configured in all three forks (done, verified this session); Rust stable toolchain (rtk, tilth builds pass today); `uv` for serena pytest; Docker for `Dockerfile.serena` rebuild; `bats-core`, `pytest` for token-diet suite; `gh` CLI authenticated for pushes and the final release.
- Sync targets (verified live against upstream remotes): rtk `rtk-ai/rtk` tag `v0.43.0`; tilth `jahala/tilth` tag `v0.9.0`; serena `oraios/serena` tag `v1.5.3` (stable tag, deliberately not `main` HEAD at 1.5.4.dev0).
- Existing code areas touched:
  - `forks/rtk/hooks/claude/rtk-rewrite.sh`, `forks/rtk/src/hooks/hook_check.rs` (token-diet integration patch to re-apply)
  - `forks/tilth/src/main.rs`, `forks/tilth/src/security.rs` (pager guard source; `security.rs` is deleted on the upstream tree, guard must move)
  - `forks/serena/src/serena/cli.py`, `forks/serena/src/serena/util/shell.py`, `forks/serena/src/serena/project.py`, `forks/serena/test/serena/test_security.py`, `forks/serena/patches/stdio.py`, `forks/serena/Dockerfile` (6 fork-local patches to extract and re-apply)
  - token-diet: `scripts/install.sh`, `scripts/token-diet`, `scripts/token-diet.ps1`, `scripts/lib/opencode-rules.md`, `.claude/settings.local.json`, `compliance/SBOM.template.json`, `CHANGELOG.md`
- Risks:
  - serena `cli.py` was rewritten near-totally upstream and `project.py` logic moved to `src/serena/memories/memory_manager.py` (path exists only on the upstream tree); patch re-application is manual re-implementation, not `git apply`.
  - rtk fork deleted `src/core/telemetry.rs` entirely; the upstream v0.43.0 tree has telemetry back. Default behavior must be verified before landing (see iteration 2 VERIFY step).
  - Upstream behavior changes beyond security (rtk 9 minor versions, tilth MCP tool renames, serena 1.x CLI restructure) can break token-diet's installed integration; token-diet's bats suite plus `install.sh --verify` and `token-diet doctor` are the safety net, exercised in iterations 3, 5, 8.
  - `git push` of fork `main` branches requires per-operation confirmation under global rules; each is listed as an acceptance criterion so it is explicit, and none is a force-push.

## 3. Iterations

#### Iteration 1 - rtk: backup refs, sync branch, patch triage

**Goal:** rtk fork has an immutable backup of today's state, a `sync/upstream-v0.43.0` branch rooted at the upstream tag, and a verified triage of every fork-only commit into DROP or KEEP.

**Shippable on its own?** Yes. Backup and sync branches are pushed refs; nothing about the current install changes.

**Source references:**
- forks/rtk/hooks/claude/rtk-rewrite.sh - carries the token-diet `rtk-disabled` sentinel integration that must survive the sync; read to record its exact current behavior before triage
- forks/rtk/src/hooks/hook_check.rs - `CURRENT_HOOK_VERSION` constant aligned with the hook script; part of the same keeper patch
- forks/rtk/CHANGELOG.md - fork-local entries enumerate every fork-only change (telemetry strip, #897 stdin-null pass, hook v4) used to seed the triage table

**Files touched:**
- CHANGELOG.md (modified - append one line recording backup/sync branch names and SHAs in token-diet)

**Commit message:**
`chore(forks): record rtk pre-sync backup refs for v0.34.5 to v0.43.0 sync`

**TDD cycle:**
- RED (failing verification before the work exists):
  - `cd forks/rtk && git rev-parse --verify backup/pre-sync-2026-07-10` - fails now (branch absent)
  - `cd forks/rtk && git rev-parse --verify sync/upstream-v0.43.0` - fails now (branch absent)
  - `cd forks/rtk && git diff --quiet backup/pre-sync-2026-07-10 main` - must pass once branch exists (tree identity)
- GREEN (minimal work to pass RED):
  - `git branch backup/pre-sync-2026-07-10 main` (also keep existing `security/permission-engine-hardening` ref as-is; it is part of the backup surface)
  - `git fetch upstream --tags && git branch sync/upstream-v0.43.0 v0.43.0`
  - Push both branches to `celstnblacc/rtk`
  - Produce triage from `git log main --not upstream/master --oneline`: DROP the 4 cherry-picks landed this week (`41a6c6b`, `40c9dbc`, `952245d`, `e16aa26` content is native upstream), DROP `5bed0f1` (weaker #886 port, superseded), DROP fork clippy-fix commits (upstream fixed its own lints); KEEP `d9c22d5` (rtk-disabled sentinel + hook version alignment), KEEP telemetry-strip policy (as policy, re-verified in iteration 2), KEEP any fork-only stdin-null call sites not present upstream
- REFACTOR: None (git operations only)

**Test pyramid for this iteration:**
- Smoke: both new branches resolve via `git rev-parse --verify`; backup tree identical to `main` (`git diff --quiet`)
- Unit: existing token-diet bats suite re-run unchanged (`bats tests/token-diet.bats`), asserts the CHANGELOG-only commit breaks nothing (153 existing tests)
- Integration: N/A
- State machine: N/A
- Contract: triage table lists every commit from `git log main --not upstream/master` exactly once (no unclassified commit)
- Regression: N/A - pure addition of refs
- Chaos: N/A
- E2E: N/A
- Performance: N/A
- TDD Parity: 100% (0 new public symbols introduced, 0 tests required, 0 gaps)
- Coverage: +0 tests, no delta (no code changed; fork repos have no coverage gate, test-count delta is the tracked metric)

**Acceptance criteria (binary):**
- [ ] `backup/pre-sync-2026-07-10` exists on `celstnblacc/rtk` remote and its tree equals current `main`
- [ ] `sync/upstream-v0.43.0` exists on remote and points at upstream tag `v0.43.0`
- [ ] Every fork-only commit hash appears in the triage table as DROP or KEEP with a one-line reason
- [ ] token-diet CHANGELOG.md has the appended ref-record line

**Estimated effort:** S

**Blocked by:** None

#### Iteration 2 - rtk: re-apply keeper patches on sync branch

**Goal:** `sync/upstream-v0.43.0` carries the token-diet hook integration and the fork's telemetry policy, with the full upstream test suite plus new fork tests green.

**Shippable on its own?** Yes. The sync branch becomes a complete, releasable fork state; `main` is untouched until iteration 3.

**Source references:**
- forks/rtk/hooks/claude/rtk-rewrite.sh - current sentinel implementation (`$HOME/.config/token-diet/rtk-disabled` early-exit, `rtk-hook-version: 4`); the upstream v0.43.0 script is restructured (version-check caching, heredoc jq), so the sentinel must be re-inserted into the new structure by hand, never auto-merged
- forks/rtk/src/hooks/hook_check.rs - fork's `CURRENT_HOOK_VERSION` handling to reconcile with upstream's cache-file approach
- forks/rtk/CHANGELOG.md - fork entry "telemetry: stripped entirely" defines the policy the VERIFY step enforces

**Files touched:**
- forks/rtk/hooks/claude/rtk-rewrite.sh (modified, on sync branch)
- forks/rtk/src/hooks/hook_check.rs (modified, on sync branch)
- forks/rtk/CHANGELOG.md (modified - append sync + keeper-patch entries)
- forks/rtk/src/core/ telemetry module on the upstream tree (modified only if VERIFY finds phone-home-by-default)

**Commit message:**
`feat(sync): re-apply token-diet integration patches on upstream v0.43.0`

**TDD cycle:**
- RED (failing tests to write first, on the sync branch):
  - `hooks::hook_check::tests::test_hook_script_contains_token_diet_sentinel` - asserts the installed hook script text contains the `rtk-disabled` sentinel check
  - `hooks::hook_check::tests::test_hook_version_constant_matches_script` - asserts `CURRENT_HOOK_VERSION` equals the `rtk-hook-version:` value in the script
  - `core::telemetry_policy_test::test_telemetry_disabled_by_default` - asserts no telemetry ping without explicit opt-in (exact assertion shaped by the VERIFY finding: either config default is off, or the module is stripped and the test asserts the dependency is absent from Cargo.toml)
- GREEN (minimal implementation to pass RED):
  - Re-insert sentinel early-exit into upstream's restructured `rtk-rewrite.sh`; bump `rtk-hook-version` and `CURRENT_HOOK_VERSION` together
  - VERIFY telemetry: read upstream v0.43.0 telemetry default; if opt-in, keep upstream code and pin default-off with the test; if opt-out (phones home unless disabled), flip the default to off in config and document in CHANGELOG
  - Run `cargo fmt --all && cargo clippy --all-targets && cargo test` on the sync branch until green
- REFACTOR: None planned; keeper patches must stay minimal diffs against upstream to ease the next sync

**Test pyramid for this iteration:**
- Smoke: `cargo build` succeeds on sync branch; `target/debug/rtk --version` prints 0.43.0
- Unit: 3 new tests named in RED; full upstream suite (upstream's own count, >1300) green
- Integration: `bash scripts/test-all.sh` (rtk's own smoke script) against the locally built binary
- State machine: N/A
- Contract: `test_hook_version_constant_matches_script` is the contract check (script text and Rust constant agree)
- Regression: upstream's own permission-engine tests (compound-allow #1213, default-ask #886, `>&file` redirect) now run natively; assert present by name in test output
- Chaos: N/A - covered by upstream suite's malformed-input tests
- E2E: N/A until iteration 3 (needs installed binary + live hook)
- Performance: `hyperfine 'target/release/rtk git status' --warmup 3` under 10ms median (rtk's own stated gate)
- TDD Parity: 100% - every re-applied behavior (sentinel, version constant, telemetry default) has a named test
- Coverage: +3 tests (rtk repo has no coverage gate; test-count delta is the tracked metric, upstream suite count is the floor)

**Acceptance criteria (binary):**
- [ ] `cargo fmt --check`, `cargo clippy --all-targets` (zero errors), `cargo test` all green on sync branch
- [ ] 3 RED tests exist and pass
- [ ] `rtk-rewrite.sh` on sync branch exits 0 silently when `$HOME/.config/token-diet/rtk-disabled` exists
- [ ] Telemetry VERIFY finding and action recorded in forks/rtk/CHANGELOG.md
- [ ] hyperfine median startup < 10ms on release build

**Estimated effort:** L

**Blocked by:** Iteration 1

#### Iteration 3 - rtk: land sync on main, bump token-diet pin, SBOM, verify install

**Goal:** rtk fork `main` tree equals the sync branch, token-diet pins the new commit, and the installed rtk on this machine is rebuilt and verified at 0.43.0.

**Shippable on its own?** Yes. This is the rtk release slice; tilth/serena remain on old pins without conflict.

**Source references:**
- scripts/install.sh - drives `rtk init -g` and hook installation; must be re-run and verified against the new hook version
- scripts/token-diet - `doctor` integrity check hashes the installed hook; verifies end state
- compliance/SBOM.template.json - rtk component version field to update

**Files touched:**
- CHANGELOG.md (modified - token-diet entry)
- compliance/SBOM.template.json (modified - rtk 0.43.0)
- scripts/token-diet (modified - TD_VERSION 1.10.8 to 1.10.9)
- scripts/token-diet.ps1 (modified - same bump)
- forks/rtk (submodule pin moved to the merge commit)

**Commit message:**
`chore(submodule): sync forks/rtk to upstream v0.43.0 + re-applied integration patches`

**TDD cycle:**
- RED (failing checks to define first):
  - `tests/install.bats` existing case `install.sh --verify` run against the new pin - fails if hook version mismatch or rtk missing
  - contract grep (new bats test) `tests/token-diet.bats::"gain: rtk version reported is 0.43"` - asserts `token-diet version` reports rtk 0.43.x
- GREEN (minimal implementation):
  - In forks/rtk: `git checkout main && git merge --no-commit sync/upstream-v0.43.0 && git checkout sync/upstream-v0.43.0 -- . && git commit` (merge commit whose tree equals the sync branch; regular push, no force)
  - Push `main` to `celstnblacc/rtk`
  - In token-diet: stage submodule pin, SBOM rtk version, TD_VERSION bumps, CHANGELOG line
  - Rebuild locally: `bash scripts/install.sh --local --rtk-only`; re-run `rtk init -g`; `token-diet doctor`
- REFACTOR: None

**Test pyramid for this iteration:**
- Smoke: `rtk --version` reports 0.43.x from `~/.local/bin/rtk`; `token-diet health` exits 0
- Unit: full token-diet bats suite (`bats tests/token-diet.bats tests/install.bats`)
- Integration: `bash scripts/install.sh --local --rtk-only` full build path; `bash scripts/install.sh --verify`
- State machine: N/A
- Contract: SBOM rtk version equals `forks/rtk/Cargo.toml` version (grep assertion); new bats version test
- Regression: `token-diet doctor` hook-integrity check green (guards against the restructured hook breaking the installed copy)
- Chaos: existing bats malformed-config cases re-run as part of the suite
- E2E: live hook check: in a scratch dir with an allow rule, `rtk rewrite "git status"` exit codes match the 0/1/2/3 protocol table
- Performance: N/A (measured in iteration 2)
- TDD Parity: 100% - one new bats test for the one new observable (reported version)
- Coverage: +1 bats test (bats has no coverage tooling; test-count delta is the tracked metric)

**Acceptance criteria (binary):**
- [ ] forks/rtk `main` pushed; `git diff --quiet main sync/upstream-v0.43.0` clean (trees identical)
- [ ] token-diet PR merged with pin + SBOM + TD_VERSION 1.10.9 + CHANGELOG
- [ ] `bats tests/*.bats` and `pytest tests/ -q` green
- [ ] `token-diet doctor` exits with rtk 0.43.x and hook integrity OK
- [ ] `bash scripts/install.sh --verify` reports rtk OK

**Estimated effort:** M

**Blocked by:** Iteration 2

#### Iteration 4 - tilth: backup, sync, containment audit, pager guard re-port

**Goal:** tilth `sync/upstream-v0.9.0` branch carries the pager-injection guard and fresh containment regression tests, all green.

**Shippable on its own?** Yes. Sync branch is complete; `main` untouched until iteration 5.

**Source references:**
- forks/tilth/src/security.rs - fork's `validate_pager` / SHELL_META guard implementation to port; this file is deleted on the upstream tree, so the guard moves to where upstream spawns the pager
- forks/tilth/src/main.rs - upstream v0.9.0 spawns `$PAGER` raw around line 421 per the audit; insertion point for the ported guard
- forks/tilth/src/mcp.rs - fork's `validate_path_in_scope` boundary (deleted upstream); the audit baseline the new containment tests must preserve

**Files touched:**
- forks/tilth/src/main.rs (modified, on sync branch - pager guard insertion)
- forks/tilth/src/mcp/mod.rs (modified, on sync branch - containment regression tests added to existing test module; path exists on the upstream tree)
- forks/tilth/CHANGELOG.md (modified - sync + keeper entries; created upstream-style if absent on that tree)

**Commit message:**
`feat(sync): re-apply pager guard + containment regression tests on upstream v0.9.0`

**TDD cycle:**
- RED (failing tests to write first, on the sync branch):
  - `mcp::tests::test_read_refuses_relative_path_without_root` - relative path + no absolute `root` param is refused (upstream `ed51e58` behavior pinned by the fork's own test)
  - `mcp::tests::test_scope_cannot_escape_root` - `scope` containing `..` that resolves outside `root` is refused
  - `mcp::tests::test_write_anchors_to_explicit_root` - `tilth_write` path resolution anchors to the request `root`, not server cwd
  - `pager_guard::tests::test_pager_with_shell_metachars_rejected` - `PAGER='less; rm -rf /tmp/x'` is rejected before spawn
  - `pager_guard::tests::test_plain_pager_accepted` - `PAGER=less` passes
- GREEN (minimal implementation):
  - Port `validate_pager` from the fork's `security.rs` into the upstream pager spawn path in `main.rs`
  - Read the final upstream containment model top-to-bottom (`anchor_path`, `resolve_scope`, `path_within_scope` in `src/mcp/mod.rs` and `src/mcp/tools/write.rs` on the sync tree, final state only, not the buggy intermediate diffs) and write the RED containment tests against observed behavior; fix nothing unless a test exposes a real hole, in which case patch minimally and record it
  - `cargo fmt && cargo clippy --all-targets && cargo test` green
- REFACTOR: None planned

**Test pyramid for this iteration:**
- Smoke: `cargo build` on sync branch; `target/debug/tilth --version` prints 0.9.0; backup/sync branches resolve
- Unit: 5 new tests named in RED plus full upstream suite green
- Integration: `tilth --mcp` starts and answers a `tilth_read` request on a fixture dir (driven via stdin JSON, one round-trip)
- State machine: N/A
- Contract: MCP tool list contains `tilth_write`, `tilth_diff`, `tilth_grok`, `tilth_savings` and does NOT contain `tilth_edit` or `tilth_map` (assert against `tools/list` response; this is the rename contract iteration 5's doc updates depend on)
- Regression: the 5 RED tests are the regression suite for the rearchitected boundary plus the silently-lost pager guard
- Chaos: `test_pager_with_shell_metachars_rejected` is the injection case; malformed MCP request returns error not panic (one test)
- E2E: N/A until iteration 5 (needs registration in a live host)
- Performance: N/A - no perf gate defined for tilth
- TDD Parity: 100% - ported guard and each audited boundary behavior has a named test
- Coverage: +6 tests (5 RED + 1 chaos; tilth repo has no coverage gate, test-count delta is the tracked metric)

**Acceptance criteria (binary):**
- [ ] `backup/pre-sync-2026-07-10` and `sync/upstream-v0.9.0` pushed to `celstnblacc/tilth`
- [ ] All 5 RED tests pass on sync branch; full `cargo test` green
- [ ] `validate_pager` guard present in the upstream spawn path with both pager tests green
- [ ] Containment audit finding recorded in forks/tilth/CHANGELOG.md (clean, or hole + minimal patch)
- [ ] `tools/list` contract test green

**Estimated effort:** L

**Blocked by:** Iteration 3

#### Iteration 5 - tilth: land sync on main, rename stale tool docs, bump pin

**Goal:** tilth `main` equals sync tree; every token-diet reference to `tilth_edit`/`tilth_map` is updated; token-diet pins tilth 0.9.0 and verifies the installed stack.

**Shippable on its own?** Yes. tilth release slice.

**Source references:**
- scripts/lib/opencode-rules.md - contains agent-facing instructions naming tilth MCP tools; stale names mislead agents after the rename
- scripts/install.sh - comments reference old tool names; also drives `tilth install <host>` (CLI verified unchanged upstream)
- scripts/token-diet.ps1 - Windows CLI mirrors the tool-name references
- .claude/settings.local.json - permission entries referencing old tilth tool names

**Files touched:**
- forks/tilth (submodule pin moved to merge commit)
- scripts/lib/opencode-rules.md (modified - tilth_edit to tilth_write, drop tilth_map)
- scripts/install.sh (modified - comment updates)
- scripts/token-diet.ps1 (modified - name updates + TD_VERSION 1.10.10)
- scripts/token-diet (modified - TD_VERSION 1.10.10)
- .claude/settings.local.json (modified - permission entries)
- compliance/SBOM.template.json (modified - tilth 0.9.0)
- CHANGELOG.md (modified)

**Commit message:**
`chore(submodule): sync forks/tilth to upstream v0.9.0 + rename tilth_edit/tilth_map references`

**TDD cycle:**
- RED (failing checks first):
  - new bats test `tests/token-diet.bats::"docs: no stale tilth_edit or tilth_map references"` - `grep -rn 'tilth_edit\|tilth_map' scripts/ .claude/settings.local.json` returns empty; fails before the doc updates
  - existing `tests/install.bats` verify cases against the new pin
- GREEN:
  - Merge sync to main in forks/tilth (same no-force merge-tree technique as iteration 3), push
  - Update the four token-diet files; pin bump; SBOM; TD_VERSION; CHANGELOG
  - `bash scripts/install.sh --local --tilth-only`; `token-diet doctor`
- REFACTOR: None

**Test pyramid for this iteration:**
- Smoke: `tilth --version` reports 0.9.0 from `~/.local/bin/tilth`; `token-diet health` exit 0
- Unit: full bats suite including the new stale-reference test
- Integration: `install.sh --local --tilth-only` build; `install.sh --verify`; MCP registration check via `token-diet mcp list` shows tilth on all hosts
- State machine: N/A
- Contract: SBOM tilth version equals `forks/tilth/Cargo.toml` version; stale-name grep test
- Regression: `token-diet doctor` green (guards MCP path registrations against the version jump)
- Chaos: existing bats malformed-config cases
- E2E: from this repo, a live `tilth_read` of `scripts/token-diet` through the registered MCP binary returns content (proves installed binary + registration end to end)
- Performance: N/A
- TDD Parity: 100% - one new observable (no stale names), one new test
- Coverage: +1 bats test (no coverage tooling for bats; test-count delta is the tracked metric)

**Acceptance criteria (binary):**
- [ ] forks/tilth `main` pushed, tree equals sync branch
- [ ] `grep -rn 'tilth_edit\|tilth_map' scripts/ .claude/settings.local.json` empty
- [ ] token-diet PR merged (pin, SBOM, TD_VERSION 1.10.10, CHANGELOG)
- [ ] `bats tests/*.bats` and `pytest tests/ -q` green; `token-diet doctor` green
- [ ] Installed `tilth --version` is 0.9.0

**Estimated effort:** M

**Blocked by:** Iteration 4

#### Iteration 6 - serena: backup, sync, patch-set extraction, stdio decision

**Goal:** serena backup and sync branches exist; the 6 fork-local patches are extracted as portable, line-number-independent patch specs; the stdio EOF question is answered with evidence.

**Shippable on its own?** Yes. Safety artifacts only; nothing installed changes.

**Source references:**
- forks/serena/src/serena/util/shell.py - `_SHELL_METACHAR_RE` guard (patch 1acd0118) to spec
- forks/serena/src/serena/project.py - memory path-traversal validation (same patch); upstream moved this logic to `src/serena/memories/memory_manager.py` (upstream-tree path), so the spec must describe behavior, not line numbers
- forks/serena/src/serena/cli.py - `--no-shell` trust mode, SIGTERM/SIGHUP handling (patches e5c8fd50, 6aab7b78); upstream rewrote this file (new `serena init`/`serena setup`, `modes` renamed `default_modes`), re-implementation target
- forks/serena/patches/stdio.py - vendored MCP stdio EOF patch (da079720); subject of the VERIFY decision
- forks/serena/test/serena/test_security.py - the fork's 21+ security tests; the canary suite iteration 7 must keep green

**Files touched:**
- CHANGELOG.md (modified - token-diet line recording serena backup/sync refs and the stdio decision)

**Commit message:**
`chore(forks): record serena pre-sync backup refs + stdio EOF carry/drop decision`

**TDD cycle:**
- RED (failing verification first):
  - `cd forks/serena && git rev-parse --verify backup/pre-sync-2026-07-10` - fails now
  - `cd forks/serena && git rev-parse --verify sync/upstream-v1.5.3` - fails now
  - patch-spec completeness check: every one of the 6 fork commit hashes (`1acd0118`, `16f45c5e`, `37944af1`, `6aab7b78`, `e5c8fd50`, `da079720`) appears in the extracted spec set with a behavior description and a target location on the v1.5.3 tree
- GREEN:
  - Create and push both branches (backup from `main`, sync from upstream tag `v1.5.3`)
  - `git format-patch` the 6 commits into the session scratchpad plus a behavior-spec note per patch (what it guards, how to observe it, where it lands on the new tree)
  - VERIFY stdio: read upstream v1.5.3's `mcp` dependency pin and the upstream repo/python-sdk issue 2549 status; decide carry `patches/stdio.py` forward or drop as fixed; record the decision and evidence in the CHANGELOG line
- REFACTOR: None

**Test pyramid for this iteration:**
- Smoke: both branches resolve; backup tree equals `main`
- Unit: fork's existing security suite re-run on the backup branch (`uv run pytest test/serena/test_security.py -q` inside forks/serena) pins the pre-sync baseline the specs describe (21+ tests)
- Integration: N/A
- State machine: N/A
- Contract: 6-of-6 patch hashes covered by specs (the completeness check above)
- Regression: N/A
- Chaos: N/A
- E2E: N/A
- Performance: N/A
- TDD Parity: 100% (0 new public symbols introduced, 0 tests required, 0 gaps)
- Coverage: +0 tests, no delta (no code changed; baseline suite count recorded for iteration 7 comparison)

**Acceptance criteria (binary):**
- [ ] `backup/pre-sync-2026-07-10` and `sync/upstream-v1.5.3` pushed to `celstnblacc/serena`
- [ ] 6 patch specs written, each naming target file(s) on the v1.5.3 tree
- [ ] stdio carry/drop decision recorded with the `mcp` version evidence
- [ ] token-diet CHANGELOG line appended

**Estimated effort:** M

**Blocked by:** Iteration 5

#### Iteration 7 - serena: re-apply patch set on sync tree

**Goal:** all keeper behaviors (shell metachar guard, memory path-traversal check, `--no-shell`, SIGTERM/SIGHUP shutdown, atomic writes/doctor, stdio patch if carried) live on `sync/upstream-v1.5.3` with the security test suite green.

**Shippable on its own?** Yes. Sync branch is a complete fork state; `main` untouched until iteration 8.

**Source references:**
- forks/serena/test/serena/test_security.py - source of the ported test suite; tests are re-targeted at the new module layout first (RED), then guards are re-implemented (GREEN)
- forks/serena/src/serena/util/shell.py - reference implementation of `_SHELL_METACHAR_RE`
- forks/serena/src/serena/cli.py - reference implementation of `--no-shell` and signal handling
- forks/serena/Dockerfile - shows how `patches/stdio.py` is applied at image build; needed only if the stdio decision is carry

**Files touched:**
- forks/serena/src/serena/util/shell.py (modified, on sync tree)
- forks/serena/src/serena/cli.py (modified, on sync tree - upstream's rewritten version gains `--no-shell` and signal handlers)
- forks/serena/src/serena/memories/memory_manager.py (modified, on sync tree - path exists only there; receives the path-traversal validation)
- forks/serena/test/serena/test_security.py (modified, on sync tree - ported + 3 new tests)
- forks/serena/patches/stdio.py and forks/serena/Dockerfile (modified only if stdio decision is carry)
- forks/serena/CHANGELOG.md (modified)

**Commit message:**
`feat(sync): re-apply fork security patch set on upstream v1.5.3`

**TDD cycle:**
- RED (failing tests first, on the sync tree):
  - port the fork's `test_security.py` suite onto the sync tree, re-targeted at the new layout; the guard tests fail (guards absent)
  - `test_security.py::test_no_shell_flag_rejects_shell_execution` - new: with `--no-shell`, any code path that would spawn a shell raises
  - `test_security.py::test_shell_metachar_guard_blocks_injection` - new name pinning the regex guard on the new tree
  - `test_security.py::test_memory_write_path_traversal_rejected` - new: memory name containing `../` cannot escape the memories dir (asserts in `memory_manager.py`)
- GREEN:
  - Re-implement each spec from iteration 6 at its new location; `--no-shell` wired into the rewritten CLI's argument surface (upstream `default_modes` naming respected)
  - If stdio decision is carry: keep `patches/stdio.py` + Dockerfile COPY; if drop: delete both and record
  - `uv run pytest test/serena/test_security.py -q` green, then the broader suite subset upstream ships for the touched modules
- REFACTOR: extract shared guard helpers only if the same regex lands in more than one module; otherwise none

**Test pyramid for this iteration:**
- Smoke: `uv run serena --help` exits 0 on sync tree; `serena --version` (or equivalent) reports 1.5.3
- Unit: ported security suite (21+ tests) plus 3 new named tests
- Integration: `serena start-mcp-server --context=claude-code --project-from-cwd` boots and answers an initialize round-trip on a fixture project
- State machine: N/A
- Contract: CLI contract greps: `--context`, `--open-web-dashboard`, `--project`, `--project-from-cwd`, `--no-shell` all present in `serena start-mcp-server --help` output (install.sh depends on the first four; the fifth is the keeper)
- Regression: the ported 21+ security tests are exactly the regression guard; any silently-dropped guard fails here
- Chaos: SIGTERM sent to a running `start-mcp-server` process exits cleanly within timeout (signal-handling test); malformed memory name test above
- E2E: N/A until iteration 8 (Docker + host registration)
- Performance: N/A
- TDD Parity: 100% of re-applied behaviors have named tests (metachar, traversal, no-shell, signals, stdio-if-carried)
- Coverage: +24 tests (3 new plus 21 ported; serena fork has no coverage gate, test-count delta vs the iteration 6 baseline is the tracked metric)

**Acceptance criteria (binary):**
- [ ] `uv run pytest test/serena/test_security.py -q` green on sync tree
- [ ] 3 new RED tests pass
- [ ] CLI contract grep finds all 5 flags
- [ ] SIGTERM chaos test green
- [ ] stdio decision executed (patch carried or deleted) and recorded in forks/serena/CHANGELOG.md

**Estimated effort:** L

**Blocked by:** Iteration 6

#### Iteration 8 - serena: land sync on main, rebuild Docker, final release

**Goal:** serena `main` equals sync tree; token-diet pins v1.5.3, Docker image rebuilds, full stack verified; token-diet v1.11.0 released and tracking issue #5 closed.

**Shippable on its own?** Yes. Final release slice.

**Source references:**
- docker/Dockerfile.serena - token-diet's own image builds from `forks/serena` source via `uv pip install`; must build against the 1.5.3 tree
- scripts/install.sh - serena registration blocks (docker run args, uvx fallback) exercised by `--serena-only`
- compliance/SBOM.template.json - serena component version field

**Files touched:**
- forks/serena (submodule pin moved to merge commit)
- docker/Dockerfile.serena (modified only if the 1.5.3 layout breaks the build; otherwise untouched)
- compliance/SBOM.template.json (modified - serena 1.5.3, final pass over all four components)
- scripts/token-diet (modified - TD_VERSION 1.10.10 to 1.11.0)
- scripts/token-diet.ps1 (modified - same)
- CHANGELOG.md (modified)

**Commit message:**
`chore(submodule): sync forks/serena to upstream v1.5.3 + release token-diet 1.11.0`

**TDD cycle:**
- RED (failing checks first):
  - `docker build -f docker/Dockerfile.serena -t token-diet/serena:local .` against the new pin - fails if the 1.5.3 source layout breaks the image
  - existing bats serena cases (`--serena-only` idempotency, malformed-config abort) against the new pin
- GREEN:
  - Merge sync to main in forks/serena (no-force merge-tree technique), push
  - token-diet: pin bump, SBOM final (rtk 0.43.0, tilth 0.9.0, serena 1.5.3, icm 0.10.50), TD_VERSION 1.11.0, CHANGELOG
  - `bash scripts/install.sh --local --serena-only`; `token-diet doctor`; full test suite
  - PR, merge, tag v1.11.0, `gh release create`, close issue #5 with a summary comment
- REFACTOR: None

**Test pyramid for this iteration:**
- Smoke: Docker image builds; `token-diet health` exit 0; `token-diet version` shows all four synced versions
- Unit: full bats + pytest suites
- Integration: `install.sh --local --serena-only`; `install.sh --verify`; `token-diet mcp list` shows serena on all hosts
- State machine: N/A
- Contract: SBOM versions equal each fork's manifest version (rtk Cargo.toml, tilth Cargo.toml, serena pyproject.toml, icm crates/icm-cli/Cargo.toml); TD_VERSION matches in both CLI scripts
- Regression: `token-diet doctor` green end-to-end; serena security suite already green from iteration 7 stays pinned
- Chaos: existing bats malformed-config abort cases against the new pin
- E2E: registered serena MCP answers an initialize + one `find_symbol` round-trip inside the rebuilt Docker container on this repo
- Performance: N/A
- TDD Parity: 100% (0 new public symbols introduced, 0 tests required, 0 gaps)
- Coverage: +0 tests, no delta (release mechanics only; every suite from iterations 1-7 re-run as the gate)

**Acceptance criteria (binary):**
- [ ] forks/serena `main` pushed, tree equals sync branch
- [ ] Docker image builds and serves MCP (E2E round-trip green)
- [ ] token-diet PR merged; tag `v1.11.0` and GitHub release exist
- [ ] SBOM lists rtk 0.43.0, tilth 0.9.0, serena 1.5.3, icm 0.10.50
- [ ] Issue artificemachine/token-diet#5 closed with summary
- [ ] Full suite green: bats + pytest + fork suites

**Estimated effort:** L

**Blocked by:** Iteration 7

## 4. Test inventory summary

| Iter | Smoke | Unit | Integration | State machine | Contract | Regression | Chaos | E2E | Performance | TDD Parity | Coverage Δ |
|------|-------|------|-------------|---------------|----------|------------|-------|-----|-------------|------------|------------|
| 1    | 2     | 0    | 0           | 0             | 1        | 0          | 0     | 0   | 0           | N/A        | N/A        |
| 2    | 2     | 3+suite | 1        | 0             | 1        | 3 (named upstream) | 0 | 0 | 1           | 100%       | N/A (+3 tests) |
| 3    | 2     | suite | 3          | 0             | 2        | 1          | suite | 1   | 0           | 100%       | N/A (+1 test)  |
| 4    | 3     | 5+suite | 1        | 0             | 1        | 5          | 2     | 0   | 0           | 100%       | N/A (+6 tests) |
| 5    | 2     | suite+1 | 3        | 0             | 2        | 1          | suite | 1   | 0           | 100%       | N/A (+1 test)  |
| 6    | 2     | 0     | 0          | 0             | 1        | 0          | 0     | 0   | 0           | N/A        | N/A        |
| 7    | 2     | 24    | 1          | 0             | 1 (5 flags) | 21      | 2     | 0   | 0           | 100%       | N/A (+24 tests) |
| 8    | 3     | suite | 3          | 0             | 2        | 1          | suite | 1   | 0           | N/A        | N/A (reruns)   |

## 5. End-to-end definition of done

Deduplicated acceptance criteria:
- All three forks' `main` branches carry the upstream stable-tag tree (rtk v0.43.0, tilth v0.9.0, serena v1.5.3) plus re-applied keeper patches, landed by merge commit, never force-push.
- Backup branches `backup/pre-sync-2026-07-10` pushed on all three fork remotes with trees identical to the pre-sync `main`.
- Every fork-only commit triaged DROP or KEEP; every KEEP behavior has a named test that passes on the synced tree.
- token-diet pins all three new commits; SBOM, TD_VERSION 1.11.0, CHANGELOG consistent; tag and GitHub release `v1.11.0` published; issue #5 closed.
- Installed stack verified: `token-diet doctor` green, `install.sh --verify` green, hook integrity OK, MCP registrations answer live round-trips.

Single end-to-end manual demo: in this repo run `token-diet version` (shows rtk 0.43.x, tilth 0.9.0, serena 1.5.3, icm 0.10.50), then `token-diet doctor` (all green), then one live `tilth_read` and one serena `find_symbol` through the registered MCP servers, then `rtk rewrite "git status && rm -rf /tmp/x"` with only `git status` allow-listed and observe exit 3 (ask), proving the permission engine survived the sync.

Final green command (every file explicit):

```bash
(cd forks/rtk && cargo test) \
&& (cd forks/tilth && cargo test) \
&& uv run --project forks/serena pytest forks/serena/test/serena/test_security.py -q \
&& bats tests/token-diet.bats tests/install.bats \
&& pytest tests/test_dashboard.py -q
```

## 6. Out of scope

- icm sync: already up to date; upstream is the fork itself. No work.
- Adopting new upstream features into token-diet's CLI surface (rtk `smart`/`deps`/`json` meta-commands, tilth `tilth_grok`/`tilth_savings` promotion in docs, serena's 15+ new language servers): deferred; sync lands them in the binaries but token-diet does not advertise them yet. Reason: keeps this plan a sync, not a feature release; each is its own small follow-up.
- rtk `run_claude`/`run_cursor` native hook adoption in token-diet's install flow: arrives with the sync but wiring token-diet's installer to prefer native hooks over `rtk-rewrite.sh` is a design change. Deferred, uncertain benefit.
- Automating the sync (CI job that opens sync PRs): deferred until one manual cycle proves the process. The existing upstream-check workflow (detection) stays as-is.
- Windows Pester suite run for each iteration: run once at iteration 8 only. Reason: no Windows-specific surface changes in the forks.

## 7. Open questions

None. The two candidate questions were resolved during planning: sync targets are upstream stable tags (not dev HEAD), and the rtk telemetry question is a VERIFY step inside iteration 2 with both outcomes specified, not a blocking decision.
