# Langfuse Token-Diet Roles

> **Superseded (2026-09-21):** RTK was removed from the stack. Independent
> benchmarks found its compression metric did not reflect real cost — see
> [comparison.md](comparison.md). Every RTK-based measurement described below is
> obsolete; the Langfuse integration itself is unaffected.

Create one new Langfuse project named `langfuse-token-diet` inside the existing self-hosted Langfuse instance. Do not create a new Git repository or deployment.

```text
langfuse-ops          → hosts the existing Langfuse instance
langfuse-bridge-mcp   → sends MCP call/error/latency metadata
token-diet            → sends provider cost/tokens + RTK + test outcome
langfuse-token-diet   → isolated Langfuse project holding both streams
AOP                   → optional read-only summary later
```

- `langfuse-ops`: unchanged hosting and operations.
- `langfuse-bridge-mcp`: point its existing metadata stream at `langfuse-token-diet`; it is not the billing source.
- `token-diet`: add the small collector/exporter here; it provides the real provider/SDK and task-success data.
