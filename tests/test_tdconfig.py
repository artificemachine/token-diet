"""Tests for scripts/lib/tdconfig.py — atomic, loud config mutation.

These encode the two failure modes found in the shipped installer on
2026-07-20 (see module docstring in tdconfig.py):
  1. open(path,"w") truncates before serializing, so a mid-write failure
     leaves a zero-byte config.
  2. `except Exception: pass` hides that from the user entirely.
"""

import json
import os
import pathlib
import sys

import pytest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "scripts" / "lib"))

import tdconfig  # noqa: E402


@pytest.fixture
def cfg(tmp_path):
    p = tmp_path / "settings.json"
    p.write_text(json.dumps({"mcpServers": {"existing": {"command": "keep-me"}}}, indent=2))
    return p


# --- atomic_write_json ----------------------------------------------------


def test_writes_json(tmp_path):
    p = tmp_path / "out.json"
    tdconfig.atomic_write_json(p, {"a": 1})
    assert json.loads(p.read_text()) == {"a": 1}


def test_original_survives_a_serialization_failure(cfg):
    """The core H1 regression: a failed write must not destroy the target.

    A set is not JSON-serializable. The old code truncated on open() and only
    then hit the error, leaving an empty file. Serializing first means the
    target is never opened.
    """
    before = cfg.read_text()
    with pytest.raises(TypeError):
        tdconfig.atomic_write_json(cfg, {"bad": {1, 2, 3}})
    assert cfg.read_text() == before
    assert json.loads(cfg.read_text())["mcpServers"]["existing"]["command"] == "keep-me"


def test_leaves_no_temp_files_behind_on_failure(cfg):
    with pytest.raises(TypeError):
        tdconfig.atomic_write_json(cfg, {"bad": {1, 2}})
    leftovers = [p for p in cfg.parent.iterdir() if p.name.endswith(".tmp")]
    assert leftovers == []


def test_preserves_file_mode(cfg):
    os.chmod(cfg, 0o644)
    tdconfig.atomic_write_json(cfg, {"a": 1})
    assert (cfg.stat().st_mode & 0o777) == 0o644


def test_creates_parent_directories(tmp_path):
    target = tmp_path / "nested" / "deep" / "cfg.json"
    tdconfig.atomic_write_json(target, {"a": 1})
    assert json.loads(target.read_text()) == {"a": 1}


# --- load_json ------------------------------------------------------------


def test_missing_file_returns_empty_by_default(tmp_path):
    assert tdconfig.load_json(tmp_path / "nope.json") == {}


def test_missing_file_raises_when_not_ok(tmp_path):
    with pytest.raises(tdconfig.ConfigError):
        tdconfig.load_json(tmp_path / "nope.json", missing_ok=False)


def test_malformed_json_raises_rather_than_silently_returning_empty(tmp_path):
    """The H1 silent-swallow regression.

    Returning {} here would make a corrupt config look like an empty one, and
    the caller would happily overwrite the user's real settings with a stub.
    """
    p = tmp_path / "broken.json"
    p.write_text('{"broken json')
    with pytest.raises(tdconfig.ConfigError) as e:
        tdconfig.load_json(p)
    assert "malformed" in str(e.value)


# --- update_json ----------------------------------------------------------


def test_update_preserves_unrelated_keys(cfg):
    tdconfig.update_json(cfg, lambda d: d["mcpServers"].update({"new": {"command": "x"}}))
    data = json.loads(cfg.read_text())
    assert data["mcpServers"]["existing"]["command"] == "keep-me"
    assert data["mcpServers"]["new"]["command"] == "x"


def test_update_takes_a_backup_on_the_success_path(cfg):
    """Backups must exist before a *successful* mutation, not only after a
    corrupt one is detected."""
    tdconfig.update_json(cfg, lambda d: d.update({"touched": True}))
    backups = list(cfg.parent.glob("settings.json.bak-token-diet-*"))
    assert len(backups) == 1
    assert json.loads(backups[0].read_text())["mcpServers"]["existing"]["command"] == "keep-me"


def test_update_can_skip_by_returning_false(cfg):
    before = cfg.read_text()
    assert tdconfig.update_json(cfg, lambda d: False) is False
    assert cfg.read_text() == before
    assert list(cfg.parent.glob("*.bak-token-diet-*")) == []


def test_update_on_malformed_input_raises_and_leaves_file_intact(tmp_path):
    p = tmp_path / "broken.json"
    p.write_text('{"broken json')
    with pytest.raises(tdconfig.ConfigError):
        tdconfig.update_json(p, lambda d: d.update({"x": 1}))
    assert p.read_text() == '{"broken json'


def test_update_does_not_write_when_mutate_raises(cfg):
    before = cfg.read_text()

    def boom(_data):
        raise RuntimeError("mutation failed")

    with pytest.raises(RuntimeError):
        tdconfig.update_json(cfg, boom)
    assert cfg.read_text() == before


# --- CLI ------------------------------------------------------------------


def test_verify_cli_accepts_valid_json(cfg):
    assert tdconfig._cli(["verify", str(cfg)]) == 0


def test_verify_cli_rejects_malformed_json(tmp_path):
    p = tmp_path / "broken.json"
    p.write_text("{nope")
    assert tdconfig._cli(["verify", str(p)]) == 1
