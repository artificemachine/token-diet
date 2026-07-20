# Token Diet MCP Conversion: Analysis & Recommendation

## 1. Current State Analysis
`token-diet` orchestrates three powerful tools (RTK, tilth, Serena) to reduce AI token consumption. It provides a CLI (`token-diet`) and a local HTTP dashboard (`token-diet-dashboard`) for users to monitor:
- System health and MCP registrations.
- Token savings and efficiency.
- Budget constraints (`.token-budget`).
- Inefficient agent behaviors (loops, redundant reads).

**The Gap:** All this rich context is presented to the *human user*, but the *AI agent* remains blind to it. If an agent starts looping a command, the human sees it on the dashboard, but the agent cannot self-correct. If the project token budget is exhausted, the agent doesn't know until the user tells it.

## 2. The Opportunity (MCP Integration)
By exposing `token-diet` itself as an MCP (Model Context Protocol) server, we bridge this gap. Agents will be able to query the `token-diet` layer to understand their own operational context. 

### Why this matters:
1. **Self-Healing:** The agent can query `check_stack_health` if it encounters issues, identifying if RTK or Serena are down and potentially running `token-diet repair`.
2. **Budget Awareness:** Before starting a large refactor, the agent can call `get_budget_status` to ensure it has enough tokens remaining for the project, adjusting its strategy (e.g., using `tilth` more aggressively) if the budget is tight.
3. **Behavioral Optimization:** The agent can proactively call `find_loops` or `find_context_leaks` to audit its own behavior during long sessions and self-correct.
4. **Tool Routing:** The agent can ask `recommend_tool` to decide whether to use standard tools, `tilth`, or `Serena` for a specific sub-task.

## 3. Recommendation
**Convert `token-diet` into a lightweight, zero-dependency Python MCP server.**

We will create a new entry point, `scripts/token-diet-mcp`, alongside the dashboard. To maintain the project's zero-dependency philosophy (which avoids `pip install` for core monitoring), we will implement a standard stdlib-based JSON-RPC server over `stdio` that adheres to the MCP specification. 

### Proposed MCP Tools:
- `token_diet_health`: Returns the health of the token-diet stack (tools active, MCP hosts registered).
- `token_diet_savings`: Returns token efficiency metrics (saved tokens, % efficiency).
- `token_diet_budget`: Returns the current project's budget status (used vs. hard/warn limits).
- `token_diet_loops`: Analyzes recent command history for inefficient loops.
- `token_diet_route`: Suggests the most token-efficient tool for a given task description.

### Implementation Strategy
The `token-diet-dashboard` script already contains robust, stdlib-only logic for gathering this data by calling the `token-diet` bash script or parsing its output. We will extract or replicate this data-gathering logic within the new `token-diet-mcp` server.