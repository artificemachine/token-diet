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
  echo "#!/bin/bash" > "$TMP_HOME/.local/bin/token-diet-mcp"
  chmod +x "$TMP_HOME/.local/bin/token-diet-mcp"

  run bash "$SCRIPTS_DIR/uninstall.sh" --force

  [ "$status" -eq 0 ]
  [ ! -f "$TMP_HOME/.local/bin/token-diet-dashboard" ]
  [ ! -f "$TMP_HOME/.local/bin/token-diet-mcp" ]
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

@test "install.sh --verify warns when Codex serena MCP path is stale" {
  mock_cmd_with_gain
  mock_cmd tilth
  mock_cmd uv
  mock_cmd codex
  mock_mcp_config codex serena "/missing/serena"

  run bash "$SCRIPTS_DIR/install.sh" --verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"Codex serena MCP command missing: /missing/serena"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 5.1 — reinstall idempotency: opencode JSON
# ---------------------------------------------------------------------------

@test "install: --serena-only --hosts opencode does not duplicate serena entry on second run" {
  mock_install_prereqs
  mock_cmd opencode
  echo '{}' > "$TMP_HOME/.opencode.json"

  bash "$SCRIPTS_DIR/install.sh" --serena-only --hosts opencode
  bash "$SCRIPTS_DIR/install.sh" --serena-only --hosts opencode

  python3 - "$TMP_HOME/.opencode.json" << 'PY'
import json, sys
d = json.load(open(sys.argv[1]))
servers = d.get("mcpServers", {})
count = sum(1 for k in servers if "serena" in k.lower())
assert count == 1, f"Expected 1 serena entry, got {count}: {list(servers.keys())}"
PY
}

@test "install: --serena-only preserves unrelated mcpServers entries in opencode config" {
  mock_install_prereqs
  mock_cmd opencode
  python3 -c "
import json
with open('$TMP_HOME/.opencode.json', 'w') as f:
    json.dump({'mcpServers': {'other-tool': {'command': 'other'}}}, f)
    f.write('\n')
"

  run bash "$SCRIPTS_DIR/install.sh" --serena-only --hosts opencode
  [ "$status" -eq 0 ]

  python3 - "$TMP_HOME/.opencode.json" << 'PY'
import json, sys
d = json.load(open(sys.argv[1]))
servers = d.get("mcpServers", {})
assert "other-tool" in servers, f"Unrelated entry was removed: {list(servers.keys())}"
assert "serena" in servers, f"Serena entry missing: {list(servers.keys())}"
PY
}

# ---------------------------------------------------------------------------
# Cycle 5.2 — malformed JSON recovery: opencode
# ---------------------------------------------------------------------------

@test "install: --serena-only recovers from malformed opencode config (backs up + fresh)" {
  mock_install_prereqs
  mock_cmd opencode
  # Malformed JSON — json.load will raise JSONDecodeError without the fix
  printf '{"broken json\n' > "$TMP_HOME/.opencode.json"

  run bash "$SCRIPTS_DIR/install.sh" --serena-only --hosts opencode
  [ "$status" -eq 0 ]

  # After recovery, the config must be valid JSON with serena registered
  python3 - "$TMP_HOME/.opencode.json" << 'PY'
import json, sys
d = json.load(open(sys.argv[1]))
servers = d.get("mcpServers", {})
assert "serena" in servers, f"serena missing after malformed-JSON recovery: {list(servers.keys())}"
PY
}

# ---------------------------------------------------------------------------
# Cycle 5.3 — malformed JSON recovery: cowork (Claude Desktop)
# ---------------------------------------------------------------------------

@test "install: --serena-only recovers from malformed cowork config (backs up + fresh)" {
  mock_install_prereqs
  mock_cmd opencode  # also detect opencode so --hosts cowork filter has >1 choice to filter

  # Create malformed cowork config so HAS_COWORK=true and the json.load site is hit
  local cowork_dir
  if [ "$(uname -s)" = "Darwin" ]; then
    cowork_dir="$TMP_HOME/Library/Application Support/Claude"
  else
    cowork_dir="$TMP_HOME/.config/Claude"
  fi
  mkdir -p "$cowork_dir"
  printf '{"broken json\n' > "$cowork_dir/claude_desktop_config.json"

  run bash "$SCRIPTS_DIR/install.sh" --serena-only --hosts cowork
  [ "$status" -eq 0 ]

  python3 - "$cowork_dir/claude_desktop_config.json" << 'PY'
import json, sys
d = json.load(open(sys.argv[1]))
servers = d.get("mcpServers", {})
assert "serena" in servers, f"serena missing after malformed-JSON recovery: {list(servers.keys())}"
PY
}

# ---------------------------------------------------------------------------
# Cycle 5.4 — uninstall idempotency
# ---------------------------------------------------------------------------

@test "uninstall: --force is idempotent (second run on clean system exits 0)" {
  run bash "$SCRIPTS_DIR/uninstall.sh" --force
  [ "$status" -eq 0 ]

  run bash "$SCRIPTS_DIR/uninstall.sh" --force
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Cycle 6.2 — modifier-only flags must not suppress install (v1.6.1, issue #38)
# ---------------------------------------------------------------------------

@test "install.sh --skip-tests (modifier-only) still triggers Serena MCP + opencode rules" {
  mock_install_prereqs
  mock_cmd opencode
  mkdir -p "$TMP_HOME/.config/opencode"
  echo '{}' > "$TMP_HOME/.config/opencode/opencode.json"

  # Wizard answers: install-all=y, dedup=y, local-mode=n (use uvx path — no Docker).
  # Pre-fix: --skip-tests set has_args=true, wizard was skipped, do_serena stayed
  # false, injection never ran. Post-fix: has_args stays false for modifier-only
  # flags, wizard runs, install proceeds normally.
  # Wizard prompts: install-all, dedup, local-mode, proceed.
  run bash -c "printf 'y\ny\nn\ny\n' | bash '$SCRIPTS_DIR/install.sh' --skip-tests --hosts opencode"
  [ "$status" -eq 0 ]

  python3 - "$TMP_HOME/.config/opencode/opencode.json" << 'PY'
import json, sys
d = json.load(open(sys.argv[1]))
p = d.get("mode", {}).get("build", {}).get("prompt", "")
assert "token-diet:begin" in p, "OpenCode rules not injected — modifier-only flag bypassed install"
PY
}

# ---------------------------------------------------------------------------
# Cycle 6.1 — OpenCode prompt rule injection (v1.6.0)
# ---------------------------------------------------------------------------

@test "install.sh injects token-diet rules into opencode mode.build.prompt and mode.plan.prompt" {
  mock_install_prereqs
  mock_cmd opencode
  mkdir -p "$TMP_HOME/.config/opencode"
  echo '{}' > "$TMP_HOME/.config/opencode/opencode.json"

  run bash "$SCRIPTS_DIR/install.sh" --serena-only --hosts opencode
  [ "$status" -eq 0 ]

  python3 - "$TMP_HOME/.config/opencode/opencode.json" << 'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for m in ("build", "plan"):
    p = d.get("mode", {}).get(m, {}).get("prompt", "")
    assert "token-diet:begin" in p, f"mode.{m}.prompt missing begin marker"
    assert "token-diet:end"   in p, f"mode.{m}.prompt missing end marker"
    assert "tilth_search"     in p, f"mode.{m}.prompt missing tilth rules"
PY
}

@test "install.sh opencode rule injection is idempotent (no duplication on second run)" {
  mock_install_prereqs
  mock_cmd opencode
  mkdir -p "$TMP_HOME/.config/opencode"
  echo '{}' > "$TMP_HOME/.config/opencode/opencode.json"

  bash "$SCRIPTS_DIR/install.sh" --serena-only --hosts opencode
  bash "$SCRIPTS_DIR/install.sh" --serena-only --hosts opencode

  python3 - "$TMP_HOME/.config/opencode/opencode.json" << 'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for m in ("build", "plan"):
    p = d.get("mode", {}).get(m, {}).get("prompt", "")
    assert p.count("token-diet:begin") == 1, f"mode.{m}.prompt has duplicated begin markers"
    assert p.count("token-diet:end")   == 1, f"mode.{m}.prompt has duplicated end markers"
PY
}

@test "install.sh opencode rule injection preserves user's existing prompt text" {
  mock_install_prereqs
  mock_cmd opencode
  mkdir -p "$TMP_HOME/.config/opencode"
  python3 -c "
import json
with open('$TMP_HOME/.config/opencode/opencode.json', 'w') as f:
    json.dump({'mode': {'build': {'prompt': 'USER ORIGINAL BUILD PROMPT'}, 'plan': {'prompt': 'USER ORIGINAL PLAN PROMPT'}}}, f)
    f.write('\n')
"

  run bash "$SCRIPTS_DIR/install.sh" --serena-only --hosts opencode
  [ "$status" -eq 0 ]

  python3 - "$TMP_HOME/.config/opencode/opencode.json" << 'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert "USER ORIGINAL BUILD PROMPT" in d["mode"]["build"]["prompt"]
assert "USER ORIGINAL PLAN PROMPT"  in d["mode"]["plan"]["prompt"]
PY
}

@test "uninstall.sh strips token-diet block from opencode prompts but preserves user text" {
  mock_cmd opencode
  mkdir -p "$TMP_HOME/.config/opencode"
  python3 -c "
import json
prompt = 'USER TEXT\n<!-- token-diet:begin -->\nrules here\n<!-- token-diet:end -->\nTRAILING USER TEXT'
with open('$TMP_HOME/.config/opencode/opencode.json', 'w') as f:
    json.dump({'mode': {'build': {'prompt': prompt}, 'plan': {'prompt': prompt}}}, f)
    f.write('\n')
"

  run bash "$SCRIPTS_DIR/uninstall.sh" --force
  [ "$status" -eq 0 ]

  python3 - "$TMP_HOME/.config/opencode/opencode.json" << 'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for m in ("build", "plan"):
    p = d["mode"][m]["prompt"]
    assert "token-diet:begin" not in p, f"mode.{m} still has markers"
    assert "USER TEXT" in p, f"mode.{m} user text lost"
    assert "TRAILING USER TEXT" in p, f"mode.{m} trailing user text lost"
PY
}

# ---------------------------------------------------------------------------

@test "install.sh writes Serena to Linux Claude Desktop config when that config exists" {
  mock_install_prereqs
  mkdir -p "$TMP_HOME/.config/Claude"
  printf '{}\n' > "$TMP_HOME/.config/Claude/claude_desktop_config.json"

  run bash "$SCRIPTS_DIR/install.sh" --serena-only --hosts cowork
  [ "$status" -eq 0 ]

  python3 - "$TMP_HOME/.config/Claude/claude_desktop_config.json" << 'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
servers = data.get("mcpServers", {})
assert "serena" in servers, "serena not written to Linux Claude Desktop config"
assert servers["serena"]["command"] == "uvx", servers["serena"]
assert "--project-from-cwd" in servers["serena"]["args"], servers["serena"]["args"]
PY
}
