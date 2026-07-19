#!/usr/bin/env python3
"""docextract.py — extract PDF/csv/html/txt to plain text before it enters an LLM context.

Usage: docextract.py <file>
Prints the cache path on success (exit 0). Exit codes:
  2 — no text extractor for this file type (binary, or a supported-but-empty PDF)
  3 — needs markitdown (docx/pptx/xlsx/epub/odt/rtf) — not installed, deferred to v2
  4 — file does not exist
"""
import csv
import pathlib
import subprocess
import sys
from html.parser import HTMLParser

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import tdcache  # noqa: E402

EXTRACT = {".pdf", ".csv", ".html", ".htm", ".txt", ".md"}
NATIVE = {".png", ".jpg", ".jpeg", ".gif", ".webp"}
NEEDS_MARKITDOWN = {".docx", ".pptx", ".xlsx", ".epub", ".odt", ".rtf"}


class _TextExtractor(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []

    def handle_data(self, data):
        if data.strip():
            self.parts.append(data.strip())


def _extract_pdf(path: pathlib.Path) -> str:
    try:
        import pdfplumber

        with pdfplumber.open(path) as pdf:
            text = "\n".join(page.extract_text() or "" for page in pdf.pages)
        if text.strip():
            return text
    except Exception:
        pass

    try:
        result = subprocess.run(
            ["pdftotext", str(path), "-"], capture_output=True, text=True, timeout=30
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout
    except Exception:
        pass

    return ""


def _extract_csv(path: pathlib.Path) -> str:
    with open(path, newline="") as f:
        rows = list(csv.reader(f))
    if not rows:
        return ""
    header, *body = rows
    lines = [
        "| " + " | ".join(header) + " |",
        "| " + " | ".join(["---"] * len(header)) + " |",
    ]
    for row in body:
        lines.append("| " + " | ".join(row) + " |")
    return "\n".join(lines)


def _extract_html(path: pathlib.Path) -> str:
    parser = _TextExtractor()
    parser.feed(path.read_text(errors="replace"))
    return "\n".join(parser.parts)


def _extract_txt(path: pathlib.Path) -> str:
    return path.read_text(errors="replace")


_EXTRACTORS = {
    ".pdf": _extract_pdf,
    ".csv": _extract_csv,
    ".html": _extract_html,
    ".htm": _extract_html,
    ".txt": _extract_txt,
    ".md": _extract_txt,
}


def extract(path: pathlib.Path) -> str:
    fn = _EXTRACTORS.get(path.suffix.lower())
    return fn(path) if fn else ""


def main(argv):
    if not argv:
        print("Usage: docextract.py <file>", file=sys.stderr)
        sys.exit(1)

    src = pathlib.Path(argv[0])
    if not src.exists():
        sys.exit(4)

    suffix = src.suffix.lower()

    if suffix in NEEDS_MARKITDOWN:
        print(
            f"'{suffix}' extraction requires markitdown (not installed) — "
            "install it: pip install markitdown",
            file=sys.stderr,
        )
        sys.exit(3)

    if suffix in NATIVE or suffix not in EXTRACT:
        print(f"no text extractor for '{suffix}'", file=sys.stderr)
        sys.exit(2)

    dest = tdcache.cache_path(src)
    if dest.exists():
        return str(dest)

    text = extract(src)
    if not text.strip() and suffix == ".pdf":
        print(f"no text extractor produced output for '{src}'", file=sys.stderr)
        sys.exit(2)

    dest.write_text(text)
    return str(dest)


if __name__ == "__main__":
    result_path = main(sys.argv[1:])
    print(result_path)
    sys.exit(0)
