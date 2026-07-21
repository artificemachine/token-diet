#!/usr/bin/env bats
# build.bats — scripts/build.sh
#
# Regression: `build.sh --rtk --tilth --release` built ONLY rtk. Line 135 ran
# `cargo test ... | tail -5` for RTK, and under `set -euo pipefail` a failing
# `cargo test` (RTK's tests fail on dead-code lints under -D warnings) made the
# pipeline non-zero and set -e killed the whole script before the tilth block.
# So a fork whose tests fail silently aborts every fork after it.
#
# These tests are hermetic: build.sh derives FORKS_DIR/DIST_DIR from its own
# location, so a copy under a throwaway root with stub forks and a stubbed cargo
# exercises the real control flow with no Rust toolchain and no submodules
# (CI checks out without them).

load test_helper

# Build a throwaway project root: a copy of build.sh, stub fork manifests, and
# a cargo stub on PATH. The stub creates the expected release binary on `build`
# and, for any fork named in FAIL_TEST_FORKS, exits non-zero on `test`.
_setup_build_sandbox() {
  ROOT="$TMP_HOME/buildproj"
  mkdir -p "$ROOT/scripts" "$ROOT/forks/rtk" "$ROOT/forks/tilth"
  cp "$SCRIPTS_DIR/build.sh" "$ROOT/scripts/build.sh"
  # build.sh only checks the fork dir exists and passes --manifest-path; the
  # file needs to exist for the stub to resolve a binary name from its dir.
  echo '[package]' > "$ROOT/forks/rtk/Cargo.toml"
  echo '[package]' > "$ROOT/forks/tilth/Cargo.toml"

  cat > "$TMP_BIN/cargo" <<'CARGOSTUB'
#!/usr/bin/env bash
# Stub cargo. Understands `build` (creates target/release/<fork>) and `test`
# (fails for forks named in FAIL_TEST_FORKS). --version for preflight.
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
fork_dir="$(dirname "$manifest")"
fork_name="$(basename "$fork_dir")"
case "$sub" in
  build)
    mkdir -p "$fork_dir/target/release"
    printf '#!/bin/sh\necho %s 9.9.9\n' "$fork_name" > "$fork_dir/target/release/$fork_name"
    chmod +x "$fork_dir/target/release/$fork_name"
    exit 0 ;;
  test)
    case " $FAIL_TEST_FORKS " in
      *" $fork_name "*) echo "test result: FAILED"; exit 101 ;;
    esac
    echo "test result: ok"; exit 0 ;;
esac
exit 0
CARGOSTUB
  chmod +x "$TMP_BIN/cargo"
}

@test "build.sh --rtk --tilth: a failing RTK test does not abort the tilth build" {
  _setup_build_sandbox
  export FAIL_TEST_FORKS="rtk"

  run bash "$ROOT/scripts/build.sh" --rtk --tilth --release

  # Both binaries must land. Before the fix, only rtk did.
  [ -f "$ROOT/dist/rtk" ]
  [ -f "$ROOT/dist/tilth" ]
}

@test "build.sh reports a fork's test failure honestly rather than claiming success" {
  _setup_build_sandbox
  export FAIL_TEST_FORKS="rtk"

  run bash "$ROOT/scripts/build.sh" --rtk --release

  # The old code printed "RTK tests passed" unconditionally after the test line.
  # A failing test run must not be reported as passed.
  [[ "$output" != *"RTK tests passed"* ]]
}
