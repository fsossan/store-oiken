"""Per-node power time series of one network (read from a generated scenario).

The scenario's streams (scenario.json["streams"], e.g. demand / pv / ev) are
kept apart, each in 3-phase kW + j kvar in its own sign: 'load' streams
consumption positive, 'generation' streams production positive. A case is a
'+'-joined list of streams ("demand+pv+ev"); `case_injection_pu` sums the
case's streams into the net injection the load flow needs, so the load flow
never sees the individual models.

CSV layout written by injection-scenarios (daily/<network>.csv, one row per
step, wide): step, hour, <node>:<stream>_kw, <node>:<stream>_kvar ... (only
nodes with a non-zero stream have a column; a missing _kvar means Q = 0).
"""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
import pandas as pd

from .config import kw_per_pu
from .network import Network

DEFAULT_STREAMS = {"demand": "load", "pv": "generation", "ev": "load"}    # outputs written without a stream list


def check_streams(signs: dict[str, str]) -> dict[str, str]:
    bad = {k: v for k, v in signs.items() if v not in ("load", "generation")}
    if bad:
        raise ValueError(f"stream signs must be 'load' or 'generation': {bad}")
    return signs


def check_cases(cases: list[str], signs: dict[str, str]) -> None:
    for c in cases:
        parts = c.split("+")
        if not set(parts) <= set(signs) or len(set(parts)) != len(parts):
            raise KeyError(f"unknown case {c}: a case joins distinct streams of the scenario with '+' ({', '.join(signs)})")


def default_cases(streams: dict[str, str]) -> list[str]:
    """Cumulative in stream order: demand, demand+pv, demand+pv+ev, ... (each case adds one driver)."""
    names = list(streams)
    return ["+".join(names[:k]) for k in range(1, len(names) + 1)]


@dataclass
class Injections:
    time_h: np.ndarray                   # [T]
    streams: dict[str, np.ndarray]       # name -> [T x N] complex kW + j kvar, in the stream's own sign
    signs: dict[str, str]                # name -> 'load' | 'generation'
    meta: dict = field(default_factory=dict)

    def aggregate(self) -> dict[str, np.ndarray]:
        """Active power of each stream summed over the nodes: {'<stream>_kw': [T]}."""
        return {f"{name}_kw": x.real.sum(axis=1) for name, x in self.streams.items()}


def case_injection_pu(inj: Injections, case: str, cfg: dict) -> np.ndarray:
    """Net injection of a case at the non-slack nodes [T x N-1], pu, generation positive."""
    s = np.zeros_like(next(iter(inj.streams.values())))
    for name in case.split("+"):
        if inj.signs[name] == "generation":
            s += inj.streams[name]
        else:
            s -= inj.streams[name]
    return s[:, 1:] / kw_per_pu(cfg)


def zero_injections(time_h: np.ndarray, n_nodes: int, signs: dict[str, str]) -> Injections:
    return Injections(time_h, {name: np.zeros((len(time_h), n_nodes), complex) for name in signs}, signs)


def read_daily_csv(path: Path, net: Network, signs: dict[str, str]) -> Injections:
    """The network's injections [T x N] in its internal node order (nodes not in
    the file, e.g. pruned ones, get zero)."""
    df = pd.read_csv(path)
    index = {name: i for i, name in enumerate(net.node_names)}
    inj = zero_injections(df["hour"].to_numpy(float), net.n_nodes, signs)
    for col in df.columns[2:]:
        node, _, column = col.rpartition(":")
        name, _, unit = column.rpartition("_")
        if not node or name not in signs or unit not in ("kw", "kvar"):
            raise KeyError(f"{path}: column {col} is not <node>:<stream>_kw|_kvar of a stream of the scenario ({', '.join(signs)})")
        i = index.get(node)
        if i is not None:
            inj.streams[name][:, i] += df[col].to_numpy(float) * (1 if unit == "kw" else 1j)
    return inj
