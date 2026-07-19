#!/usr/bin/env bash
# docextract-pre-read.sh — Claude Code PreToolUse hook shim for docextract.
#
# Installed to ~/.local/bin/token-diet-hooks/ by `install.sh --with-context-hooks`
# (never run from this repo checkout — see the Strict Installation Decoupling
# rule in CLAUDE.md). Registered on the "Read" matcher.
#
# Intercepts Read calls on extractable document types (pdf/csv/html/htm/txt/md),
# extracts to a cached plain-text file via `token-diet extract`, and blocks the
# original Read (exit 2, Claude Code's block-and-feed-stderr-as-reason contract)
# so Claude reads the cheap extracted text instead. Never blocks without a
# usable replacement already in hand — every other suffix, or any extraction
# failure, passes through untouched (exit 0, the original Read proceeds).
#
# No `set -e`: a hook shim crashing uncontrolled is worse than one that
# computes a slightly wrong value but always reaches an explicit exit.
set -uo pipefail

command -v token-diet >/dev/null 2>&1 || exit 0

payload="$(cat)"
file_path="$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get("tool_input", {}).get("file_path", ""))
except Exception:
    print("")
' 2>/dev/null)"
[ -n "${file_path:-}" ] || exit 0

suffix_lower="$(printf '%s' "${file_path##*.}" | tr '[:upper:]' '[:lower:]')"
case ".$suffix_lower" in
  .pdf | .csv | .html | .htm | .txt | .md) ;;
  *) exit 0 ;;
esac

cache_path="$(token-diet extract "$file_path" 2>/dev/null)"
extract_status=$?
[ "$extract_status" -eq 0 ] && [ -n "${cache_path:-}" ] || exit 0

echo "Extracted to $cache_path — read that file instead of the original." >&2
exit 2
