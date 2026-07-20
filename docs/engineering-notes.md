# Engineering notes

How this project is tested and debugged, told through the bugs that shaped it.
Most of these were found by a check that didn't exist yet, which is the useful
part.

## The environment lies to you

The single most productive change to this codebase was adding a CI workflow
that ran the existing test suite on a clean machine. The suite had passed
locally for months. Its first CI run failed immediately, and every failure was
real.

The tests had quietly grown dependent on the development machine. Several
mocked `uv` but not `uvx`, mocked `claude` but not `codex`, and passed only
because those binaries happened to be installed and on `PATH`. The code under
test probes for host CLIs with `command -v`, so an unmocked binary meant the
test was exercising a different branch than it claimed. Five test assertions
invoked the real `rtk` and `tilth` CLIs to check file contents, which meant
they failed with "command not found" anywhere the tools weren't installed.

None of this was visible from the machine that wrote the tests. The lesson
that stuck: **a test suite that has only ever run in one environment is
measuring that environment as much as the code.**

The working method that came out of it: reproduce every CI-only failure in a
throwaway container before fixing it.

```bash
docker run --rm -v "$PWD:/repo" -w /repo ubuntu:24.04 bash -c '
  apt-get update -qq && apt-get install -y -qq bats jq git bc python3 python3-pip
  bats tests/*.bats
'
```

This is faster than pushing to CI and reading logs, and it removes the
temptation to guess. It also caught two mistakes in the *reproduction scripts
themselves* before either was mistaken for a product bug.

## A guard that could not fail

While hardening the path-leak scanner, the first implementation of its
full-tree mode looked like this:

```bash
grep -qP "$pattern" "$file" 2>/dev/null
```

It passed. Every file was clean. It was also completely inert: BSD `grep` on
macOS has no `-P` flag, so the command failed with a usage error on every
invocation, and `2>/dev/null` discarded it. A non-zero exit from a failed
program is indistinguishable from "no match found" when you only check the
exit code.

It would have worked in CI, on Ubuntu, which is worse than failing outright —
it would have passed locally, passed in CI, and protected nothing on the
platform most of the development happens on.

It was caught only by testing the negative case: planting a known-bad string
and asserting the guard *fails*. That check now exists as a test.

**Every guard in this repo has a test that proves it fails on bad input.** A
check that has only ever been observed passing has not been observed working.
See `tests/path-leak.bats`.

## Fixing the symptom five times

`.vscode/mcp.json` was a tracked file containing a portable command name,
`"command": "tilth"`. It kept reverting to an absolute path pointing at one
developer's home directory. Git history shows five separate commits fixing it:
`4751685`, `43eebaa`, `2495d6a`, `1e9a92c`, `f408b4f`. Each one edited the path
back and moved on.

The cause was two layers away. `install.sh` calls `tilth install <host>` to
register the MCP server, and tilth's own installer writes the absolute path of
its binary into the project's config file. Every install silently rewrote a
tracked file in the repository that invoked it.

The fix was to stop tracking the file. It is per-machine IDE configuration
being rewritten by an external tool; the portable template ships to
`~/.config/token-diet/` instead.

**Five commits treating a symptom is a signal that nobody has asked what writes
the file.** The tell was the repetition, not the individual bugs.

## Dead code that pretended to work

`token-diet doctor` reported that tilth was not registered with any MCP host.
It was registered with five. The check ran `tilth doctor --json` and read the
result.

`tilth doctor` had never existed as a command. `doctor.rs` was present in the
tilth fork, fully implemented with its own unit tests, but was never declared
in `lib.rs`, so it was not compiled into the binary or reachable from the
dispatcher. Passing `doctor` to tilth meant passing it as a *search query*,
which returned perfectly valid JSON describing search results, which
`cmd_doctor` then parsed as a health report and interpreted as a failure.

Attempting to wire the module in revealed it had also bit-rotted: it imported
four symbols from `install.rs` that a later refactor had made private or
removed. It could not compile against the code around it.

Two fixes, at two layers. Downstream, `token-diet` now validates that the JSON
it receives actually looks like a health report before trusting it, and falls
back to direct config inspection when it doesn't. Upstream, the dead file was
removed from the fork.

**A subcommand that doesn't exist doesn't necessarily error.** If the parent
command accepts positional arguments, an unknown subcommand is just an
argument, and a well-formed wrong answer is harder to spot than a crash.

## Truncate, then fail, then say nothing

The installer edits config files it does not own: `~/.claude/settings.json`,
Claude Desktop's config, `opencode.json`, and others. Corrupting one breaks the
user's editor, not just this tool.

The registration code looked like this:

```python
try:
    with open(cfg) as f: data = json.load(f)
    data.setdefault("mcpServers", {})["token-diet"] = {...}
    with open(cfg, "w") as f: json.dump(data, f, indent=2)
except Exception: pass
```

`open(cfg, "w")` truncates the file immediately, before `json.dump` writes
anything. A failure between those two points leaves a zero-byte config. The
`except Exception: pass` then guarantees nobody finds out: the installer
reports success, the settings are gone, and whatever breaks next looks
unrelated.

It had a second failure mode. Malformed input hit the same handler, so a config
that was already broken was silently skipped, while seven sibling blocks
elsewhere in the same file aborted loudly on exactly that condition. Same
situation, two different behaviors, in one script.

Config mutation now goes through `scripts/lib/tdconfig.py`, which serializes
fully before touching the target, writes to a temp file in the same directory,
fsyncs, and `os.replace`s it into place. `os.replace` is atomic, so a reader
sees the whole old file or the whole new one. Backups are taken before a
successful mutation, not only after a corrupt file is detected, because a
backup you take once the file is broken is not a backup.

**`except Exception: pass` around a write is a decision to lose data quietly.**

## Debouncing on a value that always changes

`ctxwarn` warns once when a session's transcript crosses a token threshold. It
kept warning on every single tool call.

The debounce state file was keyed on `sha256(abspath + mtime_ns)`. Transcripts
are appended to on every tool use, so `mtime_ns` changed constantly, so every
invocation computed a fresh cache key, found no prior state, and treated itself
as the first run.

The evidence was sitting on disk: 154 state files, all containing `"1"`, one
per firing. The fix was to key on the path alone for this cache, while leaving
mtime keying in place for the extraction cache where it is correct.

**Cache keys that include a value which changes on every write are not caches.**
The two callers needed different keying, which is now an explicit parameter
rather than a shared assumption.

## Testing the thing you ship, not the thing you have

A release shipped with `token-diet extract` broken for every user. The tests
passed. They invoked `scripts/token-diet` from the source checkout, where
`scripts/lib/*.py` sits alongside it. The installer copied the executable to
`~/.local/bin` but not the library directory, so the installed copy could not
find its own modules.

The regression test added afterward invokes the *installed* binary
specifically. That distinction has since caught the same class of problem
twice, including when a new module was added and initially left out of the
install manifest.

**Tests that only exercise the repository layout do not test what users
install.**

## What this adds up to

The recurring shape is that each of these was invisible from the position it
was written in. Local tests hid environment coupling. A guard hid its own
inertness behind a discarded error. A tracked file hid the tool rewriting it.
A silent exception handler hid data loss.

The practices that come out of that, in rough order of value:

1. Run the suite somewhere that isn't your machine, early.
2. Prove every guard fails on bad input, not just that it passes on good input.
3. When the same fix appears more than twice, stop and find what writes the file.
4. Never wrap a write in a bare `except: pass`.
5. Test the installed artifact, not the source tree.
6. Reproduce before fixing, in an environment you can throw away.
