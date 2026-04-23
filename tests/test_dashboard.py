import json
import pathlib
import os
from unittest.mock import patch
import pytest

@pytest.fixture
def dashboard_mod():
    import importlib.machinery
    loader = importlib.machinery.SourceFileLoader("token_diet_dashboard", "scripts/token-diet-dashboard")
    return loader.load_module()

def test_collect_returns_required_keys(dashboard_mod):
    """collect() returns a dict with all expected top-level keys."""
    with patch.object(dashboard_mod, "_get_rtk_daily", return_value=None), \
         patch.object(dashboard_mod, "_get_rtk_total", return_value=0):
        result = dashboard_mod.collect()
        assert "rtk" in result
        assert "tilth" in result
        assert "serena" in result
        assert "budget" in result
        assert "budgets" in result
        assert "version" in result
        assert "alerts" in result

def test_rtk_stats_parses_json(dashboard_mod):
    """rtk_stats() parses the summary and daily fields from data dict."""
    fake_data = {
        "summary": {
            "total_commands": 10,
            "total_input": 5000,
            "total_saved": 3500,
            "avg_savings_pct": 70.0,
            "total_time_ms": 250,
        },
        "daily": [],
    }
    result = dashboard_mod.rtk_stats(fake_data)
    assert result["summary"]["total_saved"] == 3500
    assert result["summary"]["avg_savings_pct"] == 70.0

def test_rtk_stats_returns_none_when_data_missing(dashboard_mod):
    """rtk_stats() returns None when data is None."""
    assert dashboard_mod.rtk_stats(None) is None

def test_registered_hosts_detection(dashboard_mod, tmp_path):
    """_registered_hosts() finds tools in various host config files."""
    home = tmp_path / "home"
    home.mkdir()
    
    # 1. Claude settings
    claude_dir = home / ".claude"
    claude_dir.mkdir()
    (claude_dir / "settings.json").write_text(json.dumps({"mcpServers": {"tilth": {}}}))
    
    # 2. Codex config
    codex_dir = home / ".codex"
    codex_dir.mkdir()
    (codex_dir / "config.toml").write_text('[mcp_servers.tilth]\ncommand = "tilth"')

    with patch("pathlib.Path.home", return_value=home):
        hosts = dashboard_mod._registered_hosts("tilth")
        assert "claude-code" in hosts
        assert "codex" in hosts

def test_budget_stats_calculation(dashboard_mod, tmp_path):
    """budget_stats() correctly calculates used tokens based on baseline."""
    home = tmp_path / "home"
    home.mkdir()
    budget_file = home / ".token-budget"
    # warn at 1000, baseline 5000
    budget_file.write_text(json.dumps({"warn": 1000, "hard": 2000, "baseline_tokens": 5000}))
    
    with patch("pathlib.Path.home", return_value=home), \
         patch("pathlib.Path.cwd", return_value=home):
        # total input 5500 -> used 500 (OK)
        res1 = dashboard_mod.budget_stats(5500)
        assert res1["used"] == 500
        assert res1["status"] == "ok"
        
        # total input 6500 -> used 1500 (WARN)
        res2 = dashboard_mod.budget_stats(6500)
        assert res2["used"] == 1500
        assert res2["status"] == "warn"

def test_projection_stats(dashboard_mod):
    """projection_stats() calculates weekly savings based on daily history."""
    fake_data = {
        "daily": [
            {"date": "2026-04-01", "saved_tokens": 1000},
            {"date": "2026-04-02", "saved_tokens": 2000}
        ]
    }
    res = dashboard_mod.projection_stats(fake_data)
    # average saved is 1500. weekly = 1500 * 7 = 10500.
    assert res["weekly_projection"] == 10500

