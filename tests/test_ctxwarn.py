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


def test_debounce_holds_across_transcript_appends(ctxwarn, tmp_path, monkeypatch, capsys):
    """Regression: the debounce state file MUST NOT key on mtime.

    Real Claude Code sessions append to the transcript JSONL on every tool use
    (which updates mtime_ns). If the state-file cache key includes mtime, every
    PostToolUse call hashes to a different state file → band resets to 0 → the
    debounce never holds in practice. Caught live: 133 distinct `.band` files
    all containing "1" had accumulated under ~/.cache/token-diet/ctxwarn/
    across this and prior sessions, proving the warning re-fired on every
    single tool use past the threshold instead of warning once per band.

    Note on arithmetic: estimate_tokens() returns total_chars // 4. With
    threshold=500 and content sized to put the estimate in band 1 (250-499
    tokens = 1000-1999 chars), each call appends just enough to keep the
    total estimate inside band 1 — that's the realistic per-tool-use delta
    in a long session that hasn't yet crossed into band 2.
    """
    import time

    monkeypatch.setattr(ctxwarn, "tiktoken", None)
    monkeypatch.setattr(pathlib.Path, "home", staticmethod(lambda: tmp_path / "home"))
    proj = tmp_path / "proj_appends"
    proj.mkdir()
    # threshold=500 → band 1 is [500, 999] tokens (i.e. 2000-3999 chars)
    (proj / ".token-budget").write_text(json.dumps({"ctx_threshold": 500}))
    monkeypatch.chdir(proj)

    jsonl = proj / "t.jsonl"

    # Call 1: ~3000 chars of content → ~750 tokens → band 1, warns
    jsonl.write_text(json.dumps({"content": "x" * 3000}) + "\n")
    with pytest.raises(SystemExit):
        ctxwarn.main(["--transcript", str(jsonl)])
    assert "Context" in capsys.readouterr().out  # first warning

    # Call 2: append a small amount (stays in band 1). mtime_ns WILL change.
    # Pre-fix this would re-hash and reset the band, firing the warning again.
    time.sleep(0.05)  # ensure distinct mtime_ns (macOS APFS has ns precision)
    with open(jsonl, "a") as f:
        f.write(json.dumps({"content": "y" * 100}) + "\n")  # +100 chars
    with pytest.raises(SystemExit):
        ctxwarn.main(["--transcript", str(jsonl)])
    assert capsys.readouterr().out == ""  # MUST be silent — debounce holds

    # Call 3: another small append, mtime_ns changes again
    time.sleep(0.05)
    with open(jsonl, "a") as f:
        f.write(json.dumps({"content": "z" * 100}) + "\n")  # +100 chars
    with pytest.raises(SystemExit):
        ctxwarn.main(["--transcript", str(jsonl)])
    assert capsys.readouterr().out == ""  # still silent

    # Sanity: only ONE state file should exist for this transcript (not 3)
    cache_dir = pathlib.Path(tmp_path / "home") / ".cache" / "token-diet" / "ctxwarn"
    band_files = list(cache_dir.glob("*.band"))
    assert len(band_files) == 1, (
        f"expected exactly 1 state file (debounce keyed by path, not mtime); "
        f"found {len(band_files)}: {[f.name for f in band_files]}"
    )


def test_band_transitions_still_warn(ctxwarn, tmp_path, monkeypatch, capsys):
    """Complement to the mtime regression: when the estimate crosses into a
    NEW band (estimate // threshold increases), the warning MUST re-fire —
    even if the mtime changed in between. This proves the fix preserves the
    intended once-per-band semantics, not just once-ever."""
    import time

    monkeypatch.setattr(ctxwarn, "tiktoken", None)
    monkeypatch.setattr(pathlib.Path, "home", staticmethod(lambda: tmp_path / "home"))
    proj = tmp_path / "proj_bands"
    proj.mkdir()
    (proj / ".token-budget").write_text(json.dumps({"ctx_threshold": 500}))
    monkeypatch.chdir(proj)

    jsonl = proj / "t.jsonl"

    # First call: 3000 chars → ~750 tokens → band 1, warns
    jsonl.write_text(json.dumps({"content": "x" * 3000}) + "\n")
    with pytest.raises(SystemExit):
        ctxwarn.main(["--transcript", str(jsonl)])
    assert "Context" in capsys.readouterr().out

    # Second call: small append, stays in band 1 → silent
    time.sleep(0.05)
    with open(jsonl, "a") as f:
        f.write(json.dumps({"content": "y" * 100}) + "\n")
    with pytest.raises(SystemExit):
        ctxwarn.main(["--transcript", str(jsonl)])
    assert capsys.readouterr().out == ""  # silent, same band

    # Third call: large append pushes total past band 1 (>= 4000 chars total
    # would be band 2 of threshold 500). Append enough to cross.
    time.sleep(0.05)
    with open(jsonl, "a") as f:
        f.write(json.dumps({"content": "z" * 1500}) + "\n")
    with pytest.raises(SystemExit):
        ctxwarn.main(["--transcript", str(jsonl)])
    assert "Context" in capsys.readouterr().out  # MUST warn — new band


def test_band_transitions_still_warn(ctxwarn, tmp_path, monkeypatch, capsys):
    """Complement to the mtime regression: when the estimate crosses into a
    NEW band (estimate // threshold increases), the warning MUST re-fire —
    even if the mtime changed in between. This proves the fix preserves the
    intended once-per-band semantics, not just once-ever."""
    import time

    monkeypatch.setattr(ctxwarn, "tiktoken", None)
    monkeypatch.setattr(pathlib.Path, "home", staticmethod(lambda: tmp_path / "home"))
    proj = tmp_path / "proj_bands"
    proj.mkdir()
    (proj / ".token-budget").write_text(json.dumps({"ctx_threshold": 100}))
    monkeypatch.chdir(proj)

    jsonl = proj / "t.jsonl"

    # First call: band 1 (150 tokens, threshold 100)
    jsonl.write_text(json.dumps({"content": "x" * 600}) + "\n")
    with pytest.raises(SystemExit):
        ctxwarn.main(["--transcript", str(jsonl)])
    assert "Context" in capsys.readouterr().out

    # Second call: same band (still 150 tokens, appended but no growth in band)
    time.sleep(0.05)
    with open(jsonl, "a") as f:
        f.write(json.dumps({"content": "x" * 100}) + "\n")
    with pytest.raises(SystemExit):
        ctxwarn.main(["--transcript", str(jsonl)])
    assert capsys.readouterr().out == ""  # silent, same band

    # Third call: grow into band 2 (>= 200 tokens)
    time.sleep(0.05)
    with open(jsonl, "a") as f:
        f.write(json.dumps({"content": "x" * 300}) + "\n")
    with pytest.raises(SystemExit):
        ctxwarn.main(["--transcript", str(jsonl)])
    assert "Context" in capsys.readouterr().out  # MUST warn — new band
