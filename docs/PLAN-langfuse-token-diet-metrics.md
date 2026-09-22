# Plan — langfuse-token-diet metrics

## 1. Scope summary

Build an opt-in token-diet metrics path: validate one completed task receipt containing provider or SDK usage, RTK compression estimates, and a binary verification result; retain it locally; render a redacted Langfuse payload; and send it only with an explicit flag to the existing Langfuse project named langfuse-token-diet. It does not create a Langfuse project, deployment, repository, credential file, provider billing importer, or agent-observability-plane integration. Source designs: docs/ARCH-langfuse-token-diet-roles.md, docs/ARCH-token-diet-langfuse-integration.md, docs/AUDIT-langfuse-metrics.md.

Smallest possible v1: validate and retain one manually supplied complete receipt, then render its dry-run export without network traffic.

## 2. Prerequisites

- Owner creates langfuse-token-diet in the existing self-hosted instance; this external configuration is not performed by this plan.
- Runtime-only LANGFUSE_BASE_URL, LANGFUSE_PUBLIC_KEY, and LANGFUSE_SECRET_KEY come from the existing secret mechanism. No test reads real keys and no source stores a key.
- Read scripts/token-diet, scripts/install.sh, scripts/lib/tdconfig.py, tests/token-diet.bats, tests/install.bats, and docs/benchmarks.md before implementation.
- Read-only sibling references: ../langfuse-bridge-mcp/src/langfuse_bridge_mcp/shipper.py, ../langfuse-bridge-mcp/pyproject.toml, and ../langfuse-ops/README.md. Recheck their SDK and host contracts before iteration 3; they may change.
- Base revision: 8f44bc087ac0a1e3a395e73ebaf82f145b70713f. Four untracked architecture/audit notes already exist under docs/ and must be preserved. Test baseline is unknown because no build or test received approval.
- PLAN_CHECK and CANONICAL_REPO were unset. The discovered checker is $HOME/DevOpsSec/skills-canonical/tools/plan_check.py; the file and python3 were verified. Invocation: python3 $HOME/DevOpsSec/skills-canonical/tools/plan_check.py PLAN --caller plan-iter --repo-root . --allow-cross-vault.
- **Execution architecture: sequential.** Every slice writes the same shared artifact: the receipt schema and scripts/token-diet dispatch surface. Slices serialize on that shared artifact; no subagents are proposed.

## 3. Iterations

#### Iteration 1 — Validate a safe task receipt

**Goal:** Deliver token-diet metrics validate RECEIPT, which accepts only a complete redacted receipt and rejects malformed, secret-bearing, or provenance-invalid data.

**Shippable on its own?** Yes — it is an offline validation gate and does not contact Langfuse.

**Source references:**
- scripts/token-diet — add one CLI route without changing existing commands.
- scripts/install.sh — preserve installed-artifact library availability.
- docs/benchmarks.md — preserve the estimate-versus-billed distinction.

**Files touched:**
- scripts/lib/tdmetrics.py (new)
- scripts/token-diet (modified)
- scripts/install.sh (modified)
- tests/test_tdmetrics.py (new)
- tests/fixtures/metrics/valid.json (new)
- tests/token-diet.bats (modified)
- tests/install.bats (modified)

**Commit message:**
feat(metrics): validate redacted task receipts

**TDD cycle:**
- RED (failing tests to write first):
  - tests/test_tdmetrics.py::test_validates_provider_usage_rtk_estimate_and_binary_outcome — accepts the minimum complete receipt.
  - tests/test_tdmetrics.py::test_rejects_prompt_text_secret_like_fields_and_estimated_cost_as_actual — proves privacy and provenance failures.
  - tests/token-diet.bats metrics validate case — proves CLI success and non-zero invalid exit.
  - tests/install.bats installed metrics case — proves the installed binary imports tdmetrics.py.
