#!/usr/bin/env bash
# token-diet build — compile ICM from local fork, build Serena Docker image
# No crates.io, no PyPI, no GitHub access needed.
#
# ICM builds air-gap-clean by default (--no-default-features --features tui,backend-sqlite): the
# fastembed embedding model is NOT compiled in, so nothing is fetched from the network.
# Pass --icm-embeddings to compile the optional semantic-search feature (the model
# itself is then fetched once, explicitly, via `token-diet icm warmup`).
#
# Usage:
#   bash scripts/build.sh              # build all
#   bash scripts/build.sh --serena     # build Serena Docker image only
#   bash scripts/build.sh --icm        # build ICM only (keyword-only, air-gap clean)
#   bash scripts/build.sh --release    # release mode (optimized)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FORKS_DIR="$PROJECT_ROOT/forks"
DIST_DIR="$PROJECT_ROOT/dist"

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

# --- Argument parsing ---------------------------------------------------------
BUILD_SERENA=false
BUILD_ICM=false
RELEASE_MODE=false
# ICM compiles without embeddings by default so the air-gap build fetches nothing.
ICM_EMBEDDINGS=false

if [ $# -eq 0 ]; then
  BUILD_SERENA=true; BUILD_ICM=true
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --serena)  BUILD_SERENA=true ;;
    --icm)     BUILD_ICM=true ;;
    --icm-embeddings) BUILD_ICM=true; ICM_EMBEDDINGS=true ;;
    --release) RELEASE_MODE=true ;;
    --all)     BUILD_SERENA=true; BUILD_ICM=true ;;
    -h|--help)
      echo "Usage: $0 [--serena] [--icm] [--icm-embeddings] [--release] [--all]"
      echo "Build from local forks. No network required."
      echo "  --icm             build ICM (keyword-only memory, air-gap clean)"
      echo "  --icm-embeddings  build ICM with semantic search (model fetched later via warmup)"
      exit 0 ;;
    *) warn "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

CARGO_FLAGS=""
if $RELEASE_MODE; then
  CARGO_FLAGS="--release"
  info "Building in RELEASE mode"
fi

# ICM feature selection. Default is air-gap clean (no embeddings → no fastembed →
# no model download ever). --icm-embeddings restores the upstream default feature
# set; the model itself is still fetched later, explicitly, via warmup.
if $ICM_EMBEDDINGS; then
  ICM_FEATURE_FLAGS=""
  $BUILD_ICM && warn "ICM building WITH embeddings: the e5-base model (~270 MB) is fetched on first 'token-diet icm warmup', not during this build. This binary is not air-gap clean at first semantic use."
else
  ICM_FEATURE_FLAGS="--no-default-features --features tui,backend-sqlite"
fi

# --- Preflight ----------------------------------------------------------------
header "Preflight checks"

if $BUILD_ICM; then
  command -v cargo &>/dev/null || fail "Rust toolchain required. Run: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
  ok "cargo found: $(cargo --version)"
fi

if $BUILD_SERENA; then
  command -v docker &>/dev/null || fail "Docker required for Serena build."
  ok "docker found: $(docker --version)"
fi

# Check submodules are initialized
for fork in serena icm; do
  if [ -d "$FORKS_DIR/$fork" ] && [ -z "$(ls -A "$FORKS_DIR/$fork" 2>/dev/null)" ]; then
    fail "forks/$fork is empty. Run: git submodule update --init --recursive"
  fi
done

mkdir -p "$DIST_DIR"

# --- Build ICM ----------------------------------------------------------------
# ICM is a virtual cargo workspace: the binary crate is crates/icm-cli, but the
# build output lands in the WORKSPACE-ROOT target dir (forks/icm/target), NOT under
# the crate. Feature flags default to keyword-only so the build never touches the
# network and the installed binary cannot fetch a model behind the user's firewall.
if $BUILD_ICM; then
  header "Building ICM"

  if [ ! -d "$FORKS_DIR/icm" ]; then
    fail "forks/icm not found. Initialize submodules first."
  fi

  cargo build $CARGO_FLAGS $ICM_FEATURE_FLAGS \
    --manifest-path "$FORKS_DIR/icm/crates/icm-cli/Cargo.toml" 2>&1

  if $RELEASE_MODE; then
    BINARY="$FORKS_DIR/icm/target/release/icm"
  else
    BINARY="$FORKS_DIR/icm/target/debug/icm"
  fi

  if [ -f "$BINARY" ]; then
    cp "$BINARY" "$DIST_DIR/icm"
    chmod +x "$DIST_DIR/icm"
    ok "ICM built: $DIST_DIR/icm ($(du -h "$DIST_DIR/icm" | cut -f1))"
  else
    fail "ICM binary not found at $BINARY"
  fi

  # Run tests (icm-cli crate, matching the feature flags we shipped). Non-fatal,
  # from the crate's own dir.
  info "Running ICM tests..."
  if ( cd "$FORKS_DIR/icm/crates/icm-cli" && cargo test $ICM_FEATURE_FLAGS 2>&1 | tail -5 ); then
    ok "ICM tests passed"
  else
    warn "ICM tests failed (non-fatal for build) — review before release"
  fi

  # Audit dependencies
  if command -v cargo-audit &>/dev/null; then
    info "Running cargo audit..."
    cargo audit --file "$FORKS_DIR/icm/Cargo.lock" 2>&1 | tail -5 || warn "cargo audit found issues"
  fi
fi

# --- Build Serena Docker image ------------------------------------------------
if $BUILD_SERENA; then
  header "Building Serena (Docker)"

  if [ ! -d "$FORKS_DIR/serena" ]; then
    fail "forks/serena not found. Initialize submodules first."
  fi

  docker build \
    -f "$PROJECT_ROOT/docker/Dockerfile.serena" \
    -t token-diet/serena:latest \
    "$PROJECT_ROOT" 2>&1

  ok "Serena Docker image built: token-diet/serena:latest"

  # Save image as tarball for air-gapped distribution
  info "Exporting image tarball..."
  docker save token-diet/serena:latest | gzip > "$DIST_DIR/serena-image.tar.gz"
  ok "Serena image exported: $DIST_DIR/serena-image.tar.gz ($(du -h "$DIST_DIR/serena-image.tar.gz" | cut -f1))"
fi

# --- Summary ------------------------------------------------------------------
header "Build Summary"

echo ""
info "Artifacts in $DIST_DIR/:"
ls -lh "$DIST_DIR/" 2>/dev/null

echo ""
info "Install locally:"
echo "  cp $DIST_DIR/icm ~/.local/bin/"
echo "  docker load < $DIST_DIR/serena-image.tar.gz"
echo ""
info "Or run the installer:"
echo "  bash scripts/install.sh --local"
echo ""
