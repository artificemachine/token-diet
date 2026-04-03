"""Regression tests for portable tilth benchmark paths."""

import importlib.machinery
import importlib.util
from pathlib import Path


BENCHMARK_DIR = Path(__file__).parent.parent / "forks" / "tilth" / "benchmark"


def load_benchmark_module(module_name: str, filename: str, monkeypatch):
    monkeypatch.syspath_prepend(str(BENCHMARK_DIR))
    loader = importlib.machinery.SourceFileLoader(module_name, str(BENCHMARK_DIR / filename))
    spec = importlib.util.spec_from_loader(module_name, loader)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_resolve_tilth_bin_prefers_env(monkeypatch, tmp_path):
    config = load_benchmark_module("tilth_benchmark_config", "config.py", monkeypatch)
    fake_bin = tmp_path / "tilth"
    fake_bin.write_text("#!/usr/bin/env bash\n")
    fake_bin.chmod(0o755)

    monkeypatch.setenv("TILTH_BIN", str(fake_bin))

    assert config.resolve_tilth_bin() == str(fake_bin)
    codex_args = config.codex_mcp_args()
    assert str(fake_bin) in codex_args[1]


def test_portable_tilth_mcp_config_rewrites_fixture(monkeypatch, tmp_path):
    run = load_benchmark_module("tilth_benchmark_run", "run.py", monkeypatch)
    fake_bin = tmp_path / "tilth"
    fake_bin.write_text("#!/usr/bin/env bash\n")
    fake_bin.chmod(0o755)

    monkeypatch.setenv("TILTH_BIN", str(fake_bin))

    config_path = Path(run._portable_tilth_mcp_config())
    data = config_path.read_text()

    assert str(fake_bin) in data
    assert "/Users/flysikring/.cargo/bin/tilth" not in data
