#!/usr/bin/env bash
# ctxwarn-post.sh — Claude Code PostToolUse hook shim for ctxwarn.
#
# Installed to ~/.local/bin/token-diet-hooks/ by `install.sh --with-context-hooks`
# (never run from this repo checkout — see the Strict Installation Decoupling
# rule in CLAUDE.md). Registered on the "*" matcher.
#
# Reads the session transcript path from the hook payload and forwards it to
# `token-diet budget --check`, printing its stdout verbatim. That subcommand
# already always exits 0 and already debounces repeat warnings — this shim
# adds no logic beyond payload parsing, and never fails the turn on any error.
set -uo pipefail

command -v token-diet >/dev/null 2>&1 || exit 0

payload="$(cat)"
transcript_path="$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get("transcript_path", ""))
except Exception:
    print("")
' 2>/dev/null)"
[ -n "${transcript_path:-}" ] || exit 0

token-diet budget --check --transcript "$transcript_path" 2>/dev/null
exit 0
