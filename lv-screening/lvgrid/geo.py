"""Node <-> coordinates.

The grid export names nodes `N_<id_NOD>` (the node id of the DSO database);
substation-internal nodes (`N_Fus_`, `N_JbL_`, `N_JbM_`, `N_TrL_`, `N_TrM_`,
`N_SWM_`, `N_MPt_`) are components of a substation and take its position. The
network id itself is the substation's id_NOD (LV_Grid_101 <-> id_NOD 101).
`data/geo/nodes_db.csv` is the node table pulled from the DB backup by
tools/extract_nodes_from_bak.py (Swiss LV95 easting/northing).
"""
from __future__ import annotations

from collections import deque
from pathlib import Path

import numpy as np
import pandas as pd

from .config import DATA_DIR
from .data import Portfolio, network_number

INTERNAL_PREFIXES = ("N_Fus_", "N_JbL_", "N_JbM_", "N_TrL_", "N_TrM_", "N_SWM_", "N_MPt_")
GEO_DIR = DATA_DIR / "geo"


def lv95_to_wgs84(E, N):
    """Swiss LV95 (EPSG:2056) -> WGS84 lat/lon, swisstopo approximate formulas (~1 m)."""
    y = (np.asarray(E, float) - 2_600_000) / 1e6
    x = (np.asarray(N, float) - 1_200_000) / 1e6
    lon = 2.6779094 + 4.728982 * y + 0.791484 * y * x + 0.1306 * y * x**2 - 0.0436 * y**3
    lat = 16.9023892 + 3.238272 * x - 0.270978 * y**2 - 0.002528 * x**2 - 0.0447 * y**2 * x - 0.0140 * x**3
    return lat * 100 / 36, lon * 100 / 36


def load_nodes_db(path: Path | None = None) -> pd.DataFrame:
    df = pd.read_csv(path or GEO_DIR / "nodes_db.csv", dtype={"code": str, "name": str}, low_memory=False)
    return df.set_index("id_nod")


def node_id_of(name: str) -> int | None:
    """id_NOD of a regular node name `N_<int>`, else None."""
    if name.startswith("N_") and name[2:].isdigit():
        return int(name[2:])
    return None


def match_nodes(portfolio: Portfolio, nodes_db: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    """(nodes, substations) tables with LV95 and WGS84 coordinates.

    nodes: one row per (network_id, node): id_nod, code, E, N, lat, lon,
           source = 'db' (own coordinates), 'substation' (internal node placed
           at its substation), 'missing' (DB has no coordinates for it)
    substations: one row per network: id_nod, code, name, E, N, lat, lon
    """
    # substation of every internal node: the substation table that lists it
    internal_home: dict[str, str] = {}
    for nid, a, b in zip(portfolio.subs["network_id"], portfolio.subs["from"], portfolio.subs["to"]):
        internal_home.setdefault(a, nid)
        internal_home.setdefault(b, nid)

    subs = pd.DataFrame({"network_id": portfolio.ids})
    subs["id_nod"] = subs["network_id"].map(network_number)
    hit = subs["id_nod"].isin(nodes_db.index)
    subs["code"] = np.where(hit, nodes_db["code"].reindex(subs["id_nod"]).to_numpy(), "")
    subs["name"] = np.where(hit, nodes_db["name"].reindex(subs["id_nod"]).to_numpy(), "")
    subs["E"] = nodes_db["E_lv95"].reindex(subs["id_nod"]).to_numpy()
    subs["N"] = nodes_db["N_lv95"].reindex(subs["id_nod"]).to_numpy()
    sub_E = dict(zip(subs["network_id"], subs["E"]))
    sub_N = dict(zip(subs["network_id"], subs["N"]))

    pairs = pd.concat([portfolio.lines[["network_id", "from"]].rename(columns={"from": "node"}),
                       portfolio.lines[["network_id", "to"]].rename(columns={"to": "node"}),
                       portfolio.subs[["network_id", "from"]].rename(columns={"from": "node"}),
                       portfolio.subs[["network_id", "to"]].rename(columns={"to": "node"})]).drop_duplicates()
    rows = []
    for nid, name in zip(pairs["network_id"], pairs["node"]):
        i = node_id_of(name)
        if i is not None:
            if i in nodes_db.index:
                E, N = nodes_db.at[i, "E_lv95"], nodes_db.at[i, "N_lv95"]
                rows.append((nid, name, i, nodes_db.at[i, "code"], E, N, "db" if np.isfinite(E) else "missing"))
            else:
                rows.append((nid, name, i, "", np.nan, np.nan, "missing"))
        else:
            home = internal_home.get(name, nid)
            rows.append((nid, name, network_number(home), "", sub_E.get(home, np.nan), sub_N.get(home, np.nan), "substation"))
    nodes = pd.DataFrame(rows, columns=["network_id", "node", "id_nod", "code", "E", "N", "source"])
    nodes.loc[nodes["source"] == "substation", "source"] = np.where(
        np.isfinite(nodes.loc[nodes["source"] == "substation", "E"]), "substation", "missing")
    for df in (nodes, subs):
        lat, lon = lv95_to_wgs84(df["E"], df["N"])
        df["lat"], df["lon"] = lat, lon
    return nodes, subs


def write_geo(portfolio: Portfolio, out_dir: Path | None = None) -> Path:
    out_dir = out_dir or GEO_DIR
    nodes, subs = match_nodes(portfolio, load_nodes_db(out_dir / "nodes_db.csv"))
    nodes.to_csv(out_dir / "node_coordinates.csv", index=False, float_format="%.6f")
    subs.to_csv(out_dir / "substations.csv", index=False, float_format="%.6f")
    n = len(nodes)
    counts = nodes["source"].value_counts()
    print(f"{n} (network, node) pairs: {counts.get('db', 0)} with own coordinates, "
          f"{counts.get('substation', 0)} placed at their substation, {counts.get('missing', 0)} missing "
          f"({100 * (n - counts.get('missing', 0)) / n:.1f}% located)")
    print(f"{int(subs['lat'].notna().sum())} / {len(subs)} substations located -> {out_dir}")
    return out_dir


def load_geo(geo_dir: Path | None = None) -> tuple[pd.DataFrame, pd.DataFrame] | None:
    geo_dir = geo_dir or GEO_DIR
    f = geo_dir / "node_coordinates.csv"
    if not f.exists():
        return None
    nodes = pd.read_csv(f, dtype={"node": str, "code": str})
    subs = pd.read_csv(geo_dir / "substations.csv", dtype={"code": str, "name": str})
    return nodes, subs


def network_coordinates(net, geo_rows: pd.DataFrame) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """(lat, lon, located) per internal node from this network's rows of
    node_coordinates.csv; unlocated nodes are placed at the nearest located
    neighbour so that the whole network can be drawn."""
    g = geo_rows.set_index("node")
    lat = g["lat"].reindex(net.node_names).to_numpy(float)
    lon = g["lon"].reindex(net.node_names).to_numpy(float)
    located = np.isfinite(lat) & np.isfinite(lon)
    if located.any() and not located.all():
        adj = [[] for _ in range(net.n_nodes)]
        for a, b in zip(net.edge_from, net.edge_to):
            adj[a].append(b)
            adj[b].append(a)
        q = deque(np.flatnonzero(located))
        filled = located.copy()
        while q:
            u = q.popleft()
            for v in adj[u]:
                if not filled[v]:
                    lat[v], lon[v] = lat[u], lon[u]
                    filled[v] = True
                    q.append(v)
    return lat, lon, located
