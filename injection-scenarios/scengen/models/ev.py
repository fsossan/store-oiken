"""EV charging (stream `ev`, load): SFOE vehicles scaled to the region (sfoe.to_region) and split over the connections
(ev.split, models/common.SPLITS: by fuse-rated power or equally; integers); each vehicle
charges once a day at charger_kw from a random arrival until a random energy is delivered (truncated normal or
GEV), as step averages, cut at midnight; one generator per (network, day)."""
from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass

import numpy as np
import pandas as pd
from scipy import stats

from .common import National, split

NAME, SIGN = "ev", "load"
REQUIRED, OPTIONAL, NATIONAL = ("split", "charger_kw", "arrival_h", "energy_kwh", "seed_offset"), (), ("EV_national_thousands",)


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
    """Charging power per connection [n x S], 3-phase kW, as step averages: each vehicle
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
@dataclass(frozen=True)
class EVState:
    charger_kw: float
    step_min: int
    seed_offset: int
    arrival: Callable                   # (rng, n) -> n arrival times [h]
    energy: Callable                    # (rng, n) -> n session energies [kWh]


def allocate(connections: pd.DataFrame, cfg: dict, national: National) -> dict:
    """ev_count: the national fleet scaled to the region, split over the connections by `split` (integers)."""
    total = int(round(national.to_region("EV_national_thousands", 1e3)))
    connections["ev_count"] = split(connections, total, cfg["split"], integer=True, where="ev.split")
    return {"ev_split": cfg["split"], "ev_region": total, "ev_allocated": int(connections["ev_count"].sum())}


def prepare(cfg: dict, step_min: int) -> EVState:
    if not cfg["charger_kw"] > 0:
        raise ValueError("ev.charger_kw must be positive")
    arrival, energy = ev_samplers(cfg)
    return EVState(cfg["charger_kw"], step_min, cfg["seed_offset"], arrival, energy)


def series(state: EVState, connections: pd.DataFrame, days: list[int], net_num: int) -> dict[str, np.ndarray]:
    counts = connections["ev_count"].to_numpy()
    out = np.zeros((len(connections), len(days), 24 * 60 // state.step_min))
    has = np.flatnonzero(counts > 0)
    if len(has):
        for j, d in enumerate(days):
            out[has, j] = ev_node_profiles(counts[has], state.charger_kw, state.arrival, state.energy, state.step_min,
                                           np.random.default_rng([net_num + state.seed_offset, d]))
    return {"ev_kw": out}


def expected(state: EVState, rows: pd.DataFrame, days: list[int], samples: int) -> dict[str, np.ndarray]:
    """What `series` summed over many vehicles converges to (level nl4): each row's EV count times the expected
    charging power of one vehicle, the mean of `samples` simulated sessions (same arrival and energy laws, cut at
    midnight). Every day is drawn from the same laws, so the expectation is one day, repeated."""
    one = ev_node_profiles(np.array([samples]), state.charger_kw, state.arrival, state.energy, state.step_min,
                           np.random.default_rng([state.seed_offset, samples]))[0] / samples      # [S] kW per vehicle
    day = np.broadcast_to(one, (len(days), len(one)))[None]                                          # [1 x D x S]
    return {"ev_kw": rows["ev_count"].to_numpy(float)[:, None, None] * day}
