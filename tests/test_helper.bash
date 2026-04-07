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

# mock_cmd_with_gain
# Creates an rtk mock that fully handles: --version, gain --help, gain --format json
mock_cmd_with_gain() {
  cat > "$TMP_BIN/rtk" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
  --version) echo "rtk 0.34.3-mock"; exit 0 ;;
  gain)
    case "$2" in
      --help)     echo "Usage: rtk gain [OPTIONS]"; exit 0 ;;
      --format)   echo '{"summary":{"total_commands":10,"total_input":5000,"total_saved":3500,"avg_savings_pct":70.0,"total_time_ms":250},"daily":[]}' ; exit 0 ;;
      --daily)    echo '{"summary":{"total_commands":10,"total_input":5000,"total_saved":3500,"avg_savings_pct":70.0,"total_time_ms":250},"daily":[]}' ; exit 0 ;;
      *)          echo "Usage: rtk gain [OPTIONS]"; exit 0 ;;
    esac ;;
  *)  exit 0 ;;
esac
MOCK
  chmod +x "$TMP_BIN/rtk"
}

# mock_cmd_with_history
# RTK mock with per-command "By Command" text table (cargo test×5, git log×3, npm test×2).
# --format json returns the summary for budget tests.
mock_cmd_with_history() {
  cat > "$TMP_BIN/rtk" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
  --version) echo "rtk 0.34.3-mock"; exit 0 ;;
  gain)
    case "$2" in
      --help)   echo "Usage: rtk gain [OPTIONS]"; exit 0 ;;
      --format) echo '{"summary":{"total_commands":10,"total_input":65000,"total_saved":50000,"avg_savings_pct":76.9,"total_time_ms":300},"daily":[]}'; exit 0 ;;
      --daily)  echo '{"summary":{"total_commands":10,"total_input":65000,"total_saved":50000,"avg_savings_pct":76.9,"total_time_ms":300},"daily":[]}'; exit 0 ;;
      *)
        printf 'RTK Token Savings (Global Scope)\n\nBy Command\n'
        printf '────────────────────────────────────────────────────────────────────────\n'
        printf '  #  Command                   Count   Saved    Avg%%%%    Time  Impact    \n'
        printf '────────────────────────────────────────────────────────────────────────\n'
        printf ' 1.  cargo test                    5   40.0K   80.0%%%%     0ms  ██████████\n'
        printf ' 2.  git log                       3    9.0K   75.0%%%%     0ms  ████░░░░░░\n'
        printf ' 3.  npm test                      2    1.0K   33.3%%%%     0ms  ███░░░░░░░\n'
        printf '────────────────────────────────────────────────────────────────────────\n'
        exit 0 ;;
    esac ;;
  *)  exit 0 ;;
esac
MOCK
  chmod +x "$TMP_BIN/rtk"
}

# mock_cmd_no_loops
# RTK mock whose "By Command" table has all counts below the loop threshold (3).
mock_cmd_no_loops() {
  cat > "$TMP_BIN/rtk" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
  --version) echo "rtk 0.34.3-mock"; exit 0 ;;
  gain)
    case "$2" in
      --help)   echo "Usage: rtk gain [OPTIONS]"; exit 0 ;;
      --format) echo '{"summary":{"total_commands":3,"total_input":700,"total_saved":560,"avg_savings_pct":80.0,"total_time_ms":50},"daily":[]}'; exit 0 ;;
      *)
        printf 'RTK Token Savings (Global Scope)\n\nBy Command\n'
        printf '────────────────────────────────────────────────────────────────────────\n'
        printf '  #  Command                   Count   Saved    Avg%%%%    Time  Impact    \n'
        printf '────────────────────────────────────────────────────────────────────────\n'
        printf ' 1.  git status                    1    0.4K   80.0%%%%     0ms  ████░░░░░░\n'
        printf ' 2.  ls                            2    0.2K   80.0%%%%     0ms  ███░░░░░░░\n'
        printf '────────────────────────────────────────────────────────────────────────\n'
        exit 0 ;;
    esac ;;
  *)  exit 0 ;;
esac
MOCK
  chmod +x "$TMP_BIN/rtk"
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
