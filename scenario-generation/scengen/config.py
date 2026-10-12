"""Paths and settings. Everything is relative to the scenario-generation folder."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent          # scenario-generation/
DATA_DIR = ROOT.parent / "data"                        # shared inputs of the repo
SCENARIOS_DIR = ROOT / "scenarios"                     # configurations (tracked)
OUTPUT_DIR = ROOT / "output"                           # generated injections (ignored)
CONFIG_FILE = ROOT / "config.json"


def load_config(path: Path | str | None = None) -> dict:
    """config.json without the '_...' comment keys."""
    with open(Path(path) if path else CONFIG_FILE) as f:
        return _strip(json.load(f))


def _strip(obj):
    if isinstance(obj, dict):
        return {k: _strip(v) for k, v in obj.items() if not k.startswith("_")}
    return obj


def resolve(path: str | Path) -> Path:
    """Absolute path for a config entry (relative entries hang off ROOT)."""
    p = Path(path).expanduser()
    return p if p.is_absolute() else (ROOT / p).resolve()
