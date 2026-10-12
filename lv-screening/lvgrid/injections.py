"""Per-node power time series of one network, and their CSV form.

Three streams, all in 3-phase kW with consumption positive:
    demand  demand_factor x fuse-rated peak (P + jQ, constant power factor)
            times a synthetic household day shape per node
    pv      scenario kWp per node times the normalised PV profile
    ev      scenario EV count per node, uncontrolled evening charging
`case_injection_pu` combines them into the net injection the load flow needs.

CSV layout of scenarios/<name>/daily/<network>.csv (one row per step, wide):
    step, hour, <node>:demand_kw, <node>:demand_kvar, <node>:pv_kw, <node>:ev_kw ...
Only nodes with a non-zero stream get a column.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
import pandas as pd

from .config import kw_per_pu
from .network import Network

CASES = {
    "demand": ("demand",),
    "demand+pv": ("demand", "pv"),
    "demand+pv+ev": ("demand", "pv", "ev"),
}
STREAMS = ("demand_kw", "demand_kvar", "pv_kw", "ev_kw")


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


def write_daily_csv(path: Path, nodes: list[str], time_h: np.ndarray, demand_kw: np.ndarray,
                    demand_kvar: np.ndarray, pv_kw: np.ndarray, ev_kw: np.ndarray) -> None:
    """Arrays are [T x n] in the order of `nodes`; all-zero columns are left out."""
    cols = {"step": np.arange(len(time_h)), "hour": time_h}
    for name, arr in zip(STREAMS, (demand_kw, demand_kvar, pv_kw, ev_kw)):
        for j, node in enumerate(nodes):
            if np.any(arr[:, j]):
                cols[f"{node}:{name}"] = arr[:, j]
    pd.DataFrame(cols).to_csv(path, index=False, float_format="%.5g")


def read_daily_csv(path: Path, net: Network) -> Injections:
    """The network's injections [T x N] in its internal node order (nodes not in
    the file, e.g. pruned ones, get zero)."""
    df = pd.read_csv(path)
    index = {name: i for i, name in enumerate(net.node_names)}
    T, N = len(df), net.n_nodes
    arrays = {s: np.zeros((T, N)) for s in STREAMS}
    for col in df.columns[2:]:
        node, stream = col.rsplit(":", 1)
        i = index.get(node)
        if i is not None:
            arrays[stream][:, i] = df[col].to_numpy(float)
    return Injections(df["hour"].to_numpy(float), arrays["demand_kw"] + 1j * arrays["demand_kvar"],
                      arrays["pv_kw"], arrays["ev_kw"])
