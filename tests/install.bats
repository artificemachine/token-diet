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

@test "uninstall.sh removes tilth, serena and icm from claude-code settings.json" {
  mock_mcp_config claude-code tilth
  mock_mcp_config claude-code serena
  mock_mcp_config claude-code icm

  run bash "$SCRIPTS_DIR/uninstall.sh" --force

  [ "$status" -eq 0 ]
  # Keys should be gone from the JSON
  python3 - "$TMP_HOME/.claude/settings.json" << 'PY'
import json, sys
d = json.load(open(sys.argv[1]))
servers = d.get("mcpServers", {})
assert "tilth"  not in servers, "tilth still present"
assert "serena" not in servers, "serena still present"
assert "icm"    not in servers, "icm still present"
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

@test "install.sh --verify warns when Codex icm MCP path is stale" {
  mock_cmd_with_gain
  mock_cmd tilth
  mock_cmd uv
  mock_cmd codex
  mock_icm
  mock_mcp_config codex icm "/missing/icm"

  run bash "$SCRIPTS_DIR/install.sh" --verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"Codex icm MCP command missing: /missing/icm"* ]]
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
servers = d.get("mcp", {})
count = sum(1 for k in servers if "serena" in k.lower())
assert count == 1, f"Expected 1 serena entry, got {count}: {list(servers.keys())}"
PY
}

# ---------------------------------------------------------------------------
# Cycle 5.x — Strict Installation Decoupling: MCP configs must never reference
# the cloned source repo. Regression for the forks/-path leak that broke
# serena + tilth after moving/renaming the token-diet checkout.
# ---------------------------------------------------------------------------

@test "install: opencode MCP config never contains absolute forks/ paths" {
  mock_install_prereqs
  mock_cmd opencode
  echo '{}' > "$TMP_HOME/.opencode.json"

  bash "$SCRIPTS_DIR/install.sh" --serena-only --hosts opencode

  python3 - "$TMP_HOME/.opencode.json" << 'PY'
import json, sys, re
d = json.load(open(sys.argv[1]))
servers = d.get("mcp", {}) or d.get("mcpServers", {})
bad = re.compile(r"(^|/)forks/")
for name, entry in servers.items():
    cmd = entry.get("command") or entry.get("args") or []
    if isinstance(cmd, str):
        cmd = [cmd]
    flat = " ".join(str(x) for x in cmd)
    assert not bad.search(flat), (
        f"Install-decoupling leak: mcp.{name}.command contains a forks/ "
        f"path: {flat!r}. MCP configs must use bare commands + XDG-stable "
        f"launchers (see CLAUDE.md §Strict Installation Decoupling)."
    )
PY
}

@test "install: opencode tilth MCP entry uses --mcp subcommand (not bare mcp)" {
  mock_install_prereqs
  mock_cmd opencode
  echo '{}' > "$TMP_HOME/.opencode.json"

  bash "$SCRIPTS_DIR/install.sh" --serena-only --hosts opencode

  python3 - "$TMP_HOME/.opencode.json" << 'PY'
import json, sys
d = json.load(open(sys.argv[1]))
t = (d.get("mcp") or {}).get("tilth") or {}
cmd = t.get("command") or []
flat = cmd if isinstance(cmd, str) else " ".join(str(x) for x in cmd)
assert "--mcp" in flat, f"tilth MCP command must include --mcp; got: {flat!r}"
# Negative assertion: the old bug was the bare positional `mcp` arg.
parts = cmd if isinstance(cmd, list) else cmd.split()
assert "mcp" not in parts or "--mcp" in parts, (
    f"tilth command has bare 'mcp' instead of '--mcp': {flat!r}"
)
PY
}