- GREEN (minimal implementation to pass RED):
  - Define a versioned receipt model with explicit provider or sdk actual-usage provenance and separate rtk_estimate provenance.
  - Render only aggregate numeric fields and validation status.
  - Ship the new Python core beside the installed CLI.
- REFACTOR (cleanup planned after GREEN):
  - Extract CLI error rendering and keep validation in one module.

**Test pyramid for this iteration:**
- Smoke: token-diet metrics validate tests/fixtures/metrics/valid.json exits 0.
- Unit: six tests in tests/test_tdmetrics.py for schema, bounds, provenance, and redaction.
- Integration: one Bats CLI-to-Python validation path.
- State machine: N/A — no lifecycle state exists.
- Contract: one receipt-version fixture contract.
- Regression: installed-artifact import test for the missing-library failure class.
- Chaos: malformed JSON and unreadable path produce safe non-zero output.
- E2E: N/A — no external service is contacted.
- Performance: N/A — receipt files are bounded local inputs.
- TDD Parity: 100% of new validation behavior has RED evidence.
- Coverage: unknown until the approved baseline is measured; no threshold is lowered.

**Deploy + validate:**
- Install: bash scripts/install.sh --local from repository root, only after approval.
- Validate: python3 -m pytest tests/test_tdmetrics.py -q and bats tests/token-diet.bats tests/install.bats from repository root; named tests pass.
- Rollback: remove only this iteration's module and CLI branch before any commit.

**Side-effect fence:** repository files and synthetic fixtures only; no credentials, host config, MCP registration, database, or network.

**Checkpoint evidence:** RED/GREEN results, installed-artifact result, fixture names, and base revision.

**Acceptance criteria (binary):**
- [ ] A valid provider or SDK receipt with RTK estimate and pass/fail outcome exits 0.
- [ ] Prompt-like text, secret-like keys, or estimated cost marked actual exits non-zero.
- [ ] Installed token-diet validates the same fixture without a checkout path.

**Estimated effort:** S (2h; basis: schema, CLI, installer packaging, and three test layers).

**Executor:** default

**Isolation:** shared

**Delegation:** in-session

**Blocked by:** None

#### Iteration 2 — Retain complete local evidence

**Goal:** Deliver token-diet metrics record RECEIPT and token-diet metrics list with idempotent, redacted XDG-local receipt storage.

**Shippable on its own?** Yes — it provides offline evidence for cost per successful task before any egress.

**Source references:**
- scripts/lib/tdconfig.py — reuse and reverify atomic write behavior.
- scripts/lib/tdmetrics.py — extend the validation contract from iteration 1.
- scripts/token-diet — add record and list routes.

**Files touched:**
- scripts/lib/tdmetrics.py (modified)
- scripts/token-diet (modified)
- tests/test_tdmetrics.py (modified)
- tests/token-diet.bats (modified)

**Commit message:**
feat(metrics): retain verified task evidence locally

**TDD cycle:**
- RED (failing tests to write first):
  - tests/test_tdmetrics.py::test_records_one_receipt_per_run_id_idempotently — identical replay creates one record.
  - tests/test_tdmetrics.py::test_rejects_conflicting_replay_for_same_run_id — protects metric integrity.
  - tests/token-diet.bats metrics list case — projects only run ID, provenance, outcome, and cost.
- GREEN (minimal implementation to pass RED):
  - Store one atomically written completed receipt per run ID under XDG_STATE_HOME/token-diet/metrics with a standard fallback when XDG is unset.
  - Reject different normalized content for a reused run ID.
  - Never store raw prompts, tool results, paths, or credentials.
- REFACTOR (cleanup planned after GREEN):
  - Extract state-root and deterministic receipt-hash helpers.

