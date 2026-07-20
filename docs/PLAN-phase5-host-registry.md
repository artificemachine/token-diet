# PLAN — Phase 5: single host registry

**Created:** 2026-07-20
**Status:** not started
**Prerequisite:** read `docs/PLAN-production-ready.md` §5 first.

Facts here are stated as recipes, never line numbers. Re-derive before acting.
See `notes/compounding/lessons/2026-07-20-documented-facts-need-generators.md`.

---

## The actual problem

The 7-host list is enumerated **six times in `install.sh`**, plus again in
`scripts/token-diet` and `scripts/Install.ps1`. Verify:

```bash
grep -n 'HAS_[A-Z]' scripts/install.sh          # init, detection, reporting, accessor, disable
grep -n 'local slugs=' scripts/install.sh       # parallel slugs/labels arrays
```

The six sites are: `HAS_*` initialization, binary detection, found/not-found
reporting, slug→bool accessor, slug→disable, and the parallel `slugs`/`labels`
arrays. They desync silently — adding an eighth host means editing six places
and nothing fails if you miss one.

Secondary: `codex_mcp_command()` and `mcp_command_exists()` are duplicated
across both entry points. **Near-identical, not byte-identical** — they diverge
on the helper they call (`check_command` vs `check_cmd`), so a naive
copy-paste dedup silently breaks one caller. Verify:

```bash
grep -n 'codex_mcp_command()\|mcp_command_exists()' scripts/install.sh scripts/token-diet
```

## The design decision the original audit never raises

**A shared shell lib cannot live only in the repo.**

`CLAUDE.md` §"Strict Installation Decoupling": once installed, the binary must
never depend on the repo path. The installed `token-diet` runs from
`~/.local/bin`, so `source "$SCRIPT_DIR/lib/hosts.sh"` resolves to
`~/.local/bin/lib/hosts.sh` — which only exists if the installer puts it there.

This is exactly how `cmd_extract` shipped broken in v1.14.0: a new Python core
was added to `scripts/lib/` and omitted from the installer's copy manifest, so
every test passed from the dev checkout and the installed binary failed for
every user.

**Therefore, before any extraction:**

1. `install.sh` must copy `scripts/lib/*.sh` to `$bin_dir/lib/` alongside the
   Python cores (find the existing loop with
   `grep -n 'for py_core in' scripts/install.sh`).
2. `uninstall.sh` must remove them symmetrically.
3. A regression must run the **installed** binary, not `$SCRIPTS_DIR/token-diet`
   — the v1.14.0 lesson. Copy the pattern from the existing installed-binary
   tests in `tests/install.bats`.
4. `install.sh` itself sources the lib from the **repo** at install time, while
   `token-diet` sources it from **its own** `$SCRIPT_DIR/lib` at runtime. Those
   are different paths; the lib must not assume either.

Note `scripts/lib/` currently contains **no shell files at all** — this creates
the seam that `CLAUDE.md` has been wrongly claiming exists.

---

## Iteration 1 — install/uninstall the shell lib (no behavior change)

Ship the plumbing before anything depends on it.

- **RED:** bats test asserting `~/.local/bin/lib/hosts.sh` exists after install,
  and is gone after uninstall. Fails today.
- **GREEN:** create `scripts/lib/hosts.sh` containing only a version marker and
  a no-op function. Extend the installer's core-copy loop and `uninstall.sh`.
- **REFACTOR:** none.
- **Exit:** installed-binary test green; nothing sources the lib yet.

Shipping this alone is safe and reversible.

## Iteration 2 — the registry, consumed by ONE site

- **RED:** test that the registry lists exactly 7 hosts and that every slug has
  a label; test that `install.sh`'s reporting output is byte-identical before
  and after.
- **GREEN:** define the registry once in `hosts.sh` (slug, label, detect
  command). Rewrite **only** the `slugs`/`labels` array site to read from it.
- **REFACTOR:** none. One site only.
- **Exit:** full suite green, `install.sh --dry-run` output unchanged.

**Do not convert all six at once.** Convert one, ship, verify, repeat. The six
sites have subtly different semantics (init vs detect vs report vs filter) and
collapsing them in a single pass is how a silent desync becomes a silent break.

## Iterations 3-7 — one enumeration site each

Same shape per site: characterize current output, move to the registry, assert
output unchanged. Ship each independently.

Order by blast radius, lowest first: reporting → accessor → disable →
initialization → detection.

## Iteration 8 — dedupe the two functions

- **RED:** test that `codex_mcp_command` is defined exactly once across both
  entry points (mirrors the existing OQ-1 duplicate-definition tests).
- **GREEN:** move both into `hosts.sh`. **Reconcile the `check_command` vs
  `check_cmd` divergence explicitly** — pick one name, alias the other, or pass
  the checker in. Do not assume they are interchangeable.
- **Exit:** both entry points source one definition.

## Iteration 9 — Install.ps1

Windows is currently labelled experimental and runs in no workflow. Either port
the registry or explicitly document that PowerShell keeps its own list. **Decide
and write it down**; do not leave it implicit.

---

## Definition of done

```bash
# One definition of the host list
grep -c 'local slugs=' scripts/install.sh          # 0
grep -c 'HOSTS=' scripts/lib/hosts.sh              # 1

# Installed binary is self-contained
ls ~/.local/bin/lib/hosts.sh

# No duplicate functions
grep -c 'codex_mcp_command()' scripts/install.sh scripts/token-diet   # 0 and 0
```

Plus: adding an 8th host requires editing exactly one file, and a test fails if
any consumer is missed.

## Guardrails

- **Not in a long session.** This warning has survived four handoffs. It touches
  the highest-blast-radius file in the repo.
- Every iteration ships independently and ends green.
- `install.sh --dry-run` output is the characterization harness — capture it
  before touching anything and diff after each iteration.
- Every guard added must be negative-tested against planted input. See
  `notes/compounding/lessons/2026-07-20-guards-need-negative-tests.md`.