@test "install: opencode serena MCP entry uses 'serena start-mcp-server' (not nonexistent 'serena-mcp-server')" {
  mock_install_prereqs
  mock_cmd opencode
  echo '{}' > "$TMP_HOME/.opencode.json"

  bash "$SCRIPTS_DIR/install.sh" --serena-only --hosts opencode

  python3 - "$TMP_HOME/.opencode.json" << 'PY'
import json, sys
d = json.load(open(sys.argv[1]))
s = (d.get("mcp") or {}).get("serena") or {}
cmd = s.get("command") or []
flat = cmd if isinstance(cmd, str) else " ".join(str(x) for x in cmd)
assert "serena-mcp-server" not in flat, (
    f"Serena's MCP entry point is 'serena start-mcp-server' — there is no "
    f"'serena-mcp-server' binary in the venv. Got: {flat!r}"
)
assert "start-mcp-server" in flat, f"Expected start-mcp-server in {flat!r}"
PY
}

@test "install: install.sh source no longer contains the serena-mcp-server (nonexistent binary) name" {
  # Static-source regression for the historical bug: install.sh used to write
  # "$PROJECT_ROOT/forks/serena/.venv/bin/serena-mcp-server" into MCP configs.
  # That binary never existed — Serena's entry point is `serena`, which
  # dispatches `start-mcp-server`. Any reappearance of this string in the
  # installer source is a regression and must fail CI.
  ! grep -E "serena-mcp-server(\.exe)?(\"|')" "$SCRIPTS_DIR/install.sh" \
    || { echo "LEAK: install.sh still references the nonexistent serena-mcp-server binary"; false; }
  ! grep -E "serena-mcp-server(\.exe)?(\"|')" "$SCRIPTS_DIR/Install.ps1" \
    || { echo "LEAK: Install.ps1 still references the nonexistent serena-mcp-server binary"; false; }
}

@test "install: --serena-only preserves unrelated mcp entries in opencode config" {
  mock_install_prereqs
  mock_cmd opencode
  python3 -c "
import json
with open('$TMP_HOME/.opencode.json', 'w') as f:
    json.dump({'mcp': {'other-tool': {'type': 'local', 'command': ['other'], 'enabled': True}}}, f)
    f.write('\n')
"

  run bash "$SCRIPTS_DIR/install.sh" --serena-only --hosts opencode
  [ "$status" -eq 0 ]

  python3 - "$TMP_HOME/.opencode.json" << 'PY'
import json, sys
d = json.load(open(sys.argv[1]))
servers = d.get("mcp", {})
assert "other-tool" in servers, f"Unrelated entry was removed: {list(servers.keys())}"
assert "serena" in servers, f"Serena entry missing: {list(servers.keys())}"
PY
}

# ---------------------------------------------------------------------------
# Cycle 5.2 — malformed JSON is preserved, not overwritten: opencode
# ---------------------------------------------------------------------------

@test "install: --serena-only aborts and preserves a malformed opencode config (backs up, no stub)" {
  mock_install_prereqs
  mock_cmd opencode
  # Malformed JSON — the installer must refuse to overwrite it with a fresh stub.
  printf '{"broken json\n' > "$TMP_HOME/.opencode.json"

  run bash "$SCRIPTS_DIR/install.sh" --serena-only --hosts opencode
  # Safer contract: abort loudly instead of destroying existing (if broken) config.
  [ "$status" -ne 0 ]
  [[ "$output" == *"malformed JSON"* ]]

  # Original file is left untouched (NOT replaced with a fresh {serena} stub)...
  grep -q "broken json" "$TMP_HOME/.opencode.json"

  # ...and a timestamped .corrupt-* backup was written capturing it.
  local n
  n=$(ls "$TMP_HOME"/.opencode.json.corrupt-* 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -ge 1 ]
}

# ---------------------------------------------------------------------------
# Cycle 5.3 — malformed JSON is preserved, not overwritten: cowork (Claude Desktop)
# ---------------------------------------------------------------------------