**Test pyramid for this iteration:**
- Smoke: record then list a synthetic receipt under temporary XDG_STATE_HOME.
- Unit: five tests for idempotency, conflict, state-root, atomic replacement, and projection.
- Integration: one Bats record/list workflow.
- State machine: N/A — a receipt is complete and immutable.
- Contract: stored JSON matches normalized receipt schema and excludes prohibited fields.
- Regression: conflicting same-run replay remains rejected.
- Chaos: interrupted temporary file and malformed local receipt are omitted from list output.
- E2E: N/A — local evidence only.
- Performance: N/A — one file per completed task.
- TDD Parity: 100% of persistence behavior has RED coverage.
- Coverage: unknown until measured; all new branches are targeted.

**Deploy + validate:**
- Install: N/A — reuse iteration 1 installation validation after approval.
- Validate: python3 -m pytest tests/test_tdmetrics.py -q and bats tests/token-diet.bats from repository root; named tests pass.
- Rollback: delete only synthetic test state; code rollback is this iteration's changes.

**Side-effect fence:** repository and temporary XDG test directories only; never use operator state.

**Checkpoint evidence:** receipt hashes, idempotency/conflict outcomes, and affected files.

**Acceptance criteria (binary):**
- [ ] Recording one receipt twice produces exactly one local receipt.
- [ ] Different content with the same run ID exits non-zero.
- [ ] Listing exposes only allowed aggregate fields.

**Estimated effort:** S (2h; basis: durable idempotent state, edge cases, and CLI integration).

**Executor:** default

**Isolation:** shared

**Delegation:** in-session

**Blocked by:** Iteration 1

#### Iteration 3 — Render a redacted Langfuse export

**Goal:** Deliver token-diet metrics export --dry-run, which renders one reviewable aggregate Langfuse payload per complete receipt without egress.

**Shippable on its own?** Yes — operators can inspect the data boundary before allowing network traffic.

**Source references:**
- ../langfuse-bridge-mcp/src/langfuse_bridge_mcp/shipper.py — verify current supported SDK integration before selecting the adapter.
- ../langfuse-bridge-mcp/pyproject.toml — verify compatible SDK packaging.
- scripts/lib/tdmetrics.py — map validated evidence only.

**Files touched:**
- scripts/lib/tdmetrics_langfuse.py (new)
- scripts/lib/tdmetrics.py (modified)
- scripts/token-diet (modified)
- scripts/install.sh (modified)
- tests/test_tdmetrics_langfuse.py (new)
- tests/token-diet.bats (modified)

**Commit message:**
feat(metrics): render redacted Langfuse task payloads

**TDD cycle:**
- RED (failing tests to write first):
  - tests/test_tdmetrics_langfuse.py::test_maps_actual_usage_and_rtk_estimate_without_conflating_them — preserves provenance.
  - tests/test_tdmetrics_langfuse.py::test_payload_excludes_prompts_paths_credentials_and_tool_results — enforces egress allowlist.
  - tests/test_tdmetrics_langfuse.py::test_dry_run_never_calls_transport — proves no egress.
- GREEN (minimal implementation to pass RED):
  - Build an adapter against the rechecked bridge-compatible SDK contract.
  - Emit hashed run ID, source, model, actual usage/cost, RTK estimate, duration, and binary outcome only.
  - Make dry-run default; resolve credentials only during explicit send.
- REFACTOR (cleanup planned after GREEN):
  - Separate payload mapping from transport and centralize egress allowlist.

**Test pyramid for this iteration:**
- Smoke: token-diet metrics export --dry-run returns one sanitized fixture payload.
- Unit: seven tests for mapping, omission, provenance, dry-run, and transport failures.
- Integration: Bats fake-state CLI flow proves no network command is invoked.
- State machine: N/A — export eligibility is a final receipt predicate.
- Contract: payload snapshot is updated only after the sibling SDK contract is reverified.
- Regression: dry-run transport-call guard.
- Chaos: missing SDK, missing credential names, and timeout fail loudly without changing receipt data.
- E2E: N/A — live egress needs explicit approval.
- Performance: N/A — batch export is deferred.
- TDD Parity: 100% of payload/dry-run behavior begins RED.
- Coverage: baseline unknown; measure new module branches after approval.

