"""Paths and settings. Everything is relative to the injection-scenarios folder."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent          # injection-scenarios/
DATA_DIR = ROOT.parent / "data"                        # shared inputs of the repo
SCENARIOS_DIR = ROOT / "scenarios"                     # configurations (tracked)
OUTPUT_DIR = ROOT / "output"                           # generated injections (ignored): output/<name>/<level>/
CONFIG_FILE = ROOT / "config.json"

# The products of a scenario, one folder each, named by the Swiss network level (Netzebene / niveau de réseau) of
# the point where the series are injected.
LEVELS = {
    "nl7": "LV connections: per-connection daily series and per-network yearly sums",
    "nl4": "HV/MV substations (65/16 kV): expected series per substation, the sum of the LV networks it feeds",
}
DEFAULT_LEVEL = "nl7"


def output_folder(name: str, level: str = DEFAULT_LEVEL) -> Path:
    """output/<name>/<level>/: one product of a generated scenario."""
    if level not in LEVELS:
        raise ValueError(f"unknown level '{level}'; known: {', '.join(LEVELS)}")
    return OUTPUT_DIR / name / level


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
