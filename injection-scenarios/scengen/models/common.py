"""Helpers shared by the models: SFOE population scaling, the split of a regional total over the nodes, seasons."""
from __future__ import annotations

import numpy as np
import pandas as pd


def population_ratio(sfoe: dict) -> float:
    """Sion+Sierre share of the national population (scales the national SFOE figures)."""
    return sfoe["population_sion_sierre"] / sfoe["population_national"]


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


def split_by_fuse(nodes: pd.DataFrame, total: float, integer: bool = False) -> np.ndarray:
    """Share of each node in a regional total (port of the MATLAB allocate_PV_EV_SFOE): between networks in
    proportion to their fuse-rated power (sum of plmax_kw), within a network in proportion to each node's;
    nodes without a fuse rating get nothing. integer=True splits by largest remainder at both levels."""
    per_net = nodes.groupby("network_id", sort=False)["plmax_kw"].sum()
    net_share = (pd.Series(largest_remainder(int(total), per_net.to_numpy()), index=per_net.index) if integer
                 else total * per_net / per_net.sum())
    out = np.zeros(len(nodes), int if integer else float)
    w_all = nodes["plmax_kw"].to_numpy()
    for nid, idx in nodes.groupby("network_id", sort=False).indices.items():
        w = w_all[idx]
        active = w > 0
        if not active.any():
            continue
        if integer:
            out[idx[active]] = largest_remainder(int(net_share[nid]), w[active])
        else:
            out[idx[active]] = net_share[nid] * w[active] / w[active].sum()
    return out


SEASON_MONTHS = {
    "winter": (12, 1, 2), "spring": (3, 4, 5), "summer": (6, 7, 8), "autumn": (9, 10, 11), "all": tuple(range(1, 13)),
}


def season_mask(months: np.ndarray, season: str) -> np.ndarray:
    return np.isin(months, SEASON_MONTHS[season])
