#!/usr/bin/env bats
# Tests for scripts/install.sh and scripts/uninstall.sh

load test_helper

# ---------------------------------------------------------------------------
# Cycle 1.2 — install.sh: help and dry-run
# ---------------------------------------------------------------------------

@test "install.sh --help exits 0 and shows usage" {
  run bash "$SCRIPTS_DIR/install.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
  [[ "$output" == *"--dry-run"* ]]
}

@test "install.sh --dry-run prints DRY-RUN banner and exits 0" {
  mock_install_prereqs

  run bash "$SCRIPTS_DIR/install.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN"* ]]
}

@test "install.sh --dry-run does not write any files to HOME" {
  mock_install_prereqs

  run bash "$SCRIPTS_DIR/install.sh" --dry-run

  # Binaries must not be created
  [ ! -f "$TMP_HOME/.local/bin/token-diet" ]
  [ ! -f "$TMP_HOME/.local/bin/token-diet-dashboard" ]
}

# ---------------------------------------------------------------------------
# Cycle 3.1 — uninstall.sh: dry-run skeleton
# ---------------------------------------------------------------------------

@test "uninstall.sh --dry-run exits 0" {
  run bash "$SCRIPTS_DIR/uninstall.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
}

@test "uninstall.sh --dry-run does not remove any files" {
  # Plant a binary that should survive dry-run
  echo "#!/bin/bash" > "$TMP_HOME/.local/bin/token-diet"
  chmod +x "$TMP_HOME/.local/bin/token-diet"

  run bash "$SCRIPTS_DIR/uninstall.sh" --dry-run --force

  # File must still exist after dry-run
  [ -f "$TMP_HOME/.local/bin/token-diet" ]
}

# ---------------------------------------------------------------------------
# Cycle 3.2 — uninstall.sh: binary removal
# ---------------------------------------------------------------------------

@test "uninstall.sh --force removes token-diet binary" {
  echo "#!/bin/bash" > "$TMP_HOME/.local/bin/token-diet"
  chmod +x "$TMP_HOME/.local/bin/token-diet"

  run bash "$SCRIPTS_DIR/uninstall.sh" --force

  [ "$status" -eq 0 ]
  [ ! -f "$TMP_HOME/.local/bin/token-diet" ]
}

@test "uninstall.sh --force removes token-diet-dashboard binary" {
  echo "#!/bin/bash" > "$TMP_HOME/.local/bin/token-diet-dashboard"
  chmod +x "$TMP_HOME/.local/bin/token-diet-dashboard"

  run bash "$SCRIPTS_DIR/uninstall.sh" --force

  [ "$status" -eq 0 ]
  [ ! -f "$TMP_HOME/.local/bin/token-diet-dashboard" ]
}

# ---------------------------------------------------------------------------
# Cycle 3.3 — uninstall.sh: MCP JSON removal
# ---------------------------------------------------------------------------

@test "uninstall.sh removes tilth and serena from claude-code settings.json" {
  mock_mcp_config claude-code tilth
  mock_mcp_config claude-code serena

  run bash "$SCRIPTS_DIR/uninstall.sh" --force

  [ "$status" -eq 0 ]
  # Keys should be gone from the JSON
  python3 - "$TMP_HOME/.claude/settings.json" << 'PY'
import json, sys
d = json.load(open(sys.argv[1]))
servers = d.get("mcpServers", {})
assert "tilth"  not in servers, "tilth still present"
assert "serena" not in servers, "serena still present"
PY
}

# ---------------------------------------------------------------------------
# Cycle 3.5 — uninstall.sh: doc file removal
# ---------------------------------------------------------------------------

@test "uninstall.sh removes token-diet.md from claude and codex dirs" {
  echo "# token-diet" > "$TMP_HOME/.claude/token-diet.md"
  echo "# token-diet" > "$TMP_HOME/.codex/token-diet.md"

  run bash "$SCRIPTS_DIR/uninstall.sh" --force

  [ "$status" -eq 0 ]
  [ ! -f "$TMP_HOME/.claude/token-diet.md" ]
  [ ! -f "$TMP_HOME/.codex/token-diet.md" ]
}

# ---------------------------------------------------------------------------
# Cycle 3.6 — uninstall.sh: serena memories preserved by default
# ---------------------------------------------------------------------------

@test "uninstall.sh preserves serena memories without --include-data" {
  mkdir -p "$TMP_HOME/.serena/memories"
  echo "memory" > "$TMP_HOME/.serena/memories/test.md"

  run bash "$SCRIPTS_DIR/uninstall.sh" --force

  [ "$status" -eq 0 ]
  [ -f "$TMP_HOME/.serena/memories/test.md" ]
}

@test "uninstall.sh removes serena memories with --include-data" {
  mkdir -p "$TMP_HOME/.serena/memories"
  echo "memory" > "$TMP_HOME/.serena/memories/test.md"

  run bash "$SCRIPTS_DIR/uninstall.sh" --force --include-data

  [ "$status" -eq 0 ]
  [ ! -f "$TMP_HOME/.serena/memories/test.md" ]
}

# ---------------------------------------------------------------------------
# Cycle 4.1 — install.sh: --verbose flag accepted
# ---------------------------------------------------------------------------

@test "install.sh --verbose is accepted (not Unknown option)" {
  mock_install_prereqs

  run bash "$SCRIPTS_DIR/install.sh" --verbose --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"Unknown option"* ]]
}

@test "install.sh --verbose --dry-run prints full output (no tail truncation)" {
  mock_install_prereqs

  run bash "$SCRIPTS_DIR/install.sh" --verbose --dry-run
  [ "$status" -eq 0 ]
  # With --verbose, the DRY-RUN banner must appear (basic sanity)
  [[ "$output" == *"DRY-RUN"* ]]
}

@test "install.sh --help mentions --verbose" {
  run bash "$SCRIPTS_DIR/install.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--verbose"* ]]
}

@test "install.sh --verify warns when Codex tilth MCP path is stale" {
  mock_cmd_with_gain
  mock_cmd tilth
  mock_cmd uv
  mock_cmd codex
  mock_mcp_config codex tilth "/missing/tilth"

  run bash "$SCRIPTS_DIR/install.sh" --verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"Codex tilth MCP command missing: /missing/tilth"* ]]
}

@test "install.sh --verify: stale single-quoted TOML path is flagged" {
  mock_cmd_with_gain
  mock_cmd tilth
  mock_cmd uv
  mock_cmd codex
  mkdir -p "$TMP_HOME/.codex"
  printf '\n[mcp_servers.tilth]\ncommand = '"'"'/missing/tilth'"'"'\n' >> "$TMP_HOME/.codex/config.toml"

  run bash "$SCRIPTS_DIR/install.sh" --verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"Codex tilth MCP command missing: /missing/tilth"* ]]
}
