#!/usr/bin/env bash
# path-leak-scan.sh — server-side mirror of ~/.githooks/pre-commit check 1d.
#
# Scans the ADDED lines of a PR diff for hardcoded local-machine paths and
# usernames. Local pre-commit hooks never run on a PR merged through the
# GitHub API, and they don't run on external contributors' machines at all,
# so this is the only layer that can catch a path leak arriving via a fork PR.
#
# Exit 0 = clean, exit 1 = leak found (fails the check). Reads only the diff;
# never needs secrets. Pair with `on: pull_request` (NOT pull_request_target).
set -euo pipefail

BASE_SHA="${BASE_SHA:-}"
HEAD_SHA="${HEAD_SHA:-HEAD}"

if [ -z "$BASE_SHA" ]; then
  echo "BASE_SHA not set; cannot compute the PR diff range." >&2
  exit 1
fi

# Files that legitimately reference example/home paths. The scanner itself and
# the changelog are exempt; everything else (code, config, .vscode) is scanned.
SKIP_PATTERNS='(^CHANGELOG\.md$|\.github/scripts/path-leak-scan\.sh$)'

# Patterns that indicate a hardcoded local-machine reference.
# Note: \\+ tolerates JSON-escaped Windows paths (C:\\Users\\) as well as raw.
# We deliberately do NOT flag ~/ paths — ~/.local/bin is the recommended target.
LOCAL_PATH_PATTERNS=(
  '/Users/[A-Za-z0-9._-]+/(Documents|Desktop|Downloads|Library|\.local)'  # macOS personal/home
  '/home/[A-Za-z0-9._-]+/(Documents|Desktop|Downloads|\.local)'           # Linux personal/home
  'C:\\+Users\\+[A-Za-z0-9._-]+'                                          # Windows home dir
)

mapfile -t FILES < <(git diff --name-only "$BASE_SHA" "$HEAD_SHA")

FAILED=0
for file in "${FILES[@]}"; do
  [ -z "$file" ] && continue
  echo "$file" | grep -qE "$SKIP_PATTERNS" && continue

  # Only inspect added lines (leading '+', excluding the '+++' file header).
  added=$(git diff "$BASE_SHA" "$HEAD_SHA" -- "$file" \
            | grep -E '^\+' | grep -v '^+++' || true)
  [ -z "$added" ] && continue

  for pattern in "${LOCAL_PATH_PATTERNS[@]}"; do
    if echo "$added" | grep -qE -- "$pattern"; then
      n=$(echo "$added" | grep -cE -- "$pattern")
      echo "::error file=${file}::Hardcoded local path detected (pattern: ${pattern}, ${n} occurrence(s))"
      FAILED=1
    fi
  done
done

if [ "$FAILED" -ne 0 ]; then
  echo ""
  echo "Path Leak Guard FAILED. Remove hardcoded home/user paths from the added lines."
  echo "Use a bare command name (relies on PATH), \$HOME, or a repo-relative path instead."
  exit 1
fi

echo "Path Leak Guard: no hardcoded local paths in added lines."
