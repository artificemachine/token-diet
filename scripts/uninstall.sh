#!/usr/bin/env bash
# uninstall.sh — remove all token-diet components
#
# Usage:
#   bash uninstall.sh [--dry-run] [--force] [--include-data] [--include-docker]
#                     [--only LIST | --skip LIST]
#
# Flags:
#   --dry-run        Preview what would be removed without making changes
#   --force          Skip confirmation prompts
#   --include-data   Also remove ~/.serena/memories (off by default)
#   --include-docker Also remove token-diet/serena Docker image
#   --only LIST      Remove ONLY these components (comma-separated)
#   --skip LIST      Remove everything EXCEPT these components
#
# Components: serena, icm, context7, token-diet
#   Default is every component. RTK, rtk-mcp and tilth were removed from the
#   stack (deprecated after independent benchmarks found no real savings); the
#   LEGACY CLEANUP region below still removes them so machines with pre-existing
#   installs can be cleaned. Legacy targets are not selectable via --only/--skip
#   — they are always cleaned when present.
#
# Examples:
#   bash uninstall.sh --only context7           # drop Context7 registrations
#   bash uninstall.sh --only serena,icm         # drop the two local tools
#   bash uninstall.sh --skip icm                # remove all but ICM

set -euo pipefail

DRY_RUN=false
FORCE=false
INCLUDE_DATA=false
INCLUDE_DOCKER=false
ONLY=""
SKIP=""

# Selectable components. `token-diet` covers the CLI plus shared infrastructure
# (the local bin lib dir, compat.json, hosts-mcp.json) not tied to one tool.
# TD_LEGACY_COMPONENTS (rtk, rtk-mcp, tilth) are NOT selectable: their cleanup
# always runs when present, so machines installed before they were dropped from
# the stack still get fully cleaned.
TD_ALL_COMPONENTS="serena icm context7 token-diet"
TD_LEGACY_COMPONENTS="rtk rtk-mcp tilth"
COMPONENTS="$TD_ALL_COMPONENTS"

# --- Host registry ------------------------------------------------------------
# uninstall.sh runs from the repo (like install.sh), so it sources the shared
# host library and reads config/hosts-mcp.json — the single source of truth for
# where each host's config lives. It drives the MCP-removal PATH LIST for the
# hosts whose registry entries match uninstall's targets exactly (claude-desktop,
# codex) via td_host_config_paths.
#
# Phase 5 FINAL (DECISION 2 — install/uninstall symmetry): uninstall now removes
# EXACTLY what install writes, for EVERY host. The previously-diverging hosts
# (claude-code's second path ~/.claude.json, opencode's XDG path, VS Code, and
# gemini — added by install but never cleaned) are all cleaned below. Their path
# lists stay EXPLICIT rather than registry-driven because each carries host-
# specific cleanup beyond a flat path list (prompt-rule stripping, plugin de-
# registration, TOML block removal, hook + doc + instruction-file removal); see
# the comment at each site. The lib is optional: curl|sh installs that lack the
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

# --- Partial-failure reporting ------------------------------------------------
# Mirrors install.sh's TD_MUTATED/_td_on_error contract. This matters MORE here
# than in install.sh: uninstall is the rollback path, so it runs when something
# has already gone wrong. Dying at host five under `set -e` with no trap left
# the user with five hosts half-cleaned and no record of which.
TD_REMOVED=()

td_record_removal() {
  TD_REMOVED+=("$1")
}

_td_on_error() {
  local exit_code=$1 line=$2
  echo "" >&2
  printf '%b\n' "${RED:-}[uninstall] FAILED at line ${line} (exit ${exit_code})${NC:-}" >&2

  if [ "${#TD_REMOVED[@]}" -gt 0 ]; then
    echo "" >&2
    echo "Already removed or modified before the failure:" >&2
    local f
    for f in "${TD_REMOVED[@]}"; do
      echo "  - $f" >&2
    done
  else
    echo "Nothing had been removed before the failure." >&2
  fi

  echo "" >&2
  echo "Re-running uninstall.sh is safe: every removal step is idempotent." >&2
  echo "To restore a config from its backup:  cp <file>.bak-token-diet-<ts> <file>" >&2
  exit "$exit_code"
}