@test "install: --serena-only aborts and preserves a malformed cowork config (backs up, no stub)" {
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
  # Safer contract: abort loudly instead of destroying existing (if broken) config.
  [ "$status" -ne 0 ]
  [[ "$output" == *"malformed JSON"* ]]

  # Original file is left untouched (NOT replaced with a fresh {serena} stub)...
  grep -q "broken json" "$cowork_dir/claude_desktop_config.json"

  # ...and a timestamped .corrupt-* backup was written capturing it.
  local n
  n=$(ls "$cowork_dir"/claude_desktop_config.json.corrupt-* 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -ge 1 ]
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

# ---------------------------------------------------------------------------
# install.sh: codex serena idempotency uses anchored TOML table header
# Regression guard: prior behavior used bare `grep -q "serena"` which
# false-matched stray orphan arrays containing the string "serena"
# (vestigial pasted args lines) and silently skipped the real registration.
# ---------------------------------------------------------------------------

@test "install.sh registers Serena in codex config when only a stray 'serena' substring exists" {
  mock_install_prereqs
  # Config has NO real [mcp_servers.serena] block but a stray args line
  # containing "serena". The old bare-grep check treated this as
  # "already configured" and skipped real registration.
  cat > "$TMP_HOME/.codex/config.toml" << 'TOML'
[mcp_servers.tilth]
command = "/some/path/tilth"
args = ["--mcp"]

# Vestigial orphan from a bad paste — contains the substring "serena"
["--from", "git+https://github.com/celstnblacc/serena", "serena", "start-mcp-server"]
TOML

  run bash "$SCRIPTS_DIR/install.sh" --serena-only --hosts codex
  [ "$status" -eq 0 ]

  # A real [mcp_servers.serena] table header must now be present on its own line
  grep -Eq '^\[mcp_servers\.serena\]' "$TMP_HOME/.codex/config.toml"
}

@test "install.sh does not duplicate Serena block when a real [mcp_servers.serena] header already exists" {
  mock_install_prereqs
  cat > "$TMP_HOME/.codex/config.toml" << 'TOML'
[mcp_servers.serena]
command = "uvx"
args = ["--from", "git+https://github.com/celstnblacc/serena", "serena", "start-mcp-server", "--context=codex", "--headless", "--project-from-cwd"]
TOML

  run bash "$SCRIPTS_DIR/install.sh" --serena-only --hosts codex
  [ "$status" -eq 0 ]

  local header_count
  header_count=$(grep -cE '^\[mcp_servers\.serena\]' "$TMP_HOME/.codex/config.toml")
  [ "$header_count" -eq 1 ]
}

# ---------------------------------------------------------------------------
# install.sh: ICM codex idempotency uses the same anchored TOML table header.
# The idempotency guard MUST be the exact line-anchored header ^\[mcp_servers\.icm\]
# — never a loose substring match on "icm" (which would false-match a stray
# args line and silently skip the real registration).
# ---------------------------------------------------------------------------

@test "install.sh registers ICM in codex config when only a stray 'icm' substring exists" {
  mock_install_prereqs
  mock_icm
  mock_cmd codex
  # Config has NO real [mcp_servers.icm] block but a stray args line
  # containing the substring "icm". A bare-grep guard would treat this as
  # "already configured" and skip the real registration.
  cat > "$TMP_HOME/.codex/config.toml" << 'TOML'
[mcp_servers.tilth]
command = "tilth"
args = ["--mcp"]

# Vestigial orphan from a bad paste — contains the substring "icm"
["--some-icm-flag", "serve"]
TOML

  run bash "$SCRIPTS_DIR/install.sh" --icm-only --hosts codex
  [ "$status" -eq 0 ]

  # A real [mcp_servers.icm] table header must now be present on its own line
  grep -Eq '^\[mcp_servers\.icm\]' "$TMP_HOME/.codex/config.toml"
  # And the bare-PATH command is written — never a forks/ path
  grep -Eq '^command = "icm"' "$TMP_HOME/.codex/config.toml"
}

@test "install.sh does not duplicate ICM block when a real [mcp_servers.icm] header already exists" {
  mock_install_prereqs
  mock_icm
  mock_cmd codex
  cat > "$TMP_HOME/.codex/config.toml" << 'TOML'
[mcp_servers.icm]
command = "icm"
args = ["serve", "--compact"]
TOML

  run bash "$SCRIPTS_DIR/install.sh" --icm-only --hosts codex
  [ "$status" -eq 0 ]

  local header_count
  header_count=$(grep -cE '^\[mcp_servers\.icm\]' "$TMP_HOME/.codex/config.toml")
  [ "$header_count" -eq 1 ]
}

# ---------------------------------------------------------------------------
# install.sh: OpenCode mcp.icm injection — bare-PATH command, idempotent.
# ---------------------------------------------------------------------------

@test "install.sh injects mcp.icm into opencode config with bare-PATH command" {
  mock_install_prereqs
  mock_icm
  mock_cmd opencode
  echo '{}' > "$TMP_HOME/.opencode.json"

  run bash "$SCRIPTS_DIR/install.sh" --icm-only --hosts opencode
  [ "$status" -eq 0 ]

  python3 - "$TMP_HOME/.opencode.json" << 'PY'
import json, sys
d = json.load(open(sys.argv[1]))
mcp = d.get("mcp", {})
assert "icm" in mcp, f"icm not registered in opencode: {list(mcp.keys())}"
entry = mcp["icm"]
assert entry.get("type") == "local", entry
assert entry.get("command") == ["icm", "serve", "--compact"], entry
assert entry.get("enabled") is True, entry
PY
}

@test "install.sh opencode mcp.icm injection is idempotent (no duplication on second run)" {
  mock_install_prereqs
  mock_icm
  mock_cmd opencode
  echo '{}' > "$TMP_HOME/.opencode.json"

  bash "$SCRIPTS_DIR/install.sh" --icm-only --hosts opencode
  bash "$SCRIPTS_DIR/install.sh" --icm-only --hosts opencode

  python3 - "$TMP_HOME/.opencode.json" << 'PY'
import json, sys
d = json.load(open(sys.argv[1]))
mcp = d.get("mcp", {})
count = sum(1 for k in mcp if "icm" in k.lower())
assert count == 1, f"Expected 1 icm entry, got {count}: {list(mcp.keys())}"
PY
}

@test "install.sh --icm-only preserves unrelated mcp entries in opencode config" {
  mock_install_prereqs
  mock_icm
  mock_cmd opencode
  python3 -c "
import json
with open('$TMP_HOME/.opencode.json', 'w') as f:
    json.dump({'mcp': {'other-tool': {'type': 'local', 'command': ['other'], 'enabled': True}}}, f)
    f.write('\n')
"

  run bash "$SCRIPTS_DIR/install.sh" --icm-only --hosts opencode
  [ "$status" -eq 0 ]

  python3 - "$TMP_HOME/.opencode.json" << 'PY'
import json, sys
d = json.load(open(sys.argv[1]))
mcp = d.get("mcp", {})
assert "other-tool" in mcp, f"Unrelated entry was removed: {list(mcp.keys())}"
assert "icm" in mcp, f"icm entry missing: {list(mcp.keys())}"
PY
}

# ---------------------------------------------------------------------------
# Cycle 6 — docextract / ctxwarn context hooks (--with-context-hooks, opt-in)
# ---------------------------------------------------------------------------

@test "context hooks: not installed without --with-context-hooks" {
  mock_install_prereqs
  mock_icm
  mock_cmd claude

  run bash "$SCRIPTS_DIR/install.sh" --icm-only
  [ "$status" -eq 0 ]

  [ ! -d "$TMP_HOME/.local/bin/token-diet-hooks" ]
  [ ! -f "$TMP_HOME/.claude/settings.json" ]
}

@test "context hooks: --with-context-hooks registers both hooks into claude settings, preserving existing hooks" {
  mock_install_prereqs
  mock_icm
  mock_cmd claude
  python3 -c "
import json
with open('$TMP_HOME/.claude/settings.json', 'w') as f:
    json.dump({'hooks': {'SessionStart': [{'matcher': '*', 'hooks': [{'type': 'command', 'command': 'echo unrelated', 'timeout': 5}]}]}}, f)
    f.write('\n')
"

  run bash "$SCRIPTS_DIR/install.sh" --icm-only --with-context-hooks
  [ "$status" -eq 0 ]

  python3 - "$TMP_HOME/.claude/settings.json" "$TMP_HOME" << 'PY'
import json, sys
d = json.load(open(sys.argv[1]))
home = sys.argv[2]
hooks = d.get("hooks", {})

session_start = hooks.get("SessionStart", [])
assert any(h.get("command") == "echo unrelated" for e in session_start for h in e.get("hooks", [])), \
    "pre-existing SessionStart hook was lost"

pre = hooks.get("PreToolUse", [])
docextract_cmd = f"{home}/.local/bin/token-diet-hooks/docextract-pre-read.sh"
matched = [e for e in pre if e.get("matcher") == "Read"
           and any(h.get("command") == docextract_cmd for h in e.get("hooks", []))]
assert matched, f"docextract PreToolUse/Read hook missing: {pre}"

post = hooks.get("PostToolUse", [])
ctxwarn_cmd = f"{home}/.local/bin/token-diet-hooks/ctxwarn-post.sh"
matched = [e for e in post if e.get("matcher") == "*"
           and any(h.get("command") == ctxwarn_cmd for h in e.get("hooks", []))]
assert matched, f"ctxwarn PostToolUse/* hook missing: {post}"
PY
}

@test "context hooks: shims installed under .local/bin/token-diet-hooks, executable, no dev-checkout path" {
  mock_install_prereqs
  mock_icm
  mock_cmd claude

  run bash "$SCRIPTS_DIR/install.sh" --icm-only --with-context-hooks
  [ "$status" -eq 0 ]

  [ -x "$TMP_HOME/.local/bin/token-diet-hooks/docextract-pre-read.sh" ]
  [ -x "$TMP_HOME/.local/bin/token-diet-hooks/ctxwarn-post.sh" ]
  ! grep -q "$SCRIPTS_DIR" "$TMP_HOME/.local/bin/token-diet-hooks/docextract-pre-read.sh"
  ! grep -q "$SCRIPTS_DIR" "$TMP_HOME/.local/bin/token-diet-hooks/ctxwarn-post.sh"
}

@test "context hooks: idempotent — running install twice does not duplicate entries" {
  mock_install_prereqs
  mock_icm
  mock_cmd claude

  run bash "$SCRIPTS_DIR/install.sh" --icm-only --with-context-hooks
  [ "$status" -eq 0 ]
  run bash "$SCRIPTS_DIR/install.sh" --icm-only --with-context-hooks
  [ "$status" -eq 0 ]

  python3 - "$TMP_HOME/.claude/settings.json" "$TMP_HOME" << 'PY'
import json, sys
d = json.load(open(sys.argv[1]))
home = sys.argv[2]
hooks = d.get("hooks", {})

docextract_cmd = f"{home}/.local/bin/token-diet-hooks/docextract-pre-read.sh"
ctxwarn_cmd = f"{home}/.local/bin/token-diet-hooks/ctxwarn-post.sh"

pre_count = sum(1 for e in hooks.get("PreToolUse", []) for h in e.get("hooks", []) if h.get("command") == docextract_cmd)
post_count = sum(1 for e in hooks.get("PostToolUse", []) for h in e.get("hooks", []) if h.get("command") == ctxwarn_cmd)
assert pre_count == 1, f"expected 1 docextract hook, found {pre_count}"
assert post_count == 1, f"expected 1 ctxwarn hook, found {post_count}"
PY
}

@test "context hooks: malformed settings.json aborts that host's registration without writing, install still exits 0" {
  mock_install_prereqs
  mock_icm
  mock_cmd claude
  printf '{"broken json\n' > "$TMP_HOME/.claude/settings.json"

  run bash "$SCRIPTS_DIR/install.sh" --icm-only --with-context-hooks
  [ "$status" -eq 0 ]

  grep -q "broken json" "$TMP_HOME/.claude/settings.json"
  ! grep -q "token-diet-hooks" "$TMP_HOME/.claude/settings.json"
}

@test "context hooks: non-claude harness gets awareness-docextract.md" {
  mock_install_prereqs
  mock_icm
  mock_cmd codex

  # Real `claude`/opencode/gemini binaries are on this dev machine's PATH, and
  # TMP_BIN only prepends (does not isolate) — --hosts restricts host wiring
  # to codex regardless of what else install.sh detects, matching the pattern
  # every other multi-host test in this file already uses.
  run bash "$SCRIPTS_DIR/install.sh" --icm-only --with-context-hooks --hosts codex
  [ "$status" -eq 0 ]

  [ -f "$TMP_HOME/.codex/awareness-docextract.md" ]
  [ ! -f "$TMP_HOME/.claude/settings.json" ]
}

@test "context hooks: uninstall removes both hook entries and leaves unrelated hooks intact" {
  mock_install_prereqs
  mock_icm
  mock_cmd claude
  python3 -c "
import json
with open('$TMP_HOME/.claude/settings.json', 'w') as f:
    json.dump({'hooks': {'SessionStart': [{'matcher': '*', 'hooks': [{'type': 'command', 'command': 'echo unrelated', 'timeout': 5}]}]}}, f)
    f.write('\n')
"
  run bash "$SCRIPTS_DIR/install.sh" --icm-only --with-context-hooks
  [ "$status" -eq 0 ]

  run bash "$SCRIPTS_DIR/uninstall.sh" --force
  [ "$status" -eq 0 ]

  [ ! -d "$TMP_HOME/.local/bin/token-diet-hooks" ]
  python3 - "$TMP_HOME/.claude/settings.json" << 'PY'
import json, sys
d = json.load(open(sys.argv[1]))
hooks = d.get("hooks", {})

session_start = hooks.get("SessionStart", [])
assert any(h.get("command") == "echo unrelated" for e in session_start for h in e.get("hooks", [])), \
    "unrelated SessionStart hook was removed"

for event in ("PreToolUse", "PostToolUse"):
    for e in hooks.get(event, []):
        for h in e.get("hooks", []):
            assert "token-diet-hooks" not in h.get("command", ""), f"hook entry not removed: {h}"
PY
}

# ---------------------------------------------------------------------------
# Cycle 6.1 — docextract pre-read shim: suffix passthrough policy
#
# Regression: the shim's intercepted-suffix set originally included .txt/.md,
# which caused two distinct problems:
#   1. .md: docextract's cache format is always .md, so reading a .md source
#      → extracts to a .md cache file → shim intercepts the .md cache → loops
#      forever. This is the live bug caught while writing the prior handoff.
#   2. .txt: already plain text, extracting adds a pointless round-trip.
# Both must pass through (exit 0). The real extraction targets (.pdf/.csv/
# .html/.htm) must still block (exit 2) so Claude reads the extracted cache.
# ---------------------------------------------------------------------------

@test "docextract shim: .md file passes through (exit 0, no block)" {
  mock_token_diet_extract

  local md="$TMP_HOME/HANDOFF.md"
  echo "# heading" > "$md"

  run bash "$PROJECT_ROOT/scripts/lib/hooks/docextract-pre-read.sh" \
    < <(printf '{"tool_input":{"file_path":"%s"}}' "$md")
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "docextract shim: .txt file passes through (exit 0, no block)" {
  mock_token_diet_extract

  local txt="$TMP_HOME/notes.txt"
  echo "plain text" > "$txt"

  run bash "$PROJECT_ROOT/scripts/lib/hooks/docextract-pre-read.sh" \
    < <(printf '{"tool_input":{"file_path":"%s"}}' "$txt")
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "docextract shim: .pdf file still intercepts (exit 2, redirects to cache)" {
  mock_token_diet_extract

  local pdf="$TMP_HOME/sample.pdf"
  printf '%%PDF-1.4 fake\n' > "$pdf"

  run bash "$PROJECT_ROOT/scripts/lib/hooks/docextract-pre-read.sh" \
    < <(printf '{"tool_input":{"file_path":"%s"}}' "$pdf")
  [ "$status" -eq 2 ]
  [[ "$output" == *"read that file instead"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 6.2 — context hooks: OpenCode + Copilot wiring (verified 2026-07-19)
#
# Regression: prior to v1.14.5, OpenCode was silently excluded from context
# hooks (treated like Copilot — "no verified schema, awareness doc only").
# This was wrong: OpenCode HAS a documented TS plugin API with
# "tool.execute.before" / "tool.execute.after" events. v1.14.5 adds a real
# plugin under ~/.config/opencode/plugins/token-diet-hooks.ts and registers
# it in opencode.json's plugin array (idempotent merge).
#
# Copilot CLI: confirmed (via https://github.com/github/copilot-cli README)
# that v0.0.377 has NO hook surface — only custom agents / LSP / MCP. OQ-3
# resolved as: best we can do is awareness doc at ~/.copilot/. Awareness
# doc is now installed for Copilot too (previously skipped entirely).
# ---------------------------------------------------------------------------

@test "context hooks: --with-context-hooks installs OpenCode plugin + registers it in opencode.json (idempotent)" {
  mock_install_prereqs
  mock_icm
  mock_cmd claude
  mock_cmd opencode
  mkdir -p "$TMP_HOME/.config/opencode/plugins"

  # Pre-existing opencode.json with an unrelated plugin entry — exercise the
  # "merge into existing array, don't drop other plugins" path.
  cat > "$TMP_HOME/.config/opencode/opencode.json" << 'JSON'
{
  "mcp": {},
  "plugin": ["./plugins/other.ts"]
}
JSON

  run bash "$SCRIPTS_DIR/install.sh" --icm-only --with-context-hooks
  [ "$status" -eq 0 ]

  # Plugin file exists, mode 644
  [ -f "$TMP_HOME/.config/opencode/plugins/token-diet-hooks.ts" ]
  local mode
  mode=$(stat -c '%a' "$TMP_HOME/.config/opencode/plugins/token-diet-hooks.ts" 2>/dev/null || stat -f '%Lp' "$TMP_HOME/.config/opencode/plugins/token-diet-hooks.ts")
  [ "$mode" = "644" ]

  # Plugin source matches what we ship
  rtk diff "$TMP_HOME/.config/opencode/plugins/token-diet-hooks.ts" "$PROJECT_ROOT/scripts/lib/hooks-plugins/opencode.ts"
  [ "$status" -eq 0 ]

  # opencode.json: other plugin preserved, ours appended (relative path)
  python3 - "$TMP_HOME/.config/opencode/opencode.json" << 'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
plugins = d.get("plugin", [])
assert isinstance(plugins, list), f"plugin should be a list, got {type(plugins)}"
assert "./plugins/other.ts" in plugins, f"pre-existing plugin dropped: {plugins}"
assert "plugins/token-diet-hooks.ts" in plugins, f"new plugin not registered: {plugins}"
PY

  # Idempotent — second run does NOT add a duplicate entry
  run bash "$SCRIPTS_DIR/install.sh" --icm-only --with-context-hooks
  [ "$status" -eq 0 ]
  python3 - "$TMP_HOME/.config/opencode/opencode.json" << 'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
plugins = d.get("plugin", [])
n = plugins.count("plugins/token-diet-hooks.ts")
assert n == 1, f"expected exactly 1 entry, found {n}: {plugins}"
PY
}

@test "context hooks: --with-context-hooks writes awareness-docextract.md to ~/.copilot (OQ-3 resolved)" {
  mock_install_prereqs
  mock_icm
  mock_cmd claude
  # Detector checks both `github-copilot-cli` (legacy Homebrew) and `copilot`
  # (current npm @github/copilot). Mock the npm form to prove both work.
  mock_cmd copilot
  mkdir -p "$TMP_HOME/.copilot"

  run bash "$SCRIPTS_DIR/install.sh" --icm-only --with-context-hooks --hosts copilot
  [ "$status" -eq 0 ]

  [ -f "$TMP_HOME/.copilot/awareness-docextract.md" ]
}

@test "context hooks: Copilot CLI detector also accepts the legacy github-copilot-cli name" {
  mock_install_prereqs
  mock_icm
  mock_cmd claude
  # Legacy Homebrew binary name. The v1.14.5 detector checks both names
  # because some users (like this one) have only `copilot` from npm while
  # others have only `github-copilot-cli` from Homebrew — silent misses
  # are exactly what we're guarding against.
  mock_cmd github-copilot-cli
  mkdir -p "$TMP_HOME/.copilot"

  run bash "$SCRIPTS_DIR/install.sh" --icm-only --with-context-hooks --hosts copilot
  [ "$status" -eq 0 ]

  [ -f "$TMP_HOME/.copilot/awareness-docextract.md" ]
}

@test "context hooks: opencode plugin source contains both hook handlers (docextract + ctxwarn)" {
  # Pure source-level check: the shipped plugin must wire both events.
  # Catches regressions where one handler gets accidentally removed.
  local src="$PROJECT_ROOT/scripts/lib/hooks-plugins/opencode.ts"
  [ -f "$src" ]
  rtk grep -q '"tool.execute.before"' "$src"
  rtk grep -q '"tool.execute.after"'  "$src"
  # Must extract via token-diet (not native parser)
  rtk grep -q 'token-diet extract'      "$src"
  # Must mirror ctxwarn band logic (estimate / threshold / band file)
  rtk grep -q 'DEFAULT_CTX_THRESHOLD\|ctx_threshold' "$src"
}

# ---------------------------------------------------------------------------
# Cycle 7 — installed token-diet's Python cores (extract / budget --check)

# ---------------------------------------------------------------------------
# Cycle 7 — installed token-diet's Python cores (extract / budget --check)
#
# Regression: cmd_extract / cmd_budget --check shell out to
# $SCRIPT_DIR/lib/<name>.py. Every other test in this file (and every
# real-machine validation up to this point) ran token-diet FROM the repo
# checkout, where scripts/lib/ is a sibling directory — so this always
# resolved and the bug was invisible. Once installed to .local/bin, the
# installed copy's own SCRIPT_DIR became .local/bin, and its lib/ was
# never copied there, breaking both subcommands post-install. Found by a
# live `install.sh --with-context-hooks` run against a real HOME.
# ---------------------------------------------------------------------------

@test "install: Python cores (docextract/tdcache/ctxwarn) are copied to .local/bin/lib" {
  mock_install_prereqs
  mock_icm
  mock_cmd claude

  run bash "$SCRIPTS_DIR/install.sh" --icm-only
  [ "$status" -eq 0 ]

  [ -f "$TMP_HOME/.local/bin/lib/docextract.py" ]
  [ -f "$TMP_HOME/.local/bin/lib/tdcache.py" ]
  [ -f "$TMP_HOME/.local/bin/lib/ctxwarn.py" ]
}

@test "install: the INSTALLED token-diet binary (not the repo checkout) can run extract and budget --check" {
  mock_install_prereqs
  mock_icm
  mock_cmd claude

  run bash "$SCRIPTS_DIR/install.sh" --icm-only
  [ "$status" -eq 0 ]

  local sample="$TMP_HOME/sample.txt"
  echo "installed-binary smoke test" > "$sample"

  run "$TMP_HOME/.local/bin/token-diet" extract "$sample"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/.cache/token-diet/extract/"* ]]

  local jsonl="$TMP_HOME/transcript.jsonl"
  python3 -c "import json; print(json.dumps({'content': 'short'}))" > "$jsonl"
  run "$TMP_HOME/.local/bin/token-diet" budget --check --transcript "$jsonl"
  [ "$status" -eq 0 ]
}

@test "uninstall: removes .local/bin/lib" {
  mock_install_prereqs
  mock_icm
  mock_cmd claude
  run bash "$SCRIPTS_DIR/install.sh" --icm-only
  [ "$status" -eq 0 ]
  [ -d "$TMP_HOME/.local/bin/lib" ]

  run bash "$SCRIPTS_DIR/uninstall.sh" --force
  [ "$status" -eq 0 ]
  [ ! -d "$TMP_HOME/.local/bin/lib" ]
}
