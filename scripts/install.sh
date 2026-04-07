#!/usr/bin/env bash
# token-diet installer — RTK + tilth + Serena on macOS/Linux
# Supports: Claude Code, Codex CLI, OpenCode, Copilot CLI, VS Code
# Modes: --online (default, installs from fork repos) or --local (builds from forks/ submodules, no internet)
#
# Usage:
#   bash install.sh                   # install all from upstream
#   bash install.sh --local           # install from local forks/dist
#   bash install.sh --rtk-only        # install one tool
#   bash install.sh --verify          # check status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# --- Configuration -----------------------------------------------------------
RTK_REPO="https://github.com/celstnblacc/rtk"
TILTH_REPO="https://github.com/celstnblacc/tilth"
SERENA_REPO="https://github.com/celstnblacc/serena"

# Colors
if [ -t 1 ]; then
  GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
  BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; NC='\033[0m'
else
  GREEN=''; YELLOW=''; RED=''; BLUE=''; MAGENTA=''; BOLD=''; NC=''
fi

info()    { echo -e "${BLUE}[info]${NC}  $*"; }
ok()      { echo -e "${GREEN}[ok]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}  $*"; }
fail()    { echo -e "${RED}[fail]${NC}  $*"; exit 1; }
header()  { echo -e "\n${BOLD}--- $* ---${NC}\n"; }
dryrun()  { echo -e "${MAGENTA:-\033[0;35m}[dry-run]${NC} would run: $*"; }

# show_output — pipe build output through.
# Without --verbose: show only the last 5 lines (less noise).
# With --verbose:    show everything and tee to install.log.
LOG_FILE="${HOME}/.local/share/token-diet/install.log"
show_output() {
  if [ "${VERBOSE:-false}" = "true" ]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    tee -a "$LOG_FILE"
  else
    tail -5
  fi
}

rotate_log() {
  [ -f "$LOG_FILE" ] || return 0
  local size; size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
  if [ "$size" -gt 524288 ]; then   # 512 KB
    mv "$LOG_FILE" "${LOG_FILE}.1"
  fi
}

# --- Local build verification (--local mode only) ----------------------------
# Runs clippy + tests before cargo install to catch broken builds early.
# Skipped when SKIP_TESTS=true (--skip-tests flag).
verify_local_build() {
  local name="$1"        # display name, e.g. "RTK"
  local manifest="$2"    # path to Cargo.toml

  if [ "${SKIP_TESTS:-false}" = "true" ]; then
    info "$name: skipping clippy + tests (--skip-tests)"
    return 0
  fi

  info "$name: running clippy..."
  if cargo clippy --manifest-path "$manifest" --all-targets -- -D warnings 2>&1; then
    ok "$name clippy clean"
  else
    warn "$name clippy warnings found — continuing install (fix before release)"
  fi

  info "$name: running tests..."
  local log; log=$(mktemp)
  if cargo test --manifest-path "$manifest" 2>&1 | tee "$log" | show_output; then
    if grep -qE "^FAILED|error\[E" "$log"; then
      warn "$name test failures detected — continuing install (check $log)"
    else
      ok "$name tests passed"
    fi
  else
    warn "$name tests did not complete cleanly — continuing install"
  fi
  rm -f "$log"
}

# --- Prerequisite checks -----------------------------------------------------
check_command() { command -v "$1" &>/dev/null; }

# Extract the configured command for [mcp_servers.<tool>] from Codex TOML.
codex_mcp_command() {
  local tool="$1"
  local codex="$HOME/.codex/config.toml"
  check_command python3 || return 1
  [ -f "$codex" ] || return 1

  python3 - "$codex" "$tool" << 'PY'
import pathlib, re, sys

cfg_path = pathlib.Path(sys.argv[1])
tool = sys.argv[2]
text = cfg_path.read_text()
block = re.search(r'(?ms)^\[mcp_servers\.%s\]\s*(.*?)(?=^\[|\Z)' % re.escape(tool), text)
if not block:
    raise SystemExit(1)
command = re.search(r'(?m)^command\s*=\s*["\']([^"\']+)["\']\s*$', block.group(1))
if not command:
    raise SystemExit(1)
print(command.group(1))
PY
}