**Deploy + validate:**
- Install: bash scripts/install.sh --local from repository root, only after approval and SDK packaging confirmation.
- Validate: python3 -m pytest tests/test_tdmetrics.py tests/test_tdmetrics_langfuse.py -q and bats tests/token-diet.bats from repository root; no network dependency.
- Rollback: remove adapter and installer entry; local receipts remain untouched.

**Side-effect fence:** repository and synthetic fixtures only; no network, credentials, or changes to sibling repositories.

**Checkpoint evidence:** reviewed SDK revision, payload snapshot, zero transport calls, and affected files.

**Acceptance criteria (binary):**
- [ ] Dry-run represents actual usage and RTK estimates as distinct measurements.
- [ ] Dry-run payload excludes prohibited fields.
- [ ] Missing SDK or runtime configuration exits non-zero without altering receipts.

**Estimated effort:** S (2h; basis: external SDK contract, payload boundary, and transport isolation).

**Executor:** default

**Isolation:** shared

**Delegation:** in-session

**Blocked by:** Iteration 2

#### Iteration 4 — Opt in and prove one synthetic export

**Goal:** Deliver an explicit --send path and prove one synthetic completed receipt appears in langfuse-token-diet with expected aggregate fields.

**Shippable on its own?** Yes — it closes the opt-in end-to-end path while preserving dry-run by default.

**Source references:**
- ../langfuse-ops/README.md — confirm existing host and no new deployment.
- ../langfuse-bridge-mcp/src/langfuse_bridge_mcp/trace_builder.py — retain metadata-only bridge scope.
- scripts/lib/tdmetrics_langfuse.py — reverify payload and transport before enabling send.

**Files touched:**
- scripts/lib/tdmetrics_langfuse.py (modified)
- scripts/token-diet (modified)
- tests/test_tdmetrics_langfuse.py (modified)
- tests/token-diet.bats (modified)
- docs/benchmarks.md (modified)

**Commit message:**
feat(metrics): opt in to Langfuse task export

**TDD cycle:**
- RED (failing tests to write first):
  - tests/test_tdmetrics_langfuse.py::test_send_requires_explicit_flag_and_complete_receipt — default stays dry-run.
  - tests/test_tdmetrics_langfuse.py::test_send_retries_no_more_than_once_and_preserves_receipt — bounded failure behavior.
  - tests/token-diet.bats send flag case — clear refusal without --send.
- GREEN (minimal implementation to pass RED):
  - Require --send, complete receipt, and runtime credentials.
  - Use one bounded retry and report hashed run ID plus safe status only.
  - Update benchmark documentation: provider/SDK values are recorded; RTK is estimated; quality is task verification.
- REFACTOR (cleanup planned after GREEN):
  - Collapse duplicate send preconditions into one eligibility function.

**Test pyramid for this iteration:**
- Smoke: fake transport accepts one sanitized payload only with --send.
- Unit: five tests for opt-in, preconditions, retry limit, receipt preservation, and safe errors.
- Integration: fake Langfuse transport plus CLI flag behavior.
- State machine: N/A — no local service state transition.
- Contract: fake transport receives the approved aggregate payload once.
- Regression: no-send remains network-free.
- Chaos: timeout then success retries once; permanent failure retains the receipt.
- E2E: with separate explicit network approval, export one synthetic receipt and verify aggregate tokens, cost, and outcome in the Langfuse UI.
- Performance: N/A — one synthetic receipt only.
- TDD Parity: all send behavior has RED/GREEN evidence; live UI proof is supplemental.
- Coverage: baseline unknown; report measured branch coverage after approval.

**Deploy + validate:**
- Install: bash scripts/install.sh --local from repository root, only after approval.
- Validate: python3 -m pytest tests/test_tdmetrics.py tests/test_tdmetrics_langfuse.py -q and bats tests/token-diet.bats tests/install.bats; then, only with explicit network approval, token-diet metrics export --send --run-id synthetic-smoke.
- Rollback: omit --send or remove runtime credential injection; code rollback touches only this iteration.

