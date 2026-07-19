"""tests/test_ctxwarn.py — pytest for scripts/lib/ctxwarn.py"""
import importlib.machinery
import importlib.util
import json
import pathlib
import sys

import pytest

LIB_DIR = pathlib.Path(__file__).parent.parent / "scripts" / "lib"


def _load(name):
    src = LIB_DIR / f"{name}.py"
    loader = importlib.machinery.SourceFileLoader(name, str(src))
    spec = importlib.util.spec_from_loader(name, loader)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    loader.exec_module(mod)
    return mod


@pytest.fixture
def ctxwarn():
    return _load("ctxwarn")


class _BoomTiktoken:
    def get_encoding(self, *_args, **_kwargs):
        raise RuntimeError("boom")


def test_estimate_tokens_tiktoken_path(ctxwarn, tmp_path):
    jsonl = tmp_path / "transcript.jsonl"
    text = "The quick brown fox jumps over the lazy dog. " * 50
    jsonl.write_text(json.dumps({"role": "user", "content": text}) + "\n")

    import tiktoken

    enc = tiktoken.get_encoding("cl100k_base")
    expected = len(enc.encode(text))

    result = ctxwarn.estimate_tokens(jsonl)
    assert abs(result - expected) <= max(1, int(expected * 0.05))


def test_estimate_falls_back_to_chars_div_4(ctxwarn, tmp_path, monkeypatch):
    jsonl = tmp_path / "transcript.jsonl"
    text = "x" * 400
    jsonl.write_text(json.dumps({"content": text}) + "\n")
    monkeypatch.setattr(ctxwarn, "tiktoken", _BoomTiktoken())

    result = ctxwarn.estimate_tokens(jsonl)
    assert result == len(text) // 4


def test_below_threshold_prints_nothing(ctxwarn, tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(pathlib.Path, "home", staticmethod(lambda: tmp_path / "home"))
    monkeypatch.chdir(tmp_path)
    jsonl = tmp_path / "small.jsonl"
    jsonl.write_text(json.dumps({"content": "short text"}) + "\n")

    with pytest.raises(SystemExit) as exc:
        ctxwarn.main(["--transcript", str(jsonl)])
    assert exc.value.code == 0
    assert capsys.readouterr().out == ""


def test_above_threshold_prints_warning(ctxwarn, tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(ctxwarn, "tiktoken", None)
    monkeypatch.setattr(pathlib.Path, "home", staticmethod(lambda: tmp_path / "home"))
    monkeypatch.chdir(tmp_path)  # no .token-budget here -> default 100000 threshold
    jsonl = tmp_path / "big.jsonl"
    big_text = "x" * 500000  # chars//4 = 125000 tokens > 100000 default threshold
    jsonl.write_text(json.dumps({"content": big_text}) + "\n")

    with pytest.raises(SystemExit) as exc:
        ctxwarn.main(["--transcript", str(jsonl)])
    assert exc.value.code == 0
    out = capsys.readouterr().out
    assert "Context" in out
    assert "k" in out


def test_threshold_from_token_budget_file(ctxwarn, tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(ctxwarn, "tiktoken", None)
    monkeypatch.setattr(pathlib.Path, "home", staticmethod(lambda: tmp_path / "home"))
    proj = tmp_path / "proj"
    proj.mkdir()
    (proj / ".token-budget").write_text(json.dumps({"warn": 1500000, "hard": 0, "ctx_threshold": 100}))
    jsonl = proj / "t.jsonl"
    jsonl.write_text(json.dumps({"content": "x" * 500}) + "\n")  # chars//4 = 125 > 100
    monkeypatch.chdir(proj)

    with pytest.raises(SystemExit) as exc:
        ctxwarn.main(["--transcript", str(jsonl)])
    assert exc.value.code == 0
    assert "Context" in capsys.readouterr().out


def test_debounce_suppresses_second_warning(ctxwarn, tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(ctxwarn, "tiktoken", None)
    monkeypatch.setattr(pathlib.Path, "home", staticmethod(lambda: tmp_path / "home"))
    proj = tmp_path / "proj2"
    proj.mkdir()
    (proj / ".token-budget").write_text(json.dumps({"ctx_threshold": 100}))
    jsonl = proj / "t.jsonl"
    jsonl.write_text(json.dumps({"content": "x" * 500}) + "\n")
    monkeypatch.chdir(proj)

    with pytest.raises(SystemExit):
        ctxwarn.main(["--transcript", str(jsonl)])
    first_out = capsys.readouterr().out
    assert "Context" in first_out

    with pytest.raises(SystemExit):
        ctxwarn.main(["--transcript", str(jsonl)])
    second_out = capsys.readouterr().out
    assert second_out == ""


def test_missing_transcript_exits_0_silently(ctxwarn, tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(pathlib.Path, "home", staticmethod(lambda: tmp_path / "home"))
    monkeypatch.chdir(tmp_path)

    with pytest.raises(SystemExit) as exc:
        ctxwarn.main(["--transcript", str(tmp_path / "missing.jsonl")])
    assert exc.value.code == 0
    assert capsys.readouterr().out == ""


def test_malformed_jsonl_line_skipped(ctxwarn, tmp_path):
    jsonl = tmp_path / "bad.jsonl"
    jsonl.write_text("not valid json\n" + json.dumps({"content": "valid text here"}) + "\n")

    result = ctxwarn.estimate_tokens(jsonl)
    assert result > 0


@pytest.mark.parametrize(
    "scenario",
    ["below", "above", "missing", "malformed"],
)
def test_always_exits_0_contract(ctxwarn, tmp_path, monkeypatch, scenario):
    monkeypatch.setattr(ctxwarn, "tiktoken", None)
    monkeypatch.setattr(pathlib.Path, "home", staticmethod(lambda: tmp_path / "home"))
    monkeypatch.chdir(tmp_path)

    if scenario == "missing":
        transcript = tmp_path / "missing.jsonl"
    elif scenario == "below":
        transcript = tmp_path / "below.jsonl"
        transcript.write_text(json.dumps({"content": "short"}) + "\n")
    elif scenario == "above":
        transcript = tmp_path / "above.jsonl"
        transcript.write_text(json.dumps({"content": "x" * 500000}) + "\n")
    else:  # malformed
        transcript = tmp_path / "malformed.jsonl"
        transcript.write_text("not valid json\n")

    with pytest.raises(SystemExit) as exc:
        ctxwarn.main(["--transcript", str(transcript)])
    assert exc.value.code == 0
