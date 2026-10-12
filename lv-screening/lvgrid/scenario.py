"""Scenarios: configuration -> generated injections (CSV) -> consumed by the screening.

    scenarios/<name>/
        config.json       stage 1: the scenario configuration (SFOE figures, horizon,
                          demand / PV / EV settings). Written by `new-scenario`, edited by hand.
        allocation.csv    stage 2 (`generate`): network_id, node, plmax_kw, qlmax_kvar, pv_kwp, ev_count
        networks.csv      per-network totals
        pv_day.csv        the normalised PV day used for the daily product
        daily/<network_id>.csv   per-node injections of the daily product (see injections.py)
        yearly/<network_id>.csv  per-network sums over the full year: time, demand_kw, demand_kvar, pv_kw, ev_kw
        scenario.json     provenance: totals, PV day, sizes, hash of allocation.csv, version, timing

Allocation (port of the MATLAB allocate_PV_EV_SFOE): national PV [MW] and EVs
of the scenario are scaled to Sion+Sierre by population, split between networks
in proportion to their fuse-rated peak (sum of PLmax over the nodes) and within
a network in proportion to each node's PLmax; EVs are integers (largest
remainder at both levels).

Time series: demand = demand_factor x fuse-rated peak times a synthetic
household day (demand model, per (network, day) seed); PV = kWp times the
normalised yearly profile; EV = per vehicle 11 kW blocks after a random
arrival (per (network, day) seed). The daily product is the yearly series on
the representative PV day (the real day closest to the season's mean shape),
so both products are consistent, and a day does not change when more days
are generated.
"""
from __future__ import annotations

import hashlib
import json
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd

from . import __version__
from .config import ROOT, resolve
from .data import Portfolio, network_number
from .injections import Injections, read_daily_csv, write_daily_csv
from .network import Network
from .profiles import ev_node_profiles, load_demand_model, load_pv_year, pv_representative_day, pv_year_series, sample_demand

SCENARIOS_DIR = ROOT / "scenarios"


# ------------------------------------------------------- stage 1: config --
def scenario_dir(name: str) -> Path:
    return SCENARIOS_DIR / name


def new_scenario_config(cfg: dict, sfoe_key: str, name: str | None = None) -> dict:
    if sfoe_key not in cfg["sfoe"]:
        raise KeyError(f"unknown SFOE scenario {sfoe_key}; known: {', '.join(cfg['sfoe'])}")
    d = cfg["scenario_defaults"]
    return {"name": name or sfoe_key, "sfoe": {"key": sfoe_key, **cfg["sfoe"][sfoe_key]},
            "time": d["time"], "demand": d["demand"], "pv": d["pv"], "ev": d["ev"]}


def write_scenario_config(scfg: dict, folder: Path | None = None) -> Path:
    folder = Path(folder) if folder else scenario_dir(scfg["name"])
    folder.mkdir(parents=True, exist_ok=True)
    with open(folder / "config.json", "w") as f:
        json.dump(scfg, f, indent=2)
    return folder / "config.json"


def load_scenario_config(name: str) -> dict:
    path = scenario_dir(name) / "config.json"
    if not path.exists():
        raise FileNotFoundError(f"{path} missing: create it with `python -m lvgrid new-scenario <sfoe key> --name {name}`")
    with open(path) as f:
        scfg = json.load(f)
    for key in ("sfoe", "time", "demand", "pv", "ev"):
        if key not in scfg:
            raise KeyError(f"{path}: missing block '{key}'")
    scfg["name"] = name
    return scfg


# --------------------------------------------------- stage 2: generation --
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


def allocate(portfolio: Portfolio, sfoe: dict) -> tuple[pd.DataFrame, dict]:
    """PV kWp and EV count per (network, node) with a fuse rating."""
    pop_ratio = sfoe["population_sion_sierre"] / sfoe["population_national"]
    pv_region_kwp = sfoe["PV_national_MW"] * 1e3 * pop_ratio
    ev_region = int(round(sfoe["EV_national_thousands"] * 1e3 * pop_ratio))

    nodes = portfolio.nodal_ratings()[["network_id", "to", "plmax_kw", "qlmax_kvar"]].rename(columns={"to": "node"})
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


