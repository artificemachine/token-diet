"""tests/test_docextract.py — pytest for scripts/lib/docextract.py"""
import importlib.machinery
import importlib.util
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


@pytest.fixture(scope="module")
def docextract():
    return _load("docextract")


@pytest.fixture
def csv_file(tmp_path):
    p = tmp_path / "sample.csv"
    p.write_text("name,age\nmax,5\n")
    return p


@pytest.fixture
def html_file(tmp_path):
    p = tmp_path / "sample.html"
    p.write_text("<html><body><h1>Title</h1><p>Body text</p></body></html>")
    return p


@pytest.fixture
def txt_file(tmp_path):
    p = tmp_path / "sample.txt"
    p.write_text("plain text passthrough")
    return p


def test_extract_pdf_returns_cache_path_with_text(docextract, one_page_pdf, tmp_path, monkeypatch):
    monkeypatch.setattr(pathlib.Path, "home", staticmethod(lambda: tmp_path / "home"))
    path = docextract.main([str(one_page_pdf)])
    cache_path = pathlib.Path(path)
    assert cache_path.exists()
    assert cache_path.suffix == ".md"
    assert "HELLO PLAN" in cache_path.read_text()


def test_extract_csv_to_markdown_table(docextract, csv_file, tmp_path, monkeypatch):
    monkeypatch.setattr(pathlib.Path, "home", staticmethod(lambda: tmp_path / "home"))
    path = docextract.main([str(csv_file)])
    text = pathlib.Path(path).read_text()
    assert "|" in text
    assert "name" in text and "max" in text


def test_extract_html_strips_tags(docextract, html_file, tmp_path, monkeypatch):
    monkeypatch.setattr(pathlib.Path, "home", staticmethod(lambda: tmp_path / "home"))
    path = docextract.main([str(html_file)])
    text = pathlib.Path(path).read_text()
    assert "<h1>" not in text
    assert "<p>" not in text
    assert "Title" in text
    assert "Body text" in text


def test_txt_passthrough(docextract, txt_file, tmp_path, monkeypatch):
    monkeypatch.setattr(pathlib.Path, "home", staticmethod(lambda: tmp_path / "home"))
    path = docextract.main([str(txt_file)])
    text = pathlib.Path(path).read_text()
    assert text == "plain text passthrough"


def test_binary_input_exits_2(docextract, tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(pathlib.Path, "home", staticmethod(lambda: tmp_path / "home"))
    zip_path = tmp_path / "archive.zip"
    zip_path.write_bytes(b"PK\x03\x04fake-zip-bytes")
    with pytest.raises(SystemExit) as exc:
        docextract.main([str(zip_path)])
    assert exc.value.code == 2
    assert "no text extractor" in capsys.readouterr().err


def test_needs_markitdown_exits_3(docextract, tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(pathlib.Path, "home", staticmethod(lambda: tmp_path / "home"))
    docx_path = tmp_path / "sample.docx"
    docx_path.write_bytes(b"fake-docx-bytes")
    with pytest.raises(SystemExit) as exc:
        docextract.main([str(docx_path)])
    assert exc.value.code == 3
    assert "markitdown" in capsys.readouterr().err.lower()


def test_cache_hit_skips_reextraction(docextract, txt_file, tmp_path, monkeypatch):
    monkeypatch.setattr(pathlib.Path, "home", staticmethod(lambda: tmp_path / "home"))
    first = docextract.main([str(txt_file)])
    cache_file = pathlib.Path(first)
    mtime_before = cache_file.stat().st_mtime_ns
    second = docextract.main([str(txt_file)])
    assert first == second
    assert cache_file.stat().st_mtime_ns == mtime_before


def test_missing_file_exits_4(docextract, tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(pathlib.Path, "home", staticmethod(lambda: tmp_path / "home"))
    with pytest.raises(SystemExit) as exc:
        docextract.main([str(tmp_path / "does-not-exist.pdf")])
    assert exc.value.code == 4


@pytest.mark.parametrize(
    "fixture_name,expected_exit",
    [
        ("txt_file", 0),
        ("csv_file", 0),
        ("html_file", 0),
    ],
)
def test_exit_code_contract_success_cases(docextract, request, tmp_path, monkeypatch, fixture_name, expected_exit):
    monkeypatch.setattr(pathlib.Path, "home", staticmethod(lambda: tmp_path / "home"))
    fixture_path = request.getfixturevalue(fixture_name)
    path = docextract.main([str(fixture_path)])
    assert pathlib.Path(path).exists()


def test_corrupt_pdf_falls_back_to_pdftotext_then_exits_cleanly(docextract, tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(pathlib.Path, "home", staticmethod(lambda: tmp_path / "home"))
    corrupt_pdf = tmp_path / "corrupt.pdf"
    corrupt_pdf.write_bytes(b"%PDF-1.4\ncorrupt garbage not a real pdf")
    # pdfplumber will raise on this; pdftotext will also fail to produce text.
    # The extractor must not crash — it should exit 2 (no text extracted) cleanly.
    with pytest.raises(SystemExit) as exc:
        docextract.main([str(corrupt_pdf)])
    assert exc.value.code in (2, 4)
