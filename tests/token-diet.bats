#!/usr/bin/env bats
# Tests for scripts/token-diet CLI

load test_helper

# ---------------------------------------------------------------------------
# Cycle 1.1 — basic dispatch
# ---------------------------------------------------------------------------

@test "token-diet --help prints USAGE and COMMANDS and exits 0" {
  run "$SCRIPTS_DIR/token-diet" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"USAGE"* ]]
  [[ "$output" == *"COMMANDS"* ]]
}

@test "token-diet help (subcommand) exits 0" {
  run "$SCRIPTS_DIR/token-diet" help
  [ "$status" -eq 0 ]
}

@test "token-diet unknown command exits 1" {
  run "$SCRIPTS_DIR/token-diet" nonexistent-command
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Cycle 2.1 — health: missing tools
# ---------------------------------------------------------------------------

@test "health: exits 1 and prints tool names when no tools installed" {
  # Shadow real tools with stubs that exit 1 so health sees them as missing
  for tool in rtk tilth uvx docker; do
    printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP_BIN/$tool"
    chmod +x "$TMP_BIN/$tool"
  done

  run "$SCRIPTS_DIR/token-diet" health
  [ "$status" -eq 1 ]
  [[ "$output" == *"RTK"* ]]
  [[ "$output" == *"tilth"* ]]
  [[ "$output" == *"Serena"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 2.2 — health: all tools present
# ---------------------------------------------------------------------------

@test "health: exits 0 when all three tools are available" {
  mock_cmd_with_gain
  mock_cmd tilth
  mock_cmd uvx

  run "$SCRIPTS_DIR/token-diet" health
  [ "$status" -eq 0 ]
  [[ "$output" == *"All tools healthy"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 2.3 — health: MCP host registration
# ---------------------------------------------------------------------------

@test "health: shows MCP host names when tools are registered" {
  mock_cmd_with_gain
  mock_cmd tilth
  mock_cmd uvx
  mock_mcp_config claude-code tilth
  mock_mcp_config claude-code serena

  run "$SCRIPTS_DIR/token-diet" health
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude-code"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 2.4 — health: listed in --help
# ---------------------------------------------------------------------------

@test "help text includes health command" {
  run "$SCRIPTS_DIR/token-diet" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"health"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 3.7 — uninstall dispatch
# ---------------------------------------------------------------------------

@test "uninstall subcommand dispatches to uninstall.sh" {
  # Plant a file to prove uninstall ran
  mkdir -p "$TMP_HOME/.local/bin"
  echo "#!/bin/bash" > "$TMP_HOME/.local/bin/token-diet-dashboard"
  chmod +x "$TMP_HOME/.local/bin/token-diet-dashboard"

  run "$SCRIPTS_DIR/token-diet" uninstall --force
  [ "$status" -eq 0 ]
  [ ! -f "$TMP_HOME/.local/bin/token-diet-dashboard" ]
}

# ---------------------------------------------------------------------------
# Cycle 6.1 — breakdown: dispatch
# ---------------------------------------------------------------------------

@test "breakdown: exits 1 when RTK not available" {
  for tool in rtk tilth uvx docker; do
    printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP_BIN/$tool"
    chmod +x "$TMP_BIN/$tool"
  done
  run "$SCRIPTS_DIR/token-diet" breakdown
  [ "$status" -eq 1 ]
  [[ "$output" == *"RTK"* ]]
}

@test "breakdown: exits 0 when RTK present" {
  mock_cmd_with_history
  run "$SCRIPTS_DIR/token-diet" breakdown
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Cycle 6.2 — breakdown: shows top commands ranked by tokens saved
# ---------------------------------------------------------------------------

@test "breakdown: shows command names from RTK history" {
  mock_cmd_with_history
  run "$SCRIPTS_DIR/token-diet" breakdown
  [ "$status" -eq 0 ]
  [[ "$output" == *"cargo test"* ]]
  [[ "$output" == *"git log"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 6.3 — breakdown: --limit N
# ---------------------------------------------------------------------------

@test "breakdown: --limit 1 shows only one command" {
  mock_cmd_with_history
  run "$SCRIPTS_DIR/token-diet" breakdown --limit 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"cargo test"* ]]
  [[ "$output" != *"npm test"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 6.4 — breakdown: listed in --help
# ---------------------------------------------------------------------------

@test "help text includes breakdown command" {
  run "$SCRIPTS_DIR/token-diet" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"breakdown"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 7.1 — explain: no data for unknown command
# ---------------------------------------------------------------------------

@test "explain: exits 1 with message for unknown command" {
  mock_cmd_with_history
  run "$SCRIPTS_DIR/token-diet" explain "unknown-cmd-xyz"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no data"* ]] || [[ "$output" == *"not found"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 7.2 — explain: shows breakdown for known command
# ---------------------------------------------------------------------------

@test "explain: shows input/saved/pct for a known command" {
  mock_cmd_with_history
  run "$SCRIPTS_DIR/token-diet" explain "cargo test"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cargo test"* ]]
  [[ "$output" == *"80"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 7.3 — explain: listed in --help
# ---------------------------------------------------------------------------

@test "help text includes explain command" {
  run "$SCRIPTS_DIR/token-diet" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"explain"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 9.1 — budget init: creates .token-budget in cwd
# ---------------------------------------------------------------------------

@test "budget init: creates .token-budget in current directory" {
  cd "$TMP_HOME"
  run "$SCRIPTS_DIR/token-diet" budget init
  [ "$status" -eq 0 ]
  [ -f "$TMP_HOME/.token-budget" ]
}

@test "budget init: adds .token-budget to existing .gitignore" {
  local proj
  proj=$(mktemp -d)
  touch "$proj/.gitignore"
  cd "$proj"
  run "$SCRIPTS_DIR/token-diet" budget init
  [ "$status" -eq 0 ]
  grep -qxF '.token-budget' "$proj/.gitignore"
  rm -rf "$proj"
}

@test "budget init: creates .gitignore when in a git repo and none exists" {
  local proj
  proj=$(mktemp -d)
  git -C "$proj" init -q
  cd "$proj"
  run "$SCRIPTS_DIR/token-diet" budget init
  [ "$status" -eq 0 ]
  [ -f "$proj/.gitignore" ]
  grep -qxF '.token-budget' "$proj/.gitignore"
  rm -rf "$proj"
}

@test "budget init: does not duplicate .token-budget in .gitignore" {
  local proj
  proj=$(mktemp -d)
  echo '.token-budget' > "$proj/.gitignore"
  cd "$proj"
  run "$SCRIPTS_DIR/token-diet" budget init
  [ "$status" -eq 0 ]
  [ "$(grep -c '\.token-budget' "$proj/.gitignore")" -eq 1 ]
  rm -rf "$proj"
}

@test "budget init: .token-budget contains warn and hard thresholds" {
  cd "$TMP_HOME"
  run "$SCRIPTS_DIR/token-diet" budget init
  [ "$status" -eq 0 ]
  python3 - "$TMP_HOME/.token-budget" << 'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert "warn" in d, "missing warn"
assert "hard" in d, "missing hard"
PY
}

# ---------------------------------------------------------------------------
# Cycle 9.2 — budget status: reads budget and shows usage
# ---------------------------------------------------------------------------

@test "budget status: exits 0 and shows thresholds when budget exists" {
  cd "$TMP_HOME"
  # warn=200K hard=500K — mock uses 65K (below warn), so status is OK (exit 0)
  printf '{"warn":200000,"hard":500000}\n' > "$TMP_HOME/.token-budget"
  mock_cmd_with_history
  run "$SCRIPTS_DIR/token-diet" budget status
  [ "$status" -eq 0 ]
  [[ "$output" == *"200"* ]] || [[ "$output" == *"500"* ]]
}

@test "budget status: exits 1 with hint when no .token-budget found" {
  cd "$TMP_HOME"
  run "$SCRIPTS_DIR/token-diet" budget status
  [ "$status" -eq 1 ]
  [[ "$output" == *"budget init"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 9.3 — budget status: exits 2 when over warn threshold
# ---------------------------------------------------------------------------

@test "budget status: exits 2 when RTK usage exceeds warn threshold" {
  cd "$TMP_HOME"
  # warn=100 hard=1000000 — mock uses 65K (above warn, below hard) → WARN exit 2
  printf '{"warn":100,"hard":1000000}\n' > "$TMP_HOME/.token-budget"
  mock_cmd_with_history
  run "$SCRIPTS_DIR/token-diet" budget status
  [ "$status" -eq 2 ]
  [[ "$output" == *"WARN"* ]] || [[ "$output" == *"warn"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 9.4 — budget: listed in --help
# ---------------------------------------------------------------------------

@test "help text includes budget command" {
  run "$SCRIPTS_DIR/token-diet" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"budget"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 10.1 — loops: exits 0 when no repeated commands
# ---------------------------------------------------------------------------

@test "loops: exits 0 with clean message when no loops detected" {
  mock_cmd_no_loops
  run "$SCRIPTS_DIR/token-diet" loops
  [ "$status" -eq 0 ]
  [[ "$output" == *"No loops"* ]] || [[ "$output" == *"no loops"* ]] || [[ "$output" == *"clean"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 10.2 — loops: detects commands run 3+ times
# ---------------------------------------------------------------------------

@test "loops: exits 1 and flags commands run 3+ times" {
  # Plant a mock rtk that reports a looped command (count >= 3)
  cat > "$TMP_BIN/rtk" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
  --version) echo "rtk 0.34.3-mock"; exit 0 ;;
  gain)
    case "$2" in
      --help)    echo "Usage: rtk gain [OPTIONS]"; exit 0 ;;
      --history) echo '{"summary":{},"commands":[{"cmd":"cargo build","count":7,"total_input":70000,"total_saved":56000,"avg_pct":80.0},{"cmd":"git status","count":2,"total_input":1000,"total_saved":800,"avg_pct":80.0}]}'; exit 0 ;;
      --format)  echo '{"summary":{"total_commands":9,"total_input":71000,"total_saved":56800,"avg_savings_pct":80.0,"total_time_ms":100},"daily":[]}'; exit 0 ;;
      *)         echo "Usage: rtk gain [OPTIONS]"; exit 0 ;;
    esac ;;
  *)  exit 0 ;;
esac
MOCK
  chmod +x "$TMP_BIN/rtk"

  run "$SCRIPTS_DIR/token-diet" loops
  [ "$status" -eq 1 ]
  [[ "$output" == *"cargo build"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 10.3 — loops: listed in --help
# ---------------------------------------------------------------------------

@test "help text includes loops command" {
  run "$SCRIPTS_DIR/token-diet" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"loops"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 12.1 — strip: dispatch and basic output
# ---------------------------------------------------------------------------

@test "strip: exits 1 with usage when no file given" {
  run "$SCRIPTS_DIR/token-diet" strip
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

@test "strip: exits 1 when file does not exist" {
  run "$SCRIPTS_DIR/token-diet" strip "/nonexistent/path/file.py"
  [ "$status" -eq 1 ]
}

@test "strip: removes single-line comments from a Python file" {
  cat > "$TMP_HOME/sample.py" << 'PY'
# This is a top comment
def hello():
    # inline comment
    return "hi"  # end-of-line comment
PY
  run "$SCRIPTS_DIR/token-diet" strip "$TMP_HOME/sample.py"
  [ "$status" -eq 0 ]
  [[ "$output" != *"This is a top comment"* ]]
  [[ "$output" == *"def hello"* ]]
  [[ "$output" == *"return"* ]]
}

@test "strip: removes single-line comments from a bash file" {
  cat > "$TMP_HOME/sample.sh" << 'SH'
#!/usr/bin/env bash
# This header comment goes away
echo "hello"   # inline comment removed
SH
  run "$SCRIPTS_DIR/token-diet" strip "$TMP_HOME/sample.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"echo"* ]]
  [[ "$output" != *"header comment"* ]]
}

@test "strip: --stats prints reduction percentage" {
  cat > "$TMP_HOME/sample.py" << 'PY'
# comment line one
# comment line two
def work():
    pass
PY
  run "$SCRIPTS_DIR/token-diet" strip --stats "$TMP_HOME/sample.py"
  [ "$status" -eq 0 ]
  [[ "$output" == *"%"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 12.4 — strip: listed in --help
# ---------------------------------------------------------------------------

@test "help text includes strip command" {
  run "$SCRIPTS_DIR/token-diet" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"strip"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 13.1 — diff-reads: dispatch
# ---------------------------------------------------------------------------

@test "diff-reads: exits 1 with usage when no file given" {
  run "$SCRIPTS_DIR/token-diet" diff-reads
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

@test "diff-reads: exits 1 when file does not exist" {
  run "$SCRIPTS_DIR/token-diet" diff-reads "/nonexistent/file.py"
  [ "$status" -eq 1 ]
}

@test "diff-reads: exits 0 and shows line ranges for a file in a git repo" {
  # Use the real repo root — it's a git repo with real changes
  run "$SCRIPTS_DIR/token-diet" diff-reads "$SCRIPTS_DIR/token-diet"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Cycle 13.3 — diff-reads: listed in --help
# ---------------------------------------------------------------------------

@test "help text includes diff-reads command" {
  run "$SCRIPTS_DIR/token-diet" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"diff-reads"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 14.1 — route: no task given
# ---------------------------------------------------------------------------

@test "route: exits 1 with usage when no task given" {
  run "$SCRIPTS_DIR/token-diet" route
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 14.2 — route: tilth for read/search tasks
# ---------------------------------------------------------------------------

@test "route: suggests tilth for read/search tasks" {
  run "$SCRIPTS_DIR/token-diet" route "read src/main.rs"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tilth"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 14.3 — route: Serena for rename/refactor, RTK for run/build/test
# ---------------------------------------------------------------------------

@test "route: suggests Serena for rename/refactor tasks" {
  run "$SCRIPTS_DIR/token-diet" route "rename function foo to bar"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Serena"* ]] || [[ "$output" == *"serena"* ]]
}

@test "route: suggests RTK for run/build/test tasks" {
  run "$SCRIPTS_DIR/token-diet" route "run cargo test"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RTK"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 14.4 — route: listed in --help
# ---------------------------------------------------------------------------

@test "help text includes route command" {
  run "$SCRIPTS_DIR/token-diet" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"route"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 15.1 — leaks: no repeated file reads
# ---------------------------------------------------------------------------

@test "leaks: exits 0 with clean message when no repeated file reads" {
  mock_cmd_no_loops
  run "$SCRIPTS_DIR/token-diet" leaks
  [ "$status" -eq 0 ]
  [[ "$output" == *"No leaks"* ]] || [[ "$output" == *"no leaks"* ]] || [[ "$output" == *"clean"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 15.2 — leaks: detects files read 2+ times
# ---------------------------------------------------------------------------

@test "leaks: exits 1 and flags files read 2+ times" {
  cat > "$TMP_BIN/rtk" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
  --version) echo "rtk 0.34.3-mock"; exit 0 ;;
  gain)
    case "$2" in
      --history) echo '{"summary":{},"commands":[{"cmd":"cat src/auth.rs","count":3,"total_input":9000,"total_saved":7000,"avg_pct":77.0},{"cmd":"cat src/main.rs","count":2,"total_input":6000,"total_saved":4500,"avg_pct":75.0},{"cmd":"git status","count":1,"total_input":500,"total_saved":400,"avg_pct":80.0}]}'; exit 0 ;;
      --format)  echo '{"summary":{"total_commands":6,"total_input":15500,"total_saved":11900,"avg_savings_pct":76.8,"total_time_ms":100},"daily":[]}'; exit 0 ;;
      *)         echo "Usage: rtk gain [OPTIONS]"; exit 0 ;;
    esac ;;
  *)  exit 0 ;;
esac
MOCK
  chmod +x "$TMP_BIN/rtk"

  run "$SCRIPTS_DIR/token-diet" leaks
  [ "$status" -eq 1 ]
  [[ "$output" == *"auth.rs"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 15.3 — leaks: listed in --help
# ---------------------------------------------------------------------------

@test "help text includes leaks command" {
  run "$SCRIPTS_DIR/token-diet" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"leaks"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 16.1 — test-first: dispatch
# ---------------------------------------------------------------------------

@test "test-first: exits 1 with usage when no file given" {
  run "$SCRIPTS_DIR/token-diet" test-first
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 16.2 — test-first: suggests test paths
# ---------------------------------------------------------------------------

@test "test-first: suggests test file path for a Python source file" {
  run "$SCRIPTS_DIR/token-diet" test-first "src/auth.py"
  [ "$status" -eq 0 ]
  [[ "$output" == *"auth"* ]]
  [[ "$output" == *"test"* ]]
}

@test "test-first: suggests test file path for a Rust source file" {
  run "$SCRIPTS_DIR/token-diet" test-first "src/auth.rs"
  [ "$status" -eq 0 ]
  [[ "$output" == *"auth"* ]]
  [[ "$output" == *"test"* ]]
}

# ---------------------------------------------------------------------------
# Cycle 16.3 — test-first: listed in --help
# ---------------------------------------------------------------------------

@test "help text includes test-first command" {
  run "$SCRIPTS_DIR/token-diet" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-first"* ]]
}
