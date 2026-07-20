#!/usr/bin/env bash
# token-diet release gate — handles remaining manual v1.0.0 items:
#   1. cargo test + cargo clippy on both Rust forks
#   2. serena pytest
#   3. forks/README.md staging
#   4. binary signing (codesign / gpg)
#   5. git tag
#
# Usage:
#   bash scripts/release.sh              # run all checks
#   bash scripts/release.sh --sign-only  # signing + tag only
#   bash scripts/release.sh --test-only  # tests + clippy only
#   bash scripts/release.sh --dry-run    # check without signing or tagging

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
FORKS="$ROOT/forks"
DIST="$ROOT/dist"

# Single source of truth: scripts/token-diet's TD_VERSION. This was hardcoded
# to "1.2.0" until v1.15.1 — thirteen minor versions stale — so the gate would
# have tagged the wrong version had anyone run it. Never restate the version here.
VERSION="$(sed -n 's/^readonly TD_VERSION="\(.*\)"$/\1/p' "$SCRIPT_DIR/token-diet")"
[ -n "$VERSION" ] || { echo "cannot read TD_VERSION from $SCRIPT_DIR/token-diet" >&2; exit 1; }

# Curated GitHub releases to retain. Tags are permanent history and are never
# pruned; releases are the browsable surface. See docs/release-policy.md.
RELEASE_RETENTION="${RELEASE_RETENTION:-10}"

# --- Colors -------------------------------------------------------------------
if [ -t 1 ]; then
  GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
  BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
else
  GREEN=''; YELLOW=''; RED=''; BLUE=''; BOLD=''; NC=''
fi

info()   { echo -e "${BLUE}[info]${NC}   $*"; }
ok()     { echo -e "${GREEN}[ok]${NC}     $*"; }
warn()   { echo -e "${YELLOW}[warn]${NC}   $*"; }
fail()   { echo -e "${RED}[fail]${NC}   $*"; exit 1; }
skip()   { echo -e "${YELLOW}[skip]${NC}   $*"; }
header() { echo -e "\n${BOLD}=== $* ===${NC}\n"; }

PASS=0
FAIL=0
WARN=0

record_ok()   { ok "$1";   PASS=$((PASS + 1)); }
record_fail() { fail "$1"; }
record_warn() { warn "$1"; WARN=$((WARN + 1)); }

# --- Flags --------------------------------------------------------------------
DO_TESTS=true
DO_SIGN=true
DO_TAG=true
DRY_RUN=false

while [ $# -gt 0 ]; do
  case "$1" in
    --sign-only) DO_TESTS=false ;;
    --test-only) DO_SIGN=false; DO_TAG=false ;;
    --dry-run)   DRY_RUN=true; DO_SIGN=false; DO_TAG=false ;;
    -h|--help)
      sed -n '2,10p' "$0" | sed 's/^# //'
      exit 0 ;;
    *) warn "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

# --- Preflight ----------------------------------------------------------------
header "Preflight"

cd "$ROOT"

BRANCH=$(git rev-parse --abbrev-ref HEAD)
info "Branch: $BRANCH"
if [ "$BRANCH" != "main" ]; then
  record_warn "Not on main (on '$BRANCH'). Merge or switch before tagging."
fi

# Verify submodules are initialized
for fork in rtk tilth serena; do
  if [ -z "$(ls -A "$FORKS/$fork" 2>/dev/null)" ]; then
    fail "forks/$fork is empty — run: git submodule update --init --recursive"
  fi
  ok "forks/$fork initialized"
done

# Stage forks/README.md if untracked
if git status --porcelain | grep -q "^?? forks/README.md"; then
  info "Staging forks/README.md (untracked docs file)"
  git add forks/README.md
  record_ok "forks/README.md staged"
fi

# Warn about any other unstaged changes
UNSTAGED=$(git status --porcelain | grep -v "^?? " | grep -v "^M  " | wc -l | tr -d ' ')
if [ "$UNSTAGED" -gt 0 ]; then
  record_warn "Unstaged changes present — commit or stash before tagging"
  git status --short
fi