**Side-effect fence:** fake transport and temporary state by default; the live project is contacted only for approved synthetic data.

**Checkpoint evidence:** fake-transport log, synthetic run hash, Langfuse aggregate confirmation, and no secret-bearing output.

**Acceptance criteria (binary):**
- [ ] Export makes no network call without --send.
- [ ] Fake transport receives exactly one redacted payload for a complete receipt.
- [ ] With explicit approval, one synthetic receipt appears in langfuse-token-diet with matching aggregate usage, cost, and outcome.

**Estimated effort:** S (2h plus approval wait; basis: opt-in egress, failure handling, and synthetic end-to-end proof).

**Executor:** default

**Isolation:** shared

**Delegation:** in-session

**Blocked by:** Iteration 3 and owner creation of langfuse-token-diet

## 4. Test inventory summary

| Iter | Smoke | Unit | Integration | State machine | Contract | Regression | Chaos | E2E | Performance | TDD Parity | Coverage Δ |
|------|-------|------|-------------|---------------|----------|------------|-------|-----|-------------|------------|------------|
| 1 | 1 | 6 | 1 | N/A | 1 | 1 | 2 | N/A | N/A | 100% | unknown |
| 2 | 1 | 5 | 1 | N/A | 1 | 1 | 2 | N/A | N/A | 100% | unknown |
| 3 | 1 | 7 | 1 | N/A | 1 | 1 | 3 | N/A | N/A | 100% | unknown |
| 4 | 1 | 5 | 1 | N/A | 1 | 1 | 2 | 1 | N/A | 100% | unknown |

## 4b. Effort summary

| Iter | Size | Duration | Basis |
|------|------|----------|-------|
| 1 | S | 2h | schema, CLI, installer, and test layers |
| 2 | S | 2h | durable idempotent state and CLI integration |
| 3 | S | 2h | SDK contract and egress boundary |
| 4 | S | 2h plus approval wait | opt-in send and synthetic proof |

**Estimated total:** 8h of implementation work plus external approval/wait. Slices cannot overlap because they share the receipt schema and CLI dispatch.

## 5. End-to-end definition of done

- [ ] Validation rejects malformed, secret-bearing, and provenance-invalid receipts.
- [ ] Record creates one idempotent redacted local receipt per run ID.
- [ ] Dry-run makes no network call and renders only approved aggregate fields.
- [ ] Send requires explicit opt-in and succeeds for an approved synthetic receipt.
- [ ] Langfuse shows provider/SDK values, RTK estimate, and binary outcome without prompts, paths, tool results, or credentials.

Manual demo: create a synthetic complete receipt, validate it, record it under temporary XDG state, inspect dry-run, then with explicit approval send it once and verify aggregate fields in langfuse-token-diet.

Required end-state commands after approval: python3 -m pytest tests/test_tdmetrics.py tests/test_tdmetrics_langfuse.py -q; bats tests/token-diet.bats tests/install.bats; and the approved synthetic token-diet metrics export --send --run-id synthetic-smoke.

## 6. Out of scope

- Automatic provider billing imports — each provider needs separate authentication and invoice semantics.
- Automatic Codex usage capture — current session data is not provider-issued billing evidence.
- Batch export, queues, and daemons — defer until one-receipt export is measured.
- Changes to langfuse-bridge-mcp — it remains metadata-only by privacy contract.
- Changes to langfuse-ops or agent-observability-plane — hosting and shared dashboard work are independent.
- Multi-project AOP views — defer until langfuse-token-diet has stable useful data.

## 7. Open questions

- Support Claude Code SDK receipts first only, or add another provider receipt format?
- Which existing secret-manager path injects langfuse-token-diet runtime keys?
- Does deployed Langfuse accept the bridge-compatible SDK generation model unchanged? Reconfirm before iteration 3.

