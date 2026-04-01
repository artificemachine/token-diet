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
  GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
else
  GREEN=''; YELLOW=''; RED=''; BLUE=''; BOLD=''; NC=''
fi

info()  { echo -e "${BLUE}[info]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ok]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC}  $*"; }
fail()  { echo -e "${RED}[fail]${NC}  $*"; exit 1; }
header(){ echo -e "\n${BOLD}--- $* ---${NC}\n"; }

# --- Prerequisite checks -----------------------------------------------------
check_command() { command -v "$1" &>/dev/null; }

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
    rustup update stable --no-self-update 2>/dev/null || true
  else
    info "Installing Rust toolchain via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
    # shellcheck source=/dev/null
    source "$HOME/.cargo/env"
    ok "Rust installed: $(rustc --version)"
  fi
}

ensure_uv() {
  if check_command uv; then
    ok "uv found: $(uv --version 2>/dev/null)"
  else
    info "Installing uv (Python package manager)..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
    ok "uv installed: $(uv --version)"
  fi
}

ensure_docker() {
  check_command docker || fail "Docker required for local Serena install."
  ok "docker found: $(docker --version 2>/dev/null)"
}

# --- Host detection -----------------------------------------------------------
HAS_CLAUDE=false; HAS_CODEX=false; HAS_OPENCODE=false; HAS_COPILOT=false; HAS_VSCODE=false

detect_hosts() {
  check_command claude     && HAS_CLAUDE=true
  check_command codex      && HAS_CODEX=true
  check_command opencode   && HAS_OPENCODE=true
  check_command github-copilot-cli && HAS_COPILOT=true
  # VS Code: check if 'code' CLI exists
  check_command code       && HAS_VSCODE=true

  if $HAS_CLAUDE;   then ok "Claude Code ..... found"; else warn "Claude Code ..... not found"; fi
  if $HAS_CODEX;    then ok "Codex CLI ....... found"; else warn "Codex CLI ....... not found"; fi
  if $HAS_OPENCODE; then ok "OpenCode ........ found"; else warn "OpenCode ........ not found"; fi
  if $HAS_COPILOT;  then ok "Copilot CLI ..... found"; else warn "Copilot CLI ..... not found"; fi
  if $HAS_VSCODE;   then ok "VS Code ......... found"; else warn "VS Code ......... not found"; fi

  if ! $HAS_CLAUDE && ! $HAS_CODEX && ! $HAS_OPENCODE && ! $HAS_COPILOT && ! $HAS_VSCODE; then
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
    info "Building RTK from fork (no internet)..."
    cargo install --path "$PROJECT_ROOT/forks/rtk" --force 2>&1 | tail -5
    ok "RTK built and installed from fork"
  else
    cargo install --git "$RTK_REPO" --force 2>&1 | tail -5
    ok "RTK installed: $(rtk --version 2>/dev/null)"
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
    rtk init -g --opencode 2>/dev/null \
      && ok "RTK: Claude Code + Codex + OpenCode (global)" \
      || warn "RTK init failed (may already be configured)"
  elif $HAS_CLAUDE; then
    rtk init -g 2>/dev/null \
      && ok "RTK: Claude Code + Codex (global)" \
      || warn "RTK init failed (may already be configured)"
  fi

  if $HAS_CODEX && ! $HAS_CLAUDE; then
    rtk init --codex 2>/dev/null \
      && ok "RTK: Codex CLI" \
      || warn "RTK Codex init failed"
  fi

  if $HAS_OPENCODE && ! $HAS_CLAUDE; then
    rtk init -g --opencode 2>/dev/null \
      && ok "RTK: OpenCode" \
      || warn "RTK OpenCode init failed"
  fi

  # Copilot CLI uses the same hook system as Claude Code
  if $HAS_COPILOT; then
    ok "RTK: Copilot CLI (uses same hooks as Claude Code)"
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
    info "Building tilth from fork (no internet)..."
    cargo install --path "$PROJECT_ROOT/forks/tilth" --force 2>&1 | tail -5
    ok "tilth built and installed from fork"
  else
    cargo install --git "$TILTH_REPO" --force 2>&1 | tail -5
    ok "tilth installed: $(tilth --version 2>/dev/null)"
  fi

  # Host integration — tilth install <host>
  local hosts=()
  $HAS_CLAUDE   && hosts+=("claude-code")
  $HAS_CODEX    && hosts+=("codex")
  $HAS_OPENCODE && hosts+=("opencode")
  $HAS_COPILOT  && hosts+=("copilot")
  $HAS_VSCODE   && hosts+=("vscode")

  for host in "${hosts[@]}"; do
    tilth install "$host" 2>/dev/null \
      && ok "tilth MCP: $host" \
      || warn "tilth MCP: $host failed (may already exist)"
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
      info "Building Serena Docker image from fork (no internet)..."
      ensure_docker
      docker build -f "$PROJECT_ROOT/docker/Dockerfile.serena" -t token-diet/serena:latest "$PROJECT_ROOT" 2>&1 | tail -10
      ok "Serena Docker image built"
    fi

    local serena_cmd="docker run --rm -i -v \$(pwd):/workspace:ro --network none token-diet/serena:latest"
  else
    info "Verifying Serena via uvx..."
    if uvx --from "git+${SERENA_REPO}" serena --help &>/dev/null; then
      ok "Serena accessible via uvx"
    else
      warn "Serena fetch via uvx failed. May work on first real invocation."
    fi

    local serena_cmd="uvx --from git+${SERENA_REPO} serena start-mcp-server --project-from-cwd"
  fi

  # Claude Code MCP
  if $HAS_CLAUDE; then
    if $LOCAL_MODE; then
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

  # VS Code — write .vscode/mcp.json template
  if $HAS_VSCODE; then
    local vscode_template="$HOME/.config/token-diet/vscode-mcp.template.json"
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

  # OpenCode — writes to ~/.opencode.json (mcpServers format, same as tilth)
  if $HAS_OPENCODE; then
    local oc_cfg="$HOME/.opencode.json"
    if $LOCAL_MODE; then
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
}

