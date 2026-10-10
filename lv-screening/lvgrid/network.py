"""One LV network -> electrical model.

Port of the MATLAB `combined_lv_sub_SFOE` + `get_grid_SFOE` pair (tech-selection
and sanity_check), with the same modelling choices:

* the MV side of the transformer is the slack bus at V_slack; with several
  transformers, a shared MV busbar (found through the MV switches) is the slack
  and is tied to each transformer's MV node by a negligible impedance;
* closed LV switches inside the substation collapse onto the transformer's LV
  node; feeders behind open LV switches are pruned;
* transformer R/X are rebased from the transformer's own kVA base to the common
  per-unit base; zero impedances become 1e-5 pu;
* duplicate (from, to, line) rows are dropped;
* nodal ratings are read once per node from the first line that ends at it
  (parallel branches repeat the same values in the source table);
* the model is a single-phase equivalent: 3-phase kW / 3 / (Sb/1000) = pu.

One deliberate difference: the slack bus is always internal node 0 (the
MATLAB code assumed it was node 1, which fails for 15 networks whose
transformer row is stored LV->MV).
"""
from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field

import numpy as np
import pandas as pd

from .config import base_impedance_ohm

EDGE_LINE, EDGE_TRAFO, EDGE_MVBUS = 0, 2, 3
MIN_IMPEDANCE_PU = 1e-5


class NetworkError(Exception):
    """The network cannot be built (no transformer, slack missing, ...)."""


@dataclass
class Network:
    id: str
    node_names: list[str]                # internal index -> source name; 0 = slack
    edge_from: np.ndarray                # [L] internal indices
    edge_to: np.ndarray
    edge_id: list[str]                   # line id / 'T<kVA>' / 'MV_bus'
    edge_type: np.ndarray                # EDGE_LINE / EDGE_TRAFO / EDGE_MVBUS
    length_m: np.ndarray
    r_pu: np.ndarray
    x_pu: np.ndarray
    ampacity_a: np.ndarray               # per edge; transformers: kVA / (sqrt3 * V_LV)
    plmax_kw: np.ndarray                 # [N] fuse-rated peak, 3-phase kW (0 at slack)
    qlmax_kvar: np.ndarray
    pg_kw: np.ndarray                    # [N] existing PV, 3-phase kW
    trafo_kva: np.ndarray                # [n_trafo] ratings
    trafo_edges: np.ndarray              # [n_trafo] edge indices
    Y: np.ndarray                        # [N x N] complex nodal admittance, pu
    issues: list[str] = field(default_factory=list)
    pv_kwp: np.ndarray = None            # [N] scenario PV (allocation), 3-phase kWp; zeros until apply_allocation
    ev_count: np.ndarray = None          # [N] scenario EV count

    # ---- derived -------------------------------------------------------
    @property
    def n_nodes(self) -> int:
        return len(self.node_names)

    @property
    def n_edges(self) -> int:
        return len(self.edge_from)

    @property
    def y_edge(self) -> np.ndarray:
        return 1.0 / (self.r_pu + 1j * self.x_pu)

    @property
    def is_radial(self) -> bool:
        return self.n_edges == self.n_nodes - 1

    @property
    def num(self) -> int:
        return int("".join(ch for ch in self.id if ch.isdigit()))

    def reachable_from_slack(self) -> np.ndarray:
        """Boolean [N]: node connected to the slack through the edge list."""
        adj = [[] for _ in range(self.n_nodes)]
        for a, b in zip(self.edge_from, self.edge_to):
            adj[a].append(b)
            adj[b].append(a)
        seen = np.zeros(self.n_nodes, bool)
        seen[0] = True
        q = deque([0])
        while q:
            u = q.popleft()
            for v in adj[u]:
                if not seen[v]:
                    seen[v] = True
                    q.append(v)
        return seen


