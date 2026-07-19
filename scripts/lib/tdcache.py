"""tdcache.py — hash-keyed cache-path helper shared by docextract and ctxwarn."""
import hashlib
import pathlib

CACHE_ROOT = "token-diet"


def cache_dir(subdir: str) -> pathlib.Path:
    """Return `~/.cache/token-diet/<subdir>/`, creating it if needed."""
    d = pathlib.Path.home() / ".cache" / CACHE_ROOT / subdir
    d.mkdir(parents=True, exist_ok=True)
    return d


def cache_path(
    src: pathlib.Path,
    subdir: str = "extract",
    suffix: str = ".md",
    key_by_mtime: bool = True,
) -> pathlib.Path:
    """Return a hash-keyed cache path for `src` under `~/.cache/token-diet/<subdir>/`.

    By default the hash includes the source's absolute path AND its mtime,
    so an edited file gets a fresh cache entry while an unchanged file reuses
    its cache — correct for extract-style caches (docextract: re-extract a
    PDF whose content changed since last extraction).

    Set `key_by_mtime=False` to key the hash on abspath alone. Use this for
    STATE files that should persist across appends/modifications to the
    same logical source — e.g. ctxwarn's debounce band, where every transcript
    append would otherwise re-hash and reset the band to 0, breaking the
    once-per-band semantics.
    """
    abspath = str(src.resolve())
    if key_by_mtime:
        mtime = src.stat().st_mtime_ns if src.exists() else 0
        key_material = f"{abspath}:{mtime}"
    else:
        key_material = abspath
    key = hashlib.sha256(key_material.encode()).hexdigest()
    return cache_dir(subdir) / f"{key}{suffix}"
