"""Working-directory -> r3 logical-path mapping for xr3.

Pure logic (pathlib only) so it is unit-testable without r3/executor/pyyaml.
"""
from __future__ import annotations

import os
from pathlib import Path
from typing import Optional


class PathmapError(Exception):
    """Raised when a working directory cannot be mapped to an r3 path."""


def resolve_job_path(fs_path, config: dict, config_source: Optional[str] = None) -> str:
    """Map a working-directory path to its r3 logical path.

    Finds the `config['pathmap']['roots']` entry containing `fs_path` (the most
    specific / longest root wins), returns the path relative to that root, and
    applies the entry's optional `prefix`. Each root's `path` may use `~` and
    `$VARS`, which are expanded before matching. Raises PathmapError with an
    actionable message (naming `config_source`, if given) when no root matches,
    and also when `fs_path` resolves to a root itself (no job sub-path beneath it).
    """
    resolved = Path(fs_path).resolve()
    roots = (config.get("pathmap") or {}).get("roots") or []

    def _expand(p) -> Path:
        if not isinstance(p, str):
            raise PathmapError(f"pathmap root has a non-string `path`: {p!r}")
        return Path(os.path.expanduser(os.path.expandvars(p))).resolve()

    matches = []
    for entry in roots:
        root = _expand(entry["path"])
        if resolved == root or root in resolved.parents:
            matches.append((root, entry))

    if not matches:
        where = config_source or "your xr3 config"
        configured = [str(e["path"]) for e in roots] or "none"
        raise PathmapError(
            f"No pathmap root matches {resolved}.\n"
            f"Add its project root under `pathmap.roots` in {where} "
            f"(see CONTRACT.md). Configured roots: {configured}."
        )

    root, entry = max(matches, key=lambda m: len(str(m[0])))
    rel = resolved.relative_to(root)
    if str(rel) == ".":
        raise PathmapError(
            f"{resolved} is itself a pathmap root, not a job directory. "
            f"Run xr3 from inside a job directory beneath it."
        )
    prefix = entry.get("prefix")
    if prefix:
        rel = Path(prefix) / rel
    return str(rel)
