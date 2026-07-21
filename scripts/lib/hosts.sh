#!/usr/bin/env bash
# hosts.sh — shared shell library for token-diet.
#
# Sourced by BOTH entry points, from DIFFERENT paths:
#   - scripts/install.sh sources it from the repo checkout at install time
#   - the installed token-diet sources it from its own $SCRIPT_DIR/lib at runtime
# It must therefore never assume where it lives or what its caller's cwd is.
#
# Phase 5 Iteration 1 ships this file with no consumers on purpose: the
# install/uninstall plumbing lands and is proved green before anything depends
# on it. See docs/PLAN-phase5-host-registry.md.

TD_HOSTS_LIB_VERSION="2"

# Sourcing marker for consumers that need to verify the lib actually loaded
# rather than silently falling through to an unset variable.
td_hosts_lib_loaded() {
  return 0
}

# The single definition of the supported AI hosts. Order is significant: it is
# the order every consumer reports and prompts in, so changing it changes user
# -visible output.
#
# Encoded as "slug|label" in a plain indexed array rather than an associative
# array, because associative arrays need bash 4 and macOS still ships bash 3.2.
# No other file in this repo uses `declare -A`; do not be the first.
#
# Adding a host means adding ONE line here. As of Iteration 2 only the
# slugs/labels site in install.sh reads this; five other enumerations are still
# hardcoded and must be converted before that promise is fully true.
TD_HOSTS=(
  "claude|Claude Code"
  "codex|Codex CLI"
  "opencode|OpenCode"
  "copilot|Copilot CLI"
  "vscode|VS Code"
  "cowork|Cowork (Desktop)"
  "gemini|Gemini CLI"
)

# One slug per line. Labels contain spaces, so callers must read line-by-line
# rather than word-split.
td_host_slugs() {
  local entry
  for entry in "${TD_HOSTS[@]}"; do
    printf '%s\n' "${entry%%|*}"
  done
}

# One label per line, index-aligned with td_host_slugs.
td_host_labels() {
  local entry
  for entry in "${TD_HOSTS[@]}"; do
    printf '%s\n' "${entry#*|}"
  done
}

# Print the HOME-relative config file paths that the canonical MCP-host registry
# (config/hosts-mcp.json) records for <host>, one per line, in registry order.
#
# Reads the `home_configs` array. The registry path is passed IN by the caller,
# never assumed here: install.sh passes its repo copy
# ($PROJECT_ROOT/config/hosts-mcp.json); the installed token-diet passes its own
# ($SCRIPT_DIR/../config/hosts-mcp.json). This keeps the lib decoupled from where
# it lives (Strict Installation Decoupling).
#
# Returns non-zero and prints nothing when python3 is missing, the registry is
# absent/malformed, or the host has no entries, so callers can fall back to their
# previous hardcoded paths without changing behavior.
td_host_config_paths() {
  local registry="$1" host="$2"
  [ -f "$registry" ] || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$registry" "$host" <<'PY' || return 1
import json, sys
registry, host = sys.argv[1], sys.argv[2]
try:
    with open(registry, encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    sys.exit(1)
paths = [e["path"] for e in data.get("home_configs", [])
         if e.get("host") == host and e.get("path")]
if not paths:
    sys.exit(1)
for p in paths:
    print(p)
PY
}
