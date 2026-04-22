import json
import subprocess
import sys
import os
import pytest
from pathlib import Path

MCP_SCRIPT = Path(__file__).parent.parent / "scripts" / "token-diet-mcp"

def run_mcp(requests):
    """Run the MCP server with the given requests (list of dicts). Returns list of responses."""
    env = os.environ.copy()
    
    # We must ensure the script is executable or invoke via python
    cmd = [sys.executable, str(MCP_SCRIPT)]
    
    process = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env
    )
    
    # Write all requests
    for req in requests:
        process.stdin.write(json.dumps(req) + "\n")
    process.stdin.close()
    
    # Read responses
    responses = []
    for line in process.stdout:
        if line.strip():
            responses.append(json.loads(line))
            
    process.wait()
    return responses

def test_mcp_initialize():
    req = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "test-client", "version": "1.0"}
        }
    }
    responses = run_mcp([req])
    assert len(responses) == 1
    resp = responses[0]
    assert resp["jsonrpc"] == "2.0"
    assert resp["id"] == 1
    assert "result" in resp
    assert resp["result"]["protocolVersion"] == "2024-11-05"
    assert resp["result"]["serverInfo"]["name"] == "token-diet"

def test_mcp_tools_list():
    req = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/list",
        "params": {}
    }
    responses = run_mcp([req])
    assert len(responses) == 1
    resp = responses[0]
    assert resp["jsonrpc"] == "2.0"
    assert resp["id"] == 2
    assert "result" in resp
    assert "tools" in resp["result"]
    tools = {t["name"] for t in resp["result"]["tools"]}
    assert "token_diet_health" in tools
    assert "token_diet_savings" in tools
    assert "token_diet_budget" in tools
    assert "token_diet_loops" in tools
    assert "token_diet_route" in tools

def test_mcp_tools_call_health():
    req = {
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {
            "name": "token_diet_health",
            "arguments": {}
        }
    }
    responses = run_mcp([req])
    assert len(responses) == 1
    resp = responses[0]
    assert resp["jsonrpc"] == "2.0"
    assert resp["id"] == 3
    assert "result" in resp
    content = resp["result"]["content"]
    assert len(content) > 0
    assert content[0]["type"] == "text"
    assert "text" in content[0]

def test_mcp_tools_call_budget():
    req = {
        "jsonrpc": "2.0",
        "id": 4,
        "method": "tools/call",
        "params": {
            "name": "token_diet_budget",
            "arguments": {}
        }
    }
    responses = run_mcp([req])
    assert len(responses) == 1
    resp = responses[0]
    assert resp["jsonrpc"] == "2.0"
    assert "result" in resp

def test_mcp_tools_call_route():
    req = {
        "jsonrpc": "2.0",
        "id": 5,
        "method": "tools/call",
        "params": {
            "name": "token_diet_route",
            "arguments": {"task": "Find all usages of foo() in src/"}
        }
    }
    responses = run_mcp([req])
    assert len(responses) == 1
    resp = responses[0]
    assert resp["jsonrpc"] == "2.0"
    assert "result" in resp
    content = resp["result"]["content"]
    assert "text" in content[0]
