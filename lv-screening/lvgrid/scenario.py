"""Scenario generation: SFOE scenario -> a frozen, inspectable scenario folder.

    scenarios/<name>/
        scenario.json     SFOE parameters, regional totals, profile settings
                          (PV day, EV charging, demand model), totals allocated
        allocation.csv    network_id, node, plmax_kw, pv_kwp, ev_count   (nodes with a fuse rating)
        networks.csv      per network: nominal demand, PV kWp, EV count
        pv_day.csv        the normalised PV day used (step, hour, pv_norm)

Allocation (port of the MATLAB allocate_PV_EV_SFOE): national PV [MW] and EVs
of the scenario are scaled to Sion+Sierre by population, split between networks
in proportion to their fuse-rated peak (sum of PLmax over the nodes) and within
a network in proportion to each node's PLmax; EVs are integers (largest
remainder at both levels). The PV day is the real day of the yearly profile
closest to the mean shape of the chosen season.

A scenario folder is the hand-over point: the screening (and, through
`readtable`, the MATLAB MILP) consume it as is, so an edited allocation.csv is
a valid custom scenario.
"""
from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd

from . import __version__
from .config import ROOT, resolve
from .data import Portfolio
from .network import Network
from .profiles import load_pv_year, pv_representative_day

SCENARIOS_DIR = ROOT / "scenarios"


@dataclass
class Scenario:
    name: str
    meta: dict                 # everything in scenario.json
    allocation: pd.DataFrame   # network_id, node, plmax_kw, pv_kwp, ev_count
    pv_day: np.ndarray         # [S] per unit of installed kWp

    @property
    def step_min(self) -> int:
        return int(self.meta["step_min"])

    @property
    def demand(self) -> dict:
        return self.meta["demand"]

    @property
    def ev(self) -> dict:
        return self.meta["ev"]

    def apply(self, net: Network) -> None:
        """Fill net.pv_kwp / net.ev_count (3-phase kWp, count) for this network's nodes."""
        net.pv_kwp[:] = 0.0
        net.ev_count[:] = 0
        rows = self.allocation[self.allocation["network_id"] == net.id]
        index = {name: i for i, name in enumerate(net.node_names)}
        for node, pv, ev in zip(rows["node"], rows["pv_kwp"], rows["ev_count"]):
            i = index.get(node)
            if i is not None and i > 0:
                net.pv_kwp[i] = pv
                net.ev_count[i] = ev

    def provenance(self) -> dict:
        """What a run records about the scenario it used."""
        keys = ("sfoe", "year", "population_ratio", "pv_region_kwp", "ev_region", "pv_date", "pv_allocated_kwp", "ev_allocated")
        return {"name": self.name, **{k: self.meta[k] for k in keys if k in self.meta},
                "allocation_sha256": self.meta.get("allocation_sha256")}


def largest_remainder(total: int, weights: np.ndarray) -> np.ndarray:
    """Integer split of `total` proportional to `weights`, summing exactly to total."""
    w = np.asarray(weights, float)
    out = np.zeros(len(w), int)
    if total <= 0 or w.sum() <= 0:
        return out
    frac = total * w / w.sum()
    out = np.floor(frac).astype(int)
    missing = int(total - out.sum())
    if missing > 0:
        order = np.argsort(-(frac - out), kind="stable")
        out[order[:missing]] += 1
    return out


def allocate(portfolio: Portfolio, sc: dict) -> tuple[pd.DataFrame, dict]:
    """PV kWp and EV count per (network, node) for one SFOE scenario dict."""
    pop_ratio = sc["population_sion_sierre"] / sc["population_national"]
    pv_region_kwp = sc["PV_national_MW"] * 1e3 * pop_ratio
    ev_region = int(round(sc["EV_national_thousands"] * 1e3 * pop_ratio))

    nodes = portfolio.nodal_ratings()[["network_id", "to", "plmax_kw"]].rename(columns={"to": "node"})
    per_net = nodes.groupby("network_id", sort=False)["plmax_kw"].sum()
    pv_net = pv_region_kwp * per_net / per_net.sum()
    ev_net = pd.Series(largest_remainder(ev_region, per_net.to_numpy()), index=per_net.index)

    nodes["pv_kwp"] = 0.0
    nodes["ev_count"] = 0
    for nid, g in nodes.groupby("network_id", sort=False):
        w = g["plmax_kw"].to_numpy()
        active = w > 0
        if not active.any():
            continue
        pv = np.zeros(len(g))
        pv[active] = pv_net[nid] * w[active] / w[active].sum()
        ev = np.zeros(len(g), int)
        ev[active] = largest_remainder(int(ev_net[nid]), w[active])
        nodes.loc[g.index, "pv_kwp"] = pv
        nodes.loc[g.index, "ev_count"] = ev
    nodes = nodes[nodes["plmax_kw"] > 0].reset_index(drop=True)
    totals = {"population_ratio": pop_ratio, "pv_region_kwp": pv_region_kwp, "ev_region": ev_region,
              "pv_allocated_kwp": float(nodes["pv_kwp"].sum()), "ev_allocated": int(nodes["ev_count"].sum())}
    return nodes, totals


