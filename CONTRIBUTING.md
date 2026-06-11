# Contributing to token-diet

## How to Contribute

1. **Open an issue** — describe the bug, feature request, or improvement you have in mind. Include relevant context (OS, tool versions, error output).

2. **Open a pull request** — once the issue exists, submit a PR that references it (e.g. `Fixes #42`). Keep the PR focused on the single issue it addresses.

Pull requests without a corresponding issue will not be reviewed.

## Guidelines

- Follow the conventions in [CLAUDE.md](CLAUDE.md) (version bumps, CHANGELOG append-only, no automatic submodule updates).
- Run the full test suite before submitting: `bats tests/*.bats && pytest tests/ -q`.
- Never push directly to `main` — always use a feature or fix branch.