mcp_command_exists() {
  local command_value="$1"
  if [[ "$command_value" == */* ]]; then
    [ -x "$command_value" ]
  else
    check_command "$command_value"
  fi
}

codex_tilth_issue() {
  local command_value
  command_value="$(codex_mcp_command "tilth")" || return 0
  if ! mcp_command_exists "$command_value"; then
    echo "Codex tilth MCP command missing: ${command_value}"
  fi
  return 0
}

ensure_git() {
  check_command git || fail "git is required. Install it first."
  ok "git found: $(git --version)"

  # Initialize submodules so forks/ is populated for --local builds
  if [ -f "$PROJECT_ROOT/.gitmodules" ]; then
    info "Initializing submodules (forks/rtk, forks/tilth, forks/serena)..."
    git -C "$PROJECT_ROOT" submodule update --init --recursive 2>&1 \
      | grep -E "Cloning|already|error" || true
    ok "Submodules ready"
  fi
}

ensure_curl() {
  check_command curl || fail "curl is required. Install it first."
}

ensure_rust() {
  if check_command rustup; then
    ok "Rust toolchain found: $(rustc --version 2>/dev/null || echo 'updating...')"
    if [ "${DRY_RUN:-false}" = "true" ]; then
      dryrun "rustup update stable --no-self-update"
    else
      rustup update stable --no-self-update 2>/dev/null || true
    fi
  else
    if [ "${DRY_RUN:-false}" = "true" ]; then
      dryrun "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable"
    else
      info "Installing Rust toolchain via rustup..."
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
      # shellcheck source=/dev/null
      source "$HOME/.cargo/env"
      ok "Rust installed: $(rustc --version)"
    fi
  fi
}

ensure_uv() {
  if check_command uv; then
    ok "uv found: $(uv --version 2>/dev/null)"
  else
    if [ "${DRY_RUN:-false}" = "true" ]; then
      dryrun "curl -LsSf https://astral.sh/uv/install.sh | sh"
    else
      info "Installing uv (Python package manager)..."
      curl -LsSf https://astral.sh/uv/install.sh | sh
      export PATH="$HOME/.local/bin:$PATH"
      ok "uv installed: $(uv --version)"
    fi
  fi
}

ensure_docker() {
  check_command docker || fail "Docker required for local Serena install."
  ok "docker found: $(docker --version 2>/dev/null)"
}

# --- Host detection -----------------------------------------------------------
HAS_CLAUDE=false; HAS_CODEX=false; HAS_OPENCODE=false; HAS_COPILOT=false; HAS_VSCODE=false; HAS_COWORK=false
COWORK_CFG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"

detect_hosts() {
  check_command claude     && HAS_CLAUDE=true
  check_command codex      && HAS_CODEX=true
  check_command opencode   && HAS_OPENCODE=true
  check_command github-copilot-cli && HAS_COPILOT=true
  # VS Code: check if 'code' CLI exists
  check_command code       && HAS_VSCODE=true
  # Cowork (Claude Desktop): check for config file
  [ -f "$COWORK_CFG" ] && HAS_COWORK=true

  if $HAS_CLAUDE;   then ok "Claude Code ..... found"; else warn "Claude Code ..... not found"; fi
  if $HAS_CODEX;    then ok "Codex CLI ....... found"; else warn "Codex CLI ....... not found"; fi
  if $HAS_OPENCODE; then ok "OpenCode ........ found"; else warn "OpenCode ........ not found"; fi
  if $HAS_COPILOT;  then ok "Copilot CLI ..... found"; else warn "Copilot CLI ..... not found"; fi
  if $HAS_VSCODE;   then ok "VS Code ......... found"; else warn "VS Code ......... not found"; fi
  if $HAS_COWORK;   then ok "Cowork (Desktop)  found"; else warn "Cowork (Desktop)  not found"; fi

  if ! $HAS_CLAUDE && ! $HAS_CODEX && ! $HAS_OPENCODE && ! $HAS_COPILOT && ! $HAS_VSCODE && ! $HAS_COWORK; then
    warn "No AI host detected. Tools installed but integrations skipped."
  fi
}

# --- RTK ----------------------------------------------------------------------
install_rtk() {
  header "RTK (Rust Token Killer)"

  if check_command rtk && rtk gain --help &>/dev/null; then
    ok "RTK already installed: $(rtk --version 2>/dev/null)"
    info "Upgrading..."
  elif check_command rtk; then
    warn "Wrong 'rtk' detected (Rust Type Kit?). Reinstalling."
  fi

  if $LOCAL_MODE; then
    verify_local_build "RTK" "$PROJECT_ROOT/forks/rtk/Cargo.toml"
    if [ "${DRY_RUN:-false}" = "true" ]; then
      dryrun "cargo install --path $PROJECT_ROOT/forks/rtk --force"
    else
      info "Building RTK from fork (no internet)..."
      cargo install --path "$PROJECT_ROOT/forks/rtk" --force 2>&1 | show_output
      ok "RTK built and installed from fork"
    fi
  else
    if [ "${DRY_RUN:-false}" = "true" ]; then
      dryrun "cargo install --git $RTK_REPO --force"
    else
      cargo install --git "$RTK_REPO" --force 2>&1 | show_output
      ok "RTK installed: $(rtk --version 2>/dev/null)"
    fi
  fi

  # Verify
  if ! rtk gain --help &>/dev/null; then
    warn "RTK verification failed"
    return
  fi
  ok "RTK verification passed"

  # Host integration
  info "Configuring RTK for detected hosts..."

  if $HAS_CLAUDE && $HAS_OPENCODE; then
    [ "${DRY_RUN:-false}" = "true" ] \
      && dryrun "rtk init -g --opencode" \
      || { rtk init -g --opencode 2>/dev/null && ok "RTK: Claude Code + Codex + OpenCode (global)" || warn "RTK init failed (may already be configured)"; }
  elif $HAS_CLAUDE; then
    [ "${DRY_RUN:-false}" = "true" ] \
      && dryrun "rtk init -g" \
      || { rtk init -g 2>/dev/null && ok "RTK: Claude Code + Codex (global)" || warn "RTK init failed (may already be configured)"; }
  fi

  if $HAS_CODEX && ! $HAS_CLAUDE; then
    [ "${DRY_RUN:-false}" = "true" ] \
      && dryrun "rtk init --codex" \
      || { rtk init --codex 2>/dev/null && ok "RTK: Codex CLI" || warn "RTK Codex init failed"; }
  fi

  if $HAS_OPENCODE && ! $HAS_CLAUDE; then
    [ "${DRY_RUN:-false}" = "true" ] \
      && dryrun "rtk init -g --opencode" \
      || { rtk init -g --opencode 2>/dev/null && ok "RTK: OpenCode" || warn "RTK OpenCode init failed"; }
  fi

  # Copilot CLI uses the same hook system as Claude Code
  if $HAS_COPILOT; then
    ok "RTK: Copilot CLI (uses same hooks as Claude Code)"
  fi

  # Cowork (Claude Desktop) — no hook mechanism; write an awareness doc instead.
  # RTK works via shell hooks that rewrite Bash tool calls. Claude Desktop does not
  # support the same hook dispatch, so we write a markdown doc that instructs the
  # LLM to manually prefix commands with `rtk`.
  if $HAS_COWORK; then
    local cowork_dir
    cowork_dir="$(dirname "$COWORK_CFG")"
    local rtk_doc="$cowork_dir/rtk-awareness.md"
    if [ "${DRY_RUN:-false}" = "true" ]; then
      dryrun "Write RTK awareness doc to $rtk_doc"
    else
      mkdir -p "$cowork_dir"
      cat > "$rtk_doc" << 'RTKDOC'
# RTK - Rust Token Killer (Cowork / Claude Desktop)

**Usage**: Token-optimized CLI proxy for shell commands (60-90% savings).

## Rule

Always prefix shell commands with `rtk`. RTK compresses output to save tokens.
If RTK has no filter for a command, it passes through unchanged — always safe to use.

Examples:

```bash
rtk git status
rtk cargo test
rtk npm run build
rtk pytest -q
rtk docker ps
rtk ls -la
```

Even in command chains with `&&`, prefix each command:
```bash
rtk git add . && rtk git commit -m "msg" && rtk git push
```

## Meta Commands

```bash
rtk gain            # Token savings analytics
rtk gain --history  # Recent command savings history
rtk discover        # Analyze sessions for missed RTK usage
rtk proxy <cmd>     # Run raw command without filtering (debugging)
```

## Verification

```bash
rtk --version
rtk gain
which rtk
```
RTKDOC
      ok "RTK: Cowork awareness doc written ($rtk_doc)"
      info "  Cowork has no hook support — LLM instructed to prefix commands with 'rtk'"
    fi
  fi
}

# --- tilth --------------------------------------------------------------------
install_tilth() {
  header "tilth (smart code reader)"

  if check_command tilth; then
    ok "tilth already installed: $(tilth --version 2>/dev/null || echo 'unknown')"
    info "Upgrading..."
  fi

  if $LOCAL_MODE; then
    verify_local_build "tilth" "$PROJECT_ROOT/forks/tilth/Cargo.toml"
    if [ "${DRY_RUN:-false}" = "true" ]; then
      dryrun "cargo install --path $PROJECT_ROOT/forks/tilth --force"
    else
      info "Building tilth from fork (no internet)..."
      cargo install --path "$PROJECT_ROOT/forks/tilth" --force 2>&1 | show_output
      ok "tilth built and installed from fork"
    fi
  else
    if [ "${DRY_RUN:-false}" = "true" ]; then
      dryrun "cargo install --git $TILTH_REPO --force"
    else
      cargo install --git "$TILTH_REPO" --force 2>&1 | show_output
      ok "tilth installed: $(tilth --version 2>/dev/null)"
    fi
  fi

  # Host integration — tilth install <host>
  # Note: Cowork (Claude Desktop) is handled via JSON injection in install_serena,
  # not via tilth install, as it lacks a CLI integration path.
  local hosts=()
  $HAS_CLAUDE   && hosts+=("claude-code")
  $HAS_CODEX    && hosts+=("codex")
  $HAS_OPENCODE && hosts+=("opencode")
  $HAS_COPILOT  && hosts+=("copilot")
  $HAS_VSCODE   && hosts+=("vscode")

  for host in "${hosts[@]}"; do
    if [ "${DRY_RUN:-false}" = "true" ]; then
      dryrun "tilth install $host"
    else
      tilth install "$host" 2>/dev/null \
        && ok "tilth MCP: $host" \
        || warn "tilth MCP: $host failed (may already exist)"
    fi
  done

  if [ ${#hosts[@]} -eq 0 ]; then
    warn "tilth: no AI host detected, skipping MCP registration"
  fi
}

# --- Serena -------------------------------------------------------------------
install_serena() {
  header "Serena (IDE-like symbol navigation)"

  if $LOCAL_MODE; then
    if docker image inspect token-diet/serena:latest &>/dev/null; then
      ok "Serena Docker image already built"
    else
      if [ "${DRY_RUN:-false}" = "true" ]; then
        dryrun "docker build -f $PROJECT_ROOT/docker/Dockerfile.serena -t token-diet/serena:latest $PROJECT_ROOT"
      else
        info "Building Serena Docker image from fork (no internet)..."
        ensure_docker
        docker build -f "$PROJECT_ROOT/docker/Dockerfile.serena" -t token-diet/serena:latest "$PROJECT_ROOT" 2>&1 | tail -10
        ok "Serena Docker image built"
      fi
    fi
    local serena_cmd="docker run --rm -i -v \$(pwd):/workspace:ro --network none token-diet/serena:latest"
  else
    if [ "${DRY_RUN:-false}" = "true" ]; then
      dryrun "uvx --from git+${SERENA_REPO} serena --help  (prefetch check)"
    else
      info "Verifying Serena via uvx..."
      if uvx --from "git+${SERENA_REPO}" serena --help &>/dev/null; then
        ok "Serena accessible via uvx"
      else
        warn "Serena fetch via uvx failed. May work on first real invocation."
      fi
    fi
    local serena_cmd="uvx --from git+${SERENA_REPO} serena start-mcp-server --project-from-cwd"
  fi

  # Claude Code MCP
  if $HAS_CLAUDE; then
    if [ "${DRY_RUN:-false}" = "true" ]; then
      $LOCAL_MODE \
        && dryrun "claude mcp add --scope user serena -- docker run ... token-diet/serena:latest --context=claude-code" \
        || dryrun "claude mcp add --scope user serena -- uvx --from git+${SERENA_REPO} serena start-mcp-server --context=claude-code --project-from-cwd"
    elif $LOCAL_MODE; then
      claude mcp add --scope user serena -- \
        docker run --rm -i -v "\$(pwd):/workspace:ro" --network none \
        token-diet/serena:latest --context=claude-code --project /workspace \
        2>/dev/null \
        && ok "Serena MCP: Claude Code (Docker)" \
        || warn "Serena MCP: Claude Code setup failed (may already exist)"
    else
      claude mcp add --scope user serena -- \
        uvx --from "git+${SERENA_REPO}" serena start-mcp-server \
        --context=claude-code --project-from-cwd \
        2>/dev/null \
        && ok "Serena MCP: Claude Code" \
        || warn "Serena MCP: Claude Code setup failed (may already exist)"
    fi
  fi

  # Codex CLI
  if $HAS_CODEX; then
    local codex_config="$HOME/.codex/config.toml"
    if [ -f "$codex_config" ] && grep -q "serena" "$codex_config" 2>/dev/null; then
      ok "Serena MCP: Codex CLI (already configured)"
    else
      if [ "${DRY_RUN:-false}" = "true" ]; then
        dryrun "Append [mcp_servers.serena] block to $codex_config"
      else
        mkdir -p "$HOME/.codex"
        if $LOCAL_MODE; then
          cat >> "$codex_config" << 'TOML'

# Serena MCP server (added by token-diet, Docker mode)
[mcp_servers.serena]
command = "docker"
args = ["run", "--rm", "-i", "-v", ".:/workspace:ro", "--network", "none", "token-diet/serena:latest", "--context=codex", "--project", "/workspace"]
TOML
        else
          cat >> "$codex_config" << TOML

# Serena MCP server (added by token-diet)
[mcp_servers.serena]
command = "uvx"
args = ["--from", "git+${SERENA_REPO}", "serena", "start-mcp-server", "--context=codex", "--project-from-cwd"]
TOML
        fi
        ok "Serena MCP: Codex CLI"
      fi
    fi
  fi

  # VS Code — write .vscode/mcp.json template
  if $HAS_VSCODE; then
    local vscode_template="$HOME/.config/token-diet/vscode-mcp.template.json"
    if [ "${DRY_RUN:-false}" = "true" ]; then
      dryrun "Write VS Code MCP template to $vscode_template"
    else
      mkdir -p "$(dirname "$vscode_template")"
      cat > "$vscode_template" << 'JSON'
{
  "servers": {
    "serena": {
      "command": "uvx",
      "args": ["--from", "git+https://github.com/celstnblacc/serena", "serena", "start-mcp-server", "--context=ide", "--project-from-cwd"]
    },
    "tilth": {
      "command": "tilth",
      "args": ["mcp"]
    }
  }
}
JSON
      ok "VS Code MCP template: $vscode_template"
      info "  Copy to project: cp $vscode_template /path/to/project/.vscode/mcp.json"
    fi
  fi

  # OpenCode
  if $HAS_OPENCODE; then
    local oc_cfg="$HOME/.opencode.json"
    if [ "${DRY_RUN:-false}" = "true" ]; then
      dryrun "Write mcpServers.serena entry to $oc_cfg"
    elif $LOCAL_MODE; then
      python3 - "$oc_cfg" <<'PYEOF'
import json, sys
cfg = sys.argv[1]
try:
    with open(cfg) as f: data = json.load(f)
except FileNotFoundError:
    data = {}
data.setdefault("mcpServers", {})
data["mcpServers"]["serena"] = {
    "command": "docker",
    "args": ["run","--rm","-i","-v","$(pwd):/workspace:ro",
             "--network","none","token-diet/serena:latest",
             "--context=ide","--project","/workspace"]
}
with open(cfg, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF
      ok "Serena MCP: OpenCode (Docker, $oc_cfg)"
    else
      python3 - "$oc_cfg" "${SERENA_REPO}" <<'PYEOF'
import json, sys
cfg, repo = sys.argv[1], sys.argv[2]
try:
    with open(cfg) as f: data = json.load(f)
except FileNotFoundError:
    data = {}
data.setdefault("mcpServers", {})
data["mcpServers"]["serena"] = {
    "command": "uvx",
    "args": ["--from", "git+" + repo, "serena", "start-mcp-server",
             "--context=ide", "--project-from-cwd"]
}
with open(cfg, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF
      ok "Serena MCP: OpenCode ($oc_cfg)"
    fi
  fi
  if $HAS_COPILOT; then
    ok "Serena: Copilot CLI uses VS Code MCP config (shared)"
  fi

  # Cowork (Claude Desktop) — inject mcpServers.serena + mcpServers.tilth
  if $HAS_COWORK; then
    if [ "${DRY_RUN:-false}" = "true" ]; then
      dryrun "Write mcpServers.serena + mcpServers.tilth to $COWORK_CFG"
    else
      if $LOCAL_MODE; then
        python3 - "$COWORK_CFG" <<'PYEOF'
import json, sys
cfg = sys.argv[1]
try:
    with open(cfg) as f: data = json.load(f)
except FileNotFoundError:
    data = {}
data.setdefault("mcpServers", {})
data["mcpServers"]["serena"] = {
    "command": "docker",
    "args": ["run", "--rm", "-i", "-v", "$(pwd):/workspace:ro",
             "--network", "none", "token-diet/serena:latest",
             "--context=claude-code", "--project", "/workspace"]
}
with open(cfg, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF
      else
        python3 - "$COWORK_CFG" "${SERENA_REPO}" <<'PYEOF'
import json, sys
cfg, repo = sys.argv[1], sys.argv[2]
try:
    with open(cfg) as f: data = json.load(f)
except FileNotFoundError:
    data = {}
data.setdefault("mcpServers", {})
data["mcpServers"]["serena"] = {
    "command": "uvx",
    "args": ["--from", "git+" + repo, "serena", "start-mcp-server",
             "--context=claude-code", "--project-from-cwd"]
}
with open(cfg, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF
      fi

      # Also register tilth if installed
      if check_command tilth; then
        python3 - "$COWORK_CFG" <<'PYEOF'
import json, sys
cfg = sys.argv[1]
try:
    with open(cfg) as f: data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
data.setdefault("mcpServers", {})
data["mcpServers"]["tilth"] = {"command": "tilth", "args": ["mcp"]}
with open(cfg, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF
        ok "Serena + tilth MCP: Cowork / Claude Desktop ($COWORK_CFG)"
      else
        ok "Serena MCP: Cowork / Claude Desktop ($COWORK_CFG)"
      fi
    fi
  fi

  # Disable Serena's built-in web dashboard entirely.
  # On macOS, web_dashboard:true spawns a native pywebview app process per host.
  # With Serena registered in multiple hosts (claude-code, opencode, codex),
  # this causes multiple dashboard windows on every startup.
  # Users get a dashboard via `token-diet dashboard` instead.
  local serena_cfg="$HOME/.serena/serena_config.yml"
  if [ "${DRY_RUN:-false}" = "true" ]; then
    dryrun "Set web_dashboard: false + web_dashboard_open_on_launch: false in $serena_cfg"
  elif [ -f "$serena_cfg" ]; then
    sed -i.bak \
      -e 's/^web_dashboard: true/web_dashboard: false/' \
      -e 's/^web_dashboard_open_on_launch: true/web_dashboard_open_on_launch: false/' \
      "$serena_cfg"
    ok "Serena: disabled built-in web dashboard ($serena_cfg)"
  fi
}

# --- Overlap fix --------------------------------------------------------------
configure_dedup() {
  header "Overlap fix (Serena dedup)"

  if ! check_command tilth; then
    info "tilth not installed — skipping dedup config"
    return 0
  fi

  local template_dir="$HOME/.config/serena"
  local template_file="$template_dir/project.local.template.yml"
  local config_source="$SCRIPT_DIR/../config/serena-dedup.template.yml"

  if [ "${DRY_RUN:-false}" = "true" ]; then
    dryrun "Write serena dedup template to $template_file"
    return 0
  fi

  mkdir -p "$template_dir"

  if [ -f "$config_source" ]; then
    cp "$config_source" "$template_file"
  else
    cat > "$template_file" << 'YAML'
context: claude-code
disabled_tools:
  - get_symbols_overview
  - find_symbol
  - read_file
YAML
  fi

  ok "Dedup template: $template_file"
  info "Apply per project: cp $template_file /path/to/project/project.local.yml"
}

# --- Verification -------------------------------------------------------------
verify_stack() {
  header "Token Stack Verification"

  local all_ok=true

  # Tools
  if check_command rtk && rtk gain --help &>/dev/null; then
    ok "RTK ............. $(rtk --version 2>/dev/null)"
  else
    warn "RTK ............. not installed or wrong version"
    all_ok=false
  fi

  if check_command tilth; then
    ok "tilth ........... $(tilth --version 2>/dev/null || echo 'installed')"
    local tilth_codex_issue
    tilth_codex_issue="$(codex_tilth_issue)"
    if [ -n "$tilth_codex_issue" ]; then
      warn "$tilth_codex_issue"
      all_ok=false
    fi
  else
    warn "tilth ........... not installed"
    all_ok=false
  fi

  if $LOCAL_MODE; then
    if docker image inspect token-diet/serena:latest &>/dev/null; then
      ok "Serena .......... Docker image loaded"
    else
      warn "Serena .......... Docker image not found"
      all_ok=false
    fi
  else
    if check_command uv; then
      ok "Serena (via uv) . $(uv --version 2>/dev/null)"
    else
      warn "Serena (uv) ..... uv not installed"
      all_ok=false
    fi
  fi

  echo ""

  # Hosts
  if $HAS_CLAUDE;   then ok "Claude Code ..... available"; else warn "Claude Code ..... not found"; fi
  if $HAS_CODEX;    then ok "Codex CLI ....... available"; else warn "Codex CLI ....... not found"; fi
  if $HAS_OPENCODE; then ok "OpenCode ........ available"; else warn "OpenCode ........ not found"; fi
  if $HAS_COPILOT;  then ok "Copilot CLI ..... available"; else warn "Copilot CLI ..... not found"; fi
  if $HAS_VSCODE;   then ok "VS Code ......... available"; else warn "VS Code ......... not found"; fi
  if $HAS_COWORK;   then ok "Cowork (Desktop)  available"; else warn "Cowork (Desktop)  not found"; fi

  echo ""
  if $all_ok; then
    ok "All tools installed. Token diet active."
  else
    warn "Some tools or MCP registrations need attention. Re-run install or repair the host config."
  fi

  echo ""
  info "Architecture:"
  cat << 'EOF'

  +-------------------------------------------------------------------+
  |  Claude Code / Codex / OpenCode / Copilot CLI / VS Code          |
  |                     + Cowork (Claude Desktop)                     |
  +-------------------------------------------------------------------+
           |                |                |
      Code reading     Refactoring     Command output
           |                |                |
      +--------+      +---------+      +--------+
      | tilth  |      | Serena  |      |  RTK   |
      | (fast) |      |  (deep) |      | (filter)|
      +--------+      +---------+      +--------+
      tree-sitter        LSP           regex/truncate

EOF
}

# --- token-diet dashboard command ----------------------------------------------------
install_token_diet() {
  local bin_dir="$HOME/.local/bin"
  local src_bin="$SCRIPT_DIR/token-diet"
  local src_dash="$SCRIPT_DIR/token-diet-dashboard"

  if [ ! -f "$src_bin" ]; then
    warn "scripts/token-diet not found — skipping token-diet install"
    return 0
  fi

  if [ "${DRY_RUN:-false}" = "true" ]; then
    dryrun "install -m755 $src_bin $bin_dir/token-diet"
    [ -f "$src_dash" ] && dryrun "install -m755 $src_dash $bin_dir/token-diet-dashboard"
    dryrun "write ~/.claude/token-diet.md + add @token-diet.md to ~/.claude/CLAUDE.md"
    dryrun "write ~/.codex/token-diet.md + add @token-diet.md to ~/.codex/AGENTS.md"
    return 0
  fi

  mkdir -p "$bin_dir"
  install -m755 "$src_bin" "$bin_dir/token-diet"
  ok "token-diet installed: $bin_dir/token-diet"

  if [ -f "$src_dash" ]; then
    install -m755 "$src_dash" "$bin_dir/token-diet-dashboard"
    ok "token-diet-dashboard installed: $bin_dir/token-diet-dashboard"
  fi

  # Copy installer so `token-diet verify` works from ~/.local/bin
  install -m755 "$SCRIPT_DIR/install.sh" "$bin_dir/token-diet-install.sh"

  # Nudge if ~/.local/bin not in PATH
  if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    info "Add to your shell: export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi

  # Write token-diet.md into each AI host config dir and ensure it is referenced.
  # Idempotent: skips if token-diet.md already exists and is up to date.
  write_token-diet_md() {
    local config_dir="$1"
    local instruction_file="$2"  # CLAUDE.md or AGENTS.md

    [ -d "$config_dir" ] || return 0  # host not installed — skip silently

    local tkd_doc_file="$config_dir/token-diet.md"
    cat > "$tkd_doc_file" << 'TKDDOC'
# TKD — token-diet unified CLI

`token-diet` (`~/.local/bin/token-diet`) is the top-level command for the token-diet stack (RTK + tilth + Serena).

## Commands

```bash
token-diet gain       # Combined savings dashboard: RTK + tilth + Serena
token-diet version    # Installed versions of all three tools
token-diet verify     # Re-run installation verification
token-diet dashboard  # Open live browser dashboard
```

## Rules

- **`token-diet` is a real binary.** Never assume it is a typo for `rtk`.
- Run `which token-diet` if unsure whether it is installed.
- `token-diet gain` shows RTK tracked savings + tilth/Serena structural savings.
  RTK savings are exact (output compression). tilth + Serena savings are
  structural (smaller prompts, fewer turns) and shown as estimates.
TKDDOC
    ok "token-diet.md written: $tkd_doc_file"

    # Add @token-diet.md reference to instruction file if not already present
    if [ -f "$instruction_file" ] && ! grep -q "@token-diet.md" "$instruction_file"; then
      # Insert before @RTK.md if present, otherwise append
      if grep -q "@RTK.md" "$instruction_file"; then
        awk '/^@RTK\.md$/{print "@token-diet.md"}1' "$instruction_file" > "${instruction_file}.tmp" && mv "${instruction_file}.tmp" "$instruction_file"
      else
        printf "\n@token-diet.md\n" >> "$instruction_file"
      fi
      ok "@token-diet.md added to: $instruction_file"
    fi
  }

  write_token-diet_md "$HOME/.claude" "$HOME/.claude/CLAUDE.md"
  write_token-diet_md "$HOME/.codex" "$HOME/.codex/AGENTS.md"
  # Cowork (Claude Desktop) — write token-diet.md to its config dir if detected
  if $HAS_COWORK; then
    local cowork_dir
    cowork_dir="$(dirname "$COWORK_CFG")"
    write_token-diet_md "$cowork_dir" ""
  fi
}

# --- Main ---------------------------------------------------------------------
usage() {
  cat << EOF
Usage: $0 [OPTIONS]

token-diet: AI token optimization stack installer

Tools:
  RTK      CLI output compression (60-90% token savings)
  tilth    Smart code reading via tree-sitter AST
  Serena   IDE-like symbol navigation via LSP

Hosts (auto-detected):
  Claude Code, Codex CLI, OpenCode, Copilot CLI, VS Code, Cowork (Claude Desktop)

Options:
  --all          Install all three tools (default)
  --local        Install from local forks/dist (air-gapped)
  --rtk-only     Install only RTK
  --tilth-only   Install only tilth
  --serena-only  Install only Serena
  --verify       Only verify current installation
  --no-dedup     Skip overlap fix configuration
  --skip-tests   Skip clippy + tests in --local mode (faster install)
  --dry-run      Simulate install — detect hosts and show what would run, no changes made
  --verbose      Show full build output instead of last 5 lines; log to ~/.local/share/token-diet/install.log
  -h, --help     Show this help
EOF
}

# --- Interactive wizard -------------------------------------------------------
run_wizard() {
  echo ""
  echo -e "${BOLD}  token-diet interactive installer${NC}"
  echo -e "${BLUE}  RTK + tilth + Serena — security-patched forks${NC}"
  echo ""
  echo "  Tools:"
  echo "    RTK    — CLI output compression (60-90% token savings)"
  echo "    tilth  — smart code reading via tree-sitter AST"
  echo "    Serena — IDE-like symbol navigation via LSP"
  echo ""

  local answer
  read -rp "  Install all three tools? [Y/n] " answer
  if [[ "$answer" =~ ^[Nn] ]]; then
    local r t s
    read -rp "    Install RTK?    [Y/n] " r
    read -rp "    Install tilth?  [Y/n] " t
    read -rp "    Install Serena? [Y/n] " s
    [[ ! "$r" =~ ^[Nn] ]] && WIZ_RTK=true    || WIZ_RTK=false
    [[ ! "$t" =~ ^[Nn] ]] && WIZ_TILTH=true  || WIZ_TILTH=false
    [[ ! "$s" =~ ^[Nn] ]] && WIZ_SERENA=true || WIZ_SERENA=false
  else
    WIZ_RTK=true; WIZ_TILTH=true; WIZ_SERENA=true
  fi

  WIZ_DEDUP=false
  if $WIZ_TILTH && $WIZ_SERENA; then
    local d
    read -rp "  Configure Serena/tilth overlap fix? [Y/n] " d
    [[ ! "$d" =~ ^[Nn] ]] && WIZ_DEDUP=true
  fi

  WIZ_LOCAL=false
  WIZ_SKIP_TESTS=false
  local l
  read -rp "  Air-gapped / local build? [y/N] " l
  if [[ "$l" =~ ^[Yy] ]]; then
    WIZ_LOCAL=true
    local st
    read -rp "  Skip clippy + tests? (faster, not recommended) [y/N] " st
    [[ "$st" =~ ^[Yy] ]] && WIZ_SKIP_TESTS=true
  fi

  echo ""
  echo -e "${BOLD}  Ready to install:${NC}"
  $WIZ_RTK    && echo -e "  ${GREEN}+ RTK${NC}"
  $WIZ_TILTH  && echo -e "  ${GREEN}+ tilth${NC}"
  $WIZ_SERENA && echo -e "  ${GREEN}+ Serena${NC}"
  $WIZ_DEDUP  && echo -e "  ${GREEN}+ Overlap fix${NC}"
  $WIZ_LOCAL  && echo -e "  ${YELLOW}  Mode: LOCAL (air-gapped)${NC}"
  echo ""

  local confirm
  read -rp "  Proceed? [Y/n] " confirm
  [[ "$confirm" =~ ^[Nn] ]] && echo "Aborted." && exit 0
}

# --- Main ---------------------------------------------------------------------
main() {
  local do_rtk=false do_tilth=false do_serena=false
  local do_dedup=true verify_only=false has_args=false
  LOCAL_MODE=false
  SKIP_TESTS=false
  DRY_RUN=false
  VERBOSE=false

  while [ $# -gt 0 ]; do
    has_args=true
    case "$1" in
      --all)          do_rtk=true; do_tilth=true; do_serena=true ;;
      --local)        LOCAL_MODE=true ;;
      --rtk-only)     do_rtk=true ;;
      --tilth-only)   do_tilth=true ;;
      --serena-only)  do_serena=true ;;
      --verify)       verify_only=true ;;
      --no-dedup)     do_dedup=false ;;
      --skip-tests)   SKIP_TESTS=true ;;
      --dry-run)      DRY_RUN=true; SKIP_TESTS=true ;;
      --verbose)      VERBOSE=true ;;
      -h|--help)      usage; exit 0 ;;
      *)              warn "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
  done

  if [ "$VERBOSE" = "true" ]; then
    rotate_log
    info "Verbose mode — full output logged to $LOG_FILE"
  fi

  echo -e "\n${BOLD}=== token-diet ===${NC}"
  echo -e "${BOLD}    RTK + tilth + Serena${NC}"
  echo ""
  if [ "${DRY_RUN:-false}" = "true" ]; then
    echo -e "${MAGENTA}    *** DRY-RUN MODE — no changes will be made ***${NC}\n"
  fi

  if $verify_only; then
    detect_hosts
    verify_stack
    exit 0
  fi

  # Interactive mode when no args given
  if ! $has_args; then
    run_wizard
    do_rtk=$WIZ_RTK; do_tilth=$WIZ_TILTH; do_serena=$WIZ_SERENA
    do_dedup=$WIZ_DEDUP; LOCAL_MODE=$WIZ_LOCAL; SKIP_TESTS=$WIZ_SKIP_TESTS
  fi

  if $LOCAL_MODE; then echo -e "${BOLD}    Mode: LOCAL (air-gapped)${NC}\n"; fi

  # Prerequisites
  header "Prerequisites"
  ensure_git
  if ! $LOCAL_MODE; then ensure_curl; fi
  if $do_rtk || $do_tilth; then ensure_rust; fi
  if $do_serena && ! $LOCAL_MODE; then ensure_uv; fi
  if $do_serena && $LOCAL_MODE; then ensure_docker; fi

  # Detect AI hosts
  header "AI Host Detection"
  detect_hosts

  # Install tools
  $do_rtk    && install_rtk
  $do_tilth  && install_tilth
  $do_serena && install_serena

  # Overlap fix
  if $do_dedup && $do_tilth && $do_serena; then
    configure_dedup
  fi

  # Install token-diet dashboard command
  install_token_diet

  verify_stack
}

main "$@"
