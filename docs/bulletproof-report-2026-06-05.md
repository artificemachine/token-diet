# Bulletproof Report — token-diet

**Date:** 2026-06-05
**Mode:** general audit (no focus invariant)
**Scope:** Bash/PowerShell/Python/Rust-fork installer + compliance kit. Doctrine: `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `README.md`, `compliance/SBOM.json`. Source: `scripts/`, `.gitmodules`, `forks/`.

---

## Headline

The repo ships **four** tools (RTK + tilth + Serena + **ICM**) but its own doctrine still describes a **three-tool** stack in at least five places. ICM has a submodule, an installer function, a dispatch command, and an SBOM component — yet the prose, the structure tree, and the "all three" invariants never caught up.

---

## CLAIMS AUDITED

| Claim | Source | Verdict | Evidence |
|-------|--------|---------|----------|
| "wires RTK, tilth, and Serena together" / "stack installer for RTK + tilth + Serena" | `CLAUDE.md:3`, `CLAUDE.md:7` | **VIOLATED** | ICM is fully installed: `.gitmodules` `[submodule "forks/icm"]`; `scripts/install.sh:2` header + `:954 install_icm()`; `scripts/token-diet:2501 icm) … cmd_icm`; `forks/icm/` on disk |
| forks/ tree = rtk, tilth, serena only | `CLAUDE.md:28-30` | **VIOLATED** | `forks/icm/` and `forks/README.md` exist on disk, absent from tree |
| "Versions of all three tools" | `CLAUDE.md:82` | **VIOLATED** | Four tools; SBOM lists `icm@0.10.50` (`compliance/SBOM.json:97`) |
| "All three forks are pinned via submodules" | `CLAUDE.md:152` | **VIOLATED** | `.gitmodules` declares **four** submodules incl. `forks/icm` |
| "unified installer … for token optimization tools (RTK, tilth, Serena)" | `GEMINI.md:3` | **VIOLATED** | same ICM evidence; ICM omitted |
| SBOM app description: "…stack for RTK + tilth + Serena" | `compliance/SBOM.json:20` | **VIOLATED** (prose only) | Component list IS complete (`icm@0.10.50:97`); only the metadata description string drifts |
| "Stack: … Rust (RTK + tilth submodule forks)" | `CLAUDE.md:8` | **VIOLATED** (minor) | Omits ICM (also Rust) and Serena |
| "SBOM must be regenerated on each release" | `CLAUDE.md` conventions | **VIOLATED** (weak) | SBOM app `version: "1.0.0"` (`SBOM.json:12,19`) while project is `1.10.4` — app component hasn't tracked releases |
| Strict Installation Decoupling: "binary must NEVER depend on the local repo path for execution, configuration, or data" | `CLAUDE.md` (Strict Installation Decoupling) | **VIOLATED** (caveated) | `scripts/token-diet` `setup`/`upstream`/build subcommands resolve `"$SCRIPT_DIR/../forks/$tool"` (`:756-758`, `:784`). `SCRIPT_DIR` = script's own dir (`:16`); installed at `~/.local/bin`, `../forks` does not exist. Dev-maintenance commands that fail (degrade) post-install rather than misexecute — but they literally depend on repo layout |
| "Version … (current: 1.10.4)" | `CLAUDE.md:11` | **VERIFIED** | `scripts/token-diet:15 TD_VERSION="1.10.4"`; `scripts/token-diet.ps1:31 = '1.10.4'`; tag `v1.10.4` |

---

## HONESTY SCORE

**1 / 6 completion-&-invariant claims hold.** (VERIFIED: version. VIOLATED: 3-tool roster, all-three-forks-pinned, all-three-versions, SBOM-regen-each-release, decoupling-never-depends-on-repo-path.)

Blunt: token-diet's docs claim a three-tool stack while the code, submodules, installer, dispatcher, and SBOM all ship a fourth (ICM). The version string is the only invariant that's currently truthful.

---

## DRIFT-CLASS FINDINGS

- **Doc-drift (named-vs-disk):** the `CLAUDE.md` structure tree omits real, shipped files: `forks/icm/`, `forks/README.md`, `scripts/token-diet-mcp`, `scripts/release.sh`, `scripts/lib/`, `scripts/inventory.example.ini`. None are listed; all exist.
- **Cross-doc contradiction:** `CLAUDE.md`, `GEMINI.md`, and `SBOM.json` prose all assert a 3-tool roster; the operative truth (4 tools) lives only in `.gitmodules`, `install.sh`, `token-diet` dispatch, and the SBOM *component list*. The narrative and the mechanism disagree.
- **Admitted gap (not a false claim):** `AGENTS.md:8` `Stack: TBD` — honest placeholder, not a violation, but it's the one doc that could have been right and isn't filled in.
- **Unenforced invariant:** nothing tests that doctrine's tool roster equals the installed/submodule roster. That absence is exactly why the ICM drift survived every release through 1.10.4.
- **Stale memory (out of repo scope, FYI):** auto-memory `MEMORY.md` says "14 CLI commands, 77 tests." Actual: **26** top-level dispatch commands in `scripts/token-diet`, **153** bats `@test` + **17** Python `test_` cases. Not repo doctrine, so not scored — but it will mislead a future session.

---

## REMEDIATION

**Completeness manifest — "stack roster is consistent" (booleans that must hold):**
- `forks/<tool>/` exists for each of: rtk, tilth, serena, icm ✅ (all 4 present)
- `.gitmodules` declares a submodule for each ✅ (4 declared)
- `scripts/install.sh` has an install step for each ✅ (incl. `install_icm`)
- `scripts/token-diet` has a dispatch case for each tool's surface ✅ (`icm)` present)
- `compliance/SBOM.json` `components[]` includes each ✅ (incl. `icm@0.10.50`)
- **Doctrine prose names all 4** ❌ — `CLAUDE.md`, `GEMINI.md`, `SBOM.json` description, and the forks tree still say 3

The only false boolean is the prose. Fix is documentation, not code: add ICM to `CLAUDE.md` (`:3`, `:7`, `:8`, forks tree `:30`, `:82`, `:152`), `GEMINI.md:3`, and `SBOM.json:20`; fill `AGENTS.md:8`.

**Guard to add (plain test, no LLM) —** a doc-roster guard, e.g. `tests/test_doc_roster.py` or a `.bats` case, asserting: for every dir in `forks/` (excluding non-submodule files) and every `[submodule "forks/*"]` in `.gitmodules`, the tool name appears in `CLAUDE.md`, `GEMINI.md`, and `compliance/SBOM.json`. Fails CI the next time a fifth tool lands undocumented. (Not emitted this run — `--emit-guard` not passed. Re-run `/bulletproof --emit-guard --mutation-check` to write and self-verify it.)

---

## PROGRESS

First run — **baseline**. No prior `docs/bulletproof-*.md` found.
