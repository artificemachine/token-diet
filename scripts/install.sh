#!/usr/bin/env bash
# token-diet installer — RTK + tilth + Serena + ICM on macOS/Linux
# Supports: Claude Code, Codex CLI, OpenCode, Copilot CLI, VS Code, Gemini CLI
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

# Single definition of the supported host list. install.sh sources this from the
# REPO at install time; the installed token-diet sources its own copy from
# $SCRIPT_DIR/lib at runtime. Different paths, same file, so the lib must not
# assume either. See docs/PLAN-phase5-host-registry.md.
source "$SCRIPT_DIR/lib/hosts.sh"

# --- Partial-failure reporting ----------------------------------------------
# This script mutates config files it does not own, across up to seven hosts.
# With `set -e` and no trap, a failure at host five exits silently with five
# hosts already modified and no record of which. TD_MUTATED accumulates every
# path touched so the trap can tell the user exactly what state they are in.
TD_MUTATED=()

# Call after successfully modifying a file, so a later failure can report it.
td_record_mutation() {
  TD_MUTATED+=("$1")
}

_td_on_error() {
  local exit_code=$1 line=$2
  echo "" >&2
  printf '%b\n' "${RED:-}[install] FAILED at line ${line} (exit ${exit_code})${NC:-}" >&2

  if [ "${#TD_MUTATED[@]}" -gt 0 ]; then
    echo "" >&2
    echo "Files already modified before the failure:" >&2
    local f
    for f in "${TD_MUTATED[@]}"; do
      echo "  - $f" >&2
    done
    echo "" >&2
    echo "Each modified config has a timestamped backup alongside it:" >&2
    echo "  ls -t <file>.bak-token-diet-*" >&2
    echo "" >&2
    echo "To revert one:  cp <file>.bak-token-diet-<ts> <file>" >&2
    echo "To remove everything this installer added:  bash scripts/uninstall.sh" >&2
  else
    echo "No config files were modified before the failure." >&2
  fi

  echo "" >&2
  echo "Re-running install.sh is safe: every registration step is idempotent." >&2
  exit "$exit_code"
}

trap '_td_on_error $? $LINENO' ERR

# --- Configuration -----------------------------------------------------------
RTK_REPO="https://github.com/artificemachine/rtk"
TILTH_REPO="https://github.com/artificemachine/tilth"
SERENA_REPO="https://github.com/artificemachine/serena"
ICM_REPO="https://github.com/artificemachine/icm"

# Pin the default (network) install to the exact revisions the forks/ submodules
# are pinned to, so a non-local install is reproducible and matches the audited
# forks + compat.json instead of floating to upstream HEAD. Single source of
# truth is the superproject gitlink — derived, never duplicated. Empty when
# install.sh runs outside the git checkout (curl|sh of the bare script); each
# use site falls back to floating HEAD with a warning.
_pin_rev() { git -C "$PROJECT_ROOT" rev-parse "HEAD:forks/$1" 2>/dev/null || true; }
RTK_REV="$(_pin_rev rtk)"
TILTH_REV="$(_pin_rev tilth)"
SERENA_REV="$(_pin_rev serena)"
ICM_REV="$(_pin_rev icm)"
# uvx/pip git ref used across every Serena launcher + MCP registration site.
# Defined once here so the ref (and its pin) has a single definition.
SERENA_SRC="git+${SERENA_REPO}${SERENA_REV:+@${SERENA_REV}}"

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

codex_mcp_issue() {
  local tool="$1"
  local command_value
  command_value="$(codex_mcp_command "$tool")" || return 0
  if ! mcp_command_exists "$command_value"; then
    echo "Codex ${tool} MCP command missing: ${command_value}"
  fi
  return 0
}

# Inject token-diet usage rules into OpenCode mode.build.prompt + mode.plan.prompt.
# Idempotent — wraps the block in <!-- token-diet:begin --> / <!-- token-diet:end -->
# markers so repeat runs replace (never duplicate) the block and preserve user text.
inject_opencode_rules() {
  local oc_prompt_cfg="$HOME/.config/opencode/opencode.json"
  local rules_file
  rules_file="$(dirname "$0")/lib/opencode-rules.md"
  [ -f "$rules_file" ] || { warn "OpenCode rules template missing: $rules_file"; return 0; }

  if [ "${DRY_RUN:-false}" = "true" ]; then
    dryrun "Inject token-diet rules into mode.build.prompt + mode.plan.prompt at $oc_prompt_cfg"
    return 0
  fi

  mkdir -p "$(dirname "$oc_prompt_cfg")"
  [ -f "$oc_prompt_cfg" ] || echo '{}' > "$oc_prompt_cfg"

  TD_LIB_DIR="$SCRIPT_DIR/lib" python3 - "$oc_prompt_cfg" "$rules_file" <<'PYEOF'
import os, re, sys
sys.path.insert(0, os.environ["TD_LIB_DIR"])
import tdconfig

cfg_path, rules_path = sys.argv[1], sys.argv[2]
BEGIN = "<!-- token-diet:begin -->"
END   = "<!-- token-diet:end -->"
with open(rules_path) as f: rules_body = f.read().strip()
block = f"{BEGIN}\n{rules_body}\n{END}"
pattern = re.compile(re.escape(BEGIN) + r".*?" + re.escape(END), re.DOTALL)

def mutate(data):
    data.setdefault("mode", {})
    for mode_name in ("build", "plan"):
        data["mode"].setdefault(mode_name, {})
        existing = data["mode"][mode_name].get("prompt", "") or ""
        if BEGIN in existing:
            new = pattern.sub(block, existing, count=1)
        else:
            new = (existing + ("\n\n" if existing else "") + block).lstrip("\n")
        data["mode"][mode_name]["prompt"] = new

try:
    tdconfig.update_json(cfg_path, mutate)
except tdconfig.ConfigError as _e:
    _q = tdconfig.quarantine(cfg_path)
    print(f"[token-diet] ABORT: {cfg_path} is malformed JSON ({_e}); backed up to {_q}. Refusing to overwrite existing config — fix it and re-run.", file=sys.stderr)
    sys.exit(3)
PYEOF
  ok "OpenCode prompt rules injected: $oc_prompt_cfg"
}

ensure_git() {
  check_command git || fail "git is required. Install it first."
  ok "git found: $(git --version)"

  # Initialize submodules so forks/ is populated for --local builds
  if [ -f "$PROJECT_ROOT/.gitmodules" ]; then
    info "Initializing submodules (forks/rtk, forks/tilth, forks/serena, forks/icm)..."
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
HAS_CLAUDE=false; HAS_CODEX=false; HAS_OPENCODE=false; HAS_COPILOT=false; HAS_VSCODE=false; HAS_COWORK=false; HAS_GEMINI=false
HOSTS_FILTER=""   # set by --hosts flag; empty = prompt when multiple detected

resolve_cowork_cfg() {
  # The two Claude Desktop config paths come from the canonical registry
  # (config/hosts-mcp.json, host="claude-desktop"): macOS path first, Linux path
  # second, matching the registry's documented and observable order. install.sh
  # always runs from the repo, so it reads the repo copy; TD_HOSTS_MCP_REGISTRY
  # overrides that only for tests and is unset in production (identical paths).
  # Fall back to the literal pair when the registry yields anything other than
  # exactly two paths (e.g. curl|sh of the bare script with no checkout), so
  # behavior is preserved even without the registry.
  local mac_cfg linux_cfg
  local registry="${TD_HOSTS_MCP_REGISTRY:-$PROJECT_ROOT/config/hosts-mcp.json}"
  local reg_paths=()
  local _p
  while IFS= read -r _p; do
    [ -n "$_p" ] && reg_paths+=("$HOME/$_p")
  done < <(td_host_config_paths "$registry" claude-desktop)

  if [ "${#reg_paths[@]}" -eq 2 ]; then
    mac_cfg="${reg_paths[0]}"
    linux_cfg="${reg_paths[1]}"
  else
    mac_cfg="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
    linux_cfg="$HOME/.config/Claude/claude_desktop_config.json"
  fi

  if [ -f "$mac_cfg" ]; then
    echo "$mac_cfg"
    return
  fi

  if [ -f "$linux_cfg" ]; then
    echo "$linux_cfg"
    return
  fi

  case "$(uname -s)" in
    Darwin) echo "$mac_cfg" ;;
    *)      echo "$linux_cfg" ;;
  esac
}

COWORK_CFG="$(resolve_cowork_cfg)"

detect_hosts() {
  check_command claude     && HAS_CLAUDE=true
  check_command codex      && HAS_CODEX=true
  check_command opencode   && HAS_OPENCODE=true
  # Copilot CLI binary name varies: `github-copilot-cli` (legacy Homebrew) vs
  # `copilot` (current npm @github/copilot). Check both.
  { check_command github-copilot-cli || check_command copilot; } && HAS_COPILOT=true
  # VS Code: check if 'code' CLI exists
  check_command code       && HAS_VSCODE=true
  # Cowork (Claude Desktop): check for config file or desktop app
  { [ -f "$COWORK_CFG" ] || check_command claude-desktop; } && HAS_COWORK=true
  check_command gemini && HAS_GEMINI=true

  # Report detection status by looping the host registry (lib/hosts.sh) instead
  # of seven hardcoded lines. Output must stay byte-identical: each label is
  # padded with dots to a fixed column so the "found"/"not found" verbs align.
  # The longest label, "Cowork (Desktop)" (16 chars), carries zero dots and its
  # two surrounding spaces produce the observed "Cowork (Desktop)  found"; every
  # shorter label gets (16 - len) dots. Labels contain spaces, so read them
  # line-by-line, not word-split.
  local _slug _label _dots _n _dslugs=() _dlabels=()
  while IFS= read -r _slug;  do _dslugs+=("$_slug");   done < <(td_host_slugs)
  while IFS= read -r _label; do _dlabels+=("$_label"); done < <(td_host_labels)
  for i in "${!_dslugs[@]}"; do
    _slug="${_dslugs[$i]}"
    _label="${_dlabels[$i]}"
    _n=$(( 16 - ${#_label} ))
    _dots=""
    while [ "$_n" -gt 0 ]; do _dots="${_dots}."; _n=$(( _n - 1 )); done
    if [ "$(_host_is_set "$_slug")" = "true" ]; then
      ok "$_label $_dots found"
    else
      warn "$_label $_dots not found"
    fi
  done

  if ! $HAS_CLAUDE && ! $HAS_CODEX && ! $HAS_OPENCODE && ! $HAS_COPILOT && ! $HAS_VSCODE && ! $HAS_COWORK && ! $HAS_GEMINI; then
    warn "No AI host detected. Tools installed but integrations skipped."
  fi
}

# --- Host selection -----------------------------------------------------------
# Returns "true" if the given slug is currently enabled.
_host_is_set() {
  case "$1" in
    claude)   echo "$HAS_CLAUDE" ;;
    codex)    echo "$HAS_CODEX" ;;
    opencode) echo "$HAS_OPENCODE" ;;
    copilot)  echo "$HAS_COPILOT" ;;
    vscode)   echo "$HAS_VSCODE" ;;
    cowork)   echo "$HAS_COWORK" ;;
    gemini)   echo "$HAS_GEMINI" ;;
    *)        echo "false" ;;
  esac
}

