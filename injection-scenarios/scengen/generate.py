"""Scenario generation: configuration -> allocation -> injections as CSV.

    scenarios/<name>/config.json   stage 1: SFOE figures, horizon, one block per model (demand, pv, ev, ...)
    output/<name>/                 stage 2 (`generate`):
        allocation.csv    network_id, node, plmax_kw, qlmax_kvar + the models' columns (pv_kwp, ev_count)
        networks.csv      per-network totals
        pv_day.csv        the normalised PV day of the daily product
        daily/<network_id>.csv   per-node series of the representative day(s): one row per step, columns
                                 step, hour, <node>:<stream>_kw (and _kvar), e.g. <node>:demand_kw, <node>:demand_kvar,
                                 <node>:pv_kw, <node>:ev_kw (3-phase, in the stream's sign; all-zero columns left out)
        yearly/<network_id>.csv  per-network sums over the full year: time, <stream>_kw (and _kvar) ...
        scenario.json     provenance: streams and their signs, totals, PV day, sizes, hashes of config.json
                          and allocation.csv

The models (scengen/models/, one stream each) allocate their quantities to the
nodes and produce the per-node series; this module runs them over the
networks and writes the files. Stream contract read by ../lv-screening:
scenario.json["streams"] = {name: 'load' | 'generation'} in model order, load
streams consumption positive, generation streams production positive. The
daily product is the yearly series on the representative PV day, so the two
products are consistent and a day does not change with the horizon; seeds are
per (network, day).
"""
from __future__ import annotations

import hashlib
import json
import shutil
import time
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd

from . import __version__
from .config import OUTPUT_DIR, SCENARIOS_DIR
from .data import load_lines, network_number, nodal_ratings
from .models import MODELS
from .models.common import population_ratio

REQUIRED = ("sfoe", "time", "demand", "pv")


# ------------------------------------------------------- stage 1: config --
def new_scenario_config(cfg: dict, sfoe_key: str, name: str | None = None) -> dict:
    if sfoe_key not in cfg["sfoe"]:
        raise KeyError(f"unknown SFOE scenario {sfoe_key}; known: {', '.join(cfg['sfoe'])}")
    d = cfg["scenario_defaults"]
    return {"name": name or sfoe_key, "sfoe": {"key": sfoe_key, **cfg["sfoe"][sfoe_key]}, "time": d["time"],
            **{m.NAME: d[m.NAME] for m in MODELS if m.NAME in d}}


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
    for key in REQUIRED:
        if key not in scfg:
            raise KeyError(f"{path}: missing block '{key}'")
    known = {"name", *REQUIRED, *(m.NAME for m in MODELS)}
    unknown = [k for k in scfg if k not in known and not k.startswith("_")]
    if unknown:
        raise KeyError(f"{path}: unknown block(s) {', '.join(unknown)}; known: {', '.join(sorted(known - {'name'}))}")
    scfg["name"] = name
    return scfg


def active_models(scfg: dict) -> list:
    """The models whose block is in the scenario configuration, in MODELS order."""
    return [m for m in MODELS if m.NAME in scfg]


# ------------------------------------------------------------ allocation --
def allocate(ratings: pd.DataFrame, scfg: dict) -> tuple[pd.DataFrame, dict]:
    """Per (network, node) with a fuse rating: the columns of each active model (pv_kwp, ev_count, ...)."""
    nodes = ratings[["network_id", "node", "plmax_kw", "qlmax_kvar"]].copy()
    totals = {"population_ratio": population_ratio(scfg["sfoe"])}
    for m in active_models(scfg):
        totals.update(m.allocate(nodes, scfg["sfoe"], scfg[m.NAME]))
    return nodes[nodes["plmax_kw"] > 0].reset_index(drop=True), totals