# --- Tests + Clippy -----------------------------------------------------------
if $DO_TESTS; then

  header "RTK — cargo clippy + test"
  command -v cargo &>/dev/null || fail "Rust toolchain not found"

  info "Running clippy on RTK..."
  if cargo clippy --manifest-path "$FORKS/rtk/Cargo.toml" --all-targets -- -D warnings 2>&1; then
    record_ok "RTK clippy clean"
  else
    record_warn "RTK clippy warnings — review before release"
  fi

  info "Running RTK tests..."
  if cargo test --manifest-path "$FORKS/rtk/Cargo.toml" 2>&1 | tee /tmp/rtk-test.log | tail -5; then
    if grep -q "FAILED\|error\[" /tmp/rtk-test.log; then
      record_warn "RTK test failures — check /tmp/rtk-test.log"
    else
      record_ok "RTK tests passed"
    fi
  else
    record_warn "RTK tests did not complete cleanly"
  fi

  header "tilth — cargo clippy + test"

  info "Running clippy on tilth..."
  if cargo clippy --manifest-path "$FORKS/tilth/Cargo.toml" --all-targets -- -D warnings 2>&1; then
    record_ok "tilth clippy clean"
  else
    record_warn "tilth clippy warnings — review before release"
  fi

  info "Running tilth tests..."
  if cargo test --manifest-path "$FORKS/tilth/Cargo.toml" 2>&1 | tee /tmp/tilth-test.log | tail -5; then
    if grep -q "FAILED\|error\[" /tmp/tilth-test.log; then
      record_warn "tilth test failures — check /tmp/tilth-test.log"
    else
      record_ok "tilth tests passed"
    fi
  else
    record_warn "tilth tests did not complete cleanly"
  fi

  header "Serena — pytest"

  if command -v uv &>/dev/null; then
    info "Running serena pytest..."
    if ( cd "$FORKS/serena" && uv run pytest --tb=short -q 2>&1 | tee /tmp/serena-test.log | tail -10 ); then
      if grep -q "FAILED\|ERROR" /tmp/serena-test.log; then
        record_warn "serena test failures — check /tmp/serena-test.log"
      else
        record_ok "serena tests passed"
      fi
    else
      record_warn "serena pytest did not complete cleanly"
    fi
  else
    skip "uv not found — skipping serena pytest (install uv to enable)"
    WARN=$((WARN + 1))
  fi

fi  # DO_TESTS

# --- Binary Signing -----------------------------------------------------------
if $DO_SIGN && ! $DRY_RUN; then

  header "Binary Signing"

  RTK_BIN="$DIST/rtk"
  TILTH_BIN="$DIST/tilth"

  if [ ! -f "$RTK_BIN" ] || [ ! -f "$TILTH_BIN" ]; then
    skip "Binaries not found in dist/ — run 'bash scripts/build.sh --release' first"
    WARN=$((WARN + 1))
  else
    OS="$(uname -s)"

    if [ "$OS" = "Darwin" ]; then
      # --- macOS codesign -------------------------------------------------------
      info "Signing binaries with codesign (macOS)..."

      # Check for signing identity
      IDENTITY=""
      if command -v security &>/dev/null; then
        IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/' || true)
      fi

      if [ -z "$IDENTITY" ]; then
        warn "No 'Developer ID Application' certificate found in keychain."
        warn "For ad-hoc signing (local use only): codesign -s - dist/rtk dist/tilth"
        warn "For distribution: install a Developer ID certificate first."
        echo ""
        read -rp "Sign ad-hoc for local use? [y/N] " ADHOC
        if [[ "$ADHOC" =~ ^[Yy]$ ]]; then
          codesign -s - "$RTK_BIN" && record_ok "RTK signed (ad-hoc)"
          codesign -s - "$TILTH_BIN" && record_ok "tilth signed (ad-hoc)"
        else
          skip "Signing skipped — add Developer ID certificate and re-run"
          WARN=$((WARN + 1))
        fi
      else
        info "Found identity: $IDENTITY"
        codesign --sign "$IDENTITY" --options runtime --timestamp "$RTK_BIN"
        record_ok "RTK signed: $IDENTITY"
        codesign --sign "$IDENTITY" --options runtime --timestamp "$TILTH_BIN"
        record_ok "tilth signed: $IDENTITY"
      fi

    else
      # --- Linux/other: GPG detached signature ----------------------------------
      info "Signing binaries with GPG (Linux)..."

      if ! command -v gpg &>/dev/null; then
        skip "gpg not found — install gnupg and re-run"
        WARN=$((WARN + 1))
      else
        GPG_KEY=$(gpg --list-secret-keys --keyid-format=long 2>/dev/null | grep "^sec" | head -1 | awk '{print $2}' | cut -d/ -f2 || true)

        if [ -z "$GPG_KEY" ]; then
          warn "No GPG secret key found."
          warn "Generate one with: gpg --full-generate-key"
          skip "Signing skipped — no GPG key available"
          WARN=$((WARN + 1))
        else
          info "Using GPG key: $GPG_KEY"
          gpg --batch --yes --detach-sign --armor --local-user "$GPG_KEY" "$RTK_BIN"
          record_ok "RTK signed: $RTK_BIN.asc"
          gpg --batch --yes --detach-sign --armor --local-user "$GPG_KEY" "$TILTH_BIN"
          record_ok "tilth signed: $TILTH_BIN.asc"
        fi
      fi
    fi
  fi

fi  # DO_SIGN

