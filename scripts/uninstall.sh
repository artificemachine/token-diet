#!/usr/bin/env bash
# uninstall.sh — remove all token-diet components
#
# Usage:
#   bash uninstall.sh [--dry-run] [--force] [--include-data] [--include-docker]
#
# Flags:
#   --dry-run        Preview what would be removed without making changes
#   --force          Skip confirmation prompts
#   --include-data   Also remove ~/.serena/memories (off by default)
#   --include-docker Also remove token-diet/serena Docker image

set -euo pipefail

DRY_RUN=false
FORCE=false
INCLUDE_DATA=false
INCLUDE_DOCKER=false

# --- Host registry ------------------------------------------------------------
# uninstall.sh runs from the repo (like install.sh), so it sources the shared
# host library and reads config/hosts-mcp.json — the single source of truth for
# where each host's config lives. This drives the MCP-removal PATH LIST for the
# hosts whose registry entries match uninstall's historical targets exactly
# (claude-desktop, codex). Hosts whose registry path set diverges from what
# uninstall has always cleaned (claude-code's extra .claude.json, opencode's XDG
# path, the VS Code home configs/template, gemini) stay explicit below; see the
# comments at each site. The lib is optional: curl|sh installs that lack the
# checkout fall back to the literal paths, preserving behavior.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
if [ -f "$SCRIPT_DIR/lib/hosts.sh" ]; then
  # shellcheck source=lib/hosts.sh
  . "$SCRIPT_DIR/lib/hosts.sh"
fi
TD_HOSTS_MCP_REGISTRY="${TD_HOSTS_MCP_REGISTRY:-$PROJECT_ROOT/config/hosts-mcp.json}"

# Default (fallback) paths — used verbatim when the registry/lib is unavailable
# or yields an unexpected count. Registry order is macOS first, Linux second.
CD_MAC="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
CD_LINUX="$HOME/.config/Claude/claude_desktop_config.json"
CODEX_CFG_PATH="$HOME/.codex/config.toml"

# resolve_claude_desktop_paths — source the two Claude Desktop config paths from
# the registry (host="claude-desktop"). Mirrors install.sh's resolve_cowork_cfg:
# only adopt the registry pair when it yields exactly two paths, else keep the
# literal fallback so behavior is preserved without a checkout.
resolve_claude_desktop_paths() {
  command -v td_host_config_paths >/dev/null 2>&1 || return 0
  local reg_paths=() _p
  while IFS= read -r _p; do
    [ -n "$_p" ] && reg_paths+=("$HOME/$_p")
  done < <(td_host_config_paths "$TD_HOSTS_MCP_REGISTRY" claude-desktop)
  if [ "${#reg_paths[@]}" -eq 2 ]; then
    CD_MAC="${reg_paths[0]}"
    CD_LINUX="${reg_paths[1]}"
  fi
}

# resolve_codex_path — source the single Codex config path from the registry
# (host="codex"). Adopt the registry path only when it yields exactly one entry.
resolve_codex_path() {
  command -v td_host_config_paths >/dev/null 2>&1 || return 0
  local reg_paths=() _p
  while IFS= read -r _p; do
    [ -n "$_p" ] && reg_paths+=("$HOME/$_p")
  done < <(td_host_config_paths "$TD_HOSTS_MCP_REGISTRY" codex)
  if [ "${#reg_paths[@]}" -eq 1 ]; then
    CODEX_CFG_PATH="${reg_paths[0]}"
  fi
}

# --- Colors -------------------------------------------------------------------
if [ -t 1 ]; then
  GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
  BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
  GREEN=''; YELLOW=''; RED=''; BOLD=''; DIM=''; NC=''
fi

ok()   { echo -e "  ${GREEN}✓${NC}  $*"; }
warn() { echo -e "  ${YELLOW}!${NC}  $*"; }
dry()  { echo -e "  ${DIM}[dry-run]${NC}  $*"; }
miss() { echo -e "  ${DIM}–${NC}  $*  (not found, skipping)"; }

# --- Argument parsing ---------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)        DRY_RUN=true ;;
    --force)          FORCE=true ;;
    --include-data)   INCLUDE_DATA=true ;;
    --include-docker) INCLUDE_DOCKER=true ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

