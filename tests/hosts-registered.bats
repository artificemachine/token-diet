#!/usr/bin/env bats
# Characterization tests for scripts/token-diet hosts_registered().
#
# hosts_registered() scans the user's live $HOME for MCP host config files and
# reports which hosts have a given tool registered. It is NOT dry-run coverable
# (it reads real files), so verification is by planted fixture $HOME.
#
# These tests plant config files across the full host/dialect matrix and pin the
# EXACT output of hosts_registered(), so the Phase 5 convergence onto the
# canonical registry (config/hosts-mcp.json) can be proven to preserve behavior.
#
# The tests source scripts/token-diet (which self-guards its dispatch when
# sourced) and call hosts_registered() directly against a fixture $HOME.

load test_helper

# Run hosts_registered <tool> against the current fixture $HOME and put the
# result in $output / $status via bats `run`.
hr() {
  run bash -c "source '$SCRIPTS_DIR/token-diet' >/dev/null 2>&1; hosts_registered '$1'"
}

# Write a file, creating parent dirs. jw <abs-path> <content>
jw() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }

# ---------------------------------------------------------------------------
# Baseline / empty
# ---------------------------------------------------------------------------

@test "no config files -> none" {
  hr tilth
  [ "$output" = "none" ]
}

@test "config present but tool not registered -> none" {
  jw "$HOME/.claude/settings.json" '{"mcpServers":{"other":{}}}'
  hr tilth
  [ "$output" = "none" ]
}

# ---------------------------------------------------------------------------
# claude-code (two config paths, both attribute to claude-code)
# ---------------------------------------------------------------------------

@test "claude-code via .claude/settings.json" {
  jw "$HOME/.claude/settings.json" '{"mcpServers":{"tilth":{"command":"tilth"}}}'
  hr tilth
  [ "$output" = "claude-code" ]
}

@test "claude-code via .claude.json" {
  jw "$HOME/.claude.json" '{"mcpServers":{"tilth":{"command":"tilth"}}}'
  hr tilth
  [ "$output" = "claude-code" ]
}

@test "claude-code appears twice when both .claude.json and settings.json register (no dedup for claude-code)" {
  jw "$HOME/.claude/settings.json" '{"mcpServers":{"tilth":{}}}'
  jw "$HOME/.claude.json" '{"mcpServers":{"tilth":{}}}'
  hr tilth
  [ "$output" = "claude-code,claude-code" ]
}

# ---------------------------------------------------------------------------
# claude-desktop — macOS path detects; Linux .config/Claude path is a
# historical no-op (matches no attribution arm -> no host).
# ---------------------------------------------------------------------------

@test "claude-desktop via macOS Application Support path" {
  jw "$HOME/Library/Application Support/Claude/claude_desktop_config.json" '{"mcpServers":{"tilth":{}}}'
  hr tilth
  [ "$output" = "claude-desktop" ]
}

@test "QUIRK: Linux .config/Claude path is scanned but attributes no host -> none" {
  jw "$HOME/.config/Claude/claude_desktop_config.json" '{"mcpServers":{"tilth":{}}}'
  hr tilth
  [ "$output" = "none" ]
}

# ---------------------------------------------------------------------------
# opencode — legacy (.opencode.json) and XDG (.config/opencode/opencode.json);
# either counts, and the two are de-duplicated to a single "opencode".
# ---------------------------------------------------------------------------

@test "opencode via legacy $HOME/.opencode.json" {
  jw "$HOME/.opencode.json" '{"mcpServers":{"tilth":{}}}'
  hr tilth
  [ "$output" = "opencode" ]
}

@test "opencode via XDG $HOME/.config/opencode/opencode.json" {
  jw "$HOME/.config/opencode/opencode.json" '{"mcpServers":{"tilth":{}}}'
  hr tilth
  [ "$output" = "opencode" ]
}

@test "opencode legacy + XDG together de-duplicate to a single opencode" {
  jw "$HOME/.opencode.json" '{"mcpServers":{"tilth":{}}}'
  jw "$HOME/.config/opencode/opencode.json" '{"mcpServers":{"tilth":{}}}'
  hr tilth
  [ "$output" = "opencode" ]
}

# ---------------------------------------------------------------------------
# Dialect keys for JSON hosts: mcpServers and mcp both match (merged).
# The registry dialect also lists `servers`; the convergence honors it too.
# ---------------------------------------------------------------------------

@test "dialect: mcp key matches (opencode style)" {
  jw "$HOME/.opencode.json" '{"mcp":{"tilth":{}}}'
  hr tilth
  [ "$output" = "opencode" ]
}

@test "dialect: servers key is honored for JSON hosts (registry convergence)" {
  # Pre-refactor the bash matcher merged only mcpServers+mcp and IGNORED
  # `servers`, so this returned "none". The convergence onto the registry's
  # mcp_key_dialect ([mcpServers, mcp, servers]) now honors `servers` too.
  # This is a pure superset (no host that was detected before is lost) and
  # matches the dashboard's registry-driven detection.
  jw "$HOME/.opencode.json" '{"servers":{"tilth":{}}}'
  hr tilth
  [ "$output" = "opencode" ]
}

