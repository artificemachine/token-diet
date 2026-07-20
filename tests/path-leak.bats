#!/usr/bin/env bats
#
# Tests for .github/scripts/path-leak-scan.sh --full-tree
#
# Why these exist: full-tree mode was first implemented with `grep -qP` plus
# `2>/dev/null`. BSD grep (macOS) has no -P, so the error was swallowed and the
# scan silently matched nothing while appearing to pass. A guard that cannot
# fail is worse than no guard, so every case below asserts the exit code, not
# just the output text.

load test_helper

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export SCANNER="$PROJECT_ROOT/.github/scripts/path-leak-scan.sh"
  REPO="$(mktemp -d)"
  cd "$REPO"
  git init -q .
  git config user.email "test@example.com"
  git config user.name "test"
}

teardown() {
  cd /
  rm -rf "$REPO"
}

# Track a file so `git ls-files` sees it (the scanner iterates tracked files).
_track() {
  printf '%s\n' "$2" > "$1"
  git add "$1"
}

@test "full-tree: passes on a clean tree" {
  _track clean.md "install with: token-diet health"
  run bash "$SCANNER" --full-tree
  [ "$status" -eq 0 ]
  [[ "$output" == *"no hardcoded local paths"* ]]
}

@test "full-tree: fails on a macOS home path" {
  _track leak.json '"command": "/Users/somebody/.local/bin/tilth"'
  run bash "$SCANNER" --full-tree
  [ "$status" -eq 1 ]
  [[ "$output" == *"leak.json"* ]]
}

@test "full-tree: fails on a home path outside the known subdirs" {
  # The diff-mode patterns only fire on Documents|Desktop|Downloads|Library|
  # .local. A project directory slips past them — this is the exact shape of
  # the leak that sat in a committed file while diff mode stayed green.
  _track leak.md "see /Users/somebody/Projects/thing for details"
  run bash "$SCANNER" --full-tree
  [ "$status" -eq 1 ]
  [[ "$output" == *"leak.md"* ]]
}

@test "full-tree: fails on a Linux home path" {
  _track leak.sh 'cd /home/somebody/work/repo'
  run bash "$SCANNER" --full-tree
  [ "$status" -eq 1 ]
}

@test "full-tree: fails on a Windows home path" {
  _track leak.txt 'C:\Users\somebody\project'
  run bash "$SCANNER" --full-tree
  [ "$status" -eq 1 ]
}

@test "full-tree: allows documentation placeholder usernames" {
  _track docs.md "example: /Users/alice/Documents/x and /home/bob/y"
  run bash "$SCANNER" --full-tree
  [ "$status" -eq 0 ]
}

@test "full-tree: does not treat a dot-directory as a username" {
  # "/mock/home/.cache/..." yields ".cache" for the username group. Real
  # usernames never start with a dot; this was a live false positive.
  _track mock.bash 'echo "/mock/home/.cache/token-diet/extract/deadbeef.md"'
  run bash "$SCANNER" --full-tree
  [ "$status" -eq 0 ]
}

@test "full-tree: skips CHANGELOG.md and the scanner itself" {
  _track CHANGELOG.md "- fixed path /Users/somebody/thing in a past release"
  run bash "$SCANNER" --full-tree
  [ "$status" -eq 0 ]
}

@test "full-tree: ignores untracked files" {
  # Untracked files are not shipped, so they are not the guard's business.
  printf '%s\n' '/Users/somebody/secret/path' > untracked.md
  run bash "$SCANNER" --full-tree
  [ "$status" -eq 0 ]
}

@test "full-tree: reports every offending file, not just the first" {
  _track a.md '/Users/somebody/one'
  _track b.md '/Users/somebody/two'
  run bash "$SCANNER" --full-tree
  [ "$status" -eq 1 ]
  [[ "$output" == *"a.md"* ]]
  [[ "$output" == *"b.md"* ]]
}

@test "full-tree: does not require BASE_SHA (diff mode still does)" {
  _track clean.md "nothing to see"
  run env -u BASE_SHA bash "$SCANNER" --full-tree
  [ "$status" -eq 0 ]

  run env -u BASE_SHA bash "$SCANNER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BASE_SHA not set"* ]]
}
