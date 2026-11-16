"""Helpers shared by the models: national figures scaled to the region, the split of a regional total over the
connections, seasons."""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import pandas as pd


@dataclass(frozen=True)
class National:
    """The national figures of the scenario (its `sfoe` block) and the region's share of them (by `sfoe.to_region`)."""
    figures: dict
    share: float

    def to_region(self, key: str, unit: float = 1.0) -> float:
        """The national figure `key`, in `unit`s, scaled to the region."""
        return self.figures[key] * unit * self.share


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


SPLITS = {                                             # split method -> the weight of each connection
    "fuse": lambda c: c["plmax_kw"].to_numpy(float),    # its fuse-rated power (port of the MATLAB allocate_PV_EV_SFOE)
    "connections": lambda c: np.ones(len(c)),           # the same for every connection
}


def split(connections: pd.DataFrame, total: float, by: str, integer: bool = False, where: str = "split") -> np.ndarray:
    """Share of each connection in a regional total, by the split method `by` (a key of SPLITS): between networks in
    proportion to the sum of their connections' weights, within a network in proportion to each connection's weight.
    integer=True splits by largest remainder at both levels. `where` names the config key in errors."""
    if by not in SPLITS:
        raise ValueError(f"{where}: unknown split '{by}'; known: {', '.join(SPLITS)}")
    w_all = SPLITS[by](connections)
    per_net = pd.Series(w_all, index=connections.index).groupby(connections["network_id"], sort=False).sum()
    net_share = (pd.Series(largest_remainder(int(total), per_net.to_numpy()), index=per_net.index) if integer
                 else total * per_net / per_net.sum())
    out = np.zeros(len(connections), int if integer else float)
    for nid, idx in connections.groupby("network_id", sort=False).indices.items():
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
SEASONS = ("winter", "spring", "summer", "autumn")       # winter: December, January and February of the same year


def season_mask(months: np.ndarray, season: str) -> np.ndarray:
    return np.isin(months, SEASON_MONTHS[season])