# ------------------------------------------------------------ generation --
def write_daily_csv(path: Path, nodes: list[str], time_h: np.ndarray, arrays: dict[str, np.ndarray]) -> None:
    """arrays: column -> [T x n] in the order of `nodes`; all-zero columns are left out."""
    cols = {"step": np.arange(len(time_h)), "hour": time_h}
    for name, arr in arrays.items():
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
    models = active_models(scfg)
    folder = OUTPUT_DIR / name
    tcfg = scfg["time"]
    step_min = int(tcfg["step_min"])
    S = 24 * 60 // step_min
    D = int(tcfg.get("days", 1))
    yearly = tcfg.get("yearly", {"enabled": False})
    lines = load_lines()
    allocation, totals = allocate(nodal_ratings(lines), scfg)
    state = {m.NAME: m.prepare(scfg[m.NAME], step_min) for m in models}

    pv = state["pv"]                                    # the PV profile defines the calendar and the representative day
    n_year, k0 = len(pv["year"]), pv["day_index"]
    daily_days = [(k0 + i) % n_year for i in range(D)]
    days = list(range(n_year)) if yearly.get("enabled") else daily_days
    j_daily = [days.index(d) for d in daily_days]
    y_factor = int(yearly.get("step_min", step_min)) // step_min if yearly.get("enabled") else 1
    if yearly.get("enabled") and (y_factor < 1 or S % y_factor):
        raise ValueError("yearly.step_min must be a multiple of time.step_min that divides the day")

    for sub in ("daily", "yearly"):                     # one generation per folder: no files of an earlier run left over
        shutil.rmtree(folder / sub, ignore_errors=True)
    (folder / "daily").mkdir(parents=True, exist_ok=True)
    if yearly.get("enabled"):
        (folder / "yearly").mkdir(exist_ok=True)
        y_time = pv["time"].to_numpy()[::y_factor]
    ids = ids or list(lines["network_id"].unique())
    time_h = np.arange(D * S) * step_min / 60.0
    n_written = 0
    for i, nid in enumerate(ids, 1):
        if verbose and (i % 100 == 0 or i == len(ids)):
            print(f"[{i:4d}/{len(ids)}] {nid}", flush=True)
        rows = allocation[allocation["network_id"] == nid]
        if rows.empty:
            continue
        num = network_number(nid)
        series = {}                                     # column -> [n x D' x S]
        for m in models:
            series.update(m.series(state[m.NAME], rows, days, num))
        n = len(rows)
        write_daily_csv(folder / "daily" / f"{nid}.csv", rows["node"].tolist(), time_h,
                        {c: a[:, j_daily, :].reshape(n, -1).T for c, a in series.items()})     # [T x n], day-contiguous
        if yearly.get("enabled"):
            pd.DataFrame({"time": y_time, **{c: _block_average(a.sum(axis=0).ravel(), y_factor) for c, a in series.items()}}).to_csv(
                folder / "yearly" / f"{nid}.csv", index=False, float_format="%.5g")
        n_written += 1

    allocation.to_csv(folder / "allocation.csv", index=False)
    extra = {c: (c, "sum") for c in allocation.columns if c not in ("network_id", "node", "plmax_kw", "qlmax_kvar")}
    nets = allocation.groupby("network_id", sort=False).agg(n_nodes=("node", "size"), plmax_sum_kw=("plmax_kw", "sum"),
                                                            **extra).reset_index()
    nets.insert(3, "nominal_demand_kw", nets["plmax_sum_kw"] * scfg["demand"]["demand_factor"])
    nets.to_csv(folder / "networks.csv", index=False, float_format="%.6g")
    pd.DataFrame({"step": np.arange(S), "hour": np.arange(S) * step_min / 60.0, "pv_norm": pv["day"]}).to_csv(folder / "pv_day.csv", index=False)
    meta = {"name": name, "sfoe": scfg["sfoe"], "streams": {m.NAME: m.SIGN for m in models}, **totals,
            "pv_date": pv["date"], "pv_day_index": k0, "pv_series": scfg["pv"]["series"], "pv_season": scfg["pv"]["season"],
            "step_min": step_min, "days": D, "yearly": yearly, "n_networks": int(allocation["network_id"].nunique()),
            "n_nodes": len(allocation), "networks_written": n_written, "allocation_sha256": _sha(folder / "allocation.csv"),
            "config_sha256": _sha(SCENARIOS_DIR / name / "config.json"), "created": datetime.now().isoformat(timespec="seconds"),
            "scengen_version": __version__, "seconds": round(time.time() - t0, 1)}
    with open(folder / "scenario.json", "w") as f:
        json.dump(meta, f, indent=2, default=str)
    if verbose:
        sizes = [f"PV {totals['pv_allocated_kwp'] / 1e3:,.1f} MWp"] + ([f"{totals['ev_allocated']:,} EVs"] if "ev_allocated" in totals else [])
        print(f"{name}: {scfg['sfoe']['key']} {scfg['sfoe'].get('year', '')}, population share {totals['population_ratio']:.2%}, "
              f"streams {', '.join(meta['streams'])}; {' and '.join(sizes)} over {meta['n_networks']} networks / "
              f"{meta['n_nodes']} nodes; PV day {pv['date']}; daily ({D} day) and "
              f"{'yearly (' + str(yearly.get('step_min', step_min)) + ' min)' if yearly.get('enabled') else 'no yearly'} files "
              f"for {n_written} networks -> {folder}  ({meta['seconds']} s)")
    return folder
