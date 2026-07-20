#!/usr/bin/env python3
"""tdconfig.py — safe read/modify/write for the AI-host config files token-diet mutates.

token-diet edits config files it does not own: ~/.claude/settings.json,
claude_desktop_config.json, opencode.json, ~/.gemini/settings.json, and others.
Corrupting one of those breaks the user's editor, not just token-diet, so every
mutation here is atomic and every failure is loud.

Two failure modes this module exists to prevent, both found in the shipped
installer on 2026-07-20:

1. Truncate-then-fail. `open(path, "w")` truncates immediately, before the new
   content is serialized. A crash, a full disk, or a serialization error
   between the open and the write leaves a zero-byte config behind. The user's
   settings are gone and nothing says so.

2. Silent swallow. Wrapping that in `except Exception: pass` means the failure
   is invisible: the installer reports success, the config is empty, and the
   next thing to break looks unrelated.

`atomic_write_json` writes to a sibling temp file, fsyncs it, then `os.replace`s
it over the target. os.replace is atomic on POSIX and on Windows, so a reader
sees either the entire old file or the entire new one, never a partial write.
"""

from __future__ import annotations

import json
import os
import pathlib
import shutil
import sys
import tempfile
import time

__all__ = [
    "ConfigError",
    "atomic_write_json",
    "atomic_write_text",
    "backup",
    "load_json",
    "update_json",
]


class ConfigError(Exception):
    """Raised when a config file cannot be read or written safely."""


def backup(path: os.PathLike | str) -> pathlib.Path | None:
    """Copy `path` alongside itself as `<name>.bak-token-diet-<epoch>`.

    Returns the backup path, or None if the source does not exist. Uses copy2
    so mode and mtime survive. Backups are taken on the success path, before a
    mutation, not only when the input is already corrupt -- a backup you only
    take once the file is broken is not a backup.
    """
    p = pathlib.Path(path)
    if not p.exists():
        return None
    dest = p.with_name(f"{p.name}.bak-token-diet-{int(time.time())}")
    shutil.copy2(p, dest)
    return dest


def atomic_write_text(path: os.PathLike | str, text: str) -> None:
    """Write `text` to `path` atomically.

    The temp file is created in the same directory as the target so that
    os.replace stays within one filesystem; a cross-device replace is not
    atomic and would raise.
    """
    p = pathlib.Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)

    fd, tmp = tempfile.mkstemp(dir=str(p.parent), prefix=f".{p.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        # Preserve the original mode; mkstemp creates 0600, which would silently
        # tighten permissions on a config the user expects to stay readable.
        if p.exists():
            os.chmod(tmp, p.stat().st_mode & 0o7777)
        os.replace(tmp, p)
    except Exception:
        # Never leave the temp file behind on failure. The target is untouched
        # because os.replace either completed or never ran.
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def atomic_write_json(path: os.PathLike | str, data, indent: int = 2) -> None:
    """Serialize `data` to JSON and write it to `path` atomically.

    Serialization happens fully in memory before anything touches the target,
    so a non-serializable value raises without having modified the file.
    """
    text = json.dumps(data, indent=indent) + "\n"
    atomic_write_text(path, text)


def load_json(path: os.PathLike | str, *, missing_ok: bool = True):
    """Load JSON from `path`.

    Returns {} when the file is absent and `missing_ok` is set. Raises
    ConfigError on malformed JSON -- callers must decide whether to abort or
    skip that host, and they cannot decide if the error is hidden from them.
    """
    p = pathlib.Path(path)
    if not p.exists():
        if missing_ok:
            return {}
        raise ConfigError(f"{p}: does not exist")
    try:
        with open(p, encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        raise ConfigError(f"{p}: malformed JSON ({e})") from e
    except OSError as e:
        raise ConfigError(f"{p}: unreadable ({e})") from e


def update_json(path: os.PathLike | str, mutate, *, make_backup: bool = True) -> bool:
    """Read `path`, apply `mutate(data)`, write the result back atomically.

    `mutate` receives the parsed structure and may edit it in place or return a
    replacement. Returns True when the file was rewritten, False when `mutate`
    reported no change by returning False.

    Raises ConfigError on malformed input. Callers handle it; nothing is
    silently skipped.
    """
    data = load_json(path)
    result = mutate(data)
    if result is False:
        return False
    if result is not None:
        data = result
    if make_backup:
        backup(path)
    atomic_write_json(path, data)
    return True


def _cli(argv: list[str]) -> int:
    """`tdconfig.py verify <file>...` — exit non-zero if any file is bad JSON.

    Used by tests and by install.sh to check a config before mutating it.
    """
    if len(argv) < 2 or argv[0] != "verify":
        print("usage: tdconfig.py verify <file>...", file=sys.stderr)
        return 2
    bad = 0
    for target in argv[1:]:
        try:
            load_json(target, missing_ok=False)
        except ConfigError as e:
            print(f"{e}", file=sys.stderr)
            bad = 1
    return bad


if __name__ == "__main__":
    sys.exit(_cli(sys.argv[1:]))