# --- Helpers ------------------------------------------------------------------

# remove_file <path>
remove_file() {
  local path="$1"
  if [ ! -e "$path" ]; then
    miss "$path"
    return 0
  fi
  if $DRY_RUN; then
    dry "rm $path"
  else
    rm -f "$path"
    ok "Removed $path"
  fi
}

# remove_opencode_mcp_key <cfg_path> <key>
# Removes key from the "mcp" object in an OpenCode JSON config file.
# OpenCode 1.x uses "mcp", not "mcpServers" — using remove_json_key on
# OpenCode configs leaves stale "mcpServers" blocks that trigger ConfigInvalidError.
remove_opencode_mcp_key() {
  local cfg="$1"
  local key="$2"
  [ -f "$cfg" ] || { miss "$cfg (mcp.$key)"; return 0; }
  if $DRY_RUN; then
    dry "remove mcp.$key from $cfg"
    return 0
  fi
  python3 - "$cfg" "$key" << 'PY'
import json, sys
cfg_path, key = sys.argv[1], sys.argv[2]
with open(cfg_path) as f:
    d = json.load(f)
changed = False
if "mcp" in d and key in d["mcp"]:
    del d["mcp"][key]
    changed = True
# Also remove from "mcpServers" if a stale entry exists there (legacy installs)
if "mcpServers" in d and key in d["mcpServers"]:
    del d["mcpServers"][key]
    if not d["mcpServers"]:
        del d["mcpServers"]
    changed = True
if changed:
    with open(cfg_path, "w") as f:
        json.dump(d, f, indent=2)
        f.write("\n")
PY
  ok "Removed mcp.$key from $cfg"
}

# remove_json_key <cfg_path> <key>
# Removes key from mcpServers object in a JSON config file.
remove_json_key() {
  local cfg="$1"
  local key="$2"
  [ -f "$cfg" ] || { miss "$cfg (mcpServers.$key)"; return 0; }
  if $DRY_RUN; then
    dry "remove mcpServers.$key from $cfg"
    return 0
  fi
  python3 - "$cfg" "$key" << 'PY'
import json, sys
cfg_path, key = sys.argv[1], sys.argv[2]
with open(cfg_path) as f:
    d = json.load(f)
if "mcpServers" in d and key in d["mcpServers"]:
    del d["mcpServers"][key]
    with open(cfg_path, "w") as f:
        json.dump(d, f, indent=2)
        f.write("\n")
PY
  ok "Removed mcpServers.$key from $cfg"
}

# remove_vscode_template_server <cfg_path> <key>
# Removes key from the top-level "servers" object in the shared VS Code MCP
# template. The template uses "servers" (VS Code schema), not "mcpServers".
remove_vscode_template_server() {
  local cfg="$1"
  local key="$2"
  [ -f "$cfg" ] || { miss "$cfg (servers.$key)"; return 0; }
  if $DRY_RUN; then
    dry "remove servers.$key from $cfg"
    return 0
  fi
  python3 - "$cfg" "$key" << 'PY'
import json, sys
cfg_path, key = sys.argv[1], sys.argv[2]
with open(cfg_path) as f:
    d = json.load(f)
if "servers" in d and key in d["servers"]:
    del d["servers"][key]
    with open(cfg_path, "w") as f:
        json.dump(d, f, indent=2)
        f.write("\n")
PY
  ok "Removed servers.$key from $cfg"
}

