"""Settings and paths.

Everything is relative to the lv-screening folder (the parent of this
package), so commands work from any current directory.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent          # lv-screening/
CONFIG_FILE = ROOT / "config.json"
DATA_DIR = ROOT.parent / "data"                        # shared inputs of the repo
RESULTS_DIR = ROOT / "results"
SCENARIO_OUTPUT = ROOT.parent / "scenario-generation" / "output"   # generated scenarios


def load_config(path: Path | str | None = None) -> dict:
    """Read config.json (keys starting with '_' are comments and dropped)."""
    path = Path(path) if path else CONFIG_FILE
    with open(path) as f:
        cfg = json.load(f)
    return _strip_comments(cfg)


def _strip_comments(obj):
    if isinstance(obj, dict):
        return {k: _strip_comments(v) for k, v in obj.items() if not k.startswith("_")}
    return obj


def resolve(path: str | Path) -> Path:
    """Absolute path for a config entry (relative entries hang off ROOT)."""
    p = Path(path).expanduser()
    return p if p.is_absolute() else (ROOT / p).resolve()


def kw_per_pu(cfg: dict) -> float:
    """Three-phase kW represented by 1 pu of single-phase power."""
    return 3 * cfg["per_unit"]["Sb_VA"] / 1000.0


def base_current_A(cfg: dict) -> float:
    return cfg["per_unit"]["Sb_VA"] / cfg["per_unit"]["Vb_V"]


def base_impedance_ohm(cfg: dict) -> float:
    return cfg["per_unit"]["Vb_V"] ** 2 / cfg["per_unit"]["Sb_VA"]
