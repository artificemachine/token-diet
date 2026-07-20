# Security Policy

## Reporting a vulnerability

Report security issues privately via
[GitHub Security Advisories](https://github.com/artificemachine/token-diet/security/advisories/new).
Please don't open a public issue for a vulnerability.

Include what you have: affected version, reproduction steps, and impact. A
partial report is more useful than no report.

Expect an initial response within a week. If a fix is warranted, it ships in a
patch release and the advisory is published once users have had a chance to
upgrade.

## What is in scope

token-diet is an installer and CLI. It writes to configuration files owned by
other tools, installs binaries into `~/.local/bin`, and registers hooks that
run inside AI coding sessions. The interesting surface is therefore:

- **Config mutation.** `install.sh` edits `~/.claude/settings.json`,
  `~/.codex/config.toml`, `~/.gemini/settings.json`, `opencode.json`, and the
  Claude Desktop configs. Anything that lets a third party corrupt or inject
  into those files is in scope.
- **Hook execution.** With `--with-context-hooks`, `docextract` and `ctxwarn`
  run on every matching tool call. They receive file paths and transcript
  contents. Injection or path-traversal there is in scope.
- **Install-time code execution.** The default path fetches and runs installers
  for `rustup` and `uv`, and `--local` builds four pinned forks from source.
- **Document extraction.** `token-diet extract` parses PDF, CSV, and HTML,
  including files an agent was asked to read. Parser-level issues reachable
  through that path are in scope.

## Out of scope

- Vulnerabilities in the upstream tools themselves (RTK, tilth, Serena, ICM).
  Report those to their projects; if the issue is in how token-diet *invokes*
  them, that is in scope here.
- Anything requiring an attacker who already has local shell access as the
  user. At that point the config files are theirs regardless.
- The pinned forks in `forks/` being behind upstream. That is a maintenance
  concern, tracked separately by the upstream-drift workflow.

## Supported versions

The latest released version is supported. Given the release cadence, upgrading
is normally the fix.

## Hardening notes

- The Serena container runs non-root, read-only, with `network_mode: none`,
  `no-new-privileges`, and a read-only workspace mount.
- CI pins every GitHub Action to a commit SHA.
- A path-leak guard scans both PR diffs and the full tree for hardcoded home
  paths, to keep machine-local paths and usernames out of the published repo.
- Config mutations go through an atomic write helper that serializes fully
  before touching the target file and takes a backup first. See
  `scripts/lib/tdconfig.py`.
