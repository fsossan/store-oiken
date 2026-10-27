"""A generated scenario (output of ../injection-scenarios) as the screening sees it.

    <folder>/scenario.json, allocation.csv, daily/<network_id>.csv  (see injection-scenarios/README.md)

`--scenario NAME` resolves to ../injection-scenarios/output/NAME; a path works too.
"""
from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd

from .config import SCENARIO_OUTPUT
from .injections import DEFAULT_STREAMS, Injections, check_streams, default_cases, read_daily_csv, zero_injections
from .network import Network


def scenario_folder(name_or_path: str | Path) -> Path:
    p = Path(name_or_path)
    if (p / "scenario.json").exists():
        return p
    return SCENARIO_OUTPUT / str(name_or_path)


@dataclass
class Scenario:
    name: str
    folder: Path
    meta: dict                 # scenario.json
    allocation: pd.DataFrame   # network_id, node, plmax_kw, qlmax_kvar + the models' columns (pv_kwp, ev_count, ...)

    @property
    def step_min(self) -> int:
        return int(self.meta["step_min"])

    @property
    def steps(self) -> int:
        return int(self.meta["days"]) * 24 * 60 // self.step_min

    @property
    def streams(self) -> dict[str, str]:
        """Stream name -> 'load' | 'generation', in model order (outputs older than the stream list: demand, pv, ev)."""
        return check_streams(self.meta.get("streams", DEFAULT_STREAMS))

    def default_cases(self) -> list[str]:
        return default_cases(self.streams)

    def apply(self, net: Network) -> None:
        """Fill net.pv_kwp / net.ev_count (3-phase kWp, count) for this network's nodes."""
        net.pv_kwp[:] = 0.0
        net.ev_count[:] = 0
        rows = self.allocation[self.allocation["network_id"] == net.id]
        index = {name: i for i, name in enumerate(net.node_names)}
        zero = pd.Series(0, index=rows.index)
        for node, pv, ev in zip(rows["node"], rows.get("pv_kwp", zero), rows.get("ev_count", zero)):
            i = index.get(node)
            if i is not None and i > 0:
                net.pv_kwp[i] = pv
                net.ev_count[i] = ev

    def injections(self, net: Network) -> Injections:
        """The daily injections of one network from daily/<id>.csv (zeros if it has no rated node)."""
        path = self.folder / "daily" / f"{net.id}.csv"
        if path.exists():
            return read_daily_csv(path, net, self.streams)
        return zero_injections(np.arange(self.steps) * self.step_min / 60.0, net.n_nodes, self.streams)

    def provenance(self) -> dict:
        keys = ("sfoe", "population_ratio", "pv_region_kwp", "ev_region", "pv_date", "pv_allocated_kwp", "ev_allocated",
                "step_min", "days", "allocation_sha256", "config_sha256", "created")
        sha = hashlib.sha256((self.folder / "allocation.csv").read_bytes()).hexdigest()[:12]
        return {"name": self.name, "folder": str(self.folder), **{k: self.meta[k] for k in keys if k in self.meta},
                "allocation_edited_after_generation": sha != self.meta.get("allocation_sha256")}


def load_scenario(name_or_path: str | Path) -> Scenario:
    folder = scenario_folder(name_or_path)
    if not (folder / "scenario.json").exists():
        raise FileNotFoundError(f"no generated scenario in {folder}: run `python generate_scenario.py generate <name>` in injection-scenarios/")
    with open(folder / "scenario.json") as f:
        meta = json.load(f)
    allocation = pd.read_csv(folder / "allocation.csv", dtype={"network_id": str, "node": str})
    return Scenario(meta.get("name", folder.name), folder, meta, allocation)
