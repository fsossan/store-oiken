"""EV charging (stream `ev`, load): SFOE vehicles split over the nodes by fuse-rated power (integers); each vehicle
charges once a day at charger_kw from a random arrival until a random energy is delivered (truncated normal or
GEV), as step averages, cut at midnight; one generator per (network, day)."""
from __future__ import annotations

import numpy as np
import pandas as pd
from scipy import stats

from .common import population_ratio, split_by_fuse

NAME, SIGN = "ev", "load"


def truncated_sampler(spec: dict):
    """Sampler (rng, n) -> n draws of a normal or GEV distribution truncated to
    [min, max], by inverse CDF.

    spec: {"dist": "normal", "mean", "std"} (std 0 = the fixed value mean) or
    {"dist": "gev", "shape", "loc", "scale"}, plus "min", "max". The GEV shape is
    xi (xi > 0 heavy upper tail, xi = 0 Gumbel), as k in MATLAB gevrnd(k, sigma, mu);
    scipy's genextreme uses c = -xi."""
    lo, hi = spec["min"], spec["max"]
    if spec["dist"] == "normal":
        if spec["std"] == 0:
            if not lo <= spec["mean"] <= hi:
                raise ValueError(f"{spec}: mean outside [min, max]")
            return lambda rng, n: np.full(n, float(spec["mean"]))
        d = stats.norm(spec["mean"], spec["std"])
    elif spec["dist"] == "gev":
        d = stats.genextreme(-spec["shape"], spec["loc"], spec["scale"])
    else:
        raise ValueError(f"{spec}: dist must be 'normal' or 'gev'")
    u_lo, u_hi = d.cdf(lo), d.cdf(hi)
    if u_lo > 0.5:                                      # upper tail: invert the survival function (cdf rounds to 1 there)
        s_lo, s_hi = d.sf(hi), d.sf(lo)
        if not s_hi > s_lo:
            raise ValueError(f"{spec}: no probability mass between min and max")
        return lambda rng, n: np.clip(d.isf(rng.uniform(s_lo, s_hi, n)), lo, hi)
    if not u_hi > u_lo:
        raise ValueError(f"{spec}: no probability mass between min and max")
    return lambda rng, n: np.clip(d.ppf(rng.uniform(u_lo, u_hi, n)), lo, hi)


def ev_samplers(ecfg: dict):
    """(arrival [h], energy [kWh]) samplers of the `ev` block of a scenario configuration."""
    a, e = ecfg["arrival_h"], ecfg["energy_kwh"]
    if not 0 <= a["min"] < a["max"] <= 24:
        raise ValueError("ev.arrival_h: need 0 <= min < max <= 24")
    if not 0 <= e["min"] <= e["max"]:
        raise ValueError("ev.energy_kwh: need 0 <= min <= max")
    return truncated_sampler(a), truncated_sampler(e)


def ev_node_profiles(ev_counts: np.ndarray, charger_kw: float, arrival, energy, step_min: int,
                     rng: np.random.Generator) -> np.ndarray:
    """Charging power per node [n x S], 3-phase kW, as step averages: each vehicle
    arrives at a time drawn from `arrival` and charges at charger_kw until the
    energy drawn from `energy` is delivered; sessions are cut at midnight."""
    S = 24 * 60 // step_min
    dt = step_min / 60.0
    t = np.arange(S) * dt
    counts = np.asarray(ev_counts, int)
    out = np.zeros((len(counts), S))
    total = int(counts.sum())
    if total == 0:
        return out
    start = arrival(rng, total)
    end = start + energy(rng, total) / charger_kw
    overlap = np.clip(np.minimum(t[None, :] + dt, end[:, None]) - np.maximum(t[None, :], start[:, None]), 0, dt)
    owner = np.repeat(np.arange(len(counts)), counts)
    np.add.at(out, owner, overlap * (charger_kw / dt))
    return out


# ------------------------------------------------------------- interface ----
def allocate(nodes: pd.DataFrame, sfoe: dict, cfg: dict) -> dict:
    total = int(round(sfoe["EV_national_thousands"] * 1e3 * population_ratio(sfoe)))
    nodes["ev_count"] = split_by_fuse(nodes, total, integer=True)
    return {"ev_region": total, "ev_allocated": int(nodes["ev_count"].sum())}


def prepare(cfg: dict, step_min: int) -> dict:
    if "arrival_h" not in cfg or "energy_kwh" not in cfg:
        raise KeyError("ev block in the format before 2026-10-13 (arrival_mean_h ..., duration_h): replace it with the ev "
                       "block of scenario_defaults in config.json (arrival_h, energy_kwh; 44 kWh = the former 4 h x 11 kW)")
    if not cfg["charger_kw"] > 0:
        raise ValueError("ev.charger_kw must be positive")
    arrival, energy = ev_samplers(cfg)
    return {"cfg": cfg, "step_min": step_min, "arrival": arrival, "energy": energy}


def series(state: dict, rows: pd.DataFrame, days: list[int], net_num: int) -> dict[str, np.ndarray]:
    cfg, step_min = state["cfg"], state["step_min"]
    counts = rows["ev_count"].to_numpy()
    out = np.zeros((len(rows), len(days), 24 * 60 // step_min))
    has = np.flatnonzero(counts > 0)
    if len(has):
        for j, d in enumerate(days):
            out[has, j] = ev_node_profiles(counts[has], cfg["charger_kw"], state["arrival"], state["energy"], step_min,
                                           np.random.default_rng([net_num + cfg["seed_offset"], d]))
    return {"ev_kw": out}