def build_network(network_id: str, lines: pd.DataFrame, subs: pd.DataFrame, cfg: dict) -> Network:
    """Electrical model of one network from its line and substation tables."""
    Zb = base_impedance_ohm(cfg)
    Vb = cfg["per_unit"]["Vb_V"]
    issues: list[str] = []

    # ---- 1. substation elements -------------------------------------------
    is_trafo = subs["object"].str.startswith("T").to_numpy()
    is_mv = (np.minimum(subs["from_kv"], subs["to_kv"]) >= 1).to_numpy()
    trafo = subs[is_trafo].copy()
    mv_sw = subs[~is_trafo & is_mv]
    lv_sw = subs[~is_trafo & ~is_mv]
    if trafo.empty:
        raise NetworkError("no transformer in the substation table")

    # transformer pu -> common base
    zb_trafo = Vb ** 2 / (trafo["rated_kva"].to_numpy(float) * 1e3 / 3)
    conv = zb_trafo / Zb
    trafo["r_pu"] = trafo["r_pu"].to_numpy(float) * conv
    trafo["x_pu"] = trafo["x_pu"].to_numpy(float) * conv

    mv_side_is_from = (trafo["from_kv"] >= 1).to_numpy()
    trm = np.where(mv_side_is_from, trafo["from"], trafo["to"])      # MV node of each trafo
    trl = np.where(mv_side_is_from, trafo["to"], trafo["from"])      # LV node of each trafo
    if not mv_side_is_from.all():
        issues.append("transformer row stored LV->MV")

    # ---- 2. slack = shared MV busbar --------------------------------------
    shared_mv = None
    trm_set = set(trm)
    for _, row in mv_sw.iterrows():
        if row["to"] in trm_set:
            shared_mv = row["from"]
            break
    if shared_mv is None:
        if len(set(trm)) == 1:
            shared_mv = trm[0]
        else:
            shared_mv = trm[int(np.argmax(trafo["rated_kva"].to_numpy()))]
            issues.append("no shared MV bus found; using largest transformer's MV node")

    # ---- 3. collapse closed LV switches onto the transformer LV node -------
    closed = lv_sw[lv_sw["on_off"] == 1]
    adj: dict[str, list[str]] = {}
    for a, b in zip(closed["from"], closed["to"]):
        adj.setdefault(a, []).append(b)
        adj.setdefault(b, []).append(a)
    collapse: dict[str, str] = {}
    for t in trl:
        seen = {t}
        q = deque([t])
        while q:
            u = q.popleft()
            for v in adj.get(u, []):
                if v not in seen:
                    seen.add(v)
                    q.append(v)
                    collapse[v] = t
    lv_from = lines["from"].map(lambda s: collapse.get(s, s)).to_numpy()
    lv_to = lines["to"].map(lambda s: collapse.get(s, s)).to_numpy()

    # ---- 4. prune feeders behind open LV switches --------------------------
    dead = set(lv_sw.loc[lv_sw["on_off"] == 0, "to"])
    orig_from = lines["from"].to_numpy()
    orig_to = lines["to"].to_numpy()
    changed = bool(dead)
    while changed:
        new = set(orig_to[np.isin(orig_from, list(dead))]) - dead
        changed = bool(new)
        dead |= new
    live = ~np.isin(orig_from, list(dead)) if dead else np.ones(len(lines), bool)
    if (~live).any():
        issues.append(f"{int((~live).sum())} line rows pruned behind open switches")
    lines = lines[live]
    lv_from, lv_to = lv_from[live], lv_to[live]

    # ---- 5. edge list ------------------------------------------------------
    n_tr = len(trafo)
    lv_kv = np.minimum(trafo["from_kv"], trafo["to_kv"]).to_numpy(float)
    t_amp = trafo["rated_kva"].to_numpy(float) / (np.sqrt(3) * lv_kv)
    r_lv = (lines["r_ohm_km"].to_numpy(float) * lines["length_m"].to_numpy(float) / 1e3) / Zb
    x_lv = (lines["x_ohm_km"].to_numpy(float) * lines["length_m"].to_numpy(float) / 1e3) / Zb

    parts = []   # (from, to, id, length, r, x, amp, type)
    if n_tr == 1:
        slack = trm[0]
    else:
        slack = shared_mv
        for k in range(n_tr):
            parts.append((slack, trm[k], "MV_bus", 0.0, 0.0, 1e-4, t_amp[k], EDGE_MVBUS))
    for k in range(n_tr):
        parts.append((trafo["from"].iloc[k], trafo["to"].iloc[k], f"T{int(trafo['rated_kva'].iloc[k])}",
                      0.01, float(trafo["r_pu"].iloc[k]), float(trafo["x_pu"].iloc[k]), t_amp[k], EDGE_TRAFO))
    for k in range(len(lines)):
        parts.append((lv_from[k], lv_to[k], str(lines["line"].iloc[k]), float(lines["length_m"].iloc[k]),
                      r_lv[k], x_lv[k], float(lines["ampacity_a"].iloc[k]), EDGE_LINE))

    # ---- 6. node indices (slack first), duplicates ------------------------
    names = [slack]
    index = {slack: 0}
    for p in parts:
        for nm in (p[0], p[1]):
            if nm not in index:
                index[nm] = len(names)
                names.append(nm)
    seen_edges = set()
    keep = []
    for p in parts:
        key = (index[p[0]], index[p[1]], p[2])
        if key in seen_edges:
            continue
        seen_edges.add(key)
        keep.append(p)
    if len(keep) < len(parts):
        issues.append(f"{len(parts) - len(keep)} duplicate line rows dropped")
    parts = keep

    edge_from = np.array([index[p[0]] for p in parts], int)
    edge_to = np.array([index[p[1]] for p in parts], int)
    edge_id = [p[2] for p in parts]
    length = np.array([p[3] for p in parts], float)
    r = np.array([p[4] for p in parts], float)
    x = np.array([p[5] for p in parts], float)
    amp = np.array([p[6] for p in parts], float)
    etype = np.array([p[7] for p in parts], int)
    r[r == 0] = MIN_IMPEDANCE_PU
    x[x == 0] = MIN_IMPEDANCE_PU

    # ---- 7. nodal ratings: first line ending at each node -----------------
    N = len(names)
    plmax = np.zeros(N)
    qlmax = np.zeros(N)
    pg = np.zeros(N)
    assigned = np.zeros(N, bool)
    lv_rows = [(index[lv_to[k]], k) for k in range(len(lines))]
    # transformer / MV-bus edges end at substation nodes whose rating is 0:
    for e in range(len(parts)):
        if etype[e] != EDGE_LINE:
            assigned[edge_to[e]] = True
    for node, k in lv_rows:
        if not assigned[node]:
            assigned[node] = True
            plmax[node] = float(lines["plmax_kw"].iloc[k])
            qlmax[node] = float(lines["qlmax_kvar"].iloc[k])
            pg[node] = float(lines["pg_kw"].iloc[k])
    plmax[0] = qlmax[0] = pg[0] = 0.0

    # ---- 8. admittance matrix ---------------------------------------------
    y = 1.0 / (r + 1j * x)
    Y = np.zeros((N, N), complex)
    np.add.at(Y, (edge_from, edge_from), y)
    np.add.at(Y, (edge_to, edge_to), y)
    np.add.at(Y, (edge_from, edge_to), -y)
    np.add.at(Y, (edge_to, edge_from), -y)

    net = Network(
        id=network_id, node_names=names, edge_from=edge_from, edge_to=edge_to, edge_id=edge_id,
        edge_type=etype, length_m=length, r_pu=r, x_pu=x, ampacity_a=amp,
        plmax_kw=plmax, qlmax_kvar=qlmax, pg_kw=pg,
        trafo_kva=trafo["rated_kva"].to_numpy(float), trafo_edges=np.flatnonzero(etype == EDGE_TRAFO),
        Y=Y, issues=issues,
    )
    net.pv_kwp = np.zeros(N)
    net.ev_count = np.zeros(N, int)

    # ---- 9. topology checks ------------------------------------------------
    if (edge_from == edge_to).any():
        issues.append(f"{int((edge_from == edge_to).sum())} self-loop line(s)")
    unreachable = int((~net.reachable_from_slack()).sum())
    if unreachable:
        issues.append(f"{unreachable} node(s) not connected to the slack")
    if not net.is_radial:
        issues.append("meshed (more lines than nodes - 1)")
    if (amp <= 0).any():
        issues.append(f"{int((amp <= 0).sum())} line(s) without ampacity")
    if plmax.sum() > 0 and net.trafo_kva.sum() > 0 and plmax.sum() * cfg["demand_factor"] > net.trafo_kva.sum():
        issues.append("planning demand (demand_factor x fuse-rated peak) exceeds transformer rating")
    return net


def topology_ok(net: Network) -> bool:
    """False when the load flow cannot be trusted (self-loops, nodes not connected to the slack)."""
    return not any(("self-loop" in s) or ("not connected to the slack" in s) for s in net.issues)
