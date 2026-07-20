# Token Diet MCP Conversion: TDD Implementation Plan

We will implement the `token-diet` MCP server using a Test-Driven Development (TDD) approach. The server will be a zero-dependency Python script communicating over `stdio` via JSON-RPC.

## Iteration 1: MCP Server Foundation (JSON-RPC over stdio)
**Goal:** Create the basic MCP server skeleton that can respond to `initialize` and `tools/list` requests.
- **Test:** Write `tests/test_mcp_server.py` that sends an `initialize` JSON-RPC request to the script via subprocess and expects a valid `InitializeResult`. Send a `tools/list` request and expect an empty or initial tool list.
- **Implement:** Create `scripts/token-diet-mcp`. Implement a simple read-loop on `sys.stdin` that parses JSON-RPC, routes `initialize` and `tools/list` methods, and writes JSON-RPC responses to `sys.stdout`.

## Iteration 2: Core Monitoring Tools (`health` and `savings`)
**Goal:** Implement the first two tools that provide basic observability.
- **Test:** Update tests to expect `token_diet_health` and `token_diet_savings` in `tools/list`. Write tests that send a `tools/call` request for these tools and mock the underlying subprocess calls (e.g., `token-diet health`, `token-diet gain`) to verify the JSON response payload.
- **Implement:** Add tool handlers in `token-diet-mcp` that execute the corresponding CLI commands (`token-diet health`, `token-diet gain --format json`) and format the output into markdown for the agent.

## Iteration 3: Project Context Tools (`budget` and `loops`)
**Goal:** Expose project-specific budget and behavioral optimization metrics.
- **Test:** Write tests for `token_diet_budget` and `token_diet_loops`. Provide mock `.token-budget` files and mock RTK history. Ensure the server correctly reads project budgets and detects command loops.
- **Implement:** Add tool handlers. For budget, use logic similar to `token-diet-dashboard` to find and parse `.token-budget`. For loops, parse `token-diet loops` output or process RTK history directly.

## Iteration 4: Agent Assistance Tools (`route`)
**Goal:** Provide active guidance to the agent on which underlying tool to use.
- **Test:** Write a test for `token_diet_route` passing a dummy task and verifying the suggested tool response.
- **Implement:** Add the tool handler that calls `token-diet route <task>` and returns the recommendation.

## Iteration 5: Integration & Registration
**Goal:** Ensure the MCP server is installed and registered automatically.
- **Test:** Write/update bats tests in `tests/install.bats` to verify that `token-diet-mcp` is copied/symlinked and that it gets injected into MCP config files (like `claude_desktop_config.json`).
- **Implement:** Update `scripts/install.sh`, `scripts/Install.ps1`, and `scripts/token-diet` (doctor/repair) to register `token-diet` as an MCP server.

---

*Note: Execution will proceed iteration by iteration, validating tests at each step before moving on to the next.*