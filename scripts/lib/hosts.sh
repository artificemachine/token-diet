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
