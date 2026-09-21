#!/usr/bin/env bash
# test_helper.bash — shared fixtures for token-diet bats tests
#
# Every test gets an isolated sandbox:
#   TMP_HOME  — fake $HOME so tests never touch real config dirs (.claude, .codex, etc.)
#   TMP_BIN   — fake bin dir prepended to PATH for mock binaries

export PROJECT_ROOT
PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export SCRIPTS_DIR="$PROJECT_ROOT/scripts"

# Detect platform for platform-specific path assertions
platform() {
  case "$(uname -s)" in
    Darwin) echo "darwin" ;;
    Linux)  echo "linux"  ;;
    *)      echo "unknown" ;;
  esac
}

setup() {
  TMP_HOME="$(mktemp -d)"
  TMP_BIN="$(mktemp -d)"
  export HOME="$TMP_HOME"
  export PATH="$TMP_BIN:$PATH"

  # Create minimal directory structure tests expect
  mkdir -p "$TMP_HOME/.claude"
  mkdir -p "$TMP_HOME/.codex"
  mkdir -p "$TMP_HOME/.local/bin"
  mkdir -p "$TMP_HOME/.config/token-diet"
  mkdir -p "$TMP_HOME/.config/serena"

  # Preserve real python3 — hosts_registered() and remove_json_key() need it
  local real_python3
  real_python3="$(PATH="${PATH#"$TMP_BIN:"}" command -v python3 2>/dev/null || true)"
  if [ -n "$real_python3" ]; then
    ln -sf "$real_python3" "$TMP_BIN/python3"
  fi
}

teardown() {
  rm -rf "$TMP_HOME" "$TMP_BIN"
}

# ---------------------------------------------------------------------------
# Mock helpers
# ---------------------------------------------------------------------------

# mock_cmd "name" [exit_code] [output]
# Creates a minimal fake binary that exits 0 and echoes its name + version
mock_cmd() {
  local name="$1"
  local exit_code="${2:-0}"
  local output="${3:-}"
  cat > "$TMP_BIN/$name" << MOCK
#!/usr/bin/env bash
case "\$1" in
  --version) echo "$name 0.99.0-mock"; exit 0 ;;
  --help)    echo "Usage: $name [OPTIONS]"; exit 0 ;;
esac
[ -n "$output" ] && echo "$output"
exit $exit_code
MOCK
  chmod +x "$TMP_BIN/$name"
}

# mock_icm
# Creates an icm mock mirroring the serena runtime stubs: handles --version,
# --help, serve (the MCP entry point), and recall (used by `token-diet icm warmup`).
# Always exits 0 so health/route/doctor see icm as a working binary on PATH.
mock_icm() {
  cat > "$TMP_BIN/icm" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
  --version) echo "icm 0.10.50-mock"; exit 0 ;;
  --help)    echo "Usage: icm [OPTIONS] <COMMAND>"; exit 0 ;;
  serve)     exit 0 ;;
  recall)    exit 0 ;;
  *)         exit 0 ;;
esac
MOCK
  chmod +x "$TMP_BIN/icm"
}

# mock_gemini [tool1 tool2 ...]
# Writes the Gemini settings.json (HOME/.gemini/settings.json) with mcpServers
# entries for each named tool. _doctor_check_mcp_gemini reads this file directly
# (no CLI call), so the mock creates the config file rather than a CLI stub.
# With no args, creates an empty settings.json (no tools registered).
mock_gemini() {
  mkdir -p "$TMP_HOME/.gemini"
  local json='{"mcpServers":{'
  local first=true
  for t in "$@"; do
    $first || json="${json},"
    json="${json}\"${t}\":{\"command\":\"${t}\",\"args\":[]}"
    first=false
  done
  json="${json}}}"
  echo "$json" > "$TMP_HOME/.gemini/settings.json"
  # Also write a gemini stub CLI (for any test that calls gemini mcp list directly)
  {
    echo '#!/usr/bin/env bash'
    echo 'exit 0'
  } > "$TMP_BIN/gemini"
  chmod +x "$TMP_BIN/gemini"
}

# mock_mcp_config "host" "tool" ["command"]
# Writes a fake MCP config file for the given host with the tool registered.
# Safe to call multiple times — merges into existing JSON.
mock_mcp_config() {
  local host="$1"
  local tool="$2"
  local command_value="${3:-$tool}"
  local cfg

  case "$host" in
    claude-code)
      cfg="$TMP_HOME/.claude/settings.json"
      ;;
    claude-desktop)
      # Detect platform for correct path
      if [ "$(platform)" = "darwin" ]; then
        mkdir -p "$TMP_HOME/Library/Application Support/Claude"
        cfg="$TMP_HOME/Library/Application Support/Claude/claude_desktop_config.json"
      else
        mkdir -p "$TMP_HOME/.config/Claude"
        cfg="$TMP_HOME/.config/Claude/claude_desktop_config.json"
      fi
      ;;
    opencode)
      cfg="$TMP_HOME/.opencode.json"
      ;;
    codex)
      mkdir -p "$TMP_HOME/.codex"
      # Codex uses TOML — append a block
      printf '\n[mcp_servers.%s]\ncommand = "%s"\n' "$tool" "$command_value" >> "$TMP_HOME/.codex/config.toml"
      return 0
      ;;
    vscode)
      mkdir -p "$TMP_HOME/.config/Code/User"
      cfg="$TMP_HOME/.config/Code/User/settings.json"
      ;;
    *)
      echo "mock_mcp_config: unknown host '$host'" >&2
      return 1
      ;;
  esac

  # Merge tool into existing JSON or create fresh
  if [ -f "$cfg" ]; then
    python3 - "$cfg" "$tool" "$command_value" << 'PY'
