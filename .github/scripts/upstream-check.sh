#!/usr/bin/env bash
# upstream-check.sh — detection-only upstream drift check for the pinned forks
# in forks/ (rtk, tilth, serena, icm).
#
# This never merges anything. It only reports whether the original authors'
# repos have commits our pinned submodule doesn't have yet. Merging stays a
# manual, reviewed step (`token-diet upstream diff <tool>` + manual merge) —
# see CLAUDE.md: "Submodule forks in forks/ are pinned — never update them
# automatically."
#
# Output: writes a markdown report to $GITHUB_STEP_SUMMARY (if set) and to
# stdout. Sets $STATE_FILE key `drift=true|false` for the calling workflow.
set -euo pipefail

FORKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../forks" && pwd)"
STATE_FILE="${GITHUB_OUTPUT:-/dev/null}"

declare -A UPSTREAM_URLS=(
  [rtk]="https://github.com/rtk-ai/rtk.git"
  [tilth]="https://github.com/jahala/tilth.git"
  [serena]="https://github.com/oraios/serena.git"
  [icm]="https://github.com/rtk-ai/icm.git"
)

REPORT=""
DRIFT=false

for tool in rtk tilth serena icm; do
  dir="$FORKS_DIR/$tool"
  url="${UPSTREAM_URLS[$tool]}"

  if [ ! -d "$dir" ]; then
    REPORT+=$'\n'"### ${tool}"$'\n'"- submodule not checked out, skipped."$'\n'
    continue
  fi

  (cd "$dir" && (git remote add upstream "$url" 2>/dev/null || git remote set-url upstream "$url"))
  branch="main"
  if ! (cd "$dir" && git fetch upstream main --quiet 2>/dev/null); then
    branch="master"
    (cd "$dir" && git fetch upstream master --quiet 2>/dev/null) || true
  fi

  new_commits="$(cd "$dir" && git log --oneline "HEAD..upstream/$branch" 2>/dev/null || true)"

  if [ -n "$new_commits" ]; then
    DRIFT=true
    count=$(echo "$new_commits" | wc -l | tr -d ' ')
    REPORT+=$'\n'"### ${tool} — ${count} new commit(s) upstream ($url, ${branch})"$'\n'
    REPORT+='```'$'\n'"$new_commits"$'\n''```'$'\n'
    REPORT+="Audit: \`token-diet upstream diff ${tool}\`. Merge manually, re-verify security patches."$'\n'
  else
    REPORT+=$'\n'"### ${tool}"$'\n'"- up to date with $url ($branch)."$'\n'
  fi
done

echo "$REPORT"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "$REPORT" >> "$GITHUB_STEP_SUMMARY"
fi

{
  echo "drift=$DRIFT"
  echo "report<<UPSTREAM_REPORT_EOF"
  echo "$REPORT"
  echo "UPSTREAM_REPORT_EOF"
} >> "$STATE_FILE"
