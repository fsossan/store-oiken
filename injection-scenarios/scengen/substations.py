"""Level nl4: a scenario at the HV/MV substations (65/16 kV), each one the sum of the LV networks it feeds.

The allocation of level nl7 (per connection) is summed per substation (grid.networks["hvmv"], from
../data/mv/lv_to_hvmv.csv), then each model's `expected` gives the series a large sum of connections converges to:
PV exactly (linear in kWp, one profile), demand and EV in expectation (the random household days and charging
sessions average out over the thousands of connections of a substation). Same scenario, same allocation, no
per-network draw and no file per network.

Not included, as in level nl7: LV and MV losses, MV-connected customers and generators. The networks without a
substation (gaps in the MV data) are left out and counted in scenario.json ("unmapped").
"""
from __future__ import annotations

import numpy as np
import pandas as pd

from .config import DATA_DIR
from .injections import Injections

INFO = ("code", "name", "city", "mva")       # columns of ../data/mv/hvmv.csv carried into the allocation


def allocation(inj: Injections) -> tuple[pd.DataFrame, dict]:
    """Per HV/MV substation (rows sorted by id): its code, name, city and rating, the number of networks and
    connections it feeds and the sums of the allocation columns (plmax_kw, qlmax_kvar, nominal_demand_kw, pv_kwp,
    ev_count, ...); and the totals of the connections whose network has no substation."""
    alloc = inj.allocation.assign(hvmv=inj.allocation["network_id"].map(inj.grid.networks["hvmv"]))
    sums = [c for c in inj.allocation.columns if c not in ("network_id", "node")]
    mapped, lost = alloc[alloc["hvmv"].notna()], alloc[alloc["hvmv"].isna()]
    rows = mapped.groupby("hvmv").agg(n_networks=("network_id", "nunique"), n_connections=("node", "size"),
                                      **{c: (c, "sum") for c in sums}).reset_index()
    rows = rows.iloc[np.argsort(rows["hvmv"].astype(int).to_numpy(), kind="stable")].reset_index(drop=True)
    info_file = DATA_DIR / "mv" / "hvmv.csv"
    if info_file.exists():
        info = pd.read_csv(info_file, dtype={"hvmv": str})[["hvmv", *INFO]]
        rows = rows.merge(info, on="hvmv", how="left")[["hvmv", *INFO, *[c for c in rows.columns if c != "hvmv"]]]
    unmapped = {"networks": int(lost["network_id"].nunique()), "connections": int(len(lost)),
                **{c: float(lost[c].sum()) for c in sums}}
    return rows, unmapped


def series(inj: Injections, rows: pd.DataFrame, days: list[int], samples: int) -> dict[str, np.ndarray]:
    """Expected series of every substation, column (<stream>_kw / _kvar) -> [substations x days x steps]."""
    out: dict[str, np.ndarray] = {}
    for m in inj.models:
        out.update(m.expected(inj.state[m.NAME], rows, [int(d) for d in days], samples))
    return out
