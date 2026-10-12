"""The exported LV grid portfolio (../data/lv_grids, written once from
lv_grids.mat by data/tools/export_lv_grids.m). Same loader as lv-screening's."""
from __future__ import annotations

from pathlib import Path

import pandas as pd

from .config import DATA_DIR


def network_number(network_id: str) -> int:
    """LV_Grid_101 -> 101 (the DSO's node id of the substation)."""
    return int("".join(ch for ch in network_id if ch.isdigit()))


def parse_ids(spec: str | list[str]) -> list[str]:
    items = spec.split(",") if isinstance(spec, str) else list(spec)
    return [f"LV_Grid_{s.strip()}" if s.strip().isdigit() else s.strip() for s in items if s.strip()]


def load_lines(data_dir: Path | None = None) -> pd.DataFrame:
    d = Path(data_dir) if data_dir else DATA_DIR / "lv_grids"
    return pd.read_csv(d / "lines.csv", dtype={"network_id": str, "from": str, "to": str, "material": str, "kind": str})


def nodal_ratings(lines: pd.DataFrame) -> pd.DataFrame:
    """One row per (network_id, node): fuse-rated peak P/Q and existing PV of the
    node (parallel branches into a node repeat its values, hence the dedup)."""
    return (lines.drop_duplicates(["network_id", "to"])[["network_id", "to", "plmax_kw", "qlmax_kvar", "pg_kw"]]
            .rename(columns={"to": "node"}).reset_index(drop=True))
