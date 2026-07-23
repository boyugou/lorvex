"""Shared parser for script/app_metadata.sh static key/value metadata."""

from __future__ import annotations

import shlex
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
METADATA_PATH = ROOT / "script" / "app_metadata.sh"


def load_metadata(path: Path = METADATA_PATH) -> dict[str, str]:
    metadata: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if not key.isidentifier():
            continue
        parsed = shlex.split(value, comments=False, posix=True)
        metadata[key] = parsed[0] if parsed else ""
    return metadata
