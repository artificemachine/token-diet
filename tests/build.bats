#!/usr/bin/env bats
# build.bats — scripts/build.sh
#
# build.sh builds the surviving forks: serena (Docker image) and icm (cargo
# workspace — binary crate crates/icm-cli, output at the workspace-root target
# dir). --rtk/--tilth are gone; --icm-embeddings is a feature flag on the icm
# build, not a separate fork.
#
# These tests exercise the cargo-based icm path hermetically: build.sh derives
# FORKS_DIR/DIST_DIR from its own location, so a copy under a throwaway root
# with stub forks and a stubbed cargo exercises the real control flow with no
# Rust toolchain, no Docker, and no submodules (CI checks out without them).

load test_helper

# Build a throwaway project root: a copy of build.sh, stub fork manifests, and
# a cargo stub on PATH. The stub creates the expected workspace-root release
# binary on `build` and, for the crate named in FAIL_TEST_FORKS, exits
# non-zero on `test`.
_setup_build_sandbox() {
  ROOT="$TMP_HOME/buildproj"
  mkdir -p "$ROOT/scripts" "$ROOT/forks/icm/crates/icm-cli"
  cp "$SCRIPTS_DIR/build.sh" "$ROOT/scripts/build.sh"
  # build.sh checks the fork dir is non-empty and passes --manifest-path
  # pointing at the binary crate inside the icm workspace.
  echo '[package]' > "$ROOT/forks/icm/crates/icm-cli/Cargo.toml"

  cat > "$TMP_BIN/cargo" <<'CARGOSTUB'
#!/usr/bin/env bash
# Stub cargo. Understands `build` (creates the workspace-root
# target/release/<bin>) and `test` (fails for crates named in FAIL_TEST_FORKS).
sub="$1"; shift
manifest=""
while [ $# -gt 0 ]; do
  case "$1" in
    --manifest-path) manifest="$2"; shift 2 ;;
    *) shift ;;
  esac
done
case "$sub" in
  --version) echo "cargo 1.97.1 (stub)"; exit 0 ;;
esac
# build uses --manifest-path (…/crates/icm-cli/Cargo.toml); the test step cd's
# into the crate dir and omits it, so fall back to cwd to identify the crate.
if [ -n "$manifest" ]; then
  crate_dir="$(dirname "$manifest")"
else
  crate_dir="$(pwd)"
fi
crate_name="$(basename "$crate_dir")"
case "$sub" in
  build)
    # Virtual workspace: build output lands at the WORKSPACE ROOT target dir
    # (…/forks/icm/target), not under the crate — binary name is the workspace
    # name, not the crate name.
    ws_root="$(dirname "$(dirname "$crate_dir")")"
    mkdir -p "$ws_root/target/release"
    printf '#!/bin/sh\necho icm 9.9.9\n' > "$ws_root/target/release/icm"
    chmod +x "$ws_root/target/release/icm"
    exit 0 ;;
  test)
    # Record the cwd the test step runs in, so a test can assert build.sh cd's
    # into the crate rather than invoking from the repo root.
    [ -n "${CARGO_TEST_CWD_LOG:-}" ] && pwd > "$CARGO_TEST_CWD_LOG/$crate_name"
    case " $FAIL_TEST_FORKS " in
      *" $crate_name "*) echo "test result: FAILED"; exit 101 ;;
    esac
    echo "test result: ok"; exit 0 ;;
esac
exit 0
CARGOSTUB
  chmod +x "$TMP_BIN/cargo"
}

@test "build.sh --icm: a failing icm-cli test does not abort the build" {
  _setup_build_sandbox
  export FAIL_TEST_FORKS="icm-cli"

  run bash "$ROOT/scripts/build.sh" --icm --release

  # The binary must still land: the test step is non-fatal by contract.
  # Before the fix, a failing `cargo test` pipeline killed the whole script
  # under set -euo pipefail and no binary was copied.
  [ -f "$ROOT/dist/icm" ]
}

@test "build.sh --icm-embeddings implies an icm build" {
  _setup_build_sandbox

  run bash "$ROOT/scripts/build.sh" --icm-embeddings --release
  [ "$status" -eq 0 ]
  [ -f "$ROOT/dist/icm" ]
}

@test "build.sh reports a fork's test failure honestly rather than claiming success" {
  _setup_build_sandbox
  export FAIL_TEST_FORKS="icm-cli"

  run bash "$ROOT/scripts/build.sh" --icm --release

  # "ICM tests passed" printed unconditionally after the test pipeline was the
  # original defect. A failing test run must not be reported as passed.
  [[ "$output" != *"tests passed"* ]]
}

@test "build.sh runs the icm tests from the crate's own directory" {
  # Crate tests are cwd-dependent (relative fixture paths). build.sh must cd
  # into crates/icm-cli for the test step so the gate reflects real health.
  _setup_build_sandbox
  export FAIL_TEST_FORKS=""
  export CARGO_TEST_CWD_LOG="$TMP_HOME/cwdlog"
  mkdir -p "$CARGO_TEST_CWD_LOG"

  run bash "$ROOT/scripts/build.sh" --icm --release
  [ "$status" -eq 0 ]

  # Compare by basename/parent to avoid /var vs /private/var symlink noise.
  local crate_cwd
  crate_cwd="$(cat "$CARGO_TEST_CWD_LOG/icm-cli")"
  [ "$(basename "$crate_cwd")" = "icm-cli" ]
  [ "$(basename "$(dirname "$crate_cwd")")" = "crates" ]
  [ "$(basename "$(dirname "$(dirname "$crate_cwd")")")" = "icm" ]
}

@test "build.sh no longer accepts --rtk or --tilth" {
  _setup_build_sandbox

  run bash "$ROOT/scripts/build.sh" --rtk --release
  [ "$status" -ne 0 ]

  run bash "$ROOT/scripts/build.sh" --tilth --release
  [ "$status" -ne 0 ]
}