trap '_td_on_error $? $LINENO' ERR

# --- Argument parsing ---------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)        DRY_RUN=true ;;
    --force)          FORCE=true ;;
    --include-data)   INCLUDE_DATA=true ;;
    --include-docker) INCLUDE_DOCKER=true ;;
    --only)           shift; ONLY="${1:-}" ;;
    --only=*)         ONLY="${1#*=}" ;;
    --skip)           shift; SKIP="${1:-}" ;;
    --skip=*)         SKIP="${1#*=}" ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

# --- Component selection ------------------------------------------------------
# Resolve --only/--skip into COMPONENTS before any removal runs. An invalid
# selection must abort before the first mutation, not half way through.

# td_known_component <name> — true when <name> is a selectable component.
td_known_component() {
  case " $TD_ALL_COMPONENTS " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# td_validate_selection <flag> <csv> — abort naming the first unknown component.
td_validate_selection() {
  local flag="$1" csv="$2" name
  [ -n "$csv" ] || { echo "$flag requires a comma-separated component list" >&2; exit 1; }
  local IFS=','
  for name in $csv; do
    name="$(echo "$name" | tr -d '[:space:]')"
    [ -n "$name" ] || continue
    if ! td_known_component "$name"; then
      echo "Unknown component: $name" >&2
      echo "Valid components: $TD_ALL_COMPONENTS" >&2
      exit 1
    fi
  done
}

if [ -n "$ONLY" ] && [ -n "$SKIP" ]; then
  echo "--only and --skip are mutually exclusive" >&2
  exit 1
fi

if [ -n "$ONLY" ]; then
  td_validate_selection --only "$ONLY"
  COMPONENTS="$(echo "$ONLY" | tr ',' ' ' | tr -s ' ')"
elif [ -n "$SKIP" ]; then
  td_validate_selection --skip "$SKIP"
  COMPONENTS=""
  for _c in $TD_ALL_COMPONENTS; do
    case ",$SKIP," in *",$_c,"*) continue ;; esac
    COMPONENTS="$COMPONENTS $_c"
  done
  unset _c
fi

# td_component_of <path-or-key> — map a removal target to its component.
# rtk-mcp is matched before rtk so the MCP schema and the compression binary
# never collapse into the same component. Anything unrecognised belongs to
# token-diet: shared infrastructure the CLI owns.
td_component_of() {
  case "$1" in
    *rtk-mcp*)     echo "rtk-mcp" ;;
    *rtk*)         echo "rtk" ;;
    *tilth*)       echo "tilth" ;;
    *context7*)    echo "context7" ;;
    *serena*)      echo "serena" ;;
    *icm*)         echo "icm" ;;
    *)             echo "token-diet" ;;
  esac
}

# td_selected <path-or-key> — true when this target's component is in scope.
# Legacy components (rtk, rtk-mcp, tilth) are always in scope: they are not
# selectable, and their leftovers should be cleaned on every uninstall run.
td_selected() {
  local comp
  comp="$(td_component_of "$1")"
  case " $TD_LEGACY_COMPONENTS " in *" $comp "*) return 0 ;; esac
  case " $COMPONENTS " in *" $comp "*) return 0 ;; *) return 1 ;; esac
}

# --- Helpers ------------------------------------------------------------------

# remove_file <path>
remove_file() {
  local path="$1"
  td_selected "$path" || return 0
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
  td_selected "$key" || return 0
  [ -f "$cfg" ] || { miss "$cfg (mcp.$key)"; return 0; }
  if $DRY_RUN; then
    dry "remove mcp.$key from $cfg"
    return 0
  fi
  python3 - "$cfg" "$key" << 'PY'
import json, os, sys, tempfile
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
def td_load(p):
    """Load JSON, or back the file up and skip this host. Uninstall must never
    abort the whole run because one unrelated host config is malformed."""
    try:
        with open(p) as f:
            return json.load(f)
    except FileNotFoundError:
        sys.exit(0)
    except (json.JSONDecodeError, ValueError) as e:
        import shutil, time
        b = p + ".corrupt-" + time.strftime("%Y%m%d-%H%M%S")
        shutil.copy2(p, b)
        print("[token-diet] SKIP: " + p + " is malformed JSON (" + str(e)
              + "); backed up to " + b + ". Left untouched.", file=sys.stderr)
        sys.exit(0)

cfg_path, key = sys.argv[1], sys.argv[2]
d = td_load(cfg_path)
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
    atomic_write(cfg_path, json.dumps(d, indent=2) + "\n")
PY
  ok "Removed mcp.$key from $cfg"
}

