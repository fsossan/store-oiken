"""The data of the scenario browser: output/<name>/ read once and cached, and the series picked from it."""
from __future__ import annotations

import json
import threading
from functools import lru_cache

import numpy as np
import pandas as pd

from ..config import SCENARIOS_DIR, load_config, output_folder
from ..grid import load_grid
from ..models.common import SEASONS
from .constants import C, SERIES, STREAMS


def scenario_names() -> list[str]:
    return sorted(p.parent.name for p in SCENARIOS_DIR.glob("*/config.json"))


def load_output(name: str) -> dict:
    """Output of a scenario with per-network statistics (cached until scenario.json changes)."""
    with _LOADING.setdefault(name, threading.Lock()):   # parallel callbacks wait for one read instead of each reading
        return _load(name, (output_folder(name) / "scenario.json").stat().st_mtime)


_LOADING: dict[str, threading.Lock] = {}


@lru_cache(maxsize=2)
def _load(name: str, _stamp: float) -> dict:
    folder = output_folder(name)
    meta = json.loads((folder / "scenario.json").read_text())
    streams = meta["streams"]
    alloc = pd.read_csv(folder / "allocation.csv", dtype={"network_id": str, "node": str})
    nets = pd.read_csv(folder / "networks.csv", dtype={"network_id": str}).set_index("network_id")
    ids = [n for n in nets.index if (folder / "daily" / f"{n}.csv").exists()]   # the generated networks (--networks: a subset)
    nets, alloc = nets.loc[ids].copy(), alloc[alloc["network_id"].isin(ids)]
    nets["trafo_kva"] = load_grid().networks["trafo_kva"].reindex(nets.index)
    for col, per in (("pv_kwp", "pv_per_conn"), ("ev_count", "ev_per_conn")):
        if col in nets:
            nets[per] = nets[col] / nets["n_nodes"]
    d = {"name": name, "meta": meta, "streams": streams, "sign": {s: 1 if k == "load" else -1 for s, k in streams.items()},
         "alloc": alloc, "nets": nets, "Y": None}
    ydir = folder / "yearly"
    if not (ids and meta.get("yearly", {}).get("enabled") and all((ydir / f"{n}.csv").exists() for n in ids)):
        return d
    time = pd.to_datetime(pd.read_csv(ydir / f"{ids[0]}.csv", usecols=["time"])["time"], utc=True)
    time = time.dt.tz_convert("Etc/GMT-1").dt.tz_localize(None)            # local standard time (UTC+1)
    cols = [c for c in pd.read_csv(ydir / f"{ids[0]}.csv", nrows=0).columns if c != "time"]
    raw = {c: np.empty((len(ids), len(time)), np.float32) for c in cols}
    for i, n in enumerate(ids):
        y = pd.read_csv(ydir / f"{n}.csv", usecols=cols, engine="pyarrow")
        for c in cols:
            raw[c][i] = y[c].to_numpy()
    Y = {s: raw[f"{s}_kw"] for s in streams if f"{s}_kw" in raw}               # stream -> [networks x T] kW
    P = net_of(d, Y)
    Q = sum((d["sign"][s] * raw[f"{s}_kvar"] for s in streams if f"{s}_kvar" in raw), np.zeros_like(P))
    S = np.hypot(P, Q)
    dt_h = (time.iloc[1] - time.iloc[0]).total_seconds() / 3600
    for s, y in Y.items():
        nets[f"mwh_{s}"] = y.sum(axis=1) * dt_h / 1e3
    nets["net_peak_kw"] = P.max(axis=1)
    nets["net_peak_time"] = time.iloc[P.argmax(axis=1)].dt.strftime("%Y-%m-%d %H:%M").to_numpy()
    nets["net_min_kw"] = P.min(axis=1)
    nets["reverse_h"] = (P < 0).sum(axis=1) * dt_h
    nets["import_pct_trafo"] = 100 * np.where(P >= 0, S, 0).max(axis=1) / nets["trafo_kva"]
    nets["export_pct_trafo"] = 100 * np.where(P < 0, S, 0).max(axis=1) / nets["trafo_kva"]
    if "demand" in Y:
        nets["demand_peak_pct_fuse"] = 100 * Y["demand"].max(axis=1) / nets["plmax_sum_kw"]
        nets["kwh_per_conn"] = 1e3 * nets["mwh_demand"] / nets["n_nodes"]
    d.update(nets=nets, Y=Y, R={s: y.sum(axis=0, dtype=np.float64) for s, y in Y.items()},
             row={n: i for i, n in enumerate(ids)}, time=time, dt_h=dt_h, per_day=int(round(24 / dt_h)))
    return d


