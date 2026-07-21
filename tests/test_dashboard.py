import json
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
        assert "icm" in result
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

def test_icm_stats_returns_none_when_binary_missing(dashboard_mod):
    """icm_stats() returns None when the icm binary is absent (run() falsy)."""
    with patch.object(dashboard_mod, "run", return_value=None):
        assert dashboard_mod.icm_stats() is None

def test_icm_stats_parses_version_and_hosts(dashboard_mod):
    """icm_stats() returns version + registered hosts when icm is present."""
    with patch.object(dashboard_mod, "run", return_value="icm 0.10.50"), \
         patch.object(dashboard_mod, "_registered_hosts", return_value=["claude-code", "codex"]):
        result = dashboard_mod.icm_stats()
        assert result["version"] == "0.10.50"
        assert result["hosts"] == ["claude-code", "codex"]

def test_should_open_browser_defaults_true(dashboard_mod, monkeypatch):
    """should_open_browser() defaults to enabled when unset."""
    monkeypatch.delenv("TOKEN_DIET_DASHBOARD_OPEN_BROWSER", raising=False)
    assert dashboard_mod.should_open_browser() is True

@pytest.mark.parametrize("value", ["0", "false", "no", "off", "FALSE"])
def test_should_open_browser_honors_disable_flag(dashboard_mod, monkeypatch, value):
    """should_open_browser() disables browser opening for explicit false-like values."""
    monkeypatch.setenv("TOKEN_DIET_DASHBOARD_OPEN_BROWSER", value)
    assert dashboard_mod.should_open_browser() is False

def test_should_open_browser_honors_no_open_flag(dashboard_mod, monkeypatch):
    """should_open_browser() disables browser opening when --no-open is present."""
    monkeypatch.delenv("TOKEN_DIET_DASHBOARD_OPEN_BROWSER", raising=False)
    assert dashboard_mod.should_open_browser(["--no-open"]) is False

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

# --- Canonical MCP-host registry ---------------------------------------------
# The host config paths + MCP-key dialect used to be hardcoded in the dashboard
# AND independently in bash (install.sh/uninstall.sh/token-diet). Because Python
# cannot source the bash registry, the two drifted silently. The dashboard now
# reads config/hosts-mcp.json as the single source of truth.

def _write_registry(tmp_path, reg):
    reg_file = tmp_path / "hosts-mcp.json"
    reg_file.write_text(json.dumps(reg))
    return reg_file


def test_registered_hosts_reads_canonical_file(dashboard_mod, tmp_path, monkeypatch):
    """_registered_hosts() is driven by the canonical registry, not hardcoded paths."""
    reg = {
        "schema": 1,
        "mcp_key_dialect": ["mcpServers"],
        "all_hosts": ["myhost"],
        "home_configs": [{"path": "custom/cfg.json", "host": "myhost", "format": "json"}],
        "project_configs": [],
        "presence": {"myhost": {"base": "home", "paths": ["custom"]}},
    }
    reg_file = _write_registry(tmp_path, reg)
    monkeypatch.setattr(dashboard_mod, "_host_registry_path", lambda: reg_file)

    home = tmp_path / "home"
    (home / "custom").mkdir(parents=True)
    (home / "custom" / "cfg.json").write_text(json.dumps({"mcpServers": {"mytool": {}}}))
    with patch("pathlib.Path.home", return_value=home), \
         patch("pathlib.Path.cwd", return_value=home):
        hosts = dashboard_mod._registered_hosts("mytool")
        assert hosts == ["myhost"]


def test_missing_hosts_reads_canonical_file(dashboard_mod, tmp_path, monkeypatch):
    """_missing_hosts() uses all_hosts + presence from the canonical registry."""
    reg = {
        "schema": 1,
        "mcp_key_dialect": ["mcpServers"],
        "all_hosts": ["myhost"],
        "home_configs": [{"path": "custom/cfg.json", "host": "myhost", "format": "json"}],
        "project_configs": [],
        "presence": {"myhost": {"base": "home", "paths": ["custom"]}},
    }
    reg_file = _write_registry(tmp_path, reg)
    monkeypatch.setattr(dashboard_mod, "_host_registry_path", lambda: reg_file)

    home = tmp_path / "home"
    (home / "custom").mkdir(parents=True)  # host dir exists but no MCP registration
    with patch("pathlib.Path.home", return_value=home), \
         patch("pathlib.Path.cwd", return_value=home):
        missing = dashboard_mod._missing_hosts("mytool")
        assert missing == ["myhost"]


def test_real_registry_preserves_default_host_set(dashboard_mod):
    """The shipped registry encodes exactly today's six hosts, in order."""
    reg = dashboard_mod._load_host_registry()
    assert reg["all_hosts"] == [
        "claude-code", "claude-desktop", "opencode", "codex", "vscode", "gemini",
    ]
    assert reg["mcp_key_dialect"] == ["mcpServers", "mcp", "servers"]


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


# --- Low-volume filtering -----------------------------------------------------
# An unweighted mean over raw days lets a 2-command day count as much as a
# 5,000-command day, so a weekend or a day the machine was off drags the
# projection down by an amount unrelated to the actual savings rate.

def test_projection_excludes_low_volume_days(dashboard_mod):
    """A near-idle day must not drag the average down."""
    fake_data = {
        "daily": [
            {"date": "2026-04-01", "saved_tokens": 10000, "commands": 500},
            {"date": "2026-04-02", "saved_tokens": 10000, "commands": 500},
            # Machine barely used. Two commands should not count as a full day.
            {"date": "2026-04-03", "saved_tokens": 10, "commands": 2},
        ]
    }
    res = dashboard_mod.projection_stats(fake_data)
    # Only the two qualifying days average: 10000, not (10000+10000+10)/3.
    assert res["avg_daily_saved"] == 10000
    assert res["weekly_projection"] == 70000
    assert res["days_sampled"] == 2
    assert res["days_qualified"] == 2
    assert res["days_total"] == 3


def test_projection_filter_is_noop_without_volume_data(dashboard_mod):
    """Data with no "commands" key at all keeps its projection.

    Filtering must degrade to a no-op when it has nothing to judge by. Treating
    a missing field as zero volume would silently drop every day and return
    None, turning an absent field into "no data".
    """
    fake_data = {
        "daily": [
            {"date": "2026-04-01", "saved_tokens": 1000},
            {"date": "2026-04-02", "saved_tokens": 2000},
        ]
    }
    res = dashboard_mod.projection_stats(fake_data)
    assert res is not None
    assert res["weekly_projection"] == 10500


def test_projection_returns_none_when_all_days_low_volume(dashboard_mod):
    """If volume data exists and nothing qualifies, report nothing rather than a lie."""
    fake_data = {
        "daily": [
            {"date": "2026-04-01", "saved_tokens": 5, "commands": 1},
            {"date": "2026-04-02", "saved_tokens": 5, "commands": 2},
        ]
    }
    assert dashboard_mod.projection_stats(fake_data) is None


def test_projection_reports_30_day_average(dashboard_mod):
    """The 30-day baseline is reported alongside the 7-day trend."""
    daily = [
        {"date": f"2026-04-{i:02d}", "saved_tokens": 1000, "commands": 100}
        for i in range(1, 11)
    ]
    # Last 7 days run hotter than the preceding stretch.
    for d in daily[-7:]:
        d["saved_tokens"] = 2000
    res = dashboard_mod.projection_stats({"daily": daily})
    assert res["weekly_projection"] == 14000          # 7-day: 2000 * 7
    assert res["weekly_proj_30d"] < res["weekly_projection"]
    assert res["days_qualified"] == 10
