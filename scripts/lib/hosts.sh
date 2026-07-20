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

TD_HOSTS_LIB_VERSION="1"

# Sourcing marker for consumers that need to verify the lib actually loaded
# rather than silently falling through to an unset variable.
td_hosts_lib_loaded() {
  return 0
}