# --- Overlap fix --------------------------------------------------------------
configure_dedup() {
  header "Overlap fix (Serena dedup)"

  if ! check_command tilth; then
    info "tilth not installed — skipping dedup config"
    return 0
  fi

  local template_dir="$HOME/.config/serena"
  mkdir -p "$template_dir"

  local template_file="$template_dir/project.local.template.yml"
  local config_source="$SCRIPT_DIR/../config/serena-dedup.template.yml"

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

  echo ""
  if $all_ok; then
    ok "All tools installed. Token diet active."
  else
    warn "Some tools missing. Re-run to install."
  fi

  echo ""
  info "Architecture:"
  cat << 'EOF'

  +-----------------------------------------------------------+
  |  Claude Code / Codex / OpenCode / Copilot CLI / VS Code   |
  +-----------------------------------------------------------+
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
  Claude Code, Codex CLI, OpenCode, Copilot CLI, VS Code

Options:
  --all          Install all three tools (default)
  --local        Install from local forks/dist (air-gapped)
  --rtk-only     Install only RTK
  --tilth-only   Install only tilth
  --serena-only  Install only Serena
  --verify       Only verify current installation
  --no-dedup     Skip overlap fix configuration
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
  local l
  read -rp "  Air-gapped / local build? [y/N] " l
  [[ "$l" =~ ^[Yy] ]] && WIZ_LOCAL=true

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
      -h|--help)      usage; exit 0 ;;
      *)              warn "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
  done

  echo -e "\n${BOLD}=== token-diet ===${NC}"
  echo -e "${BOLD}    RTK + tilth + Serena${NC}"
  echo ""

  if $verify_only; then
    detect_hosts
    verify_stack
    exit 0
  fi

  # Interactive mode when no args given
  if ! $has_args; then
    run_wizard
    do_rtk=$WIZ_RTK; do_tilth=$WIZ_TILTH; do_serena=$WIZ_SERENA
    do_dedup=$WIZ_DEDUP; LOCAL_MODE=$WIZ_LOCAL
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

  verify_stack
}

main "$@"
