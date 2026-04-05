"""test_dashboard.py — pytest tests for token-diet-dashboard data layer."""
import json
from unittest.mock import patch


# ---------------------------------------------------------------------------
# Cycle 1.3 — collect() structure
# ---------------------------------------------------------------------------

def test_collect_returns_required_keys(dashboard_mod):
    """collect() always returns a dict with rtk, tilth, serena keys."""
    with patch.object(dashboard_mod, "run", return_value=None):
        result = dashboard_mod.collect()
    assert isinstance(result, dict)
    assert "rtk" in result
    assert "tilth" in result
    assert "serena" in result


def test_collect_returns_none_when_tools_absent(dashboard_mod):
    """When no tools respond, all values are None."""
    with patch.object(dashboard_mod, "run", return_value=None):
        result = dashboard_mod.collect()
    assert result["rtk"] is None
    assert result["tilth"] is None
    assert result["serena"] is None


# ---------------------------------------------------------------------------
# rtk_stats
# ---------------------------------------------------------------------------

def test_rtk_stats_parses_json(dashboard_mod):
    """rtk_stats() parses the summary and daily fields from rtk gain output."""
    fake_json = json.dumps({
        "summary": {
            "total_commands": 10,
            "total_input": 5000,
            "total_saved": 3500,
            "avg_savings_pct": 70.0,
            "total_time_ms": 250,
        },
        "daily": [],
    })
    with patch.object(dashboard_mod, "run", return_value=fake_json):
        result = dashboard_mod.rtk_stats()
    assert result is not None
    assert result["summary"]["total_commands"] == 10
    assert result["summary"]["avg_savings_pct"] == 70.0
    assert isinstance(result["daily"], list)


def test_rtk_stats_returns_none_when_rtk_missing(dashboard_mod):
    """rtk_stats() returns None when rtk is not installed."""
    with patch.object(dashboard_mod, "run", return_value=None):
        assert dashboard_mod.rtk_stats() is None


def test_rtk_stats_daily_capped_at_14(dashboard_mod):
    """rtk_stats() only keeps the last 14 days of daily data."""
    daily = [{"date": f"2026-03-{i:02d}", "saved": i * 100} for i in range(1, 30)]
    fake_json = json.dumps({
        "summary": {"total_commands": 1, "total_input": 1, "total_saved": 1,
                    "avg_savings_pct": 1.0, "total_time_ms": 1},
        "daily": daily,
    })
    with patch.object(dashboard_mod, "run", return_value=fake_json):
        result = dashboard_mod.rtk_stats()
    assert len(result["daily"]) == 14


# ---------------------------------------------------------------------------
# tilth_stats
# ---------------------------------------------------------------------------

def test_tilth_stats_returns_version(dashboard_mod, tmp_home):
    """tilth_stats() extracts the version string from 'tilth --version' output."""
    with patch.object(dashboard_mod, "run", return_value="tilth 0.5.7-mock"):
        result = dashboard_mod.tilth_stats()
    assert result is not None
    assert result["version"] == "0.5.7-mock"


def test_tilth_stats_returns_none_when_tilth_missing(dashboard_mod, tmp_home):
    """tilth_stats() returns None when tilth is not installed."""
    with patch.object(dashboard_mod, "run", return_value=None):
        assert dashboard_mod.tilth_stats() is None


# ---------------------------------------------------------------------------
# _registered_hosts
# ---------------------------------------------------------------------------

def test_registered_hosts_empty_when_no_configs(dashboard_mod, tmp_home):
    """_registered_hosts() returns [] when no MCP config files exist."""
    hosts = dashboard_mod._registered_hosts("tilth")
    assert hosts == []


def test_registered_hosts_detects_claude_code(dashboard_mod, tmp_home):
    """_registered_hosts() finds claude-code when tilth is in settings.json."""
    cfg = tmp_home / ".claude" / "settings.json"
    cfg.write_text(json.dumps({"mcpServers": {"tilth": {"command": "tilth"}}}))

    hosts = dashboard_mod._registered_hosts("tilth")
    assert "claude-code" in hosts


def test_registered_hosts_deduplicates(dashboard_mod, tmp_home):
    """_registered_hosts() deduplicates host labels."""
    cfg = tmp_home / ".claude" / "settings.json"
    cfg.write_text(json.dumps({"mcpServers": {"tilth": {}, "tilth-extra": {}}}))

    hosts = dashboard_mod._registered_hosts("tilth")
    assert hosts.count("claude-code") == 1


# ---------------------------------------------------------------------------
# Cycle 8.1-8.2 — breakdown_stats in collect()
# ---------------------------------------------------------------------------

def test_collect_includes_breakdown_key(dashboard_mod):
    """collect() includes a 'breakdown' key alongside rtk/tilth/serena."""
    with patch.object(dashboard_mod, "run", return_value=None):
        result = dashboard_mod.collect()
    assert "breakdown" in result


