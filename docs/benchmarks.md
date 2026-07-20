# Benchmarks — where the numbers come from

Short version: **one of the four tools has a real benchmark, one is measured
live on your own machine, and two are not quantified.** This page says which is
which, because a number without a method behind it is just a claim.

## Summary

| Tool | Claim | Basis |
|---|---|---|
| tilth | -38% to -44% cost per correct answer | Benchmarked, 160 runs across 3 models |
| RTK | 60-90% output reduction | Measured live from your own command history |
| Serena | Fewer prompt turns | Not separately measured |
| ICM | Recall replaces re-reading | Not separately measured |

## tilth — benchmarked

The full benchmark lives in [`forks/tilth/benchmark/`](../forks/tilth/benchmark/README.md).
26 code-navigation tasks, 160 runs, three models:

| Model | Runs | Baseline $/correct | tilth $/correct | Change | Baseline acc | tilth acc |
|---|---|---|---|---|---|---|
| Sonnet 4.6 | 86 | $0.26 | $0.15 | **-44%** | 84% | 94% |
| Opus 4.6 | 25 | $0.22 | $0.14 | **-39%** | 91% | 92% |
| Haiku 4.5 | 49 | $0.12 | $0.08 | **-38%** | 54% | 73% |
| **Average** | **160** | **$0.20** | **$0.12** | **-40%** | **76%** | **86%** |

### Why "cost per correct answer" and not raw tokens

Raw cost comparison treats a wrong answer as a cheap success. It isn't: you paid
for a response you can't use and you still need the answer.

If accuracy is `p`, you need `1/p` attempts on average before one succeeds, so
the expected spend is `cost_per_attempt × (1 / accuracy)`. Cost per correct
answer (`total_spend / correct_answers`) computes exactly that. It is not an
arbitrary penalty term; it is the expected cost under retry.

This metric is also why the Haiku row matters. Haiku's raw cost is lowest of the
three, but its baseline accuracy is 54%, so nearly half of what you spend buys
an answer you have to throw away.

### Caveats

- Measured against tilth v0.5.0. The pinned fork is ahead of that.
- 26 tasks on a fixed set of repositories. Navigation-shaped work, which is what
  tilth targets; it is not a general coding benchmark.
- Run counts are uneven across models (86 / 25 / 49).

## RTK — measured live, not benchmarked

RTK's savings are not an estimate from a study. They are computed from your own
`~/.rtk/history.json`: for each proxied command, the raw output size against the
filtered size. `token-diet gain` reads that history and reports your actual
numbers.

Two honest qualifications:

1. It measures **output compression**, meaning bytes RTK removed before the text
   reached the model. That is a real saving, but it is not the same as
   end-to-end session cost, which depends on how the agent behaves afterward.
2. Token counts use a `chars / 4` heuristic, not a tokenizer. Good enough for a
   ratio, not exact.

The 60-90% range reflects that compressible commands (test runs, builds, verbose
logs) sit near the top and already-terse commands near the bottom. Run
`token-diet gain` to see your own figure rather than trusting the range.

## Serena and ICM — not quantified

Both are in the stack on a structural argument, not a measurement:

- **Serena** provides LSP-grade navigation, so an agent can jump to a definition
  instead of reading whole files to find it. Fewer turns, less context consumed.
- **ICM** persists decisions and resolved errors across sessions, so an agent
  recalls a fact instead of re-deriving it.

Both are plausible and both match day-to-day experience, but neither has a
benchmark in this repository. They are listed as "structural" rather than given
a percentage, and no aggregate stack-wide number is published, because summing
a benchmarked figure with two unmeasured ones would produce a number with no
method behind it.

## Reproducing

```bash
# tilth: full harness and per-task breakdown
cat forks/tilth/benchmark/README.md

# RTK: your own measured savings
token-diet gain
token-diet breakdown        # top commands by tokens saved
token-diet explain <cmd>    # per-command cost breakdown
```

## What this page is not

There is no single headline "token-diet saves X%" figure, and this page will not
invent one. The tools compose, their savings are not independent, and combining
one benchmark with two unmeasured components into a single percentage would be
a guess wearing a decimal point.
