# golive progress — token-diet

Resume state for `/golive`. One entry per stage, newest state wins.

## Stage 1 — Recruiter First-Impression Gate: NEEDS WORK (2026-07-22)
- verdict: clean except commit-history author metadata (internal hostname + 2 personal emails, no live secret)
- blockers: 0
- evidence: gitleaks 198 commits/no leaks; git log --all author-email grep; gh repo view
- duration: 8

## Stage 2 — Git History & Release Hygiene: PASS (2026-07-22)
- verdict: branches/tags/releases/versioning clean and policy-documented; identity-correlation finding reinforces Stage 1
- blockers: 0
- evidence: gh api branches/contributors; git log --merges --all; TD_VERSION spot-check at 4 tag boundaries
- duration: 14

## Stage 3 — README + Docs: NEEDS WORK (2026-07-22)
- verdict: README READY; docs/ content review found 3 HIGH stale-doc findings + a real personal-path-in-history finding correcting Stage 1
- blockers: 0
- evidence: /readme-audit inline run, /docs-organize inline run, subagent docs content review (spot-verified HIGH findings independently), git-history blob content scan
- duration: 26

## Stage 4 — Fresh-Clone Verification + Dependency Health: PASS (2026-07-22)
- verdict: real fresh clone works verbatim per README; 278 bats + 72 pytest both green from a truly fresh clone; 3 real CVEs in fork transitive deps (fixable, low-cost) + stale/wrong-URL compliance doc
- blockers: 0
- evidence: git clone --recursive transcript, cargo audit on all 3 fork Cargo.lock files, pip-audit, dependabot.yml review
- duration: 34

## Stage 5 — Hardening Pipeline: IN PROGRESS (2026-07-22)
- verdict: NEEDS WORK overall — security NEEDS WORK/minor, threat_model SKIPPED, code_quality NEEDS WORK/2 CRITICAL verified, qa_coverage READY WITH WARNINGS, ux Adopt-with-caveats, simplify issues-found, docker PUBLISH-READY
- blockers: 0 live secrets; 2 CRITICAL code defects (dead dashboard alert feature, uninstall.sh crash-with-traceback + no ERR trap) that would block a strict gauntlet run
- evidence: 6 parallel subagents each running the underlying skill directly (not via gauntlet's loop-fix orchestrator); top findings independently re-verified against source
- duration: 42

## Stage 7 — CI/CD Governance: NEEDS WORK (2026-07-22)
- verdict: ci-gate clean; release.yml has no test-gating dependency (HIGH, verified, matches this session's own release.sh WARN-not-FAIL experience); branch protection cross-referenced from Stage 3 (enabled)
- blockers: 0
- evidence: direct read of release.yml trigger block, gh api rulesets (empty), release.sh grep for record_warn/record_fail
- duration: 12

## Stage 7b — Conditional Deployment & Installability: NEEDS HELP (2026-07-22)
- verdict: live-deployment probe N/A; app-claude-installable NEEDS HELP (2 P0s: unguarded interactive wizard on bare install.sh, token-diet MCP entry invisible to `claude mcp list`); mcp-installable findings folded into same P0 table
- blockers: 0
- evidence: source read of run_wizard()/confirm_hosts() TTY guards, live `claude mcp list` check, cross-referenced against this session's own release.sh prompt-hang incident
- duration: 18

## Stage 6 — Architecture: NEEDS HARDENING (2026-07-22)
- verdict: partial adoption of the project's own abstractions (hosts.sh not sourced by token-diet, tdconfig.py used at only 2/13 sites, 3-language config schema drift, decorative schema field, race condition, logging asymmetry, missing pyproject.toml)
- blockers: 0
- evidence: source greps independently re-verified, one count corrected (tdconfig import sites 1→2)
- duration: 46

## Stage 8 — Claims vs Reality: NEEDS WORK (2026-07-22)
- verdict: 5 new claim-vs-reality mismatches beyond the 12 already found; most serious finding of the whole audit: compliance/security-audit.md falsely claims RTK/Serena telemetry is "stripped" when it's dormant-but-present code
- blockers: 0 (no live secret, no active phoning-home — telemetry is genuinely disabled by default, just mischaracterized)
- evidence: forks/rtk/src/core/telemetry.rs read directly (606 lines, live ureq::post call), README test counts re-confirmed against this session's own measurements
- duration: 38

## Stage 9 — Final Scorecard: NOT READY (2026-07-22)
- verdict: NOT READY — driven by personal-data-in-history hard gate, compounded by 2 CRITICAL code defects, a false security-compliance claim, and an ungated release pipeline
- blockers: 0 live secrets; 1 personal-data-leak hard gate; 2 CRITICAL code defects
- evidence: full 9-stage report at docs/audits/2026-07-22-golive.md, machine-readable at docs/audits/2026-07-22-golive.json
- duration: 8