def test_breakdown_stats_returns_top_days(dashboard_mod, tmp_home):
    """breakdown_stats() returns top_days list from RTK daily history."""
    fake_daily = json.dumps({
        "summary": {"total_commands": 10, "total_input": 65000,
                    "total_saved": 50000, "avg_savings_pct": 76.9, "total_time_ms": 300},
        "daily": [
            {"date": "2026-04-01", "commands": 50, "saved_tokens": 40000, "savings_pct": 80.0,
             "input_tokens": 50000, "output_tokens": 5000, "total_time_ms": 200},
            {"date": "2026-04-02", "commands": 30, "saved_tokens": 20000, "savings_pct": 66.7,
             "input_tokens": 30000, "output_tokens": 3000, "total_time_ms": 100},
        ]
    })

    with patch.object(dashboard_mod, "run", return_value=fake_daily):
        result = dashboard_mod.breakdown_stats()

    assert result is not None
    assert "top_days" in result
    assert len(result["top_days"]) == 2
    assert result["top_days"][0]["date"] == "2026-04-01"  # highest saved_tokens first


def test_breakdown_stats_returns_none_when_rtk_missing(dashboard_mod, tmp_home):
    """breakdown_stats() returns None when RTK is not installed."""
    with patch.object(dashboard_mod, "run", return_value=None):
        assert dashboard_mod.breakdown_stats() is None


# ---------------------------------------------------------------------------
# Cycle 11.1-11.2 — budget_stats in collect()
# ---------------------------------------------------------------------------

def test_collect_includes_budget_key(dashboard_mod, tmp_home):
    """collect() includes a 'budget' key."""
    with patch.object(dashboard_mod, "run", return_value=None):
        result = dashboard_mod.collect()
    assert "budget" in result


def test_budget_stats_returns_thresholds_when_file_exists(dashboard_mod, tmp_home):
    """budget_stats() parses warn/hard from .token-budget and adds used/remaining."""
    budget_file = tmp_home / ".token-budget"
    budget_file.write_text(json.dumps({"warn": 50000, "hard": 100000}))

    fake_summary = json.dumps({
        "summary": {"total_commands": 5, "total_input": 30000,
                    "total_saved": 20000, "avg_savings_pct": 66.0, "total_time_ms": 100},
        "daily": []
    })
    with patch.object(dashboard_mod, "run", return_value=fake_summary), \
         patch.object(dashboard_mod.pathlib.Path, "cwd", return_value=tmp_home):
        result = dashboard_mod.budget_stats()

    assert result is not None
    assert result["warn"] == 50000
    assert result["hard"] == 100000
    assert result["used"] == 30000
    assert result["remaining"] == 70000


def test_budget_stats_auto_creates_global_when_no_budget_file(dashboard_mod, tmp_home):
    """budget_stats() auto-creates $HOME/.token-budget with defaults when no file exists."""
    with patch.object(dashboard_mod, "run", return_value=None), \
         patch.object(dashboard_mod.pathlib.Path, "cwd", return_value=tmp_home):
        result = dashboard_mod.budget_stats()
    global_budget = tmp_home / ".token-budget"
    assert global_budget.exists(), "global .token-budget should be auto-created"
    cfg = json.loads(global_budget.read_text())
    assert cfg["warn"] == 1500000
    assert cfg["hard"] == 0
    assert result is not None
    assert result["warn"] == 1500000
    assert result["used"] == 0


# ---------------------------------------------------------------------------
# loops_stats / leaks_stats — stub functions
# ---------------------------------------------------------------------------

def test_loops_stats_returns_none(dashboard_mod):
    """loops_stats() is a stub returning None (RTK per-command data not yet available)."""
    assert dashboard_mod.loops_stats() is None


def test_leaks_stats_returns_none(dashboard_mod):
    """leaks_stats() is a stub returning None (RTK per-file data not yet available)."""
    assert dashboard_mod.leaks_stats() is None


def test_collect_includes_loops_and_leaks_keys(dashboard_mod):
    """collect() includes 'loops' and 'leaks' keys even when stubs return None."""
    with patch.object(dashboard_mod, "run", return_value=None):
        result = dashboard_mod.collect()
    assert "loops" in result
    assert "leaks" in result
    assert result["loops"] is None
    assert result["leaks"] is None


# ---------------------------------------------------------------------------
# token-diet self version
# ---------------------------------------------------------------------------

def test_token_diet_version_returns_version_string(dashboard_mod):
    """token_diet_version() parses the version from 'token-diet --version' output."""
    with patch.object(dashboard_mod, "run", return_value="token-diet 1.2.11"):
        result = dashboard_mod.token_diet_version()
    assert result == "1.2.11"


def test_token_diet_version_returns_none_when_not_installed(dashboard_mod):
    """token_diet_version() returns None when token-diet is not on PATH."""
    with patch.object(dashboard_mod, "run", return_value=None):
        result = dashboard_mod.token_diet_version()
    assert result is None


def test_collect_includes_version_key(dashboard_mod):
    """collect() includes a 'version' key for token-diet self-version."""
    with patch.object(dashboard_mod, "run", return_value=None):
        result = dashboard_mod.collect()
    assert "version" in result
