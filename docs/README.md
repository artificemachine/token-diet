# Documentation

## Start here

| Document | What it covers |
|---|---|
| [benchmarks.md](benchmarks.md) | Where every performance number comes from, and which claims are unmeasured |
| [engineering-notes.md](engineering-notes.md) | How this project is tested and debugged, with the bugs that shaped it |
| [comparison.md](comparison.md) | How the four tools differ and when each one applies |
| [enterprise.md](enterprise.md) | Air-gapped and offline installation |

## Guides

| Document | What it covers |
|---|---|
| [GUIDE-context-warning-and-pdf-intercept-hooks.md](GUIDE-context-warning-and-pdf-intercept-hooks.md) | The opt-in `--with-context-hooks` features: `docextract` and `ctxwarn` |
| [GUIDE-required-status-checks.md](GUIDE-required-status-checks.md) | Configuring branch protection so CI actually blocks merges |

## Project direction

| Document | What it covers |
|---|---|
| [roadmap.md](roadmap.md) | Planned work |
| [PLAN-production-ready.md](PLAN-production-ready.md) | Active hardening plan, phased, derived from the audit below |
| [audits/](audits/) | Dated audit reports and their scorecards |

## archive/

Superseded material, kept because it records why decisions were made, not
because it describes current behavior. Session handoffs, completed plans, and
one-off bug reports. **Nothing in `archive/` should be treated as accurate
about the current codebase.**

## A note on the agent instruction files

`CLAUDE.md`, `AGENTS.md`, and `.github/GEMINI.md` are instruction files for AI
coding agents working in this repository. They encode the same conventions
described in [CONTRIBUTING.md](../CONTRIBUTING.md): version bumps, the
append-only changelog, branch policy, and the rule against auto-updating the
pinned submodules. A human contributor only needs CONTRIBUTING.md.
