# Contributing to token-diet

## How to Contribute

Small fixes (typos, docs, an obvious one-line bug) are welcome as a direct pull
request. No issue needed.

For anything larger, please open an issue first so we can agree on the approach
before you spend time on it. Include relevant context: OS, tool versions, and
the error output.

## Guidelines

- Run the test suite before submitting: `bats tests/*.bats && pytest tests/ -q`.
- Keep each PR focused on one change.
- Work on a branch; `main` is protected.
- `CHANGELOG.md` is append-only. Add your entry at the end, don't edit existing ones.
- Don't bump the pinned submodules in `forks/` as part of an unrelated change.

## Development setup

```bash
git clone --recursive https://github.com/artificemachine/token-diet.git
cd token-diet
bash scripts/install.sh --dry-run   # see what an install would do
bats tests/*.bats && pytest tests/ -q
```

`--recursive` matters: the four tools in `forks/` are submodules, and the
air-gapped install path (`--local`) builds from them.

Requires `bash`, `python3`, `jq`, and `bc`. `bats-core` and `pytest` for tests.

## Project conventions

Detailed conventions live in [CLAUDE.md](CLAUDE.md), which doubles as the
instruction file for AI coding agents working in this repo. The parts that
matter for a human contributor are already listed above.
