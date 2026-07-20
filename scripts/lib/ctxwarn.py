#!/usr/bin/env python3
"""ctxwarn.py — estimate a session transcript's token size and warn once per threshold band.

Usage: ctxwarn.py --transcript <jsonl>
Always exits 0 — a warn arm must never fail a turn. Prints a warning line to
stdout when the estimate crosses (or re-crosses) a `.token-budget` `ctx_threshold`
band (default 100000, matching global Gate 15); silent otherwise.
"""
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import tdcache  # noqa: E402

try:
    import tiktoken
except ImportError:
    tiktoken = None

RED = "\033[0;31m"
NC = "\033[0m"

DEFAULT_THRESHOLD = 100000


def _walk(obj):
    if isinstance(obj, dict):
        for key, value in obj.items():
            if isinstance(value, str) and key in ("text", "content"):
                yield value
            else:
                yield from _walk(value)
    elif isinstance(obj, list):
        for item in obj:
            yield from _walk(item)


def _iter_text(jsonl_path: pathlib.Path):
    with open(jsonl_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            yield from _walk(obj)


def estimate_tokens(jsonl_path: pathlib.Path) -> int:
    texts = list(_iter_text(jsonl_path))
    total_chars = sum(len(t) for t in texts)
    if tiktoken is not None:
        try:
            enc = tiktoken.get_encoding("cl100k_base")
            return sum(len(enc.encode(t)) for t in texts)
        except Exception:
            pass
    return total_chars // 4


def find_budget_file() -> pathlib.Path | None:
    """Walk up from cwd toward $HOME looking for .token-budget (mirrors the bash helper)."""
    home = pathlib.Path.home().resolve()
    d = pathlib.Path.cwd().resolve()
    while True:
        candidate = d / ".token-budget"
        if candidate.exists():
            return candidate
        if d == home:
            break
        try:
            d.relative_to(home)
        except ValueError:
            break
        d = d.parent
    return None


def read_threshold(default: int = DEFAULT_THRESHOLD) -> int:
    budget_file = find_budget_file()
    if budget_file is None:
        return default
    try:
        data = json.loads(budget_file.read_text())
    except Exception:
        return default
    return int(data.get("ctx_threshold", default))


def should_warn(estimate: int, threshold: int, state_path: pathlib.Path) -> bool:
    """True once per distinct threshold band; debounces repeat calls in the same band."""
    if threshold <= 0:
        band = 0
    else:
        band = estimate // threshold
    if band == 0:
        return False

    last_band = 0
    if state_path.exists():
        try:
            last_band = int(state_path.read_text().strip())
        except (ValueError, OSError):
            last_band = 0

    if band == last_band:
        return False

    state_path.write_text(str(band))
    return True


def main(argv):
    transcript = None
    i = 0
    while i < len(argv):
        if argv[i] == "--transcript" and i + 1 < len(argv):
            transcript = argv[i + 1]
            i += 2
        else:
            i += 1

    if not transcript:
        sys.exit(0)

    jsonl_path = pathlib.Path(transcript)
    if not jsonl_path.exists():
        sys.exit(0)

    estimate = estimate_tokens(jsonl_path)
    threshold = read_threshold()
    # key_by_mtime=False: the debounce state must persist across transcript
    # appends. Every PostToolUse fires on an actively-growing transcript whose
    # mtime_ns changes on each write — with the default mtime-based key, every
    # call would hash to a fresh state file, band would reset to 0, and the
    # once-per-band semantics would silently break (caught live: 133 stale
    # .band files all containing "1" had accumulated from this very bug).
    state_path = tdcache.cache_path(
        jsonl_path, subdir="ctxwarn", suffix=".band", key_by_mtime=False
    )

    if should_warn(estimate, threshold, state_path):
        k = estimate // 1000
        print(f"{RED}⚠️ Context ~{k}k tokens. Consider /compact or a fresh session.{NC}")

    sys.exit(0)


if __name__ == "__main__":
    main(sys.argv[1:])
