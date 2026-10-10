"""The exported LV grid portfolio.

`data/lv_grids/lines.csv` and `substations.csv` are written once from
`tech-selection/data/raw/lv_grids.mat` by `tools/export_lv_grids.m`
(the .mat holds MATLAB table objects that nothing else can read). Both files
carry the patched line and transformer parameters of the MATLAB pipelines.

lines.csv      one row per LV line segment
    network_id, from, to, line, length_m, r_ohm_km, x_ohm_km, ampacity_a,
    plmax_kw, qlmax_kvar, pg_kw, section_mm2, material, kind
    plmax/qlmax: fuse-rated peak of the connection at the `to` node (3-phase);
    pg_kw: existing PV at the `to` node. Parallel branches into the same node
    repeat the node's values, so always deduplicate on (network_id, to).
substations.csv one row per MV/LV substation element
    network_id, from, to, object (T... transformer, SW... switch), on_off,
    r_pu, x_pu, rated_kva, from_kv, to_kv
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import pandas as pd

from .config import DATA_DIR

LINE_STR_COLS = {"network_id": str, "from": str, "to": str, "material": str, "kind": str}
SUB_STR_COLS = {"network_id": str, "from": str, "to": str, "object": str}


@dataclass
class Portfolio:
    lines: pd.DataFrame
    subs: pd.DataFrame

    @property
    def ids(self) -> list[str]:
        return list(self.lines["network_id"].unique())

    def network(self, network_id: str) -> tuple[pd.DataFrame, pd.DataFrame]:
        """(lines, substation rows) of one network."""
        if network_id not in self._line_groups:
            raise KeyError(f"unknown network {network_id}")
        return self._line_groups[network_id], self._sub_groups.get(network_id, self.subs.iloc[0:0])

    def __post_init__(self):
        self._line_groups = {k: g for k, g in self.lines.groupby("network_id", sort=False)}
        self._sub_groups = {k: g for k, g in self.subs.groupby("network_id", sort=False)}

    def nodal_ratings(self) -> pd.DataFrame:
        """One row per (network_id, to) node: fuse-rated peak and existing PV."""
        return self.lines.drop_duplicates(["network_id", "to"])[
            ["network_id", "to", "plmax_kw", "qlmax_kvar", "pg_kw"]].reset_index(drop=True)


def load_portfolio(data_dir: Path | str | None = None) -> Portfolio:
    d = Path(data_dir) if data_dir else DATA_DIR / "lv_grids"
    lines = pd.read_csv(d / "lines.csv", dtype=LINE_STR_COLS)
    subs = pd.read_csv(d / "substations.csv", dtype=SUB_STR_COLS)
    return Portfolio(lines, subs)


def network_number(network_id: str) -> int:
    """LV_Grid_101 -> 101 (the DSO's node id of the substation)."""
    return int("".join(ch for ch in network_id if ch.isdigit()))


def parse_ids(spec: str | list[str]) -> list[str]:
    """Comma-separated ids or bare numbers -> ['LV_Grid_<n>', ...]."""
    items = spec.split(",") if isinstance(spec, str) else list(spec)
    ids = []
    for s in items:
        s = s.strip()
        if not s:
            continue
        ids.append(f"LV_Grid_{s}" if s.isdigit() else s)
    return ids


def select_networks(portfolio: Portfolio, selection: str | list[str] | None) -> list[str]:
    """'all' / None -> every network; a comma-separated string or list -> those ids
    (bare numbers are accepted and prefixed with LV_Grid_)."""
    if selection is None or (isinstance(selection, str) and selection.lower() == "all"):
        return portfolio.ids
    ids = parse_ids(selection)
    if not ids:
        raise ValueError("no networks selected")
    known = set(portfolio.ids)
    unknown = [s for s in ids if s not in known]
    if unknown:
        raise KeyError(f"unknown network id(s): {', '.join(unknown)}")
    return ids
