# Branch protection for `main`

As of 2026-07-20, `main` has **no branch protection**. The API returns
`Branch not protected`. Three CI gates run on every PR and none of them can
block a merge:

| Check | Job name (the required-check "context") | Currently |
|---|---|---|
| Tests | `bats + pytest` | reports only |
| Secret scan | `gitleaks` | reports only |
| Path leak guard | `Path Leak Guard` | reports only |

That is a claim/reality gap: the repo presents as gated and is not. A red run
merges exactly as easily as a green one.

## Apply it

Requires admin on the repo. The payload below is deliberately conservative.

```bash
gh api -X PUT repos/artificemachine/token-diet/branches/main/protection \
  --input docs/branch-protection.json
```

The accompanying `branch-protection.json`:

```json
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["bats + pytest", "gitleaks", "Path Leak Guard"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
```

## Why these specific settings

**`enforce_admins: false`** — deliberate, and the most important field here.
This is a solo-maintained repo. With `enforce_admins: true` and no second
reviewer available, an admin who needs to land an urgent fix has no path
forward except disabling protection, which is worse than not having had it.
False keeps the gates real for normal work while leaving an explicit,
deliberate override.

**`required_pull_request_reviews: null`** — a solo repo cannot satisfy a
required-reviewer rule. Setting it would block every merge permanently. The PR
workflow itself is already enforced by convention and by the global pre-commit
hook's main-branch guard.

**`strict: true`** — a PR must be up to date with `main` before merging, so a
green check on a stale base cannot mask a conflict-driven breakage.

**`allow_force_pushes: false` / `allow_deletions: false`** — matches the
standing rule that `main` is never force-pushed.

## Verify after applying

```bash
gh api repos/artificemachine/token-diet/branches/main/protection \
  --jq '.required_status_checks.contexts'
```

Expect the three contexts above. Then confirm it actually blocks: open a
throwaway PR that fails one check and verify the merge button is unavailable.
**Do not skip that step.** A protection rule whose check names do not exactly
match the job names silently protects nothing, which is the same failure mode
as the path-leak guard that could not fail and the release gate that could not
run.

## Check-name coupling

The `contexts` strings must match the workflow **job names** exactly. Renaming
a job in `.github/workflows/*.yml` without updating the protection payload
silently drops that gate. Current mapping:

| Workflow file | `jobs.<id>.name` | Context string |
|---|---|---|
| `test.yml` | `bats + pytest` | `bats + pytest` |
| `gitleaks.yml` | `gitleaks` | `gitleaks` |
| `path-leak.yml` | `Path Leak Guard` | `Path Leak Guard` |
