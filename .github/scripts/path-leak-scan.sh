#!/usr/bin/env bash
# path-leak-scan.sh — server-side mirror of ~/.githooks/pre-commit check 1d.
#
# Scans the ADDED lines of a PR diff for hardcoded local-machine paths and
# usernames. Local pre-commit hooks never run on a PR merged through the
# GitHub API, and they don't run on external contributors' machines at all,
# so this is the only layer that can catch a path leak arriving via a fork PR.
#
# Exit 0 = clean, exit 1 = leak found (fails the check). Reads only the diff;
# never needs secrets. Pair with the plain `on: pull_request` trigger, never
# the riskier "target" variant that runs with base-branch secrets.
set -euo pipefail

BASE_SHA="${BASE_SHA:-}"
HEAD_SHA="${HEAD_SHA:-HEAD}"

# BASE_SHA is only required for diff mode. --full-tree scans tracked files
# directly and needs no diff range, so its check happens after SKIP_PATTERNS
# is defined below.
if [ "${1:-}" != "--full-tree" ] && [ -z "$BASE_SHA" ]; then
  echo "BASE_SHA not set; cannot compute the PR diff range." >&2
  exit 1
fi

# Files that legitimately reference example/home paths. The scanner itself and
# the changelog are exempt; everything else (code, config, .vscode) is scanned.
# tests/path-leak.bats is exempt for the same reason the scanner itself is:
# its fixtures deliberately contain planted home paths, because a guard that is
# only ever observed passing has not been observed working.
SKIP_PATTERNS='(^CHANGELOG\.md$|\.github/scripts/path-leak-scan\.sh$|^tests/path-leak\.bats$)'

# Patterns that indicate a hardcoded local-machine reference.
# Note: \\+ tolerates JSON-escaped Windows paths (C:\\Users\\) as well as raw.
# We deliberately do NOT flag ~/ paths — ~/.local/bin is the recommended target.
LOCAL_PATH_PATTERNS=(
  '/Users/[A-Za-z0-9._-]+/(Documents|Desktop|Downloads|Library|\.local)'  # macOS personal/home
  '/home/[A-Za-z0-9._-]+/(Documents|Desktop|Downloads|\.local)'           # Linux personal/home
  'C:\\+Users\\+[A-Za-z0-9._-]+'                                          # Windows home dir
)

# Full-tree mode uses a BROADER pattern. The diff patterns above only fire on a
# known subdirectory (Documents|Desktop|...|.local), so a path like
# /Users/<name>/Projects/foo slips through them entirely — which is exactly how
# a home path reached a committed file despite this guard being green on every
# PR. Full-tree mode therefore flags any /Users/<name>/ or /home/<name>/ that
# isn't an obvious documentation placeholder.
# --full-tree scans every tracked file's full content, not just a PR diff.
# Use it to catch leaks that predate this guard or that arrived outside a PR.
#
# Implemented in python3, not grep: the negative-lookahead needed to exempt
# placeholder usernames requires PCRE, and `grep -P` does not exist in BSD grep
# on macOS. A `grep -qP ... 2>/dev/null` version of this silently matched
# nothing locally while working in CI — i.e. it passed without ever checking.
# python3 is already a hard dependency of this project.
if [ "${1:-}" = "--full-tree" ]; then
  python3 - "$SKIP_PATTERNS" <<'PYEOF'
import re, subprocess, sys

skip_re = re.compile(sys.argv[1])
placeholders = {
    "alice", "bob", "carol", "dave", "user", "username", "you", "me",
    "example", "mock", "test", "runner", "ubuntu", "root", "home",
}
patterns = [
    re.compile(r"/Users/([A-Za-z0-9._-]+)/"),
    re.compile(r"/home/([A-Za-z0-9._-]+)/"),
    re.compile(r"C:\\+Users\\+([A-Za-z0-9._-]+)"),
]

files = subprocess.run(
    ["git", "ls-files"], capture_output=True, text=True, check=True
).stdout.splitlines()

failed = False
for path in files:
    if not path or skip_re.search(path):
        continue
    try:
        text = open(path, encoding="utf-8", errors="ignore").read()
    except OSError:
        continue
    hits = []
    for pat in patterns:
        for m in pat.finditer(text):
            user = m.group(1)
            # A leading dot means we matched a directory, not a username --
            # e.g. "/mock/home/.cache/..." yields ".cache". Real usernames
            # don't start with a dot.
            if user.startswith("."):
                continue
            if user.lower() in placeholders:
                continue
            hits.append(m.group(0))
    if hits:
        uniq = sorted(set(hits))
        print(
            f"::error file={path}::Hardcoded local path in tracked file "
            f"({len(hits)} occurrence(s)): {', '.join(uniq[:3])}"
        )
        failed = True

if failed:
    print("")
    print("Path Leak Guard (full tree) FAILED. Remove hardcoded home/user paths.")
    print("Use a bare command name (relies on PATH), $HOME, or a repo-relative path.")
    sys.exit(1)
print("Path Leak Guard (full tree): no hardcoded local paths in tracked files.")
PYEOF
  exit $?
fi

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
