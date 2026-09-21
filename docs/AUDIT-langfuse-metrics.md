# Langfuse Metrics Audit

Langfuse can support real metrics, but not with the bridge alone.

- `langfuse-bridge-mcp` records MCP calls, latency, errors, and byte size only; it cannot measure token or cost savings. [Trace schema](/Users/airm2max/DevOpsSec/langfuse-bridge-mcp/src/langfuse_bridge_mcp/trace_builder.py)
- `superharness-langfuse-current` can store SDK-reported Claude Code input/output/cost per task; Codex usage is only self-reported. Its Langfuse exporter currently sends duration and cost, not token fields. [Exporter](/Users/airm2max/DevOpsSec/superharness-langfuse-current/src/superharness/engine/langfuse_telemetry.py)
- `agent-observability-plane` is the best dashboard foundation: it already queries Langfuse aggregates for input/output/total tokens and cost, but no current producer supplies those metrics automatically. [Metrics adapter](/Users/airm2max/DevOpsSec/agent-observability-plane/ui/lib/langfuse/computeActivity.ts)

Use provider/SDK usage as the source of truth, add RTK raw/filtered output plus parser-fallback metrics, and record each task’s test result. Then Langfuse can show real cost per successful task; `langfuse-ops` only hosts it.
