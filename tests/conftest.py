"""conftest.py — shared pytest fixtures for token-diet tests."""
import importlib.machinery
import importlib.util
import pathlib

import pytest


@pytest.fixture(scope="session")
def dashboard_mod():
    """Import the token-diet-dashboard script as a module.

    The script has no .py extension, so spec_from_file_location can't infer
    the loader automatically. SourceFileLoader treats it as a Python source file.
    """
    src = pathlib.Path(__file__).parent.parent / "scripts" / "token-diet-dashboard"
    loader = importlib.machinery.SourceFileLoader("token_diet_dashboard", str(src))
    spec = importlib.util.spec_from_loader("token_diet_dashboard", loader)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture
def tmp_home(tmp_path, monkeypatch):
    """Provide a sandboxed HOME directory and patch pathlib.Path.home()."""
    home = tmp_path / "home"
    (home / ".claude").mkdir(parents=True)
    (home / ".codex").mkdir(parents=True)
    (home / ".serena" / "memories").mkdir(parents=True)
    (home / ".serena" / "logs").mkdir(parents=True)
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setattr(pathlib.Path, "home", staticmethod(lambda: home))
    return home