# strip_opencode_rules <cfg_path>
# Removes the token-diet begin/end block from mode.build.prompt and mode.plan.prompt.
strip_opencode_rules() {
  local cfg="$1"
  [ -f "$cfg" ] || { miss "$cfg (mode.*.prompt token-diet block)"; return 0; }
  if $DRY_RUN; then
    dry "strip token-diet block from mode.build.prompt + mode.plan.prompt in $cfg"
    return 0
  fi
  python3 - "$cfg" <<'PY'
import json, re, sys
cfg_path = sys.argv[1]
BEGIN = "<!-- token-diet:begin -->"
END   = "<!-- token-diet:end -->"
pattern = re.compile(r"\n*" + re.escape(BEGIN) + r".*?" + re.escape(END) + r"\n*", re.DOTALL)
try:
    with open(cfg_path) as f: data = json.load(f)
except (json.JSONDecodeError, ValueError):
    sys.exit(0)
changed = False
for mode_name in ("build", "plan"):
    prompt = data.get("mode", {}).get(mode_name, {}).get("prompt", "")
    if BEGIN in prompt:
        data["mode"][mode_name]["prompt"] = pattern.sub("\n", prompt).strip("\n")
        changed = True
if changed:
    with open(cfg_path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
PY
  ok "Stripped token-diet prompt block from $cfg"
}

# remove_line_from_file <file> <pattern>
# Removes lines matching pattern from a file.
remove_line_from_file() {
  local file="$1"
  local pattern="$2"
  [ -f "$file" ] || { miss "$file ($pattern)"; return 0; }
  if $DRY_RUN; then
    dry "remove '$pattern' from $file"
    return 0
  fi
  local tmp; tmp=$(mktemp)
  grep -v "$pattern" "$file" > "$tmp" || true
  mv "$tmp" "$file"
  ok "Removed '$pattern' from $file"
}

# remove_hook_entry <config_json_path> <event> <command>
# Removes any hooks.<event>[] entry whose hooks[] contains a hook with this
# exact command string. Leaves all other entries (and all other events)
# untouched. Mirrors install.sh's merge_hook_entry() idempotency key.
remove_hook_entry() {
  local cfg="$1"
  local event="$2"
  local command="$3"
  [ -f "$cfg" ] || { miss "$cfg (hooks.$event)"; return 0; }
  if $DRY_RUN; then
    dry "remove hooks.$event entries matching $command from $cfg"
    return 0
  fi
  python3 - "$cfg" "$event" "$command" << 'PY'
import json, sys
cfg_path, event, command = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(cfg_path) as f:
        d = json.load(f)
except Exception:
    sys.exit(0)
hooks = d.get("hooks", {})
entries = hooks.get(event, [])
kept = [e for e in entries if not any(h.get("command") == command for h in e.get("hooks", []))]
if len(kept) != len(entries):
    hooks[event] = kept
    with open(cfg_path, "w") as f:
        json.dump(d, f, indent=2)
        f.write("\n")
PY
  ok "Removed hooks.$event entry ($command) from $cfg"
}

# confirm <message>
# Prompts for confirmation unless --force is set.
confirm() {
  $FORCE && return 0
  echo -e "${YELLOW}$1${NC}"
  read -r -p "Continue? [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
}

# --- Main ---------------------------------------------------------------------
main() {
  resolve_claude_desktop_paths
  resolve_codex_path

  echo -e "\n${BOLD}token-diet uninstall${NC}\n"

  if $DRY_RUN; then
    echo -e "  ${DIM}Dry-run mode — no files will be removed${NC}\n"
  fi

  if ! $FORCE && ! $DRY_RUN; then
    confirm "This will remove token-diet binaries, MCP registrations, and config files."
  fi

  echo -e "${BOLD}Binaries${NC}"
  remove_file "$HOME/.local/bin/token-diet"
  remove_file "$HOME/.local/bin/token-diet-dashboard"
  remove_file "$HOME/.local/bin/token-diet-mcp"
  if [ -d "$HOME/.local/bin/lib" ]; then
    if $DRY_RUN; then
      dry "rm -rf $HOME/.local/bin/lib"
    else
      rm -rf "$HOME/.local/bin/lib"
      ok "Removed $HOME/.local/bin/lib"
    fi
  else
    miss "$HOME/.local/bin/lib"
  fi
  # Version-compat data the installer copies to ~/.local/config/compat.json.
  remove_file "$HOME/.local/config/compat.json"
  # Canonical MCP-host registry the installer copies to ~/.local/config/.
  remove_file "$HOME/.local/config/hosts-mcp.json"
  # Symlinks the installer leaves in ~/.local/bin (→ ~/.cargo/bin/<tool>).
  # The install step creates these for rtk, tilth and icm but earlier uninstall
  # versions only ran `cargo uninstall`, orphaning the symlinks. Remove them here.
  remove_file "$HOME/.local/bin/rtk"
  remove_file "$HOME/.local/bin/tilth"
  remove_file "$HOME/.local/bin/icm"

  echo ""
  echo -e "${BOLD}Rust binaries (cargo uninstall)${NC}"
  if command -v cargo &>/dev/null; then
    if $DRY_RUN; then
      dry "cargo uninstall rtk"
      dry "cargo uninstall tilth"
      dry "cargo uninstall icm"
    else
      cargo uninstall rtk  2>/dev/null && ok "cargo uninstall rtk"  || miss "rtk (not installed)"
      cargo uninstall tilth 2>/dev/null && ok "cargo uninstall tilth" || miss "tilth (not installed)"
      cargo uninstall icm  2>/dev/null && ok "cargo uninstall icm"  || miss "icm (not installed)"
    fi
  else
    miss "cargo not found — skipping Rust binary removal"
  fi

  # Kept explicit (NOT registry-driven): the registry lists TWO claude-code
  # home_configs — .claude/settings.json AND .claude.json — but uninstall has
  # only ever cleaned settings.json. Iterating the registry here would newly
  # touch .claude.json (behavior expansion), so the path stays hardcoded.
  echo ""
  echo -e "${BOLD}MCP registrations — Claude Code${NC}"
  remove_json_key "$HOME/.claude/settings.json" "tilth"
  remove_json_key "$HOME/.claude/settings.json" "serena"
  remove_json_key "$HOME/.claude/settings.json" "icm"

  # Both Claude Desktop paths (macOS first, Linux second) come from the registry
  # via resolve_claude_desktop_paths; the pair matches uninstall's historical
  # targets exactly, so this is byte-identical with the production registry.
  echo ""
  echo -e "${BOLD}MCP registrations — Claude Desktop (macOS)${NC}"
  remove_json_key "$CD_MAC" "tilth"
  remove_json_key "$CD_MAC" "serena"
  remove_json_key "$CD_MAC" "icm"

  echo ""
  echo -e "${BOLD}MCP registrations — Claude Desktop (Linux)${NC}"
  remove_json_key "$CD_LINUX" "tilth"
  remove_json_key "$CD_LINUX" "serena"
  remove_json_key "$CD_LINUX" "icm"

  # Kept explicit (NOT registry-driven): the registry's single opencode entry is
  # the LEGACY .opencode.json, but install.sh writes to the XDG path
  # .config/opencode/opencode.json — which uninstall must also clean (plus strip
  # the prompt rules there). Registry-driving would drop the XDG path (behavior
  # shrink). Path stays explicit until the registry records both opencode paths.
  echo ""
  echo -e "${BOLD}MCP registrations — OpenCode${NC}"
  remove_opencode_mcp_key "$HOME/.opencode.json" "tilth"
  remove_opencode_mcp_key "$HOME/.opencode.json" "serena"
  remove_opencode_mcp_key "$HOME/.opencode.json" "icm"
  remove_opencode_mcp_key "$HOME/.config/opencode/opencode.json" "tilth"
  remove_opencode_mcp_key "$HOME/.config/opencode/opencode.json" "serena"
  remove_opencode_mcp_key "$HOME/.config/opencode/opencode.json" "icm"
  strip_opencode_rules "$HOME/.config/opencode/opencode.json"

  # Kept explicit (NOT registry-driven): the registry's vscode entries are the
  # PROJECT-scoped .vscode/mcp.json and .vscode/settings.json (project_configs),
  # which uninstall never touches. What uninstall actually cleans is the HOME
  # VS Code settings and the shared token-diet template — neither is in the
  # registry. The two path sets are disjoint, so this stays hardcoded.
  echo ""
  echo -e "${BOLD}MCP registrations — VS Code${NC}"
  remove_json_key "$HOME/.config/Code/User/settings.json" "tilth"
  remove_json_key "$HOME/.config/Code/User/settings.json" "serena"
  remove_json_key "$HOME/.config/Code/User/settings.json" "icm"
  # ICM (and Serena/tilth) are written to the shared VS Code MCP template under
  # the top-level "servers" key, not "mcpServers". Strip icm from it here.
  remove_vscode_template_server "$HOME/.config/token-diet/vscode-mcp.template.json" "icm"

  echo ""
  echo -e "${BOLD}Codex TOML — MCP block removal${NC}"
  # Registry-driven (host="codex", single path) via resolve_codex_path.
  local codex_cfg="$CODEX_CFG_PATH"
  if [ -f "$codex_cfg" ]; then
    if $DRY_RUN; then
      dry "remove [mcp_servers.{tilth,serena,icm}] blocks from $codex_cfg"
    else
      python3 - "$codex_cfg" << 'PY'
import sys, re
path = sys.argv[1]
with open(path) as f:
    content = f.read()
# Remove [mcp_servers.tilth], [mcp_servers.serena] and [mcp_servers.icm] blocks
content = re.sub(r'\[mcp_servers\.(tilth|serena|icm)\][^\[]*', '', content, flags=re.DOTALL)
with open(path, "w") as f:
    f.write(content)
PY
      ok "Removed mcp_servers.{tilth,serena,icm} from $codex_cfg"
    fi
  else
    miss "$codex_cfg"
  fi

  echo ""
  echo -e "${BOLD}Hooks and docs${NC}"
  remove_file "$HOME/.claude/hooks/rtk-rewrite.sh"
  remove_file "$HOME/.claude/token-diet.md"
  remove_file "$HOME/.codex/token-diet.md"

  echo ""
  echo -e "${BOLD}docextract / ctxwarn context hooks (--with-context-hooks)${NC}"
  local docextract_cmd="$HOME/.local/bin/token-diet-hooks/docextract-pre-read.sh"
  local ctxwarn_cmd="$HOME/.local/bin/token-diet-hooks/ctxwarn-post.sh"
  remove_hook_entry "$HOME/.claude/settings.json" "PreToolUse" "$docextract_cmd"
  remove_hook_entry "$HOME/.claude/settings.json" "PostToolUse" "$ctxwarn_cmd"
  if [ -d "$HOME/.local/bin/token-diet-hooks" ]; then
    if $DRY_RUN; then
      dry "rm -rf $HOME/.local/bin/token-diet-hooks"
    else
      rm -rf "$HOME/.local/bin/token-diet-hooks"
      ok "Removed $HOME/.local/bin/token-diet-hooks"
    fi
  else
    miss "$HOME/.local/bin/token-diet-hooks"
  fi
  remove_file "$HOME/.codex/awareness-docextract.md"
  remove_file "$HOME/.gemini/awareness-docextract.md"

  echo ""
  echo -e "${BOLD}Instruction file references${NC}"
  remove_line_from_file "$HOME/.claude/CLAUDE.md"  "@token-diet.md"
  remove_line_from_file "$HOME/.codex/AGENTS.md"   "@token-diet.md"

  echo ""
  echo -e "${BOLD}Config directories${NC}"
  if [ -d "$HOME/.config/token-diet" ]; then
    if $DRY_RUN; then
      dry "rm -rf $HOME/.config/token-diet"
    else
      rm -rf "$HOME/.config/token-diet"
      ok "Removed $HOME/.config/token-diet"
    fi
  else
    miss "$HOME/.config/token-diet"
  fi

  if $INCLUDE_DATA; then
    echo ""
    echo -e "${BOLD}Serena memories (--include-data)${NC}"
    if [ -d "$HOME/.serena/memories" ]; then
      if $DRY_RUN; then
        dry "rm -rf $HOME/.serena/memories"
      else
        rm -rf "$HOME/.serena/memories"
        ok "Removed $HOME/.serena/memories"
      fi
    else
      miss "$HOME/.serena/memories"
    fi

    echo ""
    echo -e "${BOLD}ICM config (--include-data)${NC}"
    remove_file "$HOME/.config/icm/config.toml"
  fi

  if $INCLUDE_DOCKER; then
    echo ""
    echo -e "${BOLD}Docker image (--include-docker)${NC}"
    if command -v docker &>/dev/null && docker image inspect token-diet/serena:latest &>/dev/null 2>&1; then
      if $DRY_RUN; then
        dry "docker rmi token-diet/serena:latest"
      else
        docker rmi token-diet/serena:latest
        ok "Removed Docker image token-diet/serena:latest"
      fi
    else
      miss "token-diet/serena:latest (not found)"
    fi
  fi

  echo ""
  if $DRY_RUN; then
    echo -e "  ${DIM}Dry-run complete — no changes made${NC}"
  else
    echo -e "  ${GREEN}${BOLD}token-diet uninstalled${NC}"
  fi
  echo ""
}

main
