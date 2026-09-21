# Retired tools: why RTK and tilth are not in the stack

token-diet used to install four tools. Two of them — **RTK** (CLI output
compression) and **tilth** (AST code reading) — were removed. This page records
why, so the decision is not silently reversed and the retired figures are not
quoted again.

## RTK — removed on independent evidence

RTK's pitch was a 60–90% reduction in the output an agent reads. The reduction is
real; the saving it was said to represent is not.

| Evidence | Finding |
|---|---|
| [Quesma benchmark](https://quesma.com/blog/does-rtk-make-ai-coding-cheaper/) (Sept 2026, HN front page, 1,740 attempts, ~$1,500 spent, Terminal-Bench 2.1) | No reliable cost saving. Claude Code/Fable 5: −5% total but +1% per task; OpenCode/DeepSeek V4: **+17% per task**. Verdict: *"We do not recommend RTK as a generic cost-saving tool."* |
| [JetBrains SkillsBench](https://blog.jetbrains.com/ai/2026/07/rtk-claude-code-token-savings/) | No savings; added turns at low effort. |

Two structural reasons:

1. **The metric measured the wrong thing.** `rtk gain` reports removed output
   bytes ÷ 4, not billed tokens. In one Quesma case it credited 120.5M tokens
   "saved" for two `head -1` calls that would never have returned the whole file
   — 69% of that comparison's counter. A tool can look 89% better and cost more.
2. **The compressible surface is small.** Terminal output was ~7–11% of input
   for the frontier model tested; models already limit their own output with
   `head`/`tail`; file reads and searches bypass the shell entirely. Compression
   that costs one extra turn loses money.

There was also a real failure mode: a rewriting bug sent one agent into 339
consecutive errors and ~9× the task cost (fixed upstream in 0.46.0).

## tilth — removed for lack of independent evidence

tilth is a genuine project (tree-sitter outlines, symbol search), but every
published number came from its author's own benchmarks on his own task set. No
independent evaluation existed. That is not enough to ship a tool in a stack
whose whole claim is measured savings.

## What stayed, and why

| Tool | Layer | Basis |
|---|---|---|
| [Serena](https://github.com/oraios/serena) | LSP symbol navigation | Real independent adoption: 29.7k stars, agent workflows in production, cross-file renames/references that text search cannot do |
| ICM | Cross-session memory | Local, no runtime dependency beyond itself; recall replaces re-reading |
| [Context7](https://github.com/upstash/context7) | Library documentation | The most-adopted MCP in its category; users describe it as standard equipment for preventing stale-API hallucinations |

## Layer model

```
+--------------------------------------------------+
|                   AI Agent                        |
+--------------------------------------------------+
         |                     |                |
   Symbol work            Memory            Library docs
         |                     |                |
    +---------+          +---------+      +-----------+
    | Serena  |          |   ICM   |      | Context7  |
    |  (LSP)  |          | (recall)|      | (docs)    |
    +---------+          +---------+      +-----------+
```

Each tool owns a lane that the others do not: symbol resolution, persistent
recall, documentation lookup. None of them is an output filter, and none of them
is claimed to reduce byte counts.

## If you are running an older install

`uninstall.sh` / `Uninstall.ps1` keep a marked **legacy cleanup** region that
removes RTK, rtk-mcp, and tilth artifacts (binaries, symlinks, MCP registrations,
hooks, docs) from machines installed before the removal. Your other config is
untouched — removal is key-scoped.