@lru_cache(maxsize=16)
def _daily_file(name: str, nid: str, _stamp: float) -> pd.DataFrame:
    return pd.read_csv(output_folder(name) / "daily" / f"{nid}.csv")


def daily(d: dict, nid: str) -> pd.DataFrame:
    """The network's daily product: one row per step, `<node>:<stream>_kw` columns."""
    return _daily_file(d["name"], nid, (output_folder(d["name"]) / "scenario.json").stat().st_mtime)


def demand_factor(d: dict) -> float | None:
    """The demand_factor the output was generated with (recorded in scenario.json)."""
    return d["meta"].get("demand_factor")


def pv_factors(d: dict) -> tuple[float, float] | None:
    """(yearly capacity factor of the scenario's PV profile, the realistic one of config.json `pv_realistic`), or None
    without PV or yearly files. PV x realistic / profile is the PV energy at the realistic capacity factor."""
    realistic = load_config().get("pv_realistic", {}).get("capacity_factor")
    kwp = d["nets"]["pv_kwp"].sum() if "pv_kwp" in d["nets"] else 0
    if d["Y"] is None or "pv" not in d["R"] or not kwp or not realistic:
        return None
    return float(d["R"]["pv"].mean() / kwp), float(realistic)


def season_day(d: dict, season: str) -> int | None:
    """Day-of-year index of the season's representative day (scenario.json, pv_season_days); None in an output
    written before the generator recorded it."""
    return d["meta"].get("pv_season_days", {}).get(season)


def label(s: str) -> str:
    return STREAMS.get(s, s)


def colour(s: str, streams) -> str:
    """A stream keeps its colour in every scenario and view: known streams first, then in the order of `streams`."""
    order = list(STREAMS) + [k for k in streams if k not in STREAMS]
    return SERIES[order.index(s)] if order.index(s) < len(SERIES) else C["muted"]


def net_of(d: dict, series: dict):
    """Loads minus generation, element-wise over the streams' arrays."""
    return sum(d["sign"][s] * y for s, y in series.items())


def network_series(d: dict, nid: str) -> dict[str, np.ndarray]:
    return {s: y[d["row"][nid]] for s, y in d["Y"].items()}


def daily_series(d: dict, nid: str) -> tuple[dict[str, np.ndarray], pd.Series]:
    """Per-stream network sums of the daily product and their times."""
    df = daily(d, nid)
    series = {s: df[[c for c in df.columns if c.endswith(f":{s}_kw")]].sum(axis=1).to_numpy() for s in d["streams"]}
    return series, pd.Timestamp(d["meta"].get("pv_date", "2000-01-01")) + pd.to_timedelta(df["hour"], unit="h")


def pick_day(d: dict, series: dict[str, np.ndarray], which: str, k: int | None = None) -> tuple[dict, pd.Series, str, int | None]:
    """One day of yearly series: (series, times, description, day index); k forces the day (to show another scenario)."""
    n = d["per_day"]
    if which == "mean":
        x = pd.Timestamp("2000-01-01") + pd.to_timedelta(np.arange(n) * d["dt_h"], unit="h")
        return {s: y.reshape(-1, n).mean(axis=0) for s, y in series.items()}, pd.Series(x), "mean day of the year", None
    net = net_of(d, series)
    if k is None:
        k = (season_day(d, which) if which in SEASONS else
             {"rep": d["meta"].get("pv_day_index", 0), "peak": int(net.argmax()) // n, "reverse": int(net.argmin()) // n}[which])
    sl = slice(k * n, (k + 1) * n)
    what = {"rep": "representative day", "peak": "day of the peak net load",
            "reverse": "day of the largest reverse flow" if net.min() < 0 else "no reverse flow; day of the lowest net load",
            **{q: f"representative {q} day" for q in SEASONS}}[which]
    return {s: y[sl] for s, y in series.items()}, d["time"].iloc[sl], f"{what}, {d['time'].iloc[k * n]:%a %d %b}", k
