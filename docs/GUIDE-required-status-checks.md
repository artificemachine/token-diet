# Required Status Checks — How "Refuse the Merge Button" Works

How a GitHub Actions workflow becomes an enforced merge gate, concretely for the
token-diet `Path Leak Guard`.

## The pieces and how they connect

1. **A workflow produces a "check" with a name.** `path-leak.yml` has
   `name: Path Leak Guard`. When it runs on a PR, GitHub records a status against
   the PR's latest commit: `Path Leak Guard = success | failure`. That is the
   ✅/❌ shown on the PR.

2. **Branch protection holds a list of check names that are "required."** This
   list lives on the branch (`main`), not on the workflow. If the list is empty,
   every check is informational — GitHub shows it but ignores it for merge
   decisions.

3. **Adding `"Path Leak Guard"` to the required list enforces a rule at merge
   time:** the merge button (and the `gh pr merge` API call) is refused unless
   the check named `Path Leak Guard` has reported `success` on the exact commit
   at the tip of the PR.

## The enforced flow

```
PR opened/updated  →  workflow runs  →  reports Path Leak Guard = success/failure
                                              │
              merge attempt ───────────────────┐
                                              ▼
   required list contains "Path Leak Guard"?
        ├─ check = success → merge allowed
        └─ check = failure / missing → MERGE REFUSED (button greyed, API 405)
```

## Three things that bite people

- **The name must match exactly.** Required-checks matches on the string
  `Path Leak Guard`. If the workflow is renamed, the old required entry points at
  a check that never reports → merges get stuck forever waiting on a check that
  can't pass. Renaming = update both places.

- **"Required" means it must actually run and succeed — not just "not fail."** If
  the workflow is skipped or never triggers (e.g. the `on:` trigger changes), the
  check is *missing*, and missing ≠ success → merge blocked. A required check
  that doesn't fire is a soft lock.

- **Admins can still be allowed to bypass — or not.** Branch protection has a
  separate toggle, "Do not allow bypassing the above settings / Include
  administrators." If off, a repo admin can force the merge past a red check. If
  on, even an admin is blocked.

## Summary

The workflow *reports*, the branch protection *enforces*, and the link between
them is just the check's name string.