@test "substring match: my-tilth-server key matches tool 'tilth'" {
  jw "$HOME/.claude/settings.json" '{"mcpServers":{"my-tilth-server":{}}}'
  hr tilth
  [ "$output" = "claude-code" ]
}

# ---------------------------------------------------------------------------
# Malformed / empty JSON files are skipped safely.
# ---------------------------------------------------------------------------

@test "malformed JSON is skipped -> none" {
  jw "$HOME/.claude/settings.json" '{ this is not json'
  hr tilth
  [ "$output" = "none" ]
}

@test "empty file is skipped -> none" {
  mkdir -p "$HOME/.claude"; : > "$HOME/.claude/settings.json"
  hr tilth
  [ "$output" = "none" ]
}

@test "empty JSON object -> none" {
  jw "$HOME/.claude/settings.json" '{}'
  hr tilth
  [ "$output" = "none" ]
}

# ---------------------------------------------------------------------------
# Codex — TOML block [mcp_servers.<tool>] with a command line. Exact tool name.
# ---------------------------------------------------------------------------

@test "codex via [mcp_servers.tilth] with command" {
  mkdir -p "$HOME/.codex"
  printf '\n[mcp_servers.tilth]\ncommand = "tilth"\n' > "$HOME/.codex/config.toml"
  hr tilth
  [ "$output" = "codex" ]
}

@test "codex block without command line -> none" {
  mkdir -p "$HOME/.codex"
  printf '\n[mcp_servers.tilth]\nargs = ["x"]\n' > "$HOME/.codex/config.toml"
  hr tilth
  [ "$output" = "none" ]
}

# ---------------------------------------------------------------------------
# VS Code — grep substring over $HOME/.config/Code/User/settings.json (content-blind).
# ---------------------------------------------------------------------------

@test "vscode via $HOME/.config/Code/User/settings.json (json)" {
  jw "$HOME/.config/Code/User/settings.json" '{"mcpServers":{"tilth":{}}}'
  hr tilth
  [ "$output" = "vscode" ]
}

@test "vscode grep is content-blind (matches tool name anywhere)" {
  jw "$HOME/.config/Code/User/settings.json" 'random text tilth here'
  hr tilth
  [ "$output" = "vscode" ]
}

# ---------------------------------------------------------------------------
# Gemini — $HOME/.gemini/settings.json, mcpServers+mcp merge.
# ---------------------------------------------------------------------------

@test "gemini via mcpServers" {
  jw "$HOME/.gemini/settings.json" '{"mcpServers":{"tilth":{}}}'
  hr tilth
  [ "$output" = "gemini" ]
}

@test "gemini via mcp key" {
  jw "$HOME/.gemini/settings.json" '{"mcp":{"tilth":{}}}'
  hr tilth
  [ "$output" = "gemini" ]
}

# ---------------------------------------------------------------------------
# All hosts registered at once — pins the full ordering of the output string.
# ---------------------------------------------------------------------------

@test "all hosts registered -> full ordered host list" {
  jw "$HOME/.claude/settings.json" '{"mcpServers":{"tilth":{}}}'
  jw "$HOME/.claude.json" '{"mcpServers":{"tilth":{}}}'
  jw "$HOME/Library/Application Support/Claude/claude_desktop_config.json" '{"mcpServers":{"tilth":{}}}'
  jw "$HOME/.config/Claude/claude_desktop_config.json" '{"mcpServers":{"tilth":{}}}'
  jw "$HOME/.opencode.json" '{"mcpServers":{"tilth":{}}}'
  jw "$HOME/.config/opencode/opencode.json" '{"mcpServers":{"tilth":{}}}'
  mkdir -p "$HOME/.codex"
  printf '\n[mcp_servers.tilth]\ncommand = "tilth"\n' > "$HOME/.codex/config.toml"
  jw "$HOME/.config/Code/User/settings.json" '{"mcpServers":{"tilth":{}}}'
  jw "$HOME/.gemini/settings.json" '{"mcpServers":{"tilth":{}}}'
  hr tilth
  [ "$output" = "claude-code,claude-code,claude-desktop,opencode,codex,vscode,gemini" ]
}

# ---------------------------------------------------------------------------
# Registry decoupling: hosts_registered must read the registry from
# $SCRIPT_DIR/../config/hosts-mcp.json (installed layout) — same resolution as
# _compat_min. With no registry reachable it falls back to the historical
# hardcoded path list, so detection still works.
# ---------------------------------------------------------------------------

@test "detection still works when the registry is unreadable (hardcoded fallback)" {
  # Point the script at an isolated copy with NO registry alongside it, so the
  # $SCRIPT_DIR/../config/hosts-mcp.json lookup misses and the fallback list is used.
  local iso; iso="$(mktemp -d)"
  cp "$SCRIPTS_DIR/token-diet" "$iso/token-diet"
  mkdir -p "$iso/lib"
  cp "$SCRIPTS_DIR"/lib/*.sh "$iso/lib/" 2>/dev/null || true
  jw "$HOME/.claude/settings.json" '{"mcpServers":{"tilth":{}}}'
  run bash -c "cd /; source '$iso/token-diet' >/dev/null 2>&1; hosts_registered tilth"
  rm -rf "$iso"
  [ "$output" = "claude-code" ]
}
