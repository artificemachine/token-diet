# Token-Diet Langfuse Integration

> **Superseded (2026-09-21):** RTK was removed from the stack. Independent
> benchmarks found its compression metric did not reflect real cost — see
> [comparison.md](comparison.md). Every RTK-based measurement described below is
> obsolete; the Langfuse integration itself is unaffected.

## Review result

**CHANGES REQUESTED.** `agent-observability-plane` was pulled to `bee10f5`; static audit found 3 high and 3 medium issues. No tests ran.

- The pull changes liveness and authority producers to `/mnt/gitsilence/...`, while the UI still reads `/mnt/pve/...`; new data will not reach those UI readers.
- The Langfuse API has no versioned deployed credential injection, and it cannot measure RTK ROI yet.
- Do not create a repository. Create a separate Langfuse project named `token-diet-metrics`; leave the existing AOP Langfuse project for its current workloads.

## Proposed architecture

```text
                     per task attempt
┌─────────────────────────────────────────────────────────┐
│ harness / agent                                         │
│  ├─ provider or SDK → actual input/output/cache/cost    │
│  ├─ RTK            → raw/filtered estimate + fallback  │
│  └─ test or grader  → pass/fail + quality score         │
└──────────────────────────┬──────────────────────────────┘
                           │
                 token-diet collector
                           │
                           ▼
         Langfuse project: token-diet-metrics
          ├─ cost per successful task
          ├─ RTK-on versus RTK-off comparison
          └─ tool failures / latency correlation
                           │
                           ▼
             Langfuse native dashboard first
                           │
                  optional, read-only later
                           ▼
        agent-observability-plane multi-project summary
```

The AOP stays a shared dashboard; it is not the collector or billing source. The MCP bridge remains metadata-only.

## References

- [Audit report](/Users/airm2max/DevOpsSec/agent-observability-plane/docs/audits/2026-09-08-arch-audit.md)
- [Prior architecture](ARCH-langfuse-metrics-architecture.md)