def build_scenario(portfolio: Portfolio, cfg: dict, sfoe_key: str, name: str | None = None) -> Scenario:
    if sfoe_key not in cfg["scenarios"]:
        raise KeyError(f"unknown SFOE scenario {sfoe_key}; known: {', '.join(cfg['scenarios'])}")
    sc = cfg["scenarios"][sfoe_key]
    allocation, totals = allocate(portfolio, sc)
    pcfg = cfg["pv"]
    step_min = cfg["time"]["step_min"]
    pv_day, pv_date, day_idx = pv_representative_day(load_pv_year(resolve(pcfg["file"])), pcfg["series"], pcfg["season"], step_min)
    pv_day = pv_day * pcfg.get("scale", 1.0)
    meta = {"name": name or sfoe_key, "sfoe": sfoe_key, **sc, **totals,
            "pv": {**pcfg, "date": pv_date, "day_index": day_idx}, "pv_date": pv_date,
            "ev": dict(cfg["ev"]), "demand": {"demand_factor": cfg["demand_factor"], **cfg["demand"]},
            "step_min": step_min, "n_networks": int(allocation["network_id"].nunique()), "n_nodes": len(allocation),
            "created": datetime.now().isoformat(timespec="seconds"), "lvgrid_version": __version__}
    return Scenario(meta["name"], meta, allocation, pv_day)


def scenario_dir(name: str) -> Path:
    return SCENARIOS_DIR / name


def save_scenario(sc: Scenario, folder: Path | None = None) -> Path:
    folder = Path(folder) if folder else scenario_dir(sc.name)
    folder.mkdir(parents=True, exist_ok=True)
    sc.allocation.to_csv(folder / "allocation.csv", index=False)                  # full precision: it is read back
    sc.meta["allocation_sha256"] = hashlib.sha256((folder / "allocation.csv").read_bytes()).hexdigest()[:12]
    nets = sc.allocation.groupby("network_id", sort=False).agg(n_nodes=("node", "size"), plmax_sum_kw=("plmax_kw", "sum"),
                                                                pv_kwp=("pv_kwp", "sum"), ev_count=("ev_count", "sum")).reset_index()
    nets.insert(3, "nominal_demand_kw", nets["plmax_sum_kw"] * sc.demand["demand_factor"])
    nets.to_csv(folder / "networks.csv", index=False, float_format="%.6g")
    hours = np.arange(len(sc.pv_day)) * sc.step_min / 60.0
    pd.DataFrame({"step": np.arange(len(sc.pv_day)), "hour": hours, "pv_norm": sc.pv_day}).to_csv(folder / "pv_day.csv", index=False)
    with open(folder / "scenario.json", "w") as f:
        json.dump(sc.meta, f, indent=2, default=str)
    return folder


def load_scenario(folder: Path | str) -> Scenario:
    folder = Path(folder)
    if not (folder / "scenario.json").exists():
        raise FileNotFoundError(f"no scenario in {folder} (run `python -m lvgrid scenario --scenario <sfoe key>`)")
    with open(folder / "scenario.json") as f:
        meta = json.load(f)
    allocation = pd.read_csv(folder / "allocation.csv", dtype={"network_id": str, "node": str})
    sha = hashlib.sha256((folder / "allocation.csv").read_bytes()).hexdigest()[:12]
    if sha != meta.get("allocation_sha256"):
        meta["allocation_sha256"] = sha + " (edited after creation)"
    pv_day = pd.read_csv(folder / "pv_day.csv")["pv_norm"].to_numpy(float)
    return Scenario(meta.get("name", folder.name), meta, allocation, pv_day)


def get_scenario(portfolio: Portfolio, cfg: dict, name: str, verbose: bool = True) -> Scenario:
    """The scenario folder `name` if it exists, else built from the SFOE key `name` and saved."""
    folder = scenario_dir(name)
    if (folder / "scenario.json").exists():
        return load_scenario(folder)
    sc = build_scenario(portfolio, cfg, name)
    save_scenario(sc)
    if verbose:
        print(f"scenario {name} built and saved to {folder}")
    return sc