import json, sys
cfg_path, tool_name, command_value = sys.argv[1], sys.argv[2], sys.argv[3]
with open(cfg_path) as f:
    d = json.load(f)
d.setdefault("mcpServers", {})[tool_name] = {"command": command_value}
with open(cfg_path, "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
PY
  else
    local dir; dir="$(dirname "$cfg")"
    mkdir -p "$dir"
    jq -n --arg t "$tool" --arg c "$command_value" \
      '{"mcpServers": {($t): {"command": $c}}}' > "$cfg"
  fi
}

# mock_context7_mcp [host]
# Registers context7 the way install.sh does: a REMOTE HTTP MCP entry
# ({"type": "http", "url": "https://mcp.context7.com/mcp"}), never a local
# command — context7 has no binary on PATH. Codex gets a TOML block with a
# url key instead of a command.
mock_context7_mcp() {
  local host="${1:-claude-code}"
  local cfg

  case "$host" in
    codex)
      mkdir -p "$TMP_HOME/.codex"
      printf '\n[mcp_servers.context7]\nurl = "https://mcp.context7.com/mcp"\n' >> "$TMP_HOME/.codex/config.toml"
      return 0
      ;;
    claude-code)
      cfg="$TMP_HOME/.claude/settings.json"
      ;;
    opencode)
      cfg="$TMP_HOME/.opencode.json"
      ;;
    *)
      echo "mock_context7_mcp: unknown host '$host'" >&2
      return 1
      ;;
  esac

  if [ -f "$cfg" ]; then
    python3 - "$cfg" << 'PY'
import json, sys
cfg_path = sys.argv[1]
with open(cfg_path) as f:
    d = json.load(f)
d.setdefault("mcpServers", {})["context7"] = {
    "type": "http",
    "url": "https://mcp.context7.com/mcp",
}
with open(cfg_path, "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
PY
  else
    local dir; dir="$(dirname "$cfg")"
    mkdir -p "$dir"
    printf '{"mcpServers": {"context7": {"type": "http", "url": "https://mcp.context7.com/mcp"}}}\n' > "$cfg"
  fi
}

# mock_token_diet_extract
# Creates a token-diet mock whose `extract <path>` always succeeds and prints
# a deterministic .md cache path — matching the real docextract.py behavior,
# where every extraction lands in ~/.cache/token-diet/extract/<hash>.md.
# This is what surfaces the .md loop bug in the shim regression test: with a
# successful extract returning a .md cache path, the shim's interception
# policy is what decides whether the original Read gets blocked or not.
mock_token_diet_extract() {
  cat > "$TMP_BIN/token-diet" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
  --version) echo "token-diet 1.14.1-mock"; exit 0 ;;
  --help)    echo "Usage: token-diet [OPTIONS] COMMAND"; exit 0 ;;
  extract)
    # Pretend any input file extracts successfully to a .md cache file.
    # Hash is irrelevant — the shim only reads what token-diet prints.
    echo "/mock/home/.cache/token-diet/extract/deadbeef.md"
    exit 0 ;;
  *) exit 0 ;;
esac
MOCK
  chmod +x "$TMP_BIN/token-diet"
}

# mock_install_prereqs
# Creates mock binaries for all install.sh prerequisites
mock_install_prereqs() {
  mock_cmd git
  mock_cmd cargo
  mock_cmd rustup
  mock_cmd curl
  mock_cmd uv
  mock_cmd uvx

  # git needs to handle 'submodule update' without failing
  cat > "$TMP_BIN/git" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
  submodule) exit 0 ;;
  --version) echo "git version 2.50.0-mock"; exit 0 ;;
  rev-parse) echo "/mock/repo"; exit 0 ;;
  *) exit 0 ;;
esac
MOCK
  chmod +x "$TMP_BIN/git"

  # cargo needs to handle 'install' subcommand
  cat > "$TMP_BIN/cargo" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
  install)   echo "[mock] cargo install done"; exit 0 ;;
  test)      echo "test result: ok. 0 passed"; exit 0 ;;
  clippy)    exit 0 ;;
  build)     exit 0 ;;
  --version) echo "cargo 1.99.0-mock"; exit 0 ;;
  *)         exit 0 ;;
esac
MOCK
  chmod +x "$TMP_BIN/cargo"
}
