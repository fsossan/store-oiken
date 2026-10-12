"""Scenario generation: configuration -> allocation -> injections as CSV.

    scenarios/<name>/config.json   stage 1: SFOE figures, horizon, demand / PV / EV settings
    output/<name>/                 stage 2 (`generate`):
        allocation.csv    network_id, node, plmax_kw, qlmax_kvar, pv_kwp, ev_count
        networks.csv      per-network totals
        pv_day.csv        the normalised PV day of the daily product
        daily/<network_id>.csv   per-node series of the representative day(s): one row per step, columns
                                 step, hour, <node>:demand_kw, <node>:demand_kvar, <node>:pv_kw, <node>:ev_kw
                                 (3-phase kW, consumption positive; all-zero columns left out)
        yearly/<network_id>.csv  per-network sums over the full year: time, demand_kw, demand_kvar, pv_kw, ev_kw
        scenario.json     provenance: totals, PV day, sizes, hashes of config.json and allocation.csv

Allocation (port of the MATLAB allocate_PV_EV_SFOE): national PV [MW] and EVs
are scaled to Sion+Sierre by population, split between networks in proportion
to their fuse-rated peak and within a network in proportion to each node's
PLmax; EVs are integers (largest remainder at both levels).

Series: demand = demand_factor x fuse-rated peak times a synthetic household day
(demand model, one seed per (network, day)); PV = kWp times the normalised
yearly profile; EV = per vehicle charger_kw blocks after a random arrival (one
seed per (network, day)). The daily product is the yearly series on the
representative PV day (the real day closest to the season's mean shape), so
the two products are consistent and a day does not change with the horizon.
"""
from __future__ import annotations

import hashlib
import json
import time
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd

from . import __version__
from .config import OUTPUT_DIR, SCENARIOS_DIR, resolve
from .data import load_lines, network_number, nodal_ratings
from .profiles import ev_node_profiles, load_demand_model, load_pv_year, pv_representative_day, pv_year_series, sample_demand

STREAMS = ("demand_kw", "demand_kvar", "pv_kw", "ev_kw")


# ------------------------------------------------------- stage 1: config --
def new_scenario_config(cfg: dict, sfoe_key: str, name: str | None = None) -> dict:
    if sfoe_key not in cfg["sfoe"]:
        raise KeyError(f"unknown SFOE scenario {sfoe_key}; known: {', '.join(cfg['sfoe'])}")
    d = cfg["scenario_defaults"]
    return {"name": name or sfoe_key, "sfoe": {"key": sfoe_key, **cfg["sfoe"][sfoe_key]},
            "time": d["time"], "demand": d["demand"], "pv": d["pv"], "ev": d["ev"]}


def write_scenario_config(scfg: dict) -> Path:
    folder = SCENARIOS_DIR / scfg["name"]
    folder.mkdir(parents=True, exist_ok=True)
    with open(folder / "config.json", "w") as f:
        json.dump(scfg, f, indent=2)
    return folder / "config.json"


def load_scenario_config(name: str) -> dict:
    path = SCENARIOS_DIR / name / "config.json"
    if not path.exists():
        raise FileNotFoundError(f"{path} missing: create it with `python generate_scenario.py new <sfoe key> --name {name}`")
    with open(path) as f:
        scfg = json.load(f)
    for key in ("sfoe", "time", "demand", "pv", "ev"):
        if key not in scfg:
            raise KeyError(f"{path}: missing block '{key}'")
    scfg["name"] = name
    return scfg


# ------------------------------------------------------------ allocation --
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


def allocate(ratings: pd.DataFrame, sfoe: dict) -> tuple[pd.DataFrame, dict]:
    """PV kWp and EV count per (network, node) with a fuse rating."""
    pop_ratio = sfoe["population_sion_sierre"] / sfoe["population_national"]
    pv_region_kwp = sfoe["PV_national_MW"] * 1e3 * pop_ratio
    ev_region = int(round(sfoe["EV_national_thousands"] * 1e3 * pop_ratio))

    nodes = ratings[["network_id", "node", "plmax_kw", "qlmax_kvar"]].copy()
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


# ------------------------------------------------------------ generation --
def write_daily_csv(path: Path, nodes: list[str], time_h: np.ndarray, arrays: dict[str, np.ndarray]) -> None:
    """arrays: stream -> [T x n] in the order of `nodes`; all-zero columns are left out."""
    cols = {"step": np.arange(len(time_h)), "hour": time_h}
    for name in STREAMS:
        arr = arrays[name]
        for j, node in enumerate(nodes):
            if np.any(arr[:, j]):
                cols[f"{node}:{name}"] = arr[:, j]
    pd.DataFrame(cols).to_csv(path, index=False, float_format="%.5g")


def _block_average(x: np.ndarray, factor: int) -> np.ndarray:
    return x.reshape(-1, factor).mean(axis=1) if factor > 1 else x


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()[:12]


def generate(name: str, ids: list[str] | None = None, verbose: bool = True) -> Path:
    """Stage 2: allocation + daily per-node injections + yearly per-network sums -> output/<name>/."""
    t0 = time.time()
    scfg = load_scenario_config(name)
    folder = OUTPUT_DIR / name
    tcfg, dcfg, pcfg, ecfg = scfg["time"], scfg["demand"], scfg["pv"], scfg["ev"]
    step_min = int(tcfg["step_min"])
    S = 24 * 60 // step_min
    D = int(tcfg.get("days", 1))
    yearly = tcfg.get("yearly", {"enabled": False})
    lines = load_lines()
    allocation, totals = allocate(nodal_ratings(lines), scfg["sfoe"])

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
    if yearly.get("enabled") and (y_factor < 1 or S % y_factor):
        raise ValueError("yearly.step_min must be a multiple of time.step_min that divides the day")

    (folder / "daily").mkdir(parents=True, exist_ok=True)
    if yearly.get("enabled"):
        (folder / "yearly").mkdir(exist_ok=True)
        y_time = pv_df["time"].to_numpy()[::y_factor]
    ids = ids or list(lines["network_id"].unique())
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

        def daily(a):                                   # [n x D' x S] -> [T x n], day-contiguous
            return a[:, j_daily, :].reshape(n, -1).T

        time_h = np.arange(D * S) * step_min / 60.0
        write_daily_csv(folder / "daily" / f"{nid}.csv", nodes, time_h,
                        {"demand_kw": daily(demand.real), "demand_kvar": daily(demand.imag), "pv_kw": daily(pv), "ev_kw": daily(ev)})
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
            "config_sha256": _sha(SCENARIOS_DIR / name / "config.json"), "created": datetime.now().isoformat(timespec="seconds"),
            "scengen_version": __version__, "seconds": round(time.time() - t0, 1)}
    with open(folder / "scenario.json", "w") as f:
        json.dump(meta, f, indent=2, default=str)
    if verbose:
        print(f"{name}: {scfg['sfoe']['key']} {scfg['sfoe'].get('year', '')}, population share {totals['population_ratio']:.2%}, "
              f"PV {totals['pv_allocated_kwp'] / 1e3:,.1f} MWp and {totals['ev_allocated']:,} EVs over {meta['n_networks']} networks / "
              f"{meta['n_nodes']} nodes; PV day {pv_date}; daily ({D} day) and "
              f"{'yearly (' + str(yearly.get('step_min', step_min)) + ' min)' if yearly.get('enabled') else 'no yearly'} files "
              f"for {n_written} networks -> {folder}  ({meta['seconds']} s)")
    return folder