def _block_average(x: np.ndarray, factor: int) -> np.ndarray:
    return x.reshape(-1, factor).mean(axis=1) if factor > 1 else x


def generate(portfolio: Portfolio, name: str, ids: list[str] | None = None, verbose: bool = True) -> "Scenario":
    """Stage 2: allocation + daily per-node injections + yearly per-network sums."""
    t0 = time.time()
    scfg = load_scenario_config(name)
    folder = scenario_dir(name)
    tcfg, dcfg, pcfg, ecfg = scfg["time"], scfg["demand"], scfg["pv"], scfg["ev"]
    step_min = int(tcfg["step_min"])
    S = 24 * 60 // step_min
    D = int(tcfg.get("days", 1))
    yearly = tcfg.get("yearly", {"enabled": False})
    allocation, totals = allocate(portfolio, scfg["sfoe"])

    pv_df = load_pv_year(resolve(pcfg["file"]))
    pv_year = pv_year_series(pv_df, pcfg["series"], step_min) * pcfg.get("scale", 1.0)      # [n_days x S]
    n_year = len(pv_year)
    pv_day, pv_date, k0 = pv_representative_day(pv_df, pcfg["series"], pcfg["season"], step_min)
    pv_day = pv_day * pcfg.get("scale", 1.0)
    model = load_demand_model(resolve(dcfg["model_file"]))
    if int(model["steps_per_day"]) != S:
        raise ValueError("demand model resolution differs from time.step_min")
    daily_days = [(k0 + i) % n_year for i in range(D)]
    days = list(range(n_year)) if yearly.get("enabled") else daily_days
    j_daily = [days.index(d) for d in daily_days]
    y_factor = int(yearly.get("step_min", step_min)) // step_min if yearly.get("enabled") else 1
    if yearly.get("enabled") and (S % y_factor or y_factor < 1):
        raise ValueError("yearly.step_min must be a multiple of time.step_min that divides the day")

    (folder / "daily").mkdir(parents=True, exist_ok=True)
    if yearly.get("enabled"):
        (folder / "yearly").mkdir(exist_ok=True)
        y_time = pv_df["time"].to_numpy()[::y_factor]
    ids = ids or portfolio.ids
    n_written = 0
    for i, nid in enumerate(ids, 1):
        if verbose and (i % 100 == 0 or i == len(ids)):
            print(f"[{i:4d}/{len(ids)}] {nid}", flush=True)
        rows = allocation[allocation["network_id"] == nid]
        if rows.empty:
            continue
        nodes = rows["node"].tolist()
        n = len(nodes)
        num = network_number(nid)
        nominal = dcfg["demand_factor"] * (rows["plmax_kw"].to_numpy() + 1j * rows["qlmax_kvar"].to_numpy())
        shape, _ = sample_demand(model, n, days, num + dcfg["seed_offset"])          # [n x D' x S]
        demand = shape * nominal[:, None, None]
        pv = pv_year[days][None, :, :] * rows["pv_kwp"].to_numpy()[:, None, None]       # [n x D' x S]
        ev = np.zeros((n, len(days), S))
        counts = rows["ev_count"].to_numpy()
        has_e = np.flatnonzero(counts > 0)
        for j, d in enumerate(days):
            if len(has_e):
                ev[has_e, j] = ev_node_profiles(counts[has_e], ecfg, step_min, np.random.default_rng([num + ecfg["seed_offset"], d]))
        # daily product: [T x n]
        sel = lambda a: a[:, j_daily, :].reshape(n, -1).T  # noqa: E731
        time_h = np.arange(D * S) * step_min / 60.0
        write_daily_csv(folder / "daily" / f"{nid}.csv", nodes, time_h, sel(demand.real), sel(demand.imag), sel(pv), sel(ev))
        if yearly.get("enabled"):
            agg = {"demand_kw": demand.real.sum(axis=0).ravel(), "demand_kvar": demand.imag.sum(axis=0).ravel(),
                   "pv_kw": pv.sum(axis=0).ravel(), "ev_kw": ev.sum(axis=0).ravel()}
            pd.DataFrame({"time": y_time, **{c: _block_average(v, y_factor) for c, v in agg.items()}}).to_csv(
                folder / "yearly" / f"{nid}.csv", index=False, float_format="%.5g")
        n_written += 1

    allocation.to_csv(folder / "allocation.csv", index=False)
    nets = allocation.groupby("network_id", sort=False).agg(n_nodes=("node", "size"), plmax_sum_kw=("plmax_kw", "sum"),
                                                            pv_kwp=("pv_kwp", "sum"), ev_count=("ev_count", "sum")).reset_index()
    nets.insert(3, "nominal_demand_kw", nets["plmax_sum_kw"] * dcfg["demand_factor"])
    nets.to_csv(folder / "networks.csv", index=False, float_format="%.6g")
    pd.DataFrame({"step": np.arange(S), "hour": np.arange(S) * step_min / 60.0, "pv_norm": pv_day}).to_csv(folder / "pv_day.csv", index=False)
    meta = {"name": name, "sfoe": scfg["sfoe"], **totals, "pv_date": pv_date, "pv_day_index": k0,
            "pv_series": pcfg["series"], "pv_season": pcfg["season"], "step_min": step_min, "days": D,
            "yearly": yearly, "n_networks": int(allocation["network_id"].nunique()), "n_nodes": len(allocation),
            "networks_written": n_written, "allocation_sha256": _sha(folder / "allocation.csv"),
            "config_sha256": _sha(folder / "config.json"), "created": datetime.now().isoformat(timespec="seconds"),
            "lvgrid_version": __version__, "seconds": round(time.time() - t0, 1)}
    with open(folder / "scenario.json", "w") as f:
        json.dump(meta, f, indent=2, default=str)
    if verbose:
        print(f"{name}: {scfg['sfoe']['key']} {scfg['sfoe'].get('year', '')}, population share {totals['population_ratio']:.2%}, "
              f"PV {totals['pv_allocated_kwp'] / 1e3:,.1f} MWp and {totals['ev_allocated']:,} EVs over {meta['n_networks']} networks / "
              f"{meta['n_nodes']} nodes; PV day {pv_date}; daily ({D} day) and "
              f"{'yearly (' + str(yearly.get('step_min', step_min)) + ' min)' if yearly.get('enabled') else 'no yearly'} files "
              f"for {n_written} networks -> {folder}  ({meta['seconds']} s)")
    return load_scenario(name)


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()[:12]


