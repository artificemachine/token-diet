# Release policy

Canonical location for this project's tag and release retention rules.

Until v1.15.1 these rules existed only in `HANDOFF.md`, which is untracked and
gitignored, and an archived handoff stated a *different* number ("keep latest
5"). The repo therefore documented a rule it did not carry and could not be
checked against. This file is the single source of truth.

## Tags vs releases

They are deliberately different things and are retained differently.

| | Retention | Rationale |
|---|---|---|
| **Git tags** | Permanent, never pruned | Immutable history. A tag is how you check out exactly what shipped. Deleting one breaks `git checkout v1.9.0` and any external reference to it. |
| **GitHub releases** | Newest **10** | Curated, browsable surface. A release page is a human-facing artifact with notes; keeping every one turns the releases page into an unreadable wall. |

A tag with no GitHub release is **expected and not a defect**. At the time of
writing there are 72 tags and 10 releases. The 62 tags without a release page
are older versions that remain fully checkoutable.

## Retention count

`RELEASE_RETENTION` in `scripts/release.sh`, default `10`. Override for a single
run with the environment variable:

```bash
RELEASE_RETENTION=15 bash scripts/release.sh
```

## Enforcement

Retention is enforced in **two** places, and both are necessary.

**`.github/workflows/release.yml`** is the one that matters in practice. It
prunes immediately after creating a release, on every pushed `v*` tag. When
this workflow first ran (v1.15.1) the release count went straight to 11,
because the prune step existed only in `scripts/release.sh` and nothing runs
that script on the tag path. Enforcement living somewhere that never executes
is not enforcement — the same failure mode as a release gate that could not
complete a run and a path-leak guard that could not fail.

**`scripts/release.sh`** prunes automatically after the tag step. It deletes the
GitHub release only and leaves the tag in place.

- `--dry-run` reports what would be pruned without deleting anything.
- If `gh` is missing or unauthenticated, the step skips with a notice rather
  than failing the gate — retention is hygiene, not a correctness gate.
- Pruning failures are recorded as warnings, not fatal errors.

## Why this is automated

Between v1.10.x and v1.15.0 the release count drifted from the stated threshold
to 13 while the policy sat in an untracked file. Manual retention steps
documented outside the tracked tree do not survive. If the rule is worth
stating, it is worth executing.

## Version source of truth

`TD_VERSION` in `scripts/token-diet` is the only place the version is declared
for release purposes. `scripts/release.sh` derives `VERSION` from it by parsing
that line. It was previously hardcoded to `1.2.0` — thirteen minor versions
stale — which meant the gate would have created a `v1.2.0` tag on a 1.15.0 tree
had anyone run it. Do not reintroduce a literal version string in `release.sh`.

Note that `scripts/token-diet.ps1` carries its own `$script:TD_VERSION` which
must be bumped in lockstep; that is a known duplication, not a second source of
truth.
