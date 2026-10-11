"""Per-node power time series of one network for a scenario.

Three streams, all in 3-phase kW with consumption positive:
    demand  demand_factor x fuse-rated peak (P + jQ, constant power factor)
            times a synthetic household day shape per node (demand model)
    pv      scenario kWp per node times the scenario's PV day
    ev      scenario EV count per node, uncontrolled evening charging
`case_injection_pu` combines them into the net injection the load flow needs.
Seeds derive from the network number so a network gets the same demand and EV
realisation in every scenario; scenarios differ only by PV and EV magnitudes.
"""
from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from .config import kw_per_pu
from .network import Network
from .profiles import ev_node_profiles, sample_demand
from .scenario import Scenario

CASES = {
    "demand": ("demand",),
    "demand+pv": ("demand", "pv"),
    "demand+pv+ev": ("demand", "pv", "ev"),
}


@dataclass
class Injections:
    time_h: np.ndarray           # [T]
    demand_kw: np.ndarray        # [T x N] complex, consumption positive
    pv_kw: np.ndarray            # [T x N] generation positive
    ev_kw: np.ndarray            # [T x N] consumption positive
    meta: dict = field(default_factory=dict)

    def aggregate(self) -> dict[str, np.ndarray]:
        return {"demand_kw": self.demand_kw.real.sum(axis=1), "pv_kw": self.pv_kw.sum(axis=1),
                "ev_kw": self.ev_kw.sum(axis=1)}


def build_injections(net: Network, sc: Scenario, demand_model: dict, n_days: int = 1) -> Injections:
    """net must carry the scenario's pv_kwp / ev_count (Scenario.apply)."""
    S = len(sc.pv_day)
    N = net.n_nodes
    T = S * n_days
    time_h = np.arange(T) * sc.step_min / 60.0

    nominal = sc.demand["demand_factor"] * (net.plmax_kw + 1j * net.qlmax_kvar)
    has_d = np.flatnonzero(nominal.real > 0)
    demand = np.zeros((T, N), complex)
    clusters = np.zeros(N, int)
    if len(has_d):
        rng = np.random.default_rng(net.num + sc.demand["seed_offset"])
        shape, cl = sample_demand(demand_model, len(has_d), n_days, rng)        # [n x D x S]
        demand[:, has_d] = shape.reshape(len(has_d), T).T * nominal[has_d][None, :]
        clusters[has_d] = cl

    pv = np.tile(sc.pv_day, n_days)[:, None] * net.pv_kwp[None, :] if net.pv_kwp.sum() > 0 else np.zeros((T, N))

    ev = np.zeros((T, N))
    has_e = np.flatnonzero(net.ev_count > 0)
    if len(has_e):
        rng = np.random.default_rng(net.num + sc.ev["seed_offset"])
        ev_day = ev_node_profiles(net.ev_count[has_e], sc.ev, sc.step_min, rng)   # [n x S]
        ev[:, has_e] = np.tile(ev_day.T, (n_days, 1))

    return Injections(time_h, demand, pv, ev, {"demand_clusters": clusters, "n_days": n_days})


def case_injection_pu(inj: Injections, case: str, cfg: dict) -> np.ndarray:
    """Net injection at the non-slack nodes [T x N-1], pu, generation positive."""
    streams = CASES[case]
    s = np.zeros_like(inj.demand_kw)
    if "demand" in streams:
        s -= inj.demand_kw
    if "pv" in streams:
        s += inj.pv_kw
    if "ev" in streams:
        s -= inj.ev_kw
    return s[:, 1:] / kw_per_pu(cfg)
