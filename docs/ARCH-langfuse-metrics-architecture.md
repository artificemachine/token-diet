# Langfuse Metrics Architecture

> **Superseded (2026-09-21):** RTK was removed from the stack. Independent
> benchmarks found its compression metric did not reflect real cost — see
> [comparison.md](comparison.md). Every RTK-based measurement described below is
> obsolete; the Langfuse integration itself is unaffected.

Do not create a new repository.

Use `token-diet` as the small collector, and reuse the existing observability plane as the dashboard:

```text
RTK history + provider/SDK usage + task test result
                     ↓
             token-diet collector
                     ↓
        Langfuse + agent-observability-plane
```

- `token-diet` records one task run: model, provider tokens/cost, RTK estimated compression, parser fallback, duration, and test pass/fail.
- Langfuse stores and graphs those runs; `agent-observability-plane` already has the aggregate token/cost dashboard.
- Keep `langfuse-bridge-mcp` unchanged: it adds MCP call/error/latency correlation, but must not become the billing source.

Provider/SDK usage is real cost evidence; RTK telemetry is only a compression indicator. Compare matched runs with RTK enabled versus disabled, then calculate cost per successful task.