# remove_opencode_plugin <cfg_path> <relpath>
# Removes <relpath> from the top-level "plugin" array in an OpenCode JSON config
# (install_context_hooks registers "plugins/token-diet-hooks.ts" there). Leaves
# all other plugins untouched and preserves the rest of the config.
remove_opencode_plugin() {
  local cfg="$1"
  local relpath="$2"
  # The hooks plugin ships with the token-diet CLI, not with any single tool.
  td_selected "token-diet" || return 0
  [ -f "$cfg" ] || { miss "$cfg (plugin $relpath)"; return 0; }
  if $DRY_RUN; then
    dry "remove plugin $relpath from $cfg"
    return 0
  fi
  python3 - "$cfg" "$relpath" << 'PY'
import json, os, sys, tempfile
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
def td_load(p):
    try:
        with open(p) as f:
            return json.load(f)
    except FileNotFoundError:
        sys.exit(0)
    except (json.JSONDecodeError, ValueError) as e:
        import shutil, time
        b = p + ".corrupt-" + time.strftime("%Y%m%d-%H%M%S")
        shutil.copy2(p, b)
        print("[token-diet] SKIP: " + p + " is malformed JSON (" + str(e)
              + "); backed up to " + b + ". Left untouched.", file=sys.stderr)
        sys.exit(0)

cfg_path, relpath = sys.argv[1], sys.argv[2]
d = td_load(cfg_path)
plugins = d.get("plugin")
if isinstance(plugins, list) and relpath in plugins:
    d["plugin"] = [p for p in plugins if p != relpath]
    atomic_write(cfg_path, json.dumps(d, indent=2) + "\n")
PY
  ok "Removed plugin $relpath from $cfg"
}

# remove_json_key <cfg_path> <key>
# Removes key from mcpServers object in a JSON config file.
remove_json_key() {
  local cfg="$1"
  local key="$2"
  td_selected "$key" || return 0
  [ -f "$cfg" ] || { miss "$cfg (mcpServers.$key)"; return 0; }
  if $DRY_RUN; then
    dry "remove mcpServers.$key from $cfg"
    return 0
  fi
  python3 - "$cfg" "$key" << 'PY'
import json, os, sys, tempfile
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
def td_load(p):
    try:
        with open(p) as f:
            return json.load(f)
    except FileNotFoundError:
        sys.exit(0)
    except (json.JSONDecodeError, ValueError) as e:
        import shutil, time
        b = p + ".corrupt-" + time.strftime("%Y%m%d-%H%M%S")
        shutil.copy2(p, b)
        print("[token-diet] SKIP: " + p + " is malformed JSON (" + str(e)
              + "); backed up to " + b + ". Left untouched.", file=sys.stderr)
        sys.exit(0)

cfg_path, key = sys.argv[1], sys.argv[2]
d = td_load(cfg_path)
if "mcpServers" in d and key in d["mcpServers"]:
    del d["mcpServers"][key]
    atomic_write(cfg_path, json.dumps(d, indent=2) + "\n")
PY
  ok "Removed mcpServers.$key from $cfg"
}

