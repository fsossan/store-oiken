"""The files: prepared injections -> output/<name>/<level>/, one folder per network level (config.LEVELS).

output/<name>/nl7/  LV connections (the default level)
    allocation.csv    per connection: network_id, node (where it connects), plmax_kw, qlmax_kvar + the models'
                      columns (nominal_demand_kw, pv_kwp, ev_count)
    networks.csv      per-network totals of the allocation
    pv_day.csv        the normalised PV day of the daily product
    daily/<network_id>.csv   per-connection series of the representative day(s): one row per step, columns
                             step, hour, <node>:<stream>_kw (and _kvar), e.g. <node>:demand_kw, <node>:demand_kvar,
                             <node>:pv_kw, <node>:ev_kw (3-phase, in the stream's sign; all-zero columns left out)
    yearly/<network_id>.csv  per-network sums over the full year: time, <stream>_kw (and _kvar) ...
    scenario.json     provenance: streams and their signs, grid, totals (with to_region, region_share and each model's
                      split), PV day, the representative day of each season (pv_season_days, day-of-year indices),
                      sizes, hashes of the scenario and of allocation.csv, level

output/<name>/nl4/  HV/MV substations (substations.py): the same allocation summed per substation, expected series
    allocation.csv    per substation: hvmv, code, name, city, mva, n_networks, n_connections + the summed columns
    daily.csv         one row per substation and step of the daily product: hvmv, step, hour, <stream>_kw (and
                      _kvar), net_kw, net_kvar (loads minus generation: > 0 drawn from the 65 kV grid)
    yearly.csv        the same over the full year at yearly.step_min: hvmv, time, <stream>_kw ..., net_kw, net_kvar
    pv_day.csv        as in nl7
    scenario.json     as in nl7, plus the expectation samples and the networks without a substation ("unmapped")

Stream contract read by ../lv-screening: scenario.json["streams"] = {name: 'load' | 'generation'} in model order,
load streams consumption positive, generation streams production positive.
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

from . import __version__, substations
from .config import DEFAULT_LEVEL, SCENARIOS_DIR, load_config, output_folder
from .injections import Injections
from .models.common import SEASONS
from .scenario import file_hash, scenario_hash


def write(inj: Injections, ids: list[str] | None = None, verbose: bool = True, level: str = DEFAULT_LEVEL,
          samples: int | None = None) -> Path:
    """Write output/<name>/<level>/ and return the folder. nl7: `ids` a subset of the networks (default all); the
    daily and yearly files of an earlier run are replaced, so the folder holds one generation. nl4: every
    substation; `samples` the Monte Carlo size of the expectations (default: nl4.expectation_samples of
    config.json)."""
    t0 = time.time()
    folder = output_folder(inj.name, level)
    if level == "nl4":
        if ids:
            raise ValueError("a subset of networks applies to level nl7 only; nl4 sums every network of each substation")
        samples = int(samples or load_config()["nl4"]["expectation_samples"])
        meta = write_substations(inj, folder, samples, t0)
    else:
        ids = list(ids) if ids else inj.ids
        unknown = [nid for nid in ids if nid not in inj.ids]
        if unknown:                                     # before anything is deleted: a typo must not empty the folder
            raise KeyError(f"not in the grid data or without a fuse-rated connection: {', '.join(unknown)}; nothing written")
        write_series(inj, folder, ids, verbose)
        write_tables(inj, folder)
        meta = write_metadata(inj, folder, len(ids), time.time() - t0, level)
    if verbose:
        print(_summary(inj, meta, folder))
    return folder


def write_substations(inj: Injections, folder: Path, samples: int, t0: float) -> dict:
    """Level nl4: allocation.csv, daily.csv, yearly.csv (if the scenario asks for it), pv_day.csv, scenario.json."""
    cal = inj.calendar
    rows, unmapped = substations.allocation(inj)
    folder.mkdir(parents=True, exist_ok=True)
    for f in ("daily.csv", "yearly.csv"):
        (folder / f).unlink(missing_ok=True)
    rows.to_csv(folder / "allocation.csv", index=False, float_format="%.6g")
    if cal.yearly_step_min is not None:                 # the daily product is cut out of the year: the same numbers
        year = substations.series(inj, rows, cal.year, samples)
        daily = {c: a[:, cal.days] for c, a in year.items()}
        yearly = {c: np.stack([_block_average(r.ravel(), cal.yearly_factor) for r in a]) for c, a in year.items()}
        _long_csv(folder / "yearly.csv", inj, rows, {"time": cal.yearly_time}, yearly)
    else:
        daily = substations.series(inj, rows, cal.days, samples)
    n = len(rows)
    _long_csv(folder / "daily.csv", inj, rows, {"step": np.arange(len(cal.hours)), "hour": cal.hours},
              {c: a.reshape(n, -1) for c, a in daily.items()})
    pd.DataFrame({"step": np.arange(cal.steps), "hour": np.arange(cal.steps) * cal.step_min / 60.0,
                  "pv_norm": inj.state["pv"].day}).to_csv(folder / "pv_day.csv", index=False)
    return write_metadata(inj, folder, int(rows["n_networks"].sum()), time.time() - t0, "nl4",
                          {"n_substations": n, "expectation_samples": samples, "unmapped": unmapped})


def _long_csv(path: Path, inj: Injections, rows: pd.DataFrame, time_cols: dict, arrays: dict[str, np.ndarray]) -> None:
    """One row per substation and time step: hvmv, the time columns, every column of `arrays` ([substations x T]),
    then the net load (net_kw, net_kvar: loads minus generation)."""
    n, T = len(rows), len(next(iter(time_cols.values())))
    p, q = inj.net_load(arrays)
    cols = {"hvmv": np.repeat(rows["hvmv"].to_numpy(), T), **{k: np.tile(v, n) for k, v in time_cols.items()},
            **{c: a.ravel() for c, a in arrays.items()}, "net_kw": p.ravel(), "net_kvar": q.ravel()}
    pd.DataFrame(cols).to_csv(path, index=False, float_format="%.6g")


def write_series(inj: Injections, folder: Path, ids: list[str], verbose: bool = False) -> None:
    """daily/<network_id>.csv per connection and, if the scenario asks for them, yearly/<network_id>.csv per network."""
    cal = inj.calendar
    yearly = cal.yearly_step_min is not None
    for sub in ("daily", "yearly"):
        shutil.rmtree(folder / sub, ignore_errors=True)
    (folder / "daily").mkdir(parents=True, exist_ok=True)
    if yearly:
        (folder / "yearly").mkdir()
    for i, nid in enumerate(ids, 1):
        if verbose and (i % 100 == 0 or i == len(ids)):
            print(f"[{i:4d}/{len(ids)}] {nid}", flush=True)
        if yearly:                                      # the daily product is cut out of the year: the same numbers
            year = inj.series(nid, cal.year)            # column -> [connections x days of the year x steps]
            daily = {c: a[:, cal.days] for c, a in year.items()}
            _write_yearly_csv(folder / "yearly" / f"{nid}.csv", cal.yearly_time,
                              {c: _block_average(a.sum(axis=0).ravel(), cal.yearly_factor) for c, a in year.items()})
        else:
            daily = inj.series(nid)
        nodes = inj.network(nid)["node"].tolist()
        write_daily_csv(folder / "daily" / f"{nid}.csv", nodes, cal.hours,
                        {c: a.reshape(len(nodes), -1).T for c, a in daily.items()})  # [T x connections], day-contiguous


def write_tables(inj: Injections, folder: Path) -> None:
    """allocation.csv, networks.csv (its sums per network) and pv_day.csv."""
    cal, allocation = inj.calendar, inj.allocation
    allocation.to_csv(folder / "allocation.csv", index=False)
    model_columns = {c: (c, "sum") for c in allocation.columns if c not in ("network_id", "node", "plmax_kw", "qlmax_kvar")}
    networks = allocation.groupby("network_id", sort=False).agg(n_nodes=("node", "size"), plmax_sum_kw=("plmax_kw", "sum"),
                                                                **model_columns).reset_index()
    networks.to_csv(folder / "networks.csv", index=False, float_format="%.6g")
    pd.DataFrame({"step": np.arange(cal.steps), "hour": np.arange(cal.steps) * cal.step_min / 60.0,
                  "pv_norm": inj.state["pv"].day}).to_csv(folder / "pv_day.csv", index=False)


def write_metadata(inj: Injections, folder: Path, n_written: int, seconds: float, level: str = DEFAULT_LEVEL,
                   extra: dict | None = None) -> dict:
    """scenario.json: what the files are and what they were made from."""
    cal, scenario, sfoe = inj.calendar, inj.scenario, inj.scenario["sfoe"]
    meta = {"name": inj.name, "level": level, **(extra or {}),
            "sfoe": sfoe, "grid": {"region": inj.grid.name, "population": inj.grid.population[sfoe["year"]]},
            "streams": inj.streams, **inj.totals,
            "pv_date": cal.date, "pv_day_index": cal.days[0], "pv_series": scenario["pv"]["series"], "pv_season": scenario["pv"]["season"],
            "pv_season_days": {q: inj.state["pv"].season_day(q) for q in SEASONS},
            "step_min": cal.step_min, "days": len(cal.days), "yearly": scenario["time"].get("yearly", {"enabled": False}),
            "n_networks": len(inj.ids), "n_nodes": len(inj.allocation), "networks_written": n_written,
            "allocation_sha256": _sha(folder / "allocation.csv"), "config_sha256": scenario_hash(scenario),
            "created": datetime.now().isoformat(timespec="seconds"), "scengen_version": __version__, "seconds": round(seconds, 1)}
    with open(folder / "scenario.json", "w") as f:
        json.dump(meta, f, indent=2, default=str)
    return meta


def output_status(name: str, level: str = DEFAULT_LEVEL) -> tuple[str, str]:
    """('ok' | 'stale' | 'missing', text) of output/<name>/<level>/ against scenarios/<name>/config.json and the code
    version."""
    meta_file = output_folder(name, level) / "scenario.json"
    if not meta_file.exists():
        option = "" if level == DEFAULT_LEVEL else f" --level {level}"
        return "missing", f"not generated: python3 generate_scenario.py generate {name}{option}"
    meta = json.loads(meta_file.read_text())
    when = meta.get("created", "?").replace("T", " ")
    if not (SCENARIOS_DIR / name / "config.json").exists():
        return "stale", f"generated ({when}) from a configuration that is not in scenarios/{name}/"
    if meta.get("scengen_version") != __version__:
        return "stale", (f"generated ({when}) by an older generator ({meta.get('scengen_version', 'unknown')}, now {__version__}): "
                         "regenerate to see the current models")
    if meta.get("config_sha256") != file_hash(name):
        return "stale", f"config.json changed after this output was generated ({when}): it shows the old configuration"
    return "ok", f"output matches config.json (generated {when})"


# --------------------------------------------------------------- helpers --
def write_daily_csv(path: Path, nodes: list[str], time_h: np.ndarray, arrays: dict[str, np.ndarray]) -> None:
    """arrays: column -> [T x n], one column per connection, named by its node (`nodes`); all-zero columns are left out."""
    cols = {"step": np.arange(len(time_h)), "hour": time_h}
    for name, arr in arrays.items():
        for j, node in enumerate(nodes):
            if np.any(arr[:, j]):
                cols[f"{node}:{name}"] = arr[:, j]
    pd.DataFrame(cols).to_csv(path, index=False, float_format="%.5g")


def _write_yearly_csv(path: Path, time_: np.ndarray, arrays: dict[str, np.ndarray]) -> None:
    pd.DataFrame({"time": time_, **arrays}).to_csv(path, index=False, float_format="%.5g")


def _block_average(x: np.ndarray, factor: int) -> np.ndarray:
    return x.reshape(-1, factor).mean(axis=1) if factor > 1 else x


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()[:12]


def _summary(inj: Injections, meta: dict, folder: Path) -> str:
    cal, sfoe, totals = inj.calendar, inj.scenario["sfoe"], inj.totals
    sizes = [f"PV {totals['pv_allocated_kwp'] / 1e3:,.1f} MWp (split by {totals['pv_split']})"] + (
        [f"{totals['ev_allocated']:,} EVs (split by {totals['ev_split']})"] if "ev_allocated" in totals else [])
    return (f"{inj.name}: {sfoe['key']} {sfoe['year']}, {inj.grid.name} at {totals['region_share']:.2%} of the national "
            f"figures (by {totals['to_region']}), streams {', '.join(inj.streams)}; {' and '.join(sizes)} over {meta['n_networks']} networks / "
            f"{meta['n_nodes']} connections; PV day {cal.date}; daily ({len(cal.days)} day) and "
            f"{f'yearly ({cal.yearly_step_min} min)' if cal.yearly_step_min else 'no yearly'} files "
            + (f"for {meta['n_substations']} HV/MV substations ({meta['networks_written']} networks; "
               f"{meta['unmapped']['networks']} without a substation left out)" if meta["level"] == "nl4"
               else f"for {meta['networks_written']} networks")
            + f" -> {folder}  ({meta['seconds']} s)")