# ----------------------------------------------------- stage 3: consumer --
@dataclass
class Scenario:
    name: str
    meta: dict                 # scenario.json
    allocation: pd.DataFrame   # network_id, node, plmax_kw, qlmax_kvar, pv_kwp, ev_count

    @property
    def folder(self) -> Path:
        return scenario_dir(self.name)

    @property
    def step_min(self) -> int:
        return int(self.meta["step_min"])

    @property
    def steps(self) -> int:
        return int(self.meta["days"]) * 24 * 60 // self.step_min

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

    def injections(self, net: Network) -> Injections:
        """The daily injections of one network from daily/<id>.csv (zeros if it has no rated node)."""
        path = self.folder / "daily" / f"{net.id}.csv"
        if path.exists():
            return read_daily_csv(path, net)
        T, N = self.steps, net.n_nodes
        return Injections(np.arange(T) * self.step_min / 60.0, np.zeros((T, N), complex), np.zeros((T, N)), np.zeros((T, N)))

    def provenance(self) -> dict:
        keys = ("sfoe", "population_ratio", "pv_region_kwp", "ev_region", "pv_date", "pv_allocated_kwp", "ev_allocated",
                "step_min", "days", "allocation_sha256", "config_sha256", "created")
        return {"name": self.name, "folder": f"scenarios/{self.name}", **{k: self.meta[k] for k in keys if k in self.meta},
                "edited_after_generation": _sha(self.folder / "config.json") != self.meta.get("config_sha256")
                or _sha(self.folder / "allocation.csv") != self.meta.get("allocation_sha256")}


def load_scenario(name: str) -> Scenario:
    folder = scenario_dir(name)
    if not (folder / "scenario.json").exists():
        raise FileNotFoundError(f"{folder} has no generated injections: run `python -m lvgrid generate {name}`")
    with open(folder / "scenario.json") as f:
        meta = json.load(f)
    allocation = pd.read_csv(folder / "allocation.csv", dtype={"network_id": str, "node": str})
    return Scenario(name, meta, allocation)