# remove_vscode_template_server <cfg_path> <key>
# Removes key from the top-level "servers" object in the shared VS Code MCP
# template. The template uses "servers" (VS Code schema), not "mcpServers".
remove_vscode_template_server() {
  local cfg="$1"
  local key="$2"
  td_selected "$key" || return 0
  [ -f "$cfg" ] || { miss "$cfg (servers.$key)"; return 0; }
  if $DRY_RUN; then
    dry "remove servers.$key from $cfg"
    return 0
  fi
  python3 - "$cfg" "$key" << 'PY'
import json, os, sys, tempfile
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
def td_load(p):
    try:
        with open(p) as f:
            return json.load(f)
    except FileNotFoundError:
        sys.exit(0)
    except (json.JSONDecodeError, ValueError) as e:
        import shutil, time
        b = p + ".corrupt-" + time.strftime("%Y%m%d-%H%M%S")
        shutil.copy2(p, b)
        print("[token-diet] SKIP: " + p + " is malformed JSON (" + str(e)
              + "); backed up to " + b + ". Left untouched.", file=sys.stderr)
        sys.exit(0)

cfg_path, key = sys.argv[1], sys.argv[2]
d = td_load(cfg_path)
if "servers" in d and key in d["servers"]:
    del d["servers"][key]
    atomic_write(cfg_path, json.dumps(d, indent=2) + "\n")
PY
  ok "Removed servers.$key from $cfg"
}

# strip_opencode_rules <cfg_path>
# Removes the token-diet begin/end block from mode.build.prompt and mode.plan.prompt.
strip_opencode_rules() {
  local cfg="$1"
  # The injected rules block describes the whole stack and is written by the
  # token-diet CLI install step, so it survives a single-tool removal.
  td_selected "token-diet" || return 0
  [ -f "$cfg" ] || { miss "$cfg (mode.*.prompt token-diet block)"; return 0; }
  if $DRY_RUN; then
    dry "strip token-diet block from mode.build.prompt + mode.plan.prompt in $cfg"
    return 0
  fi
  python3 - "$cfg" <<'PY'
import json, os, re, sys, tempfile
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
cfg_path = sys.argv[1]
BEGIN = "<!-- token-diet:begin -->"
END   = "<!-- token-diet:end -->"
pattern = re.compile(r"\n*" + re.escape(BEGIN) + r".*?" + re.escape(END) + r"\n*", re.DOTALL)
def td_load(p):
    try:
        with open(p) as f:
            return json.load(f)
    except FileNotFoundError:
        sys.exit(0)
    except (json.JSONDecodeError, ValueError) as e:
        import shutil, time
        b = p + ".corrupt-" + time.strftime("%Y%m%d-%H%M%S")
        shutil.copy2(p, b)
        print("[token-diet] SKIP: " + p + " is malformed JSON (" + str(e)
              + "); backed up to " + b + ". Left untouched.", file=sys.stderr)
        sys.exit(0)

data = td_load(cfg_path)
changed = False
for mode_name in ("build", "plan"):
    prompt = data.get("mode", {}).get(mode_name, {}).get("prompt", "")
    if BEGIN in prompt:
        data["mode"][mode_name]["prompt"] = pattern.sub("\n", prompt).strip("\n")
        changed = True
if changed:
    atomic_write(cfg_path, json.dumps(data, indent=2) + "\n")
PY
  ok "Stripped token-diet prompt block from $cfg"
}

