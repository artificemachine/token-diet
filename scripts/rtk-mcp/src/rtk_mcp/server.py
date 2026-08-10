"""rtk-mcp — MCP server exposing rtk CLI subcommands as MCP tools.

Run via ``rtk-mcp`` (installed by ``pip install -e .``).
"""

from __future__ import annotations

import functools
import subprocess
from typing import Annotated

from mcp.server.fastmcp import FastMCP

mcp = FastMCP("rtk")

# Subcommand help text is fetched on import; the prompt to the LLM includes
# the relevant section of `rtk <cmd> --help` so it knows what flags to pass.
_HELP_CACHE: dict[str, str] = {}


def _help_for(cmd: str, limit: int = 400) -> str:
    """Return the first ``limit`` chars of ``rtk <cmd> --help``."""
    if cmd in _HELP_CACHE:
        return _HELP_CACHE[cmd]
    try:
        r = subprocess.run(["rtk", cmd, "--help"], capture_output=True, text=True, timeout=5)
        text = (r.stdout or r.stderr or "").strip().replace("\n", " ")
    except Exception as e:  # noqa: BLE001
        text = f"(help unavailable: {e})"
    _HELP_CACHE[cmd] = text[:limit]
    return _HELP_CACHE[cmd]


def _run_rtk(cmd: str, args: list[str]) -> str:
    """Shell out to ``rtk <cmd> <args...>`` and return stdout+stderr."""
    try:
        r = subprocess.run(
            ["rtk", cmd, *args],
            capture_output=True,
            text=True,
            timeout=60,
        )
        out = r.stdout
        if r.stderr:
            out += "\n[stderr]\n" + r.stderr
        if r.returncode != 0:
            out += f"\n[returncode={r.returncode}]"
        return out or "(no output)"
    except subprocess.TimeoutExpired:
        return f"Error: rtk {cmd} timed out after 60s"
    except FileNotFoundError:
        return "Error: rtk binary not found on PATH (install rtk first)"
    except Exception as e:  # noqa: BLE001
        return f"Error: {e}"


def _make_tool(cmd: str) -> None:
    """Register ``rtk_<cmd>`` as an MCP tool that shells out to ``rtk <cmd>``."""
    tool_name = "rtk_" + cmd.replace("-", "_")
    desc = f"Run `rtk {cmd}` (token-compressed wrapper). {_help_for(cmd)}"

    # NOTE: do NOT use functools.wraps(_run_rtk) here — it would copy _run_rtk's
    # ``(cmd, args)`` signature onto the inner closure, and FastMCP would then
    # expose ``cmd`` as a required argument to the tool (causing pydantic
    # validation errors at call time). Keep the closure's own clean signature
    # so FastMCP introspection sees only ``args``.
    def rtk_tool(args: list[str]) -> str:
        return _run_rtk(cmd, list(args))

    rtk_tool.__name__ = tool_name
    rtk_tool.__qualname__ = tool_name
    rtk_tool.__doc__ = desc

    mcp.tool(name=tool_name, description=desc)(rtk_tool)


# Register one MCP tool per rtk subcommand. Tokens-cheap so we don't memoize;
# discovery runs once on MCP initialize.
try:
    r = subprocess.run(["rtk", "--help"], capture_output=True, text=True, timeout=5)
    in_commands = False
    for line in r.stdout.splitlines():
        if line.strip().startswith("Commands:"):
            in_commands = True
            continue
        if in_commands:
            stripped = line.strip()
            if not stripped or stripped.startswith("Options:"):
                break
            head = stripped.split(maxsplit=1)[0]
            if head and head.isidentifier() is False and "-" in head or head.isalnum():
                _make_tool(head)
except Exception as e:  # noqa: BLE001
    # Fallback: minimal core set if `rtk --help` parsing failed
    for cmd in ("ls", "tree", "read", "git", "find", "diff", "log", "deps", "env", "smart", "json", "test"):
        _make_tool(cmd)


def main() -> None:
    """Run the MCP server over stdio."""
    mcp.run()


if __name__ == "__main__":
    main()
