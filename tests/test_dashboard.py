import json
import pathlib
from unittest.mock import patch
import pytest

@pytest.fixture
def dashboard_mod():
    import importlib.machinery
    loader = importlib.machinery.SourceFileLoader("token_diet_dashboard", "scripts/token-diet-dashboard")
    return loader.load_module()

def test_collect_returns_required_keys(dashboard_mod):
    """collect() returns a dict with all expected top-level keys.

    The rtk-gain savings panels are gone (rtk_stats/tilth_stats/_get_rtk_daily/
    _get_rtk_total removed with the rtk/tilth drop); the dashboard reports
    per-component status for the surviving stack: serena, icm, context7.
    run() is patched to None so no subprocess or network call escapes the test;
    home/cwd are repointed so the budget walk stays hermetic.
    """
    dashboard_mod._CACHE["data"] = None
    dashboard_mod._CACHE["expires"] = 0
    home = pathlib.Path("/nonexistent-token-diet-test-home")
    with patch.object(dashboard_mod, "run", return_value=None), \
         patch("pathlib.Path.home", return_value=home), \
         patch("pathlib.Path.cwd", return_value=home):
        result = dashboard_mod.collect()
    assert "serena" in result
    assert "icm" in result
    assert "context7" in result
    assert "budget" in result
    assert "budgets" in result
    assert "missing_hosts" in result
    assert "version" in result
    # Dropped components must not come back.
    assert "rtk" not in result
    assert "tilth" not in result

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
    (claude_dir / "settings.json").write_text(json.dumps({"mcpServers": {"icm": {}}}))
    
    # 2. Codex config
    codex_dir = home / ".codex"
    codex_dir.mkdir()
    (codex_dir / "config.toml").write_text('[mcp_servers.icm]\ncommand = "icm"')

    with patch("pathlib.Path.home", return_value=home):
        hosts = dashboard_mod._registered_hosts("icm")
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


def test_budget_stats_reads_thresholds_without_usage_tracking(dashboard_mod, tmp_path):
    """budget_stats() (no args) reports the thresholds from the active budget file.

    Per-command token usage died with RTK and nothing replaced it (Serena/ICM/
    context7 have no per-command counter), so the entry must say so via
    usage_tracked=False instead of pretending to measure a burn-down.
    """
    home = tmp_path / "home"
    home.mkdir()
    (home / ".token-budget").write_text(json.dumps({"warn": 1000, "hard": 0}))

    with patch("pathlib.Path.home", return_value=home), \
         patch("pathlib.Path.cwd", return_value=home):
        res = dashboard_mod.budget_stats()

    assert res["warn"] == 1000
    assert res["hard"] == 0
    assert res["unlimited"] is True
    assert res["status"] == "ok"
    assert res["used"] == 0
    assert res["usage_tracked"] is False

def test_budget_stats_returns_none_when_no_budget_file(dashboard_mod, tmp_path):
    """budget_stats() reports nothing when no .token-budget exists anywhere."""
    home = tmp_path / "home"
    home.mkdir()
    with patch("pathlib.Path.home", return_value=home), \
         patch("pathlib.Path.cwd", return_value=home):
        assert dashboard_mod.budget_stats() is None

def test_context7_stats_reports_registration_only(dashboard_mod, tmp_path, monkeypatch):
    """context7_stats() is presence-only: remote URL + registered hosts.

    context7 has no local binary or version to probe — registration state is
    the entire health signal.
    """
    reg = {
        "schema": 1,
        "mcp_key_dialect": ["mcpServers"],
        "all_hosts": ["claude-code"],
        "home_configs": [{"path": ".claude/settings.json", "host": "claude-code", "format": "json"}],
        "project_configs": [],
        "presence": {},
    }
    reg_file = tmp_path / "hosts-mcp.json"
    reg_file.write_text(json.dumps(reg))
    monkeypatch.setattr(dashboard_mod, "_host_registry_path", lambda: reg_file)

    home = tmp_path / "home"
    (home / ".claude").mkdir(parents=True)
    (home / ".claude" / "settings.json").write_text(
        json.dumps({"mcpServers": {"context7": {"type": "http", "url": "https://mcp.context7.com/mcp"}}})
    )
    with patch("pathlib.Path.home", return_value=home):
        res = dashboard_mod.context7_stats()
    assert res["url"] == "https://mcp.context7.com/mcp"
    assert res["hosts"] == ["claude-code"]