# --- Git Tag ------------------------------------------------------------------
if $DO_TAG && ! $DRY_RUN; then

  header "Git Tag v$VERSION"

  if git tag -l "v$VERSION" | grep -q "v$VERSION"; then
    skip "Tag v$VERSION already exists"
    WARN=$((WARN + 1))
  else
    if [ "$WARN" -gt 0 ]; then
      echo ""
      warn "$WARN warning(s) above. Tag anyway?"
      read -rp "Create tag v$VERSION? [y/N] " CONFIRM
      [[ "$CONFIRM" =~ ^[Yy]$ ]] || { info "Tag skipped."; exit 0; }
    fi

    # Every value here is derived. The previous template hardcoded all of it and
    # every single field had drifted false: it printed token-diet's own $VERSION
    # as RTK's version, claimed tilth 0.5.7 (actually 0.9.0) and serena-agent
    # 0.1.4 (actually 1.5.4.dev0), listed three stale submodule SHAs, and omitted
    # forks/icm entirely -- there are four forks, not three.
    #
    # It also asserted "0 vulnerabilities (164 deps)" on every tag. No audit runs
    # at tag time, so that was an unverified security claim baked into permanent
    # history. Dropped rather than derived: state what is known, not what sounds
    # reassuring. Run `cargo audit` / `uv run pip-audit` separately and record
    # real results in the release notes if that claim is wanted.
    TAG_MSG="token-diet v$VERSION

Tool versions:
$(for t in rtk tilth icm; do
    # `<tool> --version` prints "<tool> X.Y.Z"; keep only the version field.
    v="$(command -v "$t" >/dev/null 2>&1 && "$t" --version 2>/dev/null | tail -1 | awk '{print $NF}')"
    printf '  %-7s %s\n' "$t:" "${v:-not installed}"
  done)
$(sp="$(sed -n 's/^version *= *"\(.*\)"$/\1/p' "$FORKS/serena/pyproject.toml" 2>/dev/null | head -1)"
  printf '  %-7s %s\n' "serena:" "${sp:-unknown}")

Submodule commits:
$(git submodule status 2>/dev/null | awk '{printf "  %-14s %s\n", $2":", $1}' | sed 's/[+-]//')

See CHANGELOG.md for full details."

    git tag -a "v$VERSION" -m "$TAG_MSG"
    record_ok "Tag v$VERSION created (run 'git push origin v$VERSION' to publish)"
  fi

fi  # DO_TAG

# --- Release Retention --------------------------------------------------------
# Enforces docs/release-policy.md: keep the newest $RELEASE_RETENTION releases.
# Deletes the GitHub *release* only; the underlying tag is left in place, so
# nothing is lost from history. Drifted to 13 before v1.15.1 because this was a
# manual step documented in an untracked file.
prune_releases() {
  command -v gh >/dev/null 2>&1 || { skip "gh not installed — release retention not checked"; return 0; }
  gh auth status >/dev/null 2>&1 || { skip "gh not authenticated — release retention not checked"; return 0; }

  local all excess
  # gh lists newest-first; anything past the retention count is excess.
  all=$(gh release list --limit 200 --json tagName --jq '.[].tagName' 2>/dev/null) || {
    record_warn "Could not list releases — retention not enforced"; return 0; }
  [ -n "$all" ] || return 0

  excess=$(printf '%s\n' "$all" | tail -n +$((RELEASE_RETENTION + 1)))
  if [ -z "$excess" ]; then
    record_ok "Release retention: $(printf '%s\n' "$all" | grep -c .) release(s), within the $RELEASE_RETENTION limit"
    return 0
  fi

  if $DRY_RUN; then
    warn "Would prune $(printf '%s\n' "$excess" | grep -c .) release(s) beyond the newest $RELEASE_RETENTION:"
    printf '%s\n' "$excess" | sed 's/^/           /'
    return 0
  fi

  local t
  while read -r t; do
    [ -n "$t" ] || continue
    if gh release delete "$t" --yes >/dev/null 2>&1; then
      info "Pruned release $t (tag retained)"
    else
      record_warn "Failed to prune release $t"
    fi
  done <<< "$excess"
  record_ok "Release retention enforced — newest $RELEASE_RETENTION kept"
}

# Only runs on a real release path. --test-only / --sign-only must never delete
# a release as a side effect of running checks; --dry-run reports without acting.
if $DO_TAG || $DRY_RUN; then
  header "Release Retention"
  prune_releases
fi

# --- Summary ------------------------------------------------------------------
header "Release Gate Summary"

echo -e "  ${GREEN}Passed${NC}:   $PASS"
echo -e "  ${YELLOW}Warnings${NC}: $WARN"
echo ""

if [ "$WARN" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}READY for v$VERSION${NC}"
else
  echo -e "${YELLOW}${BOLD}READY WITH WARNINGS — review items above before publishing${NC}"
fi

echo ""
if ! $DRY_RUN && ! git tag -l "v$VERSION" | grep -q "v$VERSION"; then
  info "Next: git push origin v$VERSION"
fi
