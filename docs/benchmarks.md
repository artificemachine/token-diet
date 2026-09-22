# Benchmarks — where the numbers come from

Short version: **this stack no longer publishes a tracked savings figure.** The
metric the stack used to lead with was removed along with the tools that produced
it, because independent benchmarks showed it did not measure what it claimed.

## Why there is no headline number

The old stack led with a compression figure (e.g. "83.9% saved") computed by
RTK's `rtk gain` from command history. Two independent evaluations found that
figure does not translate into real cost savings:

- **Quesma** (Sept 2026, ~$1,500 of real spend, 1,740 attempts on
  Terminal-Bench 2.1, Claude Code/Fable 5 and OpenCode/DeepSeek V4): no
  reliable saving. Fable's total was −5% but per-task cost was +1%; DeepSeek's
  per-task cost rose **17%** on average. Their conclusion: *"We do not recommend
  RTK as a generic cost-saving tool."* They also documented that `rtk gain`
  counts removed output bytes ÷ 4 — not billed tokens — and once credited
  120.5M tokens "saved" on a `head -1` command that would never have returned
  the whole file (69% of that comparison's savings counter).
- **JetBrains SkillsBench**: found no savings and extra turns.

The mechanism explains the result: terminal output is only ~7–11% of a frontier
model's input, models already self-limit with `head`/`tail`, and file-read tools
bypass the filter entirely. Extra turns can cost more than the compression saves.

So this page no longer repeats the retired figures. [docs/comparison.md](comparison.md)
records the removal decision in full.

## What is claimed today

| Tool | Claim | Basis |
|---|---|---|
| Serena | Fewer prompt turns on symbol-level work | Not separately measured |
| ICM | Recall replaces re-reading across sessions | Not separately measured |
| Context7 | Current library docs instead of guessed APIs | Not separately measured |

All three are in the stack on a structural argument, not a measurement:

- **Serena** provides LSP-grade navigation — definitions, references, renames —
  so an agent jumps to a symbol instead of reading files to find it.
- **ICM** persists decisions and resolved errors across sessions, so an agent
  recalls a fact instead of re-deriving it.
- **Context7** serves current library documentation, so the agent stops
  inventing function names that were renamed two versions ago.

These are plausible and match day-to-day experience, but none has a benchmark in
this repository. They are listed as "structural" rather than given a percentage,
and no aggregate stack-wide number is published — summing measured and unmeasured
components would produce a number with no method behind it.

## What would make a number publishable

A claim belongs here only with: the model and harness, the task set, the number
of runs, and a cost basis in money or billed tokens rather than bytes. A
compression ratio measured on stdout is not that. The Quesma methodology
(cost per passed task, both platforms, N runs per task, task-level means) is the
bar this project would hold itself to before publishing anything.

## What this page is not

There is no single headline "token-diet saves X%" figure, and this page will not
invent one.