# Sets the flag for the given slug to false.
_host_disable() {
  case "$1" in
    claude)   HAS_CLAUDE=false ;;
    codex)    HAS_CODEX=false ;;
    opencode) HAS_OPENCODE=false ;;
    copilot)  HAS_COPILOT=false ;;
    vscode)   HAS_VSCODE=false ;;
    cowork)   HAS_COWORK=false ;;
    gemini)   HAS_GEMINI=false ;;
  esac
}

# Applies --hosts filter or prompts when multiple hosts are found.
# Zeros out HAS_* flags for any host not selected.
confirm_hosts() {
  # Read from the single registry in lib/hosts.sh. Line-by-line, not word-split:
  # labels contain spaces ("Cowork (Desktop)").
  local slugs=() labels=()
  while IFS= read -r _slug;  do slugs+=("$_slug");   done < <(td_host_slugs)
  while IFS= read -r _label; do labels+=("$_label"); done < <(td_host_labels)
  local detected_slugs=()
  local detected_labels=()

  for i in "${!slugs[@]}"; do
    if [ "$(_host_is_set "${slugs[$i]}")" = "true" ]; then
      detected_slugs+=("${slugs[$i]}")
      detected_labels+=("${labels[$i]}")
    fi
  done

  # --hosts flag supplied — apply without prompting, regardless of how many
  # hosts were auto-detected. An explicit --hosts must always be honored:
  # it previously only applied when 2+ hosts were detected, so on a machine
  # with exactly 0 or 1 host detected, --hosts silently had no effect.
  if [ -n "$HOSTS_FILTER" ] && [ "$HOSTS_FILTER" != "all" ]; then
    for slug in "${slugs[@]}"; do
      if ! echo ",$HOSTS_FILTER," | grep -qi ",$slug,"; then
        _host_disable "$slug"
      fi
    done
    info "Host integrations limited to: $HOSTS_FILTER"
    return
  fi

  if [ "${#detected_slugs[@]}" -le 1 ]; then return; fi   # nothing to choose from

  # Interactive prompt (skip in dry-run / non-interactive)
  if [ "${DRY_RUN:-false}" = "true" ] || [ ! -t 0 ]; then return; fi

  echo ""
  echo -e "${BOLD}  Detected AI hosts:${NC}"
  local n=1
  for label in "${detected_labels[@]}"; do
    echo -e "    ${BLUE}[$n] $label${NC}"
    n=$((n+1))
  done
  echo ""
  echo -e "${BOLD}  Install integrations for all detected hosts? [Y/n/list]${NC}"
  echo    "  Y = all (default)  |  n = none  |  list = e.g. 1,3 or claude,vscode"
  local answer
  read -rp "  > " answer

  if [ -z "$answer" ] || echo "$answer" | grep -qi '^y'; then return; fi

  local selected_slugs=()
  if ! echo "$answer" | grep -qi '^n$'; then
    IFS=', ' read -ra tokens <<< "$answer"
    for token in "${tokens[@]}"; do
      token=$(echo "$token" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
      # numeric index
      if [[ "$token" =~ ^[0-9]+$ ]] && [ "$token" -ge 1 ] && [ "$token" -le "${#detected_slugs[@]}" ]; then
        selected_slugs+=("${detected_slugs[$((token-1))]}")
      else
        # slug name — validate it's in detected list
        for s in "${detected_slugs[@]}"; do
          if [ "$s" = "$token" ]; then
            selected_slugs+=("$token")
          fi
        done
      fi
    done
  fi

  # Zero out unselected
  for slug in "${detected_slugs[@]}"; do
    if ! printf '%s\n' "${selected_slugs[@]}" | grep -qx "$slug"; then
      _host_disable "$slug"
    fi
  done

  if [ "${#selected_slugs[@]}" -eq 0 ]; then
    warn "No hosts selected — integrations will be skipped."
  else
    info "Host integrations limited to: ${selected_slugs[*]}"
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
    if [ -n "$RTK_REV" ]; then
      if [ "${DRY_RUN:-false}" = "true" ]; then
        dryrun "cargo install --git $RTK_REPO --rev $RTK_REV --force"
      else
        cargo install --git "$RTK_REPO" --rev "$RTK_REV" --force 2>&1 | show_output
        ok "RTK installed (pinned $RTK_REV): $(rtk --version 2>/dev/null)"
      fi
    else
      warn "RTK: no pinned rev (not a git checkout) — installing from upstream HEAD"
      if [ "${DRY_RUN:-false}" = "true" ]; then
        dryrun "cargo install --git $RTK_REPO --force"
      else
        cargo install --git "$RTK_REPO" --force 2>&1 | show_output
        ok "RTK installed: $(rtk --version 2>/dev/null)"
      fi
    fi
  fi

  # Symlink cargo binary into ~/.local/bin so it takes effect on PATH without
  # restarting the shell. macOS security policy kills copied Rust binaries in
  # ~/.local/bin (SIGKILL) but honours symlinks into ~/.cargo/bin.
  local cargo_rtk="$HOME/.cargo/bin/rtk"
  local local_rtk="$HOME/.local/bin/rtk"
  if [ -f "$cargo_rtk" ] && [ "${DRY_RUN:-false}" != "true" ]; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$cargo_rtk" "$local_rtk"
    ok "RTK symlinked: $local_rtk → $cargo_rtk"
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

  # Gemini CLI — rtk init --gemini registers the shell hook natively
  if $HAS_GEMINI; then
    if [ "${DRY_RUN:-false}" = "true" ]; then
      dryrun "rtk init --gemini"
    else
      rtk init --gemini 2>/dev/null \
        && ok "RTK: Gemini CLI" \
        || warn "RTK: Gemini CLI init failed (may already be configured)"
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
    if [ -n "$TILTH_REV" ]; then
      if [ "${DRY_RUN:-false}" = "true" ]; then
        dryrun "cargo install --git $TILTH_REPO --rev $TILTH_REV tilth --force"
      else
        # The tilth repo also carries a fuzz/ package (tilth-fuzz); cargo install
        # --git searches the whole cloned repo for any Cargo.toml with a [[bin]],
        # so an unqualified install is ambiguous between the two. Pin the package
        # name explicitly, same as the icm-cli install below.
        cargo install --git "$TILTH_REPO" --rev "$TILTH_REV" tilth --force 2>&1 | show_output
        ok "tilth installed (pinned $TILTH_REV): $(tilth --version 2>/dev/null)"
      fi
    else
      warn "tilth: no pinned rev (not a git checkout) — installing from upstream HEAD"
      if [ "${DRY_RUN:-false}" = "true" ]; then
        dryrun "cargo install --git $TILTH_REPO tilth --force"
      else
        cargo install --git "$TILTH_REPO" tilth --force 2>&1 | show_output
        ok "tilth installed: $(tilth --version 2>/dev/null)"
      fi
    fi
  fi

  # Symlink cargo binary into ~/.local/bin — same reason as RTK above.
  local cargo_tilth="$HOME/.cargo/bin/tilth"
  local local_tilth="$HOME/.local/bin/tilth"
  if [ -f "$cargo_tilth" ] && [ "${DRY_RUN:-false}" != "true" ]; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$cargo_tilth" "$local_tilth"
    ok "tilth symlinked: $local_tilth → $cargo_tilth"
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

  # Gemini CLI — gemini mcp add --scope user
  # NOTE: tilth MCP subcommand is --mcp (not `mcp`); see forks/tilth/ARCHITECTURE.md §143.
  if $HAS_GEMINI; then
    if [ "${DRY_RUN:-false}" = "true" ]; then
      dryrun "gemini mcp add --scope user tilth -- tilth --mcp"
    elif gemini mcp list 2>/dev/null | grep -q '"tilth"'; then
      ok "tilth MCP: Gemini CLI (already configured)"
    else
      gemini mcp add --scope user tilth -- tilth --mcp 2>/dev/null \
        && ok "tilth MCP: Gemini CLI" \
        || warn "tilth MCP: Gemini CLI setup failed"
    fi
  fi

  if [ ${#hosts[@]} -eq 0 ] && ! $HAS_GEMINI; then
    warn "tilth: no AI host detected, skipping MCP registration"
  fi
}

# --- Serena -------------------------------------------------------------------
install_serena() {
  header "Serena (IDE-like symbol navigation)"

  # Strict Installation Decoupling (CLAUDE.md): the MCP config must NEVER depend
  # on the local repo path. We always expose a bare `serena` command at the
  # XDG-stable launcher path ~/.local/bin/serena, regardless of whether the
  # underlying runtime is a venv, a Docker image, or uvx. Host registrations
  # below therefore use the bare name; the wrapper hides the runtime.
  local serena_data_dir="$HOME/.local/share/token-diet/serena"
  local serena_launcher="$HOME/.local/bin/serena"
  mkdir -p "$serena_data_dir" "$HOME/.local/bin"

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
    # Write a small wrapper at ~/.local/bin/serena that invokes docker. This
    # keeps the MCP config host-agnostic — every host just calls `serena`.
    if [ "${DRY_RUN:-false}" != "true" ]; then
      cat > "$serena_launcher" <<'WRAP'
#!/usr/bin/env bash
# token-diet Serena launcher (Docker runtime) — generated by install.sh
# Do not edit; rerun `bash install.sh --serena-only` to regenerate.
exec docker run --rm -i \
  -v "$(pwd):/workspace:ro" \
  --network none \
  token-diet/serena:latest \
  serena start-mcp-server "$@"
WRAP
      chmod +x "$serena_launcher"
      ok "Serena launcher (docker): $serena_launcher"
    fi
  else
    if [ "${DRY_RUN:-false}" = "true" ]; then
      dryrun "uvx --from ${SERENA_SRC} serena --help  (prefetch check)"
    else
      info "Verifying Serena via uvx..."
      if uvx --from "${SERENA_SRC}" serena --help &>/dev/null; then
        ok "Serena accessible via uvx"
      else
        warn "Serena fetch via uvx failed. May work on first real invocation."
      fi
    fi
    # Write a small wrapper at ~/.local/bin/serena that invokes uvx. Same
    # decoupling rationale as the Docker wrapper above.
    if [ "${DRY_RUN:-false}" != "true" ]; then
      cat > "$serena_launcher" <<WRAP
#!/usr/bin/env bash
# token-diet Serena launcher (uvx runtime) — generated by install.sh
# Do not edit; rerun \`bash install.sh --serena-only\` to regenerate.
exec uvx --from "${SERENA_SRC}" serena start-mcp-server "\$@"
WRAP
      chmod +x "$serena_launcher"
      ok "Serena launcher (uvx): $serena_launcher"
    fi
  fi

  # Verify the launcher is actually on PATH (the XDG-stable contract).
  if [ "${DRY_RUN:-false}" != "true" ]; then
    if command -v serena >/dev/null 2>&1; then
      ok "Serena on PATH: $(command -v serena)"
    else
      warn "Serena launcher written to $serena_launcher but not on PATH. Add ~/.local/bin to PATH."
    fi
  fi

  # Claude Code MCP
  if $HAS_CLAUDE; then
    if [ "${DRY_RUN:-false}" = "true" ]; then
      $LOCAL_MODE \
        && dryrun "claude mcp add --scope user serena -- docker run ... -v .:/workspace:ro token-diet/serena:latest --context=claude-code" \
        || dryrun "claude mcp add --scope user serena -- uvx --from ${SERENA_SRC} serena start-mcp-server --context=claude-code --open-web-dashboard false --project-from-cwd"
    elif claude mcp get serena &>/dev/null; then
      ok "Serena MCP: Claude Code (already configured)"
    elif $LOCAL_MODE; then
      # MCP stdio servers exec argv directly (no shell), so a literal
      # "$(pwd)" arg here never expands — it was passed to docker unresolved.
      # Use "." instead: docker resolves relative -v paths against its own
      # invocation cwd, which is inherited from Claude Code's spawn (the
      # project directory), same fix already used in the Codex block below.
      claude mcp add --scope user serena -- \
        docker run --rm -i -v ".:/workspace:ro" --network none \
        token-diet/serena:latest --context=claude-code --open-web-dashboard false --project /workspace \
        2>/dev/null \
        && ok "Serena MCP: Claude Code (Docker)" \
        || warn "Serena MCP: Claude Code setup failed"
    else
      claude mcp add --scope user serena -- \
        uvx --from "${SERENA_SRC}" serena start-mcp-server \
        --context=claude-code --open-web-dashboard false --project-from-cwd \
        2>/dev/null \
        && ok "Serena MCP: Claude Code" \
        || warn "Serena MCP: Claude Code setup failed"
    fi
  fi

  # Codex CLI
  if $HAS_CODEX; then
    local codex_config="$HOME/.codex/config.toml"
    # Anchor to the actual TOML table header, not any substring.
    # A stray orphan line like `["--from", "git+...serena", ...]` or a comment
    # containing "serena" must NOT be treated as a real registration.
    if [ -f "$codex_config" ] && grep -Eq '^\[mcp_servers\.serena\]' "$codex_config" 2>/dev/null; then
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
args = ["run", "--rm", "-i", "-v", ".:/workspace:ro", "--network", "none", "token-diet/serena:latest", "--context=codex", "--open-web-dashboard", "false", "--project", "/workspace"]
TOML
        else
          cat >> "$codex_config" << TOML

# Serena MCP server (added by token-diet)
[mcp_servers.serena]
command = "uvx"
args = ["--from", "${SERENA_SRC}", "serena", "start-mcp-server", "--context=codex", "--open-web-dashboard", "false", "--project-from-cwd"]
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
      # Use the pinned SERENA_SRC (git+<repo>@<rev>) so the VS Code template
      # matches the audited fork revision, not floating upstream HEAD. Falls back
      # to the bare git+<repo> ref only outside a git checkout (SERENA_REV empty),
      # matching SERENA_SRC's own ${SERENA_REV:+@...} behavior. Heredoc is now
      # unquoted so ${SERENA_SRC} expands; the JSON body has no other $ or `.
      cat > "$vscode_template" << JSON
{
  "servers": {
    "serena": {
      "command": "uvx",
      "args": ["--from", "${SERENA_SRC}", "serena", "start-mcp-server", "--context=ide", "--open-web-dashboard", "false", "--project-from-cwd"]
    },
    "tilth": {
      "command": "tilth",
      "args": ["--mcp"]
    }
  }
}
JSON
      ok "VS Code MCP template: $vscode_template"
      info "  Copy to project: cp $vscode_template /path/to/project/.vscode/mcp.json"
    fi
  fi

  # OpenCode
  # Config file location: $HOME/.config/opencode/opencode.json (XDG standard).
  # The legacy path $HOME/.opencode.json is checked as a fallback.
  # OpenCode uses lowercase "mcp" key with objects that have "type", "command" array, and "enabled".
  if $HAS_OPENCODE; then
    local oc_cfg
    if [ -f "$HOME/.config/opencode/opencode.json" ]; then
      oc_cfg="$HOME/.config/opencode/opencode.json"
    elif [ -f "$HOME/.opencode.json" ]; then
      oc_cfg="$HOME/.opencode.json"
    else
      mkdir -p "$HOME/.config/opencode"
      oc_cfg="$HOME/.config/opencode/opencode.json"
    fi
    if [ "${DRY_RUN:-false}" = "true" ]; then
      dryrun "Write mcp.serena + mcp.tilth entries to $oc_cfg"
    elif $LOCAL_MODE; then
      TD_LIB_DIR="$SCRIPT_DIR/lib" python3 - "$oc_cfg" "$PROJECT_ROOT" <<'PYEOF'
import os, sys
sys.path.insert(0, os.environ["TD_LIB_DIR"])
import tdconfig

cfg, project_root = sys.argv[1], sys.argv[2]

def mutate(data):
    data.setdefault("mcp", {})
    # Strict Installation Decoupling (CLAUDE.md §"Strict Installation Decoupling"):
    # NEVER write forks/-relative absolute paths into a host MCP config. The
    # install_serena() and install_tilth() functions above already provision
    # bare commands at XDG-stable paths (~/.local/bin/serena, ~/.local/bin/tilth).
    # We register the bare names + their MCP subcommand arguments only.
    data["mcp"]["serena"] = {
        "type": "local",
        "command": ["serena", "start-mcp-server",
                    "--context=ide", "--open-web-dashboard", "false", "--project-from-cwd"],
        "enabled": True,
    }
    data["mcp"]["tilth"] = {
        "type": "local",
        "command": ["tilth", "--mcp"],
        "enabled": True,
    }

try:
    tdconfig.update_json(cfg, mutate)
except tdconfig.ConfigError as _e:
    _q = tdconfig.quarantine(cfg)
    print(f"[token-diet] ABORT: {cfg} is malformed JSON ({_e}); backed up to {_q}. Refusing to overwrite existing config — fix it and re-run.", file=sys.stderr)
    sys.exit(3)
PYEOF
      ok "Serena + tilth MCP: OpenCode local ($oc_cfg)"
    else
      TD_LIB_DIR="$SCRIPT_DIR/lib" python3 - "$oc_cfg" "${SERENA_SRC}" <<'PYEOF'
import os, sys
sys.path.insert(0, os.environ["TD_LIB_DIR"])
import tdconfig

# serena_src is the pinned SERENA_SRC (git+<repo>@<rev>), so the registration
# matches the audited fork revision instead of floating to upstream HEAD. It
# already carries the git+ prefix and the @<rev> pin (bare git+<repo> only
# outside a git checkout), so pass it through verbatim.
cfg, serena_src = sys.argv[1], sys.argv[2]

def mutate(data):
    data.setdefault("mcp", {})
    data["mcp"]["serena"] = {
        "type": "local",
        "command": ["uvx", "--from", serena_src, "serena", "start-mcp-server",
                    "--context=ide", "--open-web-dashboard", "false", "--project-from-cwd"],
        "enabled": True
    }
    data["mcp"]["tilth"] = {
        "type": "local",
        "command": ["tilth", "--mcp"],
        "enabled": True
    }

try:
    tdconfig.update_json(cfg, mutate)
except tdconfig.ConfigError as _e:
    _q = tdconfig.quarantine(cfg)
    print(f"[token-diet] ABORT: {cfg} is malformed JSON ({_e}); backed up to {_q}. Refusing to overwrite existing config — fix it and re-run.", file=sys.stderr)
    sys.exit(3)
PYEOF
      ok "Serena + tilth MCP: OpenCode ($oc_cfg)"
    fi
    inject_opencode_rules
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
        TD_LIB_DIR="$SCRIPT_DIR/lib" python3 - "$COWORK_CFG" <<'PYEOF'
import os, sys
sys.path.insert(0, os.environ["TD_LIB_DIR"])
import tdconfig

cfg = sys.argv[1]

def mutate(data):
    data.setdefault("mcpServers", {})
    # "." not "$(pwd)": MCP stdio configs are exec'd as argv directly, no
    # shell, so "$(pwd)" would never expand. Docker resolves a relative -v
    # path against its own invocation cwd instead — same fix as the Codex
    # and Claude Code / Gemini CLI registrations above.
    data["mcpServers"]["serena"] = {
        "command": "docker",
        "args": ["run", "--rm", "-i", "-v", ".:/workspace:ro",
                 "--network", "none", "token-diet/serena:latest",
                 "--context=claude-code", "--open-web-dashboard", "false", "--project", "/workspace"]
    }

try:
    tdconfig.update_json(cfg, mutate)
except tdconfig.ConfigError as _e:
    _q = tdconfig.quarantine(cfg)
    print(f"[token-diet] ABORT: {cfg} is malformed JSON ({_e}); backed up to {_q}. Refusing to overwrite existing config — fix it and re-run.", file=sys.stderr)
    sys.exit(3)
PYEOF
      else
        TD_LIB_DIR="$SCRIPT_DIR/lib" python3 - "$COWORK_CFG" "${SERENA_SRC}" <<'PYEOF'
import os, sys
sys.path.insert(0, os.environ["TD_LIB_DIR"])
import tdconfig

# serena_src is the pinned SERENA_SRC (git+<repo>@<rev>) — pass through verbatim
# so Cowork registers the audited fork revision, not floating upstream HEAD.
cfg, serena_src = sys.argv[1], sys.argv[2]

def mutate(data):
    data.setdefault("mcpServers", {})
    data["mcpServers"]["serena"] = {
        "command": "uvx",
        "args": ["--from", serena_src, "serena", "start-mcp-server",
                 "--context=claude-code", "--open-web-dashboard", "false", "--project-from-cwd"]
    }

try:
    tdconfig.update_json(cfg, mutate)
except tdconfig.ConfigError as _e:
    _q = tdconfig.quarantine(cfg)
    print(f"[token-diet] ABORT: {cfg} is malformed JSON ({_e}); backed up to {_q}. Refusing to overwrite existing config — fix it and re-run.", file=sys.stderr)
    sys.exit(3)
PYEOF
      fi

      # Also register tilth if installed
      if check_command tilth; then
        TD_LIB_DIR="$SCRIPT_DIR/lib" python3 - "$COWORK_CFG" <<'PYEOF'
import os, sys
sys.path.insert(0, os.environ["TD_LIB_DIR"])
import tdconfig

cfg = sys.argv[1]

def mutate(data):
    data.setdefault("mcpServers", {})
    data["mcpServers"]["tilth"] = {"command": "tilth", "args": ["--mcp"]}

try:
    tdconfig.update_json(cfg, mutate)
except tdconfig.ConfigError as _e:
    _q = tdconfig.quarantine(cfg)
    print(f"[token-diet] ABORT: {cfg} is malformed JSON ({_e}); backed up to {_q}. Refusing to overwrite existing config — fix it and re-run.", file=sys.stderr)
    sys.exit(3)
PYEOF
        ok "Serena + tilth MCP: Cowork / Claude Desktop ($COWORK_CFG)"
      else
        ok "Serena MCP: Cowork / Claude Desktop ($COWORK_CFG)"
      fi
    fi
  fi

  # Gemini CLI — gemini mcp add --scope user
  if $HAS_GEMINI; then
    if [ "${DRY_RUN:-false}" = "true" ]; then
      $LOCAL_MODE \
        && dryrun "gemini mcp add --scope user serena docker run ... -v .:/workspace:ro token-diet/serena:latest" \
        || dryrun "gemini mcp add --scope user serena uvx --from ${SERENA_SRC} serena start-mcp-server"
    elif gemini mcp list 2>/dev/null | grep -q '"serena"'; then
      ok "Serena MCP: Gemini CLI (already configured)"
    elif $LOCAL_MODE; then
      # Same argv-not-shell issue as the Claude Code Docker block above: "."
      # instead of "$(pwd)" resolves correctly with no shell involved.
      gemini mcp add --scope user serena docker run --rm -i -v ".:/workspace:ro" --network none \
        token-diet/serena:latest --context=gemini-cli --open-web-dashboard false --project /workspace \
        2>/dev/null \
        && ok "Serena MCP: Gemini CLI (Docker)" \
        || warn "Serena MCP: Gemini CLI setup failed"
    else
      gemini mcp add --scope user serena \
        uvx --from "${SERENA_SRC}" serena start-mcp-server \
        --context=gemini-cli --open-web-dashboard false --project-from-cwd \
        2>/dev/null \
        && ok "Serena MCP: Gemini CLI" \
        || warn "Serena MCP: Gemini CLI setup failed"
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

# --- ICM ----------------------------------------------------------------------
# ICM (Infinite Context Memory) — cross-tool persistent memory MCP server.
# Build/install mirrors RTK (cargo + ~/.local/bin symlink for the macOS SIGKILL
# issue). MCP registration mirrors Serena (self-written config entries). We never
# call `icm init`: it bakes absolute current_exe() paths into ~20 host configs and
# would violate the install-decoupling rule. We register the bare-PATH command
# `icm serve --compact` ourselves instead.
#
# Embeddings policy (the air-gap decision):
#   --local → lean build (--no-default-features --features tui,backend-sqlite): fastembed
#             is never compiled, so the binary physically cannot fetch a model.
#   online  → embeddings compiled but DISABLED in config (embeddings.enabled=false)
#             so nothing is fetched silently. `token-diet icm warmup` performs the
#             one-time ~270 MB model download with consent; ICM then runs offline.
install_icm() {
  header "ICM (Infinite Context Memory)"

  if check_command icm; then
    ok "ICM already installed: $(icm --version 2>/dev/null || echo 'unknown')"
    info "Upgrading..."
  fi

  if $LOCAL_MODE; then
    verify_local_build "ICM" "$PROJECT_ROOT/forks/icm/crates/icm-cli/Cargo.toml"
    if [ "${DRY_RUN:-false}" = "true" ]; then
      dryrun "cargo install --path $PROJECT_ROOT/forks/icm/crates/icm-cli --no-default-features --features tui,backend-sqlite --force"
    else
      info "Building ICM from fork (keyword-only, air-gapped, no internet)..."
      cargo install --path "$PROJECT_ROOT/forks/icm/crates/icm-cli" --no-default-features --features tui,backend-sqlite --force 2>&1 | show_output
      ok "ICM built and installed from fork (keyword-only memory)"
    fi
  else
    if [ -n "$ICM_REV" ]; then
      if [ "${DRY_RUN:-false}" = "true" ]; then
        dryrun "cargo install --git $ICM_REPO --rev $ICM_REV icm-cli --force"
      else
        cargo install --git "$ICM_REPO" --rev "$ICM_REV" icm-cli --force 2>&1 | show_output
        ok "ICM installed (pinned $ICM_REV): $(icm --version 2>/dev/null)"
      fi
    else
      warn "ICM: no pinned rev (not a git checkout) — installing from upstream HEAD"
      if [ "${DRY_RUN:-false}" = "true" ]; then
        dryrun "cargo install --git $ICM_REPO icm-cli --force"
      else
        cargo install --git "$ICM_REPO" icm-cli --force 2>&1 | show_output
        ok "ICM installed: $(icm --version 2>/dev/null)"
      fi
    fi
  fi

  # Symlink cargo binary into ~/.local/bin — same macOS SIGKILL reason as RTK.
  local cargo_icm="$HOME/.cargo/bin/icm"
  local local_icm="$HOME/.local/bin/icm"
  if [ -f "$cargo_icm" ] && [ "${DRY_RUN:-false}" != "true" ]; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$cargo_icm" "$local_icm"
    ok "ICM symlinked: $local_icm → $cargo_icm"
  fi

  # Verify
  if [ "${DRY_RUN:-false}" != "true" ]; then
    if icm --version &>/dev/null; then
      ok "ICM verification passed"
    else
      warn "ICM verification failed"
      return
    fi
  fi

  # Embeddings policy: the online build ships embeddings compiled but OFF by default
  # (config default is enabled=true upstream) so nothing is fetched behind the
  # firewall. `token-diet icm warmup` turns it on. Air-gapped builds have no
  # embedding code at all, so this is a harmless no-op there.
  if ! $LOCAL_MODE; then
    local icm_cfg="$HOME/.config/icm/config.toml"
    if [ "${DRY_RUN:-false}" = "true" ]; then
      dryrun "Set [embeddings] enabled=false in $icm_cfg (warmup enables it)"
    else
      mkdir -p "$(dirname "$icm_cfg")"
      python3 - "$icm_cfg" <<'PYEOF'
import os, sys, re, pathlib, tempfile
def atomic_write(path, text):
    d = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".td-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        try:
            os.chmod(tmp, os.stat(path).st_mode & 0o7777)
        except OSError:
            pass
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
p = pathlib.Path(sys.argv[1])
text = p.read_text() if p.exists() else ""
# Set enabled=false strictly inside the [embeddings] table — the config has many
# other `enabled` keys (extraction, recall, cloud, ...) we must not touch.
m = re.search(r'(?ms)^\[embeddings\][^\n]*\n(.*?)(?=^\[|\Z)', text)
if m:
    body = m.group(1)
    if re.search(r'(?m)^\s*enabled\s*=', body):
        body = re.sub(r'(?m)^(\s*enabled\s*=\s*).*$', r'\g<1>false', body, count=1)
    else:
        body = "enabled = false\n" + body
    text = text[:m.start(1)] + body + text[m.end(1):]
else:
    prefix = text.rstrip() + "\n\n" if text.strip() else ""
    text = prefix + "[embeddings]\nenabled = false\n"
atomic_write(str(p), text)
PYEOF
      ok "ICM semantic search is OFF until warmup ($icm_cfg)"
      info "  Enable cross-tool semantic recall (one-time ~270 MB model download):"
      info "    token-diet icm warmup"
    fi
  fi

  # --- MCP registration (self-written, NEVER 'icm init') ----------------------
  # Always the bare-PATH command 'icm serve --compact' — no repo path, no docker,
  # no uvx. Identical for local and online installs (icm is on PATH either way).
  info "Registering ICM MCP server for detected hosts..."

  # Claude Code
  if $HAS_CLAUDE; then
    if [ "${DRY_RUN:-false}" = "true" ]; then
      dryrun "claude mcp add --scope user icm -- icm serve --compact"
    elif claude mcp get icm &>/dev/null; then
      ok "ICM MCP: Claude Code (already configured)"
    else
      claude mcp add --scope user icm -- icm serve --compact 2>/dev/null \
        && ok "ICM MCP: Claude Code" \
        || warn "ICM MCP: Claude Code setup failed"
    fi
  fi

  # Codex CLI — anchor to the actual TOML table header, never a loose substring.
  if $HAS_CODEX; then
    local codex_config="$HOME/.codex/config.toml"
    if [ -f "$codex_config" ] && grep -Eq '^\[mcp_servers\.icm\]' "$codex_config" 2>/dev/null; then
      ok "ICM MCP: Codex CLI (already configured)"
    elif [ "${DRY_RUN:-false}" = "true" ]; then
      dryrun "Append [mcp_servers.icm] block to $codex_config"
    else
      mkdir -p "$HOME/.codex"
      cat >> "$codex_config" << 'TOML'

# ICM MCP server (added by token-diet)
[mcp_servers.icm]
command = "icm"
args = ["serve", "--compact"]
TOML
      ok "ICM MCP: Codex CLI"
    fi
  fi

  # VS Code — merge into the shared template (servers.icm). A merge (not a heredoc)
  # so --icm-only populates it even when Serena did not rewrite the template.
  if $HAS_VSCODE; then
    local vscode_template="$HOME/.config/token-diet/vscode-mcp.template.json"
    if [ "${DRY_RUN:-false}" = "true" ]; then
      dryrun "Merge servers.icm into $vscode_template"
    else
      mkdir -p "$(dirname "$vscode_template")"
      python3 - "$vscode_template" <<'PYEOF'
import json, os, sys, pathlib, tempfile
def atomic_write(path, text):
    d = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".td-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        try:
            os.chmod(tmp, os.stat(path).st_mode & 0o7777)
        except OSError:
            pass
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
p = pathlib.Path(sys.argv[1])
try:
    data = json.loads(p.read_text())
except FileNotFoundError:
    data = {}
except (json.JSONDecodeError, ValueError) as _e:
    import shutil, time
    _bak = str(p) + ".corrupt-" + time.strftime("%Y%m%d-%H%M%S")
    shutil.copy2(str(p), _bak)
    print(f"[token-diet] ABORT: {p} is malformed JSON ({_e}); backed up to {_bak}. Refusing to overwrite existing config — fix it and re-run.", file=sys.stderr)
    sys.exit(3)
data.setdefault("servers", {})
data["servers"]["icm"] = {"command": "icm", "args": ["serve", "--compact"]}
atomic_write(str(p), json.dumps(data, indent=2) + "\n")
PYEOF
      ok "ICM MCP: VS Code template ($vscode_template)"
    fi
  fi

  # OpenCode — bare-PATH command (NOT a forks/ path; icm is always on PATH).
  if $HAS_OPENCODE; then
    local oc_cfg
    if [ -f "$HOME/.config/opencode/opencode.json" ]; then
      oc_cfg="$HOME/.config/opencode/opencode.json"
    elif [ -f "$HOME/.opencode.json" ]; then
      oc_cfg="$HOME/.opencode.json"
    else
      mkdir -p "$HOME/.config/opencode"
      oc_cfg="$HOME/.config/opencode/opencode.json"
    fi
    if [ "${DRY_RUN:-false}" = "true" ]; then
      dryrun "Write mcp.icm to $oc_cfg"
    else
      TD_LIB_DIR="$SCRIPT_DIR/lib" python3 - "$oc_cfg" <<'PYEOF'
import os, sys
sys.path.insert(0, os.environ["TD_LIB_DIR"])
import tdconfig

cfg = sys.argv[1]

def mutate(data):
    data.setdefault("mcp", {})
    data["mcp"]["icm"] = {"type": "local", "command": ["icm", "serve", "--compact"], "enabled": True}

try:
    tdconfig.update_json(cfg, mutate)
except tdconfig.ConfigError as _e:
    _q = tdconfig.quarantine(cfg)
    print(f"[token-diet] ABORT: {cfg} is malformed JSON ({_e}); backed up to {_q}. Refusing to overwrite existing config — fix it and re-run.", file=sys.stderr)
    sys.exit(3)
PYEOF
      ok "ICM MCP: OpenCode ($oc_cfg)"
    fi
  fi

  # Cowork (Claude Desktop)
  if $HAS_COWORK; then
    if [ "${DRY_RUN:-false}" = "true" ]; then
      dryrun "Write mcpServers.icm to $COWORK_CFG"
    else
      TD_LIB_DIR="$SCRIPT_DIR/lib" python3 - "$COWORK_CFG" <<'PYEOF'
import os, sys
sys.path.insert(0, os.environ["TD_LIB_DIR"])
import tdconfig

cfg = sys.argv[1]

def mutate(data):
    data.setdefault("mcpServers", {})
    data["mcpServers"]["icm"] = {"command": "icm", "args": ["serve", "--compact"]}

try:
    tdconfig.update_json(cfg, mutate)
except tdconfig.ConfigError as _e:
    _q = tdconfig.quarantine(cfg)
    print(f"[token-diet] ABORT: {cfg} is malformed JSON ({_e}); backed up to {_q}. Refusing to overwrite existing config — fix it and re-run.", file=sys.stderr)
    sys.exit(3)
PYEOF
      ok "ICM MCP: Cowork / Claude Desktop ($COWORK_CFG)"
    fi
  fi

  if $HAS_COPILOT; then
    ok "ICM: Copilot CLI uses VS Code MCP config (shared)"
  fi

  # Gemini CLI — `gemini mcp add --scope user` writes mcpServers entries into
  # ~/.gemini/settings.json (empirically verified against gemini v0.49.0: the CLI
  # reports "added to user settings" and the key lands in settings.json, NOT a
  # separate config/mcp_config.json). uninstall.sh cleans that same file, so the
  # install/uninstall pair is symmetric.
  if $HAS_GEMINI; then
    if [ "${DRY_RUN:-false}" = "true" ]; then
      dryrun "gemini mcp add --scope user icm icm serve --compact"
    elif gemini mcp list 2>/dev/null | grep -q '"icm"'; then
      ok "ICM MCP: Gemini CLI (already configured)"
    else
      gemini mcp add --scope user icm icm serve --compact 2>/dev/null \
        && ok "ICM MCP: Gemini CLI" \
        || warn "ICM MCP: Gemini CLI setup failed"
    fi
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
    tilth_codex_issue="$(codex_mcp_issue "tilth")"
    if [ -n "$tilth_codex_issue" ]; then
      warn "$tilth_codex_issue"
      all_ok=false
    fi
  else
    warn "tilth ........... not installed"
    all_ok=false
  fi

  if check_command icm; then
    ok "ICM ............. $(icm --version 2>/dev/null || echo 'installed')"
    local icm_codex_issue
    icm_codex_issue="$(codex_mcp_issue "icm")"
    if [ -n "$icm_codex_issue" ]; then
      warn "$icm_codex_issue"
      all_ok=false
    fi
  else
    warn "ICM ............. not installed"
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

  local serena_codex_issue
  serena_codex_issue="$(codex_mcp_issue "serena")"
  if [ -n "$serena_codex_issue" ]; then
    warn "$serena_codex_issue"
    all_ok=false
  fi

  echo ""

  # Hosts
  if $HAS_CLAUDE;   then ok "Claude Code ..... available"; else warn "Claude Code ..... not found"; fi
  if $HAS_CODEX;    then ok "Codex CLI ....... available"; else warn "Codex CLI ....... not found"; fi
  if $HAS_OPENCODE; then ok "OpenCode ........ available"; else warn "OpenCode ........ not found"; fi
  if $HAS_COPILOT;  then ok "Copilot CLI ..... available"; else warn "Copilot CLI ..... not found"; fi
  if $HAS_VSCODE;   then ok "VS Code ......... available"; else warn "VS Code ......... not found"; fi
  if $HAS_COWORK;   then ok "Cowork (Desktop)  available"; else warn "Cowork (Desktop)  not found"; fi
  if $HAS_GEMINI;   then ok "Gemini CLI ...... available"; else warn "Gemini CLI ...... not found"; fi

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
  |            + Cowork (Claude Desktop) + Gemini CLI                 |
  +-------------------------------------------------------------------+
         |              |              |               |
    Code reading   Refactoring   Command output   Persistent memory
         |              |              |               |
    +--------+    +---------+    +--------+      +--------+
    | tilth  |    | Serena  |    |  RTK   |      |  ICM   |
    | (fast) |    |  (deep) |    |(filter)|      |(memory)|
    +--------+    +---------+    +--------+      +--------+
    tree-sitter      LSP        regex/trunc      vec+FTS5

EOF
}

# --- token-diet dashboard command ----------------------------------------------------
install_token_diet() {
  local bin_dir="$HOME/.local/bin"
  local src_bin="$SCRIPT_DIR/token-diet"
  local src_dash="$SCRIPT_DIR/token-diet-dashboard"
  local src_mcp="$SCRIPT_DIR/token-diet-mcp"

  if [ ! -f "$src_bin" ]; then
    warn "scripts/token-diet not found — skipping token-diet install"
    return 0
  fi

  local src_lib="$SCRIPT_DIR/lib"

  if [ "${DRY_RUN:-false}" = "true" ]; then
    dryrun "install -m755 $src_bin $bin_dir/token-diet"
    [ -f "$src_dash" ] && dryrun "install -m755 $src_dash $bin_dir/token-diet-dashboard"
    [ -f "$src_mcp" ] && dryrun "install -m755 $src_mcp $bin_dir/token-diet-mcp"
    dryrun "install $src_lib/{docextract,tdcache,ctxwarn,tdconfig}.py to $bin_dir/lib/ (cmd_extract / budget --check / MCP registration depend on these at runtime)"
    dryrun "write ~/.claude/token-diet.md + add @token-diet.md to ~/.claude/CLAUDE.md"
    dryrun "write ~/.codex/token-diet.md + add @token-diet.md to ~/.codex/AGENTS.md"
    dryrun "register token-diet MCP server"
    return 0
  fi

  mkdir -p "$bin_dir"
  install -m755 "$src_bin" "$bin_dir/token-diet"
  ok "token-diet installed: $bin_dir/token-diet"

  # cmd_extract / cmd_budget --check shell out to $SCRIPT_DIR/lib/<name>.py —
  # SCRIPT_DIR resolves to wherever this token-diet copy lives, so the
  # installed copy needs its own lib/ alongside it or those subcommands
  # silently break post-install (only worked from the dev checkout).
  # tdconfig is required by the installed token-diet-install.sh (MCP
  # registration imports it), so it ships with the other cores. Omitting a
  # newly-added core here is exactly how cmd_extract shipped broken in v1.14.0.
  for py_core in docextract tdcache ctxwarn tdconfig; do
    if [ -f "$src_lib/$py_core.py" ]; then
      mkdir -p "$bin_dir/lib"
      install -m644 "$src_lib/$py_core.py" "$bin_dir/lib/$py_core.py"
    fi
  done
  ok "Python cores installed: $bin_dir/lib/{docextract,tdcache,ctxwarn,tdconfig}.py"

  # Shared shell libs. Globbed, not listed: a hardcoded manifest is what let
  # cmd_extract ship broken in v1.14.0 — the new core was added to scripts/lib/
  # and forgotten here, so every test passed from the dev checkout while the
  # installed binary failed. Adding a lib file must be enough on its own.
  shell_lib_count=0
  for shell_lib in "$src_lib"/*.sh; do
    [ -f "$shell_lib" ] || continue
    mkdir -p "$bin_dir/lib"
    install -m644 "$shell_lib" "$bin_dir/lib/$(basename "$shell_lib")"
    shell_lib_count=$((shell_lib_count + 1))
  done
  if [ "$shell_lib_count" -gt 0 ]; then
    ok "Shell libs installed: $shell_lib_count file(s) in $bin_dir/lib/"
  fi

  # Version-compat gate data. token-diet reads $SCRIPT_DIR/../config/compat.json;
  # installed SCRIPT_DIR is $bin_dir, so this must land at $bin_dir/../config.
  # Without it _compat_min falls back to "0.0.0" and the entire gate is a dead
  # no-op on every installed system — it only ever worked from the dev checkout.
  if [ -f "$PROJECT_ROOT/config/compat.json" ]; then
    mkdir -p "$bin_dir/../config"
    install -m644 "$PROJECT_ROOT/config/compat.json" "$bin_dir/../config/compat.json"
    ok "Compat data installed: $bin_dir/../config/compat.json"
  fi

  # Canonical MCP-host registry. token-diet-dashboard reads
  # $SCRIPT_DIR/../config/hosts-mcp.json at runtime; installed SCRIPT_DIR is
  # $bin_dir, so it must land at $bin_dir/../config. Without it the dashboard's
  # host detection has no data source (same decoupling class as compat.json).
  if [ -f "$PROJECT_ROOT/config/hosts-mcp.json" ]; then
    mkdir -p "$bin_dir/../config"
    install -m644 "$PROJECT_ROOT/config/hosts-mcp.json" "$bin_dir/../config/hosts-mcp.json"
    ok "Host registry installed: $bin_dir/../config/hosts-mcp.json"
  fi

  if [ -f "$src_dash" ]; then
    install -m755 "$src_dash" "$bin_dir/token-diet-dashboard"
    ok "token-diet-dashboard installed: $bin_dir/token-diet-dashboard"
  fi

  if [ -f "$src_mcp" ]; then
    install -m755 "$src_mcp" "$bin_dir/token-diet-mcp"
    ok "token-diet-mcp installed: $bin_dir/token-diet-mcp"
    
    # Register MCP server
    if command -v codex &>/dev/null; then
      python3 - "$HOME/.codex/config.toml" << 'PYEOF'
import os, pathlib, sys, re, tempfile
def atomic_write(path, text):
    d = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".td-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        try:
            os.chmod(tmp, os.stat(path).st_mode & 0o7777)
        except OSError:
            pass
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
cfg = pathlib.Path(sys.argv[1])
if cfg.exists():
    text = cfg.read_text()
    if '[mcp_servers.token-diet]' not in text:
        atomic_write(str(cfg), text + '\n[mcp_servers.token-diet]\ncommand = "token-diet-mcp"\n')
PYEOF
    fi

    # Claude/Cowork configs use "mcpServers"; OpenCode 1.x uses "mcp" only —
    # injecting "mcpServers" into an OpenCode config triggers ConfigInvalidError.
    for cfg in "$HOME/.claude/settings.json" "$HOME/Library/Application Support/Claude/claude_desktop_config.json" "$HOME/.config/Claude/claude_desktop_config.json" "$COWORK_CFG"; do
      if [ -f "$cfg" ]; then
        if ! TD_LIB_DIR="$SCRIPT_DIR/lib" python3 - "$cfg" << 'PYEOF'
import os, sys
sys.path.insert(0, os.environ["TD_LIB_DIR"])
import tdconfig

cfg = sys.argv[1]
try:
    tdconfig.update_json(
        cfg,
        lambda d: d.setdefault("mcpServers", {}).update(
            {"token-diet": {"command": "token-diet-mcp", "args": []}}
        ),
    )
except tdconfig.ConfigError as e:
    print(f"skipped (config unreadable): {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
        then
          warn "token-diet MCP: skipped $cfg (see message above)"
        else
          td_record_mutation "$cfg"
        fi
      fi
    done
    # OpenCode uses "mcp" key — write there, not "mcpServers"
    for cfg in "$HOME/.config/opencode/opencode.json" "$HOME/.opencode.json"; do
      if [ -f "$cfg" ]; then
        if ! TD_LIB_DIR="$SCRIPT_DIR/lib" python3 - "$cfg" << 'PYEOF'
import os, sys
sys.path.insert(0, os.environ["TD_LIB_DIR"])
import tdconfig

cfg = sys.argv[1]
try:
    tdconfig.update_json(
        cfg,
        lambda d: d.setdefault("mcp", {}).update(
            {"token-diet": {"type": "local", "command": ["token-diet-mcp"], "enabled": True}}
        ),
    )
except tdconfig.ConfigError as e:
    print(f"skipped (config unreadable): {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
        then
          warn "token-diet MCP: skipped $cfg (see message above)"
        else
          td_record_mutation "$cfg"
        fi
      fi
    done
  fi

  # Copy installer + uninstaller so `token-diet verify/uninstall` work from ~/.local/bin
  install -m755 "$SCRIPT_DIR/install.sh" "$bin_dir/token-diet-install.sh"
  if [ -f "$SCRIPT_DIR/uninstall.sh" ]; then
    install -m755 "$SCRIPT_DIR/uninstall.sh" "$bin_dir/uninstall.sh"
  fi

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
# Token Diet — AI Context Optimization

`token-diet` is a unified optimization layer for AI agents. It orchestrates RTK, tilth, Serena, and ICM to maximize context efficiency.

## Core Commands

- `token-diet gain`: Current token savings and efficiency stats.
- `token-diet mcp list`: Check which hosts are currently optimized.
- `token-diet hook off`: Disable RTK (raw output) for troubleshooting.
- `token-diet hook on`: Re-enable RTK optimization.
- `token-diet budget status`: Check project-specific token consumption.
- `token-diet route <task>`: Ask `token-diet` which tool is best for your current task.
- `token-diet doctor`: Run diagnostics if tools are unresponsive.

## Agent Guidelines

1. **Self-Monitor**: Regularly run `token-diet budget status` to stay within thresholds.
2. **Tool Selection**:
   - Use **tilth** for code reading and symbol search.
   - Use **Serena** for complex refactoring and diagnostics.
   - Use **RTK** for running commands and builds.
   - Use **ICM** for persistent cross-session memory: recall past decisions and store new facts.
3. **Be Precise**: Use `tilth_read` with line ranges (found via `token-diet diff-reads`) to minimize context waste.
4. **Optimization**: If you detect you are looping or wasting tokens, run `token-diet loops` or `token-diet leaks` to self-audit.
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

  # Gemini CLI — write token-diet.md into ~/.gemini and reference from GEMINI.md
  if $HAS_GEMINI; then
    write_token-diet_md "$HOME/.gemini" "$HOME/.gemini/GEMINI.md"
  fi
}

# --- docextract / ctxwarn context hooks (opt-in) -------------------------------
# merge_hook_entry <config_json_path> <event> <matcher> <command> <timeout>
#
# Idempotent: adds hooks.<event> += [{matcher, hooks:[{type:command,command,timeout}]}]
# unless a hook with this exact command string already exists anywhere under
# that event. Preserves every other key and every other hook entry. Never
# partial-writes — if the file doesn't parse as JSON, prints a warning to
# stderr and exits 1 without touching the file; the caller decides whether
# that's fatal (it isn't, for this opt-in feature — see install_context_hooks).
merge_hook_entry() {
  local cfg="$1" event="$2" matcher="$3" command="$4" timeout="${5:-15}"
  [ -f "$cfg" ] || return 0
  python3 - "$cfg" "$event" "$matcher" "$command" "$timeout" << 'PYEOF'
import json, os, sys, pathlib, tempfile
def atomic_write(path, text):
    d = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".td-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        try:
            os.chmod(tmp, os.stat(path).st_mode & 0o7777)
        except OSError:
            pass
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise

cfg_path, event, matcher, command, timeout = sys.argv[1:6]
p = pathlib.Path(cfg_path)
try:
    data = json.loads(p.read_text())
except Exception as e:
    print(f"  ! skipped {cfg_path}: cannot parse existing JSON ({e})", file=sys.stderr)
    sys.exit(1)

hooks = data.setdefault("hooks", {})
entries = hooks.setdefault(event, [])

for entry in entries:
    for h in entry.get("hooks", []):
        if h.get("command") == command:
            sys.exit(0)  # already registered — no-op

entries.append({
    "matcher": matcher,
    "hooks": [{"type": "command", "command": command, "timeout": int(timeout)}],
})

atomic_write(str(p), json.dumps(data, indent=2) + "\n")
PYEOF
}

install_context_hooks() {
  header "docextract / ctxwarn context hooks (--with-context-hooks)"

  local hooks_src_dir="$SCRIPT_DIR/lib/hooks"
  local hooks_bin_dir="$HOME/.local/bin/token-diet-hooks"
  local docextract_shim="$hooks_bin_dir/docextract-pre-read.sh"
  local ctxwarn_shim="$hooks_bin_dir/ctxwarn-post.sh"

  if [ "${DRY_RUN:-false}" = "true" ]; then
    dryrun "install -m755 $hooks_src_dir/*.sh $hooks_bin_dir/"
    $HAS_CLAUDE && dryrun "merge PreToolUse/Read + PostToolUse/* hooks into $HOME/.claude/settings.json (backed up first)"
    $HAS_GEMINI && dryrun "merge PreToolUse/read_file + PostToolUse/* hooks into $HOME/.gemini/settings.json (backed up first)"
    dryrun "write awareness-docextract.md to codex, gemini, copilot, cowork configs (OpenCode handled below)"
    $HAS_OPENCODE && dryrun "install opencode.ts plugin + register in opencode.json plugin array (backed up first)"
    return 0
  fi

  mkdir -p "$hooks_bin_dir"
  install -m755 "$hooks_src_dir/docextract-pre-read.sh" "$docextract_shim"
  install -m755 "$hooks_src_dir/ctxwarn-post.sh" "$ctxwarn_shim"
  ok "Hook shims installed: $hooks_bin_dir"

  if $HAS_CLAUDE; then
    local cc_settings="$HOME/.claude/settings.json"
    if [ ! -f "$cc_settings" ]; then
      mkdir -p "$(dirname "$cc_settings")"
      echo '{}' > "$cc_settings"
    else
      cp "$cc_settings" "$cc_settings.bak-token-diet-hooks-$(date +%s)"
    fi
    if merge_hook_entry "$cc_settings" "PreToolUse" "Read" "$docextract_shim" 15 \
      && merge_hook_entry "$cc_settings" "PostToolUse" "*" "$ctxwarn_shim" 15; then
      ok "Claude Code: docextract + ctxwarn hooks registered in $cc_settings"
    else
      warn "Claude Code: $cc_settings could not be parsed as JSON — hook registration skipped, file left untouched"
    fi
  fi

  # Gemini CLI: verified hooks schema (2026-07-19) by extracting the
  # `gemini hooks migrate --from-claude` implementation from the v0.49.0
  # bundle (`gemini-APNDCIQH.js`). Gemini CLI uses the EXACT same
  # settings.json JSON format as Claude Code, with one difference:
  # tool names are mapped (Read→read_file, Bash→run_shell_command, etc.)
  # via TOOL_NAME_MAPPING. The matchers we register map to:
  #   docextract:  Read → read_file
  #   ctxwarn:     *    → * (universal — no mapping needed)
  # OQ-2 resolved: no guessing needed; the schema is proven compatible.
  if $HAS_GEMINI; then
    local gm_settings="$HOME/.gemini/settings.json"
    if [ ! -f "$gm_settings" ]; then
      warn "Gemini CLI: $gm_settings not found — hook registration skipped"
    else
      cp "$gm_settings" "$gm_settings.bak-token-diet-hooks-$(date +%s)"
      # Gemini tool name mapping: Read → read_file (verified in
      # gemini-APNDCIQH.js TOOL_NAME_MAPPING: Read: "read_file").
      if merge_hook_entry "$gm_settings" "PreToolUse" "read_file" "$docextract_shim" 15 \
        && merge_hook_entry "$gm_settings" "PostToolUse" "*" "$ctxwarn_shim" 15; then
        ok "Gemini CLI: docextract + ctxwarn hooks registered in $gm_settings"
      else
        warn "Gemini CLI: $gm_settings could not be parsed as JSON — hook registration skipped, file left untouched"
      fi
    fi
  fi

  # Every other detected harness — awareness-doc fallback, no hook schema verified yet.
  local awareness_src="$SCRIPT_DIR/lib/awareness-docextract.md"
  write_awareness_docextract() {
    local config_dir="$1"
    [ -d "$config_dir" ] || return 0
    cp "$awareness_src" "$config_dir/awareness-docextract.md"
    ok "awareness-docextract.md written: $config_dir/awareness-docextract.md"
  }

  $HAS_CODEX    && write_awareness_docextract "$HOME/.codex"
  # Gemini CLI: now has real hooks (see block above). Awareness-doc is a
  # courtesy fallback — the hooks provide automated enforcement, the awareness
  # doc reminds the agent what to do if hooks fail or are disabled.
  $HAS_GEMINI   && write_awareness_docextract "$HOME/.gemini"
  # Copilot CLI: OQ-3 resolved (2026-07-19) — verified config dir is ~/.copilot/
  # via README inspection (https://github.com/github/copilot-cli). No hook
  # surface exists in copilot CLI v0.0.377 — awareness doc is the best we can
  # do until/unless upstream adds one.
  $HAS_COPILOT  && write_awareness_docextract "$HOME/.copilot"

  # OpenCode: full hook surface EXISTS via the plugin API (verified by reading
  # ~/.config/opencode/node_modules/@opencode-ai/plugin/dist/index.d.ts —
  # "tool.execute.before" / "tool.execute.after" events, PluginInput.client
  # gives access to the session SDK). Install our TS plugin to
  # ~/.config/opencode/plugins/ and add it to opencode.json's plugin array
  # (idempotent merge — never duplicates).
  if $HAS_OPENCODE; then
    local opencode_dir="$HOME/.config/opencode"
    local opencode_cfg="$opencode_dir/opencode.json"
    if [ -d "$opencode_dir" ]; then
      local plugins_dir="$opencode_dir/plugins"
      mkdir -p "$plugins_dir"
      local plugin_src="$SCRIPT_DIR/lib/hooks-plugins/opencode.ts"
      local plugin_dst="$plugins_dir/token-diet-hooks.ts"
      if [ -f "$plugin_src" ]; then
        install -m644 "$plugin_src" "$plugin_dst"
        ok "OpenCode plugin installed: $plugin_dst"

        # Register in opencode.json's plugin array (idempotent — match by
        # the relative path we just installed). Always-backup before write.
        if [ -f "$opencode_cfg" ]; then
          cp "$opencode_cfg" "$opencode_cfg.bak-token-diet-opencode-$(date +%s)"
          TD_LIB_DIR="$SCRIPT_DIR/lib" python3 - "$opencode_cfg" "$plugin_dst" << 'PY'
import os, sys
sys.path.insert(0, os.environ["TD_LIB_DIR"])
import tdconfig

cfg_path, plugin_dst = sys.argv[1], sys.argv[2]
# The plugin array stores paths relative to the opencode config file
# directory (parent of opencode.json). plugins/token-diet-hooks.ts is the
# canonical relative form.
rel = "plugins/token-diet-hooks.ts"

def mutate(cfg):
    plugins = cfg.get("plugin", [])
    if not isinstance(plugins, list):
        plugins = []
    if rel not in plugins and plugin_dst not in plugins:
        plugins.append(rel)
    cfg["plugin"] = plugins

# This previously did `except Exception: cfg = {}`, which treated a malformed
# opencode.json as EMPTY and then wrote it back containing only the plugin key
# -- silently destroying every other setting the user had. Same shape as the
# two truncate-then-swallow sites fixed in v1.15.0; this one survived that pass.
# Now it aborts and preserves the original for inspection.
try:
    tdconfig.update_json(cfg_path, mutate)
except tdconfig.ConfigError as _e:
    _q = tdconfig.quarantine(cfg_path)
    print(f"[token-diet] ABORT: {cfg_path} is malformed JSON ({_e}); backed up to {_q}. Refusing to overwrite existing config — fix it and re-run.", file=sys.stderr)
    sys.exit(3)
PY
          ok "OpenCode plugin registered in $opencode_cfg"
        else
          warn "OpenCode: $opencode_cfg not found — plugin installed to $plugin_dst but not registered"
        fi
      else
        warn "OpenCode plugin source missing: $plugin_src"
      fi
    fi
  fi

  if $HAS_COWORK; then
    local cowork_dir; cowork_dir="$(dirname "$COWORK_CFG")"
    write_awareness_docextract "$cowork_dir"
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
  ICM      Persistent cross-tool memory (MCP server)

Hosts (auto-detected):
  Claude Code, Codex CLI, OpenCode, Copilot CLI, VS Code, Cowork (Claude Desktop), Gemini CLI

Options:
  --all          Install all three tools (default)
  --local        Install from local forks/dist (air-gapped)
  --rtk-only     Install only RTK
  --tilth-only   Install only tilth
  --serena-only  Install only Serena
  --icm-only     Install only ICM
  --verify       Only verify current installation
  --no-dedup     Skip overlap fix configuration
  --skip-tests   Skip clippy + tests in --local mode (faster install)
  --hosts LIST   Comma-separated list of AI hosts to wire integrations for.
                 Valid: claude, codex, opencode, copilot, vscode, cowork, gemini
                 Default: prompt when multiple hosts detected.
                 Example: --hosts "claude,vscode"
  --dry-run      Simulate install — detect hosts and show what would run, no changes made
  --verbose      Show full build output instead of last 5 lines; log to ~/.local/share/token-diet/install.log
  --with-context-hooks
                 Opt-in: register docextract (PreToolUse/Read) + ctxwarn (PostToolUse)
                 hooks into Claude Code's settings.json. Off by default — this is the
                 first token-diet feature that intercepts a live tool call. Every other
                 detected harness gets the awareness-doc fallback instead (its hook
                 schema is unverified — see PLAN-docextract-ctxwarn.md OQ-2/OQ-3).
  -h, --help     Show this help
EOF
}

# --- Interactive wizard -------------------------------------------------------
run_wizard() {
  echo ""
  echo -e "${BOLD}  token-diet interactive installer${NC}"
  echo -e "${BLUE}  RTK + tilth + Serena + ICM — security-patched forks${NC}"
  echo ""
  echo "  The stack — each tool is independent; install any subset:"
  echo ""
  echo -e "  ${BOLD}RTK${NC}     command output compression"
  echo    "          What: a CLI proxy that filters verbose command output."
  echo    "          Why:  long build / test / git output floods the context window."
  echo    "          Gain: 60-90% fewer tokens on tracked commands (measured)."
  echo -e "  ${BOLD}tilth${NC}   AST-aware code reading"
  echo    "          What: tree-sitter reader returning symbols/structure, not whole files."
  echo    "          Why:  reading entire files to find one function wastes context."
  echo    "          Gain: ~38-44% smaller reads on average."
  echo -e "  ${BOLD}Serena${NC}  LSP symbol navigation"
  echo    "          What: language-server rename / find-references / diagnostics."
  echo    "          Why:  precise refactors without re-reading files."
  echo    "          Gain: fewer wrong edits and fewer prompt turns on multi-file work."
  echo -e "  ${BOLD}ICM${NC}     persistent cross-tool memory"
  echo    "          What: a memory MCP server shared across Claude, Codex, Gemini, OpenCode"
  echo    "          Why:  recall past decisions and facts instead of re-explaining each session."
  echo    "          Gain: cross-session, cross-tool continuity — recall replaces re-reading."
  echo ""

  local answer
  read -rp "  Install the full stack (all 4)? [Y/n]  (n = choose individually) " answer
  if [[ "$answer" =~ ^[Nn] ]]; then
    echo ""
    local r t s i
    read -rp "    + RTK    — output compression, 60-90% fewer tokens?     [Y/n] " r
    read -rp "    + tilth  — AST code reading, ~40% smaller reads?         [Y/n] " t
    read -rp "    + Serena — rename / find-refs / diagnostics (LSP)?       [Y/n] " s
    read -rp "    + ICM    — cross-tool memory, recall not re-explain?     [Y/n] " i
    [[ ! "$r" =~ ^[Nn] ]] && WIZ_RTK=true    || WIZ_RTK=false
    [[ ! "$t" =~ ^[Nn] ]] && WIZ_TILTH=true  || WIZ_TILTH=false
    [[ ! "$s" =~ ^[Nn] ]] && WIZ_SERENA=true || WIZ_SERENA=false
    [[ ! "$i" =~ ^[Nn] ]] && WIZ_ICM=true    || WIZ_ICM=false
  else
    WIZ_RTK=true; WIZ_TILTH=true; WIZ_SERENA=true; WIZ_ICM=true
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
  $WIZ_ICM    && echo -e "  ${GREEN}+ ICM${NC}"
  $WIZ_DEDUP  && echo -e "  ${GREEN}+ Overlap fix${NC}"
  $WIZ_LOCAL  && echo -e "  ${YELLOW}  Mode: LOCAL (air-gapped)${NC}"
  echo ""

  local confirm
  read -rp "  Proceed? [Y/n] " confirm
  if [[ "$confirm" =~ ^[Nn] ]]; then
    echo "Aborted."
    exit 0
  fi
}

# --- Main ---------------------------------------------------------------------
main() {
  local do_rtk=false do_tilth=false do_serena=false do_icm=false
  local do_dedup=true verify_only=false has_args=false
  LOCAL_MODE=false
  SKIP_TESTS=false
  DRY_RUN=false
  VERBOSE=false
  WITH_CONTEXT_HOOKS=false

  # has_args tracks *intent* flags (--all, --rtk-only, --tilth-only, --serena-only,
  # --verify). Modifier-only flags (--skip-tests, --local, --verbose, --hosts, etc.)
  # leave has_args=false so the wizard still runs and picks install targets.
  # Regression fix (issue #38): previously has_args was set for any flag, so a bare
  # `install.sh --skip-tests` skipped the wizard AND left do_* false, leading to
  # a silent no-op that only updated the token-diet CLI binary.
  while [ $# -gt 0 ]; do
    case "$1" in
      --all)          has_args=true; do_rtk=true; do_tilth=true; do_serena=true ;;
      --rtk-only)     has_args=true; do_rtk=true ;;
      --tilth-only)   has_args=true; do_tilth=true ;;
      --serena-only)  has_args=true; do_serena=true ;;
      --icm-only)     has_args=true; do_icm=true ;;
      --verify)       has_args=true; verify_only=true ;;
      --local)        LOCAL_MODE=true ;;
      --no-dedup)     do_dedup=false ;;
      --skip-tests)   SKIP_TESTS=true ;;
      --dry-run)      DRY_RUN=true; SKIP_TESTS=true ;;
      --verbose)      VERBOSE=true ;;
      --with-context-hooks) WITH_CONTEXT_HOOKS=true ;;
      --hosts)        shift; HOSTS_FILTER="$1" ;;
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
  echo -e "${BOLD}    RTK + tilth + Serena + ICM${NC}"
  echo ""
  if [ "${DRY_RUN:-false}" = "true" ]; then
    echo -e "${MAGENTA}    *** DRY-RUN MODE — no changes will be made ***${NC}\n"
  fi

  if $verify_only; then
    detect_hosts
    verify_stack
    exit 0
  fi

  # Interactive mode when no args given at all.
  # If only modifier flags were given (e.g. --skip-tests, --verbose, --dry-run,
  # --local, --hosts), default to installing all three tools — the user clearly
  # wants the install to run, they just tweaked *how*. Without this default,
  # modifier-only invocations silently no-op (issue #38).
  local any_arg=false
  if $has_args; then
    any_arg=true
    # If user provided ONLY a modifier (like --local) but NO tool flags, we default to ALL tools.
    if ! $do_rtk && ! $do_tilth && ! $do_serena && ! $do_icm; then
      do_rtk=true; do_tilth=true; do_serena=true; do_icm=true
    fi
  elif $LOCAL_MODE || $SKIP_TESTS || $DRY_RUN || $VERBOSE || [ -n "${HOSTS_FILTER:-}" ] || ! $do_dedup; then
    any_arg=true
    do_rtk=true; do_tilth=true; do_serena=true; do_icm=true
  fi
  if ! $any_arg; then
    run_wizard
    do_rtk=$WIZ_RTK; do_tilth=$WIZ_TILTH; do_serena=$WIZ_SERENA; do_icm=$WIZ_ICM
    do_dedup=$WIZ_DEDUP; LOCAL_MODE=$WIZ_LOCAL; SKIP_TESTS=$WIZ_SKIP_TESTS
  fi

  if $LOCAL_MODE; then echo -e "${BOLD}    Mode: LOCAL (air-gapped)${NC}\n"; fi

  # Prerequisites
  header "Prerequisites"
  ensure_git
  if ! $LOCAL_MODE; then ensure_curl; fi
  if $do_rtk || $do_tilth || $do_icm; then ensure_rust; fi
  if $do_serena && ! $LOCAL_MODE; then ensure_uv; fi
  if $do_serena && $LOCAL_MODE; then ensure_docker; fi

  # Detect AI hosts
  header "AI Host Detection"
  detect_hosts
  confirm_hosts

  # Install tools
  $do_rtk    && install_rtk
  $do_tilth  && install_tilth
  $do_serena && install_serena
  $do_icm    && install_icm

  # Overlap fix
  if $do_dedup && $do_tilth && $do_serena; then
    configure_dedup
  fi

  # Install token-diet dashboard command
  install_token_diet

  $WITH_CONTEXT_HOOKS && install_context_hooks

  setup_project_hubs

  verify_stack
}

# --- Discovery Configuration --------------------------------------------------
setup_project_hubs() {
  # Skip in CI or if already configured
  [ -t 0 ] || return 0
  local cfg_dir="${HOME}/.config/token-diet"
  local cfg_file="${cfg_dir}/config.json"
  if [ -f "$cfg_file" ]; then return 0; fi

  header "Discovery Configuration"
  echo "token-diet can automatically find all your project budgets."
  echo "Where do you usually keep your project folders?"
  echo -e "${DIM}(Example: ~/Projects, ~/Code)${NC}"
  echo ""
  
  local user_hubs
  printf "  Enter path(s) [leave blank to skip]: "
  read -r user_hubs || true
  
  if [ -n "$user_hubs" ]; then
    mkdir -p "$cfg_dir"
    TD_LIB_DIR="$SCRIPT_DIR/lib" python3 - "$cfg_file" "$user_hubs" << 'PY'
import os, pathlib, sys
sys.path.insert(0, os.environ["TD_LIB_DIR"])
import tdconfig

path = pathlib.Path(sys.argv[1])
raw = sys.argv[2].replace(",", " ").split()
hubs = [h.strip() for h in raw if h.strip()]
home = str(pathlib.Path.home())
hubs = [h.replace(home, "~") for h in hubs]
# Creating a fresh file (the caller early-returns if it already exists), so
# there is no existing user data to lose here -- atomic_write_json is used for
# consistency and to avoid leaving a half-written file behind on a crash.
tdconfig.atomic_write_json(path, {"project_hubs": hubs})
PY
    ok "Saved project hubs to $cfg_file"
  else
    info "Skipped hub configuration. You can add them later via: token-diet budget hubs add <path>"
  fi
}

main "$@"
