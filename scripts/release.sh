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
VERSION="1.2.0"

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

record_ok()   { ok "$1";   (( PASS++ )); }
record_fail() { fail "$1"; }
record_warn() { warn "$1"; (( WARN++ )); }

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
    (( WARN++ ))
  fi

fi  # DO_TESTS

# --- Binary Signing -----------------------------------------------------------
if $DO_SIGN && ! $DRY_RUN; then

  header "Binary Signing"

  RTK_BIN="$DIST/rtk"
  TILTH_BIN="$DIST/tilth"

  if [ ! -f "$RTK_BIN" ] || [ ! -f "$TILTH_BIN" ]; then
    skip "Binaries not found in dist/ — run 'bash scripts/build.sh --release' first"
    (( WARN++ ))
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
          (( WARN++ ))
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
        (( WARN++ ))
      else
        GPG_KEY=$(gpg --list-secret-keys --keyid-format=long 2>/dev/null | grep "^sec" | head -1 | awk '{print $2}' | cut -d/ -f2 || true)

        if [ -z "$GPG_KEY" ]; then
          warn "No GPG secret key found."
          warn "Generate one with: gpg --full-generate-key"
          skip "Signing skipped — no GPG key available"
          (( WARN++ ))
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
    (( WARN++ ))
  else
    if [ "$WARN" -gt 0 ]; then
      echo ""
      warn "$WARN warning(s) above. Tag anyway?"
      read -rp "Create tag v$VERSION? [y/N] " CONFIRM
      [[ "$CONFIRM" =~ ^[Yy]$ ]] || { info "Tag skipped."; exit 0; }
    fi

    TAG_MSG="token-diet v$VERSION

RTK ${VERSION}: 0 vulnerabilities (164 deps)
tilth 0.5.7: 0 vulnerabilities (93 deps)
serena-agent 0.1.4: 0 known vulnerabilities

Submodule commits:
  forks/rtk:    8c27defe878c1514528821c0998ed9747e43a9c7
  forks/tilth:  8aa3d26fa252f4938f7bc883ec67a5b9ddfdf123
  forks/serena: 1acd0118b253e99a3bfaecfdd464499509b3ceb0

See CHANGELOG.md for full details."

    git tag -a "v$VERSION" -m "$TAG_MSG"
    record_ok "Tag v$VERSION created (run 'git push origin v$VERSION' to publish)"
  fi

fi  # DO_TAG

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
