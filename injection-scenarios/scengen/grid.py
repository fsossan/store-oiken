"""The grid: the LV portfolio of the region and the region's population. Fixed inputs, read once.

    connections   one row per connection point with a fuse rating: network_id, node, plmax_kw, qlmax_kvar
                  (the fuse-rated peak P/Q of the connection, 3-phase)
    networks      one row per network with at least one such connection (index network_id, in file order):
                  connections (their number), plmax_kw (their sum), trafo_kva (rated kVA of the transformers),
                  hvmv (the HV/MV substation feeding the network; missing if it is not mapped)
    population    {year: residents of the region}, which scales national figures to the region

From ../data: lv_grids/lines.csv and substations.csv (written once from lv_grids.mat by data/tools/export_lv_grids.m),
lv_grids/region.json (name and population of the region) and mv/lv_to_hvmv.csv (`python -m lvgrid mv-map` in
../lv-screening). The scenario (scenario.py) holds no grid facts and the grid no assumptions.
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

import pandas as pd

from .config import DATA_DIR


@dataclass(frozen=True)
class Grid:
    name: str                           # the region, e.g. "Sion+Sierre"
    connections: pd.DataFrame
    networks: pd.DataFrame
    population: dict[int, int]

    @property
    def ids(self) -> list[str]:
        return list(self.networks.index)

    def population_share(self, year: int, national: float) -> float:
        """The region's share of the national population in `year` (scales the national SFOE figures)."""
        if year not in self.population:
            raise KeyError(f"no population of {self.name} for {year} in region.json (known: {', '.join(map(str, self.population))})")
        return self.population[year] / national


@lru_cache(maxsize=None)
def load_grid(data_dir: Path | None = None) -> Grid:
    """The grid of ../data (or of another folder laid out like it). Cached: treat the tables as read-only."""
    d = Path(data_dir) if data_dir else DATA_DIR
    lines = pd.read_csv(d / "lv_grids" / "lines.csv", usecols=["network_id", "to", "plmax_kw", "qlmax_kvar"],
                        dtype={"network_id": str, "to": str})
    nodes = lines.drop_duplicates(["network_id", "to"]).rename(columns={"to": "node"})    # parallel branches repeat the node
    connections = nodes[nodes["plmax_kw"] > 0].reset_index(drop=True)

    by_network = connections.groupby("network_id", sort=False)
    networks = pd.DataFrame({"connections": by_network.size(), "plmax_kw": by_network["plmax_kw"].sum()})
    subs = pd.read_csv(d / "lv_grids" / "substations.csv", dtype={"network_id": str})
    networks["trafo_kva"] = subs[subs["object"].str.startswith("T")].groupby("network_id")["rated_kva"].sum().reindex(networks.index)
    hvmv_file = d / "mv" / "lv_to_hvmv.csv"
    if hvmv_file.exists():
        hvmv = pd.read_csv(hvmv_file, dtype=str)
        networks["hvmv"] = hvmv[hvmv["status"] == "ok"].set_index("network_id")["hvmv"].reindex(networks.index)
    else:
        networks["hvmv"] = pd.NA

    region = json.loads((d / "lv_grids" / "region.json").read_text())
    return Grid(region["name"], connections, networks, {int(year): n for year, n in region["population"].items()})


def network_number(network_id: str) -> int:
    """LV_Grid_101 -> 101 (the DSO's node id of the substation)."""
    return int("".join(ch for ch in network_id if ch.isdigit()))


def parse_ids(spec: str | list[str]) -> list[str]:
    items = spec.split(",") if isinstance(spec, str) else list(spec)
    return [f"LV_Grid_{s.strip()}" if s.strip().isdigit() else s.strip() for s in items if s.strip()]
