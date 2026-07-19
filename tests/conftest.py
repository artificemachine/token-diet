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


def make_minimal_pdf(text: str) -> bytes:
    """Build a byte-exact, single-page PDF containing `text`, no external deps.

    No PDF-writing library (reportlab/fpdf/pypdf) is installed in this repo's
    Python env — hand-rolling the PDF structure with computed xref offsets is
    the only dependency-free way to produce a fixture pdfplumber can parse.
    """
    esc = text.replace("\\", r"\\").replace("(", r"\(").replace(")", r"\)")
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 4 0 R >> >> "
        b"/MediaBox [0 0 612 792] /Contents 5 0 R >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    stream_content = ("BT /F1 24 Tf 100 700 Td (%s) Tj ET" % esc).encode("latin-1")
    objects.append(
        b"<< /Length %d >>\nstream\n" % len(stream_content) + stream_content + b"\nendstream"
    )

    buf = bytearray(b"%PDF-1.4\n")
    offsets = [0]
    for i, obj in enumerate(objects, start=1):
        offsets.append(len(buf))
        buf += ("%d 0 obj\n" % i).encode()
        buf += obj
        buf += b"\nendobj\n"
    xref_offset = len(buf)
    buf += ("xref\n0 %d\n" % (len(objects) + 1)).encode()
    buf += b"0000000000 65535 f \n"
    for off in offsets[1:]:
        buf += ("%010d 00000 n \n" % off).encode()
    buf += b"trailer\n"
    buf += ("<< /Size %d /Root 1 0 R >>\n" % (len(objects) + 1)).encode()
    buf += b"startxref\n"
    buf += ("%d\n" % xref_offset).encode()
    buf += b"%%EOF"
    return bytes(buf)


@pytest.fixture
def one_page_pdf(tmp_path):
    """A generated single-page PDF containing the text 'HELLO PLAN'."""
    pdf_path = tmp_path / "sample.pdf"
    pdf_path.write_bytes(make_minimal_pdf("HELLO PLAN"))
    return pdf_path
