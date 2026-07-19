"""tdcache.py — hash-keyed cache-path helper shared by docextract and ctxwarn."""
import hashlib
import pathlib

CACHE_ROOT = "token-diet"


def cache_dir(subdir: str) -> pathlib.Path:
    """Return `~/.cache/token-diet/<subdir>/`, creating it if needed."""
    d = pathlib.Path.home() / ".cache" / CACHE_ROOT / subdir
    d.mkdir(parents=True, exist_ok=True)
    return d


def cache_path(src: pathlib.Path, subdir: str = "extract", suffix: str = ".md") -> pathlib.Path:
    """Return a hash-keyed cache path for `src` under `~/.cache/token-diet/<subdir>/`.

    The hash includes the source's absolute path and mtime, so an edited
    file gets a fresh cache entry while an unchanged file reuses its cache.
    """
    abspath = str(src.resolve())
    mtime = src.stat().st_mtime_ns if src.exists() else 0
    key = hashlib.sha256(f"{abspath}:{mtime}".encode()).hexdigest()
    return cache_dir(subdir) / f"{key}{suffix}"
