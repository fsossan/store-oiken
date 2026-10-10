"""SFOE scenario -> PV capacity and EV count per node (port of allocate_PV_EV_SFOE).

National PV [MW] and EV [count] of the scenario are scaled to Sion+Sierre by the
population ratio, split between networks in proportion to their fuse-rated peak
(sum of PLmax over the network's nodes), and within a network in proportion to
each node's PLmax. EVs are integers (largest-remainder rounding at both levels).
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import pandas as pd

from .data import Portfolio


@dataclass
class Allocation:
    scenario: str
    nodes: pd.DataFrame        # network_id, to, plmax_kw, pv_kwp, ev_count
    pv_region_kwp: float
    ev_region: int
    pop_ratio: float

    def for_network(self, network_id: str) -> pd.DataFrame:
        return self.nodes[self.nodes["network_id"] == network_id]


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


def allocate_pv_ev(portfolio: Portfolio, scenario: str, cfg: dict) -> Allocation:
    sc = cfg["scenarios"][scenario]
    pop_ratio = sc["population_sion_sierre"] / sc["population_national"]
    pv_region_kwp = sc["PV_national_MW"] * 1e3 * pop_ratio
    ev_region = int(round(sc["EV_national_thousands"] * 1e3 * pop_ratio))

    nodes = portfolio.nodal_ratings().copy()
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
    return Allocation(scenario, nodes, pv_region_kwp, ev_region, pop_ratio)


def apply_allocation(net, alloc: Allocation | None) -> None:
    """Fill net.pv_kwp / net.ev_count (3-phase kWp, count) from the allocation."""
    N = net.n_nodes
    net.pv_kwp = np.zeros(N)
    net.ev_count = np.zeros(N, int)
    if alloc is None:
        return
    rows = alloc.for_network(net.id)
    index = {name: i for i, name in enumerate(net.node_names)}
    for name, pv, ev in zip(rows["to"], rows["pv_kwp"], rows["ev_count"]):
        i = index.get(name)
        if i is not None and i > 0:
            net.pv_kwp[i] = pv
            net.ev_count[i] = ev