# remove_line_from_file <file> <pattern>
# Removes lines matching pattern from a file.
remove_line_from_file() {
  local file="$1"
  local pattern="$2"
  # The pattern names the doc being unlinked (e.g. '@token-diet.md').
  td_selected "$pattern" || return 0
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
  # The hook command path names its owner (rtk-rewrite.sh -> rtk,
  # token-diet-hooks/* -> token-diet), so the component falls out of the path.
  td_selected "$command" || return 0
  [ -f "$cfg" ] || { miss "$cfg (hooks.$event)"; return 0; }
  if $DRY_RUN; then
    dry "remove hooks.$event entries matching $command from $cfg"
    return 0
  fi
  python3 - "$cfg" "$event" "$command" << 'PY'
import json, os, sys, tempfile
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
def td_load(p):
    try:
        with open(p) as f:
            return json.load(f)
    except FileNotFoundError:
        sys.exit(0)
    except (json.JSONDecodeError, ValueError) as e:
        import shutil, time
        b = p + ".corrupt-" + time.strftime("%Y%m%d-%H%M%S")
        shutil.copy2(p, b)
        print("[token-diet] SKIP: " + p + " is malformed JSON (" + str(e)
              + "); backed up to " + b + ". Left untouched.", file=sys.stderr)
        sys.exit(0)

cfg_path, event, command = sys.argv[1], sys.argv[2], sys.argv[3]
d = td_load(cfg_path)
hooks = d.get("hooks", {})
entries = hooks.get(event, [])
kept = [e for e in entries if not any(h.get("command") == command for h in e.get("hooks", []))]
if len(kept) != len(entries):
    hooks[event] = kept
    atomic_write(cfg_path, json.dumps(d, indent=2) + "\n")
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
  # Shared shell libs belong to the token-diet component, not to any one tool.
  if td_selected "token-diet" && [ -d "$HOME/.local/bin/lib" ]; then
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
  # The install step creates these for icm but earlier uninstall versions only
  # ran `cargo uninstall`, orphaning the symlinks. Remove them here.
  # (rtk/tilth symlinks are cleaned in the LEGACY CLEANUP region below.)
  remove_file "$HOME/.local/bin/icm"
  # Serena launcher wrapper the installer generates at ~/.local/bin/serena
  # (install.sh install_serena, uvx- or docker-runtime). It is NOT a cargo
  # symlink like icm above, so `cargo uninstall` never touches it — earlier
  # uninstall versions removed the cargo tools but left this behind (install/
  # uninstall asymmetry). Remove it here for symmetry with what install writes.
  remove_file "$HOME/.local/bin/serena"

  echo ""
  echo -e "${BOLD}Rust binaries (cargo uninstall)${NC}"
  if command -v cargo &>/dev/null; then
    # rtk/tilth crates are legacy (see LEGACY CLEANUP below) but their cargo
    # entries are cleaned here too — always selected, never selectable.
    for _crate in rtk tilth icm; do
      td_selected "$_crate" || continue
      if $DRY_RUN; then
        dry "cargo uninstall $_crate"
      else
        cargo uninstall "$_crate" 2>/dev/null \
          && ok "cargo uninstall $_crate" \
          || miss "$_crate (not installed)"
      fi
    done
    unset _crate
  else
    miss "cargo not found — skipping Rust binary removal"
  fi

  # Symmetric with install (Phase 5 DECISION 2). The registry lists TWO
  # claude-code home_configs and install writes to BOTH:
  #   - ~/.claude.json         <- serena/icm/context7 via `claude mcp add --scope
  #                               user`
  #   - ~/.claude/settings.json <- the token-diet MCP server (install_token_diet)
  # Uninstall now cleans both (closing the 1-path/2-path asymmetry Iter 7 flagged).
  # remove_json_key is key-scoped, so a key install never wrote to a given file is
  # a harmless no-op and unrelated user servers are always preserved.
  echo ""
  echo -e "${BOLD}MCP registrations — Claude Code${NC}"
  remove_json_key "$HOME/.claude/settings.json" "serena"
  remove_json_key "$HOME/.claude/settings.json" "icm"
  remove_json_key "$HOME/.claude/settings.json" "context7"
  remove_json_key "$HOME/.claude/settings.json" "token-diet"
  remove_json_key "$HOME/.claude.json" "serena"
  remove_json_key "$HOME/.claude.json" "icm"
  remove_json_key "$HOME/.claude.json" "context7"

  # ICM registers its OWN SessionStart hook in Claude Code (`icm hook start`).
  # It is a hook, not an MCP registration, so remove_json_key above never saw
  # it and a completed uninstall left a command that silently fails on every
  # session (the `|| true` hides it). remove_hook_entry matches the command
  # exactly and gates itself through td_component_of (`*icm*` -> icm), so
  # --only/--skip are honoured and unrelated SessionStart entries survive.
  remove_hook_entry "$HOME/.claude/settings.json" "SessionStart" "icm hook start 2>/dev/null || true"

  # Both Claude Desktop paths (macOS first, Linux second) come from the registry
  # via resolve_claude_desktop_paths; the pair matches uninstall's historical
  # targets exactly, so this is byte-identical with the production registry.
  echo ""
  echo -e "${BOLD}MCP registrations — Claude Desktop (macOS)${NC}"
  remove_json_key "$CD_MAC" "serena"
  remove_json_key "$CD_MAC" "icm"
  remove_json_key "$CD_MAC" "context7"
  remove_json_key "$CD_MAC" "token-diet"

  echo ""
  echo -e "${BOLD}MCP registrations — Claude Desktop (Linux)${NC}"
  remove_json_key "$CD_LINUX" "serena"
  remove_json_key "$CD_LINUX" "icm"
  remove_json_key "$CD_LINUX" "context7"
  remove_json_key "$CD_LINUX" "token-diet"

  # Kept explicit (NOT registry-driven): the registry now records BOTH opencode
  # paths (legacy .opencode.json + XDG .config/opencode/opencode.json), but
  # opencode cleanup is more than a path list — it also strips the prompt rules
  # and de-registers the plugin, both of which target only the XDG path install
  # writes them to. Driving the mcp-key removal from the registry while the rule/
  # plugin logic stays hardcoded would split one host's cleanup across two
  # mechanisms, so the whole block stays explicit.
  echo ""
  echo -e "${BOLD}MCP registrations — OpenCode${NC}"
  remove_opencode_mcp_key "$HOME/.opencode.json" "serena"
  remove_opencode_mcp_key "$HOME/.opencode.json" "icm"
  remove_opencode_mcp_key "$HOME/.opencode.json" "context7"
  remove_opencode_mcp_key "$HOME/.opencode.json" "token-diet"
  remove_opencode_mcp_key "$HOME/.config/opencode/opencode.json" "serena"
  remove_opencode_mcp_key "$HOME/.config/opencode/opencode.json" "icm"
  remove_opencode_mcp_key "$HOME/.config/opencode/opencode.json" "context7"
  remove_opencode_mcp_key "$HOME/.config/opencode/opencode.json" "token-diet"
  strip_opencode_rules "$HOME/.config/opencode/opencode.json"
  # Symmetric with install_context_hooks: it installs an OpenCode plugin file and
  # registers its relative path in opencode.json's "plugin" array. Remove both so
  # a user's other plugins survive and no dangling reference is left behind.
  remove_opencode_plugin "$HOME/.config/opencode/opencode.json" "plugins/token-diet-hooks.ts"
  remove_file "$HOME/.config/opencode/plugins/token-diet-hooks.ts"

  # Kept explicit (NOT registry-driven). VS Code has three distinct locations and
  # only the home settings path is in the registry (project_configs .vscode/* are
  # for detection only; the shared token-diet template is a token-diet-internal
  # file, deliberately not a host config). install writes ONLY the template
  # (install_serena/install_icm) and then instructs the user to copy it into their
  # VS Code config. Uninstall therefore cleans the template (the file install
  # wrote) AND, as a documented courtesy, strips the same three keys from
  # ~/.config/Code/User/settings.json in case the user performed that manual copy —
  # this is the one intentional "clean slightly more than install directly wrote"
  # case. It is safe: remove_json_key is key-scoped (serena/icm/context7 only) and
  # never touches unrelated servers. This is a superset of install's own writes by
  # design, mirroring the manual step install documents.
  echo ""
  echo -e "${BOLD}MCP registrations — VS Code${NC}"
  remove_json_key "$HOME/.config/Code/User/settings.json" "serena"
  remove_json_key "$HOME/.config/Code/User/settings.json" "icm"
  remove_json_key "$HOME/.config/Code/User/settings.json" "context7"
  # Serena, icm AND context7 are written to the shared VS Code MCP template under
  # the top-level "servers" key (not "mcpServers"). install writes all three, so
  # uninstall strips all three for symmetry.
  remove_vscode_template_server "$HOME/.config/token-diet/vscode-mcp.template.json" "serena"
  remove_vscode_template_server "$HOME/.config/token-diet/vscode-mcp.template.json" "icm"
  remove_vscode_template_server "$HOME/.config/token-diet/vscode-mcp.template.json" "context7"

  echo ""
  echo -e "${BOLD}Codex TOML — MCP block removal${NC}"
  # Registry-driven (host="codex", single path) via resolve_codex_path.
  local codex_cfg="$CODEX_CFG_PATH"
  if [ -f "$codex_cfg" ]; then
    if $DRY_RUN; then
      dry "remove [mcp_servers.*] blocks ($(echo "$COMPONENTS $TD_LEGACY_COMPONENTS" | tr ' ' ',')) from $codex_cfg"
    else
      python3 - "$codex_cfg" "$COMPONENTS $TD_LEGACY_COMPONENTS" << 'PY'
import os, re, sys, tempfile
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
path = sys.argv[1]
with open(path) as f:
    lines = f.read().splitlines(keepends=True)

# Proper TOML-block removal (symmetric with install). The previous
# `[^\[]*` regex stopped at the first '[' inside a block body, so an
# `args = ["--from", ...]` line orphaned its array and the token-diet block was
# never removed at all. Remove each token-diet table in full: its header, every
# body line up to (but not including) the next TABLE header, and an immediately
# preceding "added by token-diet" comment line. A table header is `[name]` on its
# own line; an inline array literal (`["--from", ...]`) is NOT a header and stays
# part of the body being removed. User tables are never entered, so their content
# is preserved verbatim.
header_re = re.compile(r'^\[[A-Za-z0-9_.\-]+\]$')            # any TOML table header
# Live components (argv[2], space-separated) plus legacy ones (rtk, rtk-mcp,
# tilth) are removed, so a --only/--skip run still cleans legacy tables while
# leaving deselected live tables in place.
_selected = sorted(sys.argv[2].split(), key=len, reverse=True)
# The trailing (\.[^\]]+)? also matches a server's SUB-tables, e.g.
# [mcp_servers.icm.env]. Without it the parent table is removed and its children
# are orphaned: the body loop stops at the child header (a table header in its
# own right), leaving config that references a server no longer defined.
td_re     = re.compile(
    r'^\[mcp_servers\.(' + '|'.join(re.escape(c) for c in _selected) + r')(\.[^\]]+)?\]$'
)
out, i = [], 0
while i < len(lines):
    if td_re.match(lines[i].strip()):
        if out and "added by token-diet" in out[-1]:
            out.pop()                                        # drop install's comment
            if out and out[-1].strip() == "":
                out.pop()                                    # and the blank before it
        i += 1
        while i < len(lines) and not header_re.match(lines[i].strip()):
            i += 1
        continue
    out.append(lines[i])
    i += 1

atomic_write(path, "".join(out))
PY
      ok "Removed mcp_servers blocks ($(echo "$COMPONENTS $TD_LEGACY_COMPONENTS" | tr ' ' ',')) from $codex_cfg"
    fi
  else
    miss "$codex_cfg"
  fi

  # Symmetric with install (Phase 5 DECISION 2): install registers serena/icm/
  # context7 for Gemini via `gemini mcp add --scope user`, which writes mcpServers
  # entries into ~/.gemini/settings.json. Uninstall never cleaned any of them
  # (Iter 7 gap). remove_json_key is key-scoped, so unrelated user servers stay.
  echo ""
  echo -e "${BOLD}MCP registrations — Gemini CLI${NC}"
  remove_json_key "$HOME/.gemini/settings.json" "serena"
  remove_json_key "$HOME/.gemini/settings.json" "icm"
  remove_json_key "$HOME/.gemini/settings.json" "context7"

  echo ""
  echo -e "${BOLD}Hooks and docs${NC}"
  remove_file "$HOME/.claude/token-diet.md"
  remove_file "$HOME/.codex/token-diet.md"
  # Gemini: install writes ~/.gemini/token-diet.md (write_token-diet.md).
  remove_file "$HOME/.gemini/token-diet.md"
  # Cowork / Claude Desktop: install writes token-diet.md (write_token-diet_md)
  # and awareness-docextract.md (install_context_hooks) into the Claude Desktop
  # config directory. Clean both the macOS and Linux dirs for symmetry.
  local _cd
  for _cd in "$(dirname "$CD_MAC")" "$(dirname "$CD_LINUX")"; do
    remove_file "$_cd/token-diet.md"
    remove_file "$_cd/awareness-docextract.md"
  done

  echo ""
  echo -e "${BOLD}docextract / ctxwarn context hooks (--with-context-hooks)${NC}"
  local docextract_cmd="$HOME/.local/bin/token-diet-hooks/docextract-pre-read.sh"
  local ctxwarn_cmd="$HOME/.local/bin/token-diet-hooks/ctxwarn-post.sh"
  remove_hook_entry "$HOME/.claude/settings.json" "PreToolUse" "$docextract_cmd"
  remove_hook_entry "$HOME/.claude/settings.json" "PostToolUse" "$ctxwarn_cmd"
  # Gemini CLI shares Claude Code's hooks JSON schema; install registers the same
  # two shims (docextract under matcher "read_file", ctxwarn under "*") into
  # ~/.gemini/settings.json. Remove them symmetrically (same command-string key).
  remove_hook_entry "$HOME/.gemini/settings.json" "PreToolUse" "$docextract_cmd"
  remove_hook_entry "$HOME/.gemini/settings.json" "PostToolUse" "$ctxwarn_cmd"
  if td_selected "token-diet" && [ -d "$HOME/.local/bin/token-diet-hooks" ]; then
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
  # Gemini: install adds the @token-diet.md reference to ~/.gemini/GEMINI.md.
  remove_line_from_file "$HOME/.gemini/GEMINI.md"  "@token-diet.md"

  echo ""
  echo -e "${BOLD}Config directories${NC}"
  if td_selected "token-diet" && [ -d "$HOME/.config/token-diet" ]; then
    if $DRY_RUN; then
      dry "rm -rf $HOME/.config/token-diet"
    else
      rm -rf "$HOME/.config/token-diet"
      ok "Removed $HOME/.config/token-diet"
    fi
  else
    miss "$HOME/.config/token-diet"
  fi

  # --- LEGACY CLEANUP -----------------------------------------------------------
  # rtk, rtk-mcp and tilth were removed from the stack (deprecated after
  # independent benchmarks found no real savings). These sections are not
  # selectable via --only/--skip: td_selected always approves legacy components,
  # so pre-existing installs are fully cleaned on every uninstall run.
  echo ""
  echo -e "${BOLD}Legacy cleanup (rtk / rtk-mcp / tilth from pre-existing installs)${NC}"
  remove_file "$HOME/.local/bin/rtk"
  remove_file "$HOME/.local/bin/tilth"
  remove_file "$HOME/.claude/hooks/rtk-rewrite.sh"
  remove_json_key "$HOME/.claude/settings.json" "tilth"
  remove_json_key "$HOME/.claude/settings.json" "rtk-mcp"
  remove_json_key "$HOME/.claude.json" "tilth"
  remove_json_key "$HOME/.claude.json" "rtk-mcp"
  remove_json_key "$CD_MAC" "tilth"
  remove_json_key "$CD_MAC" "rtk-mcp"
  remove_json_key "$CD_LINUX" "tilth"
  remove_json_key "$CD_LINUX" "rtk-mcp"
  remove_opencode_mcp_key "$HOME/.opencode.json" "tilth"
  remove_opencode_mcp_key "$HOME/.opencode.json" "rtk-mcp"
  remove_opencode_mcp_key "$HOME/.config/opencode/opencode.json" "tilth"
  remove_opencode_mcp_key "$HOME/.config/opencode/opencode.json" "rtk-mcp"
  remove_json_key "$HOME/.config/Code/User/settings.json" "tilth"
  remove_vscode_template_server "$HOME/.config/token-diet/vscode-mcp.template.json" "tilth"
  remove_json_key "$HOME/.gemini/settings.json" "tilth"
  remove_json_key "$HOME/.gemini/settings.json" "rtk-mcp"
  for _cd in "$(dirname "$CD_MAC")" "$(dirname "$CD_LINUX")"; do
    remove_file "$_cd/rtk-awareness.md"
  done

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
