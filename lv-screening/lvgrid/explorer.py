"""Grid data explorer (Dash, local server, read-only): what the LV grid export holds, before any scenario.

    python -m lvgrid explore [--port 8051]      ->  http://127.0.0.1:8051
    (?network=LV_Grid_101 opens a network, ?tab=checks|map|networks a tab)

Overview  key figures and distributions: transformers, fuse sizes, line km by cross-section, feeder lengths,
          planning demand against transformer rating, LV networks per HV/MV substation.
Checks    data-quality checks on the tables and on the networks as network.py builds them for the load flow;
          a row filters the network table to the affected networks.
Map       the MV/LV substations, coloured by check status, a figure, or the HV/MV substation that feeds them.
Networks  one row per network (sortable, filterable); a row opens the network.
Network   facts and checks, topology on the map (lines by ampacity, connections by fuse-rated power), its lines and
          connections as tables.

Everything is computed from ../data at start-up (a few seconds) and kept in memory; map tiles need internet access.
"""
from __future__ import annotations

import re
import time
from dataclasses import dataclass
from functools import lru_cache
from urllib.parse import parse_qs

import numpy as np
import pandas as pd
import plotly.graph_objects as go
from dash import Dash, Input, Output, ctx, dash_table, dcc, html, no_update
from dash.dash_table.Format import Format, Group, Scheme
from scipy.sparse import csr_matrix
from scipy.sparse.csgraph import dijkstra

from .dashboard import BLUE_RAMP, C
from .data import Portfolio, load_portfolio, network_number
from .geo import load_geo, network_coordinates
from .mv import MV_DIR
from .network import EDGE_LINE, Network, build_network, topology_ok

FUSE_A_PER_KW = 1 / (np.sqrt(3) * 0.4 * 0.9)        # PLmax = sqrt(3) x 400 V x I_fuse x cos(phi) 0.9 (oiken-db-extraction)
SECTION_PLACEHOLDERS = (0, 999)
CHECKS = [   # key, severity, label, what is counted, meaning
    ("build_error", "error", "cannot be built", "network", "no transformer in the substation table: no load flow possible"),
    ("not_connected", "error", "nodes cut off from the transformer", "nodes",
     "no path to the transformer; the screening reports topology_error"),
    ("self_loop", "error", "self-loop lines", "lines",
     "both ends on one node once the closed LV switches are collapsed; the screening reports topology_error"),
    ("no_connections", "warning", "no connection with a fuse rating", "network", "the network carries no demand"),
    ("fuse_over_trafo", "warning", "connection fuse above the transformer rating", "connections",
     "one connection's fuse-rated power exceeds the network's transformer kVA: an entry error, or a placeholder transformer"),
    ("pv_over_trafo", "warning", "existing generation above the transformer rating", "nodes",
     "one node's pg_kw exceeds the network's transformer kVA: mostly plants (usine, pompage, prod), so pg_kw is not only PV"),
    ("planning_over_trafo", "warning", "planning demand above the transformer rating", "network",
     "demand_factor x the fuse-rated power of all connections exceeds the transformer kVA"),
    ("meshed", "info", "meshed LV lines", "network", "loops or parallel branches; the load flow handles them"),
    ("several_trafos", "info", "several transformers", "network", "a shared MV busbar is the slack (network.py)"),
    ("tiny_trafo", "info", "transformer of 10 kVA or less", "network",
     "found at plant and pumping sites: likely a placeholder rather than a real LV transformer"),
    ("trafo_reversed", "info", "transformer row stored LV->MV", "network", "read correctly by the network builder"),
    ("duplicate_rows", "info", "duplicate line rows", "lines", "dropped by the network builder"),
    ("section_placeholder", "info", "cross-section missing or placeholder", "lines",
     "section_mm2 empty, 0 or 999; the load flow does not use it (r, x and ampacity are set)"),
    ("unlocated", "info", "nodes without coordinates", "nodes", "drawn at the nearest located neighbour"),
    ("hvmv_unmapped", "info", "HV/MV substation unknown", "network",
     "gaps in the MV data between this network and the HV/MV transformers"),
]
SEVERITY_LABEL = {"error": "✗ error", "warning": "! warning", "info": "i info"}
STATUS_LABEL = {"ok": "✓ ok", "warnings": "! warnings", "errors": "✗ errors"}
STATUS_COLOR = {"ok": C["ok"], "warnings": C["not_converged"], "errors": C["violation"]}   # reserved status steps
AMP_BUCKETS = [(0, 100, "< 100 A"), (100, 200, "100–199 A"), (200, 300, "200–299 A"), (300, np.inf, "≥ 300 A")]
AMP_COLORS = ["#86b6ef", "#3987e5", "#1c5cab", "#0d366b"]    # blue ramp 250/400/550/700, validated as an ordinal ramp
MAP_RAMP = BLUE_RAMP[2:]                                      # sequential, light end still visible on the light basemap
TABS = ("overview", "checks", "map", "networks", "network")
COLOR_BY = {"status": "check status", "trafo_kva": "transformer rating [kVA]", "n_connections": "connections",
            "fuse_kw": "fuse-rated power [kW]", "planning_pct_trafo": "planning demand [% of transformer]",
            "existing_pv_kw": "existing generation [kW]", "longest_m": "longest path from the transformer [m]",
            "located_pct": "nodes with coordinates [%]"}
TABLE_COLS = [   # column, label, decimals (None = text)
    ("network_id", "network", None), ("name", "substation", None), ("hvmv_label", "HV/MV", None),
    ("status_label", "status", None), ("n_connections", "connections", 0), ("n_nodes", "nodes", 0),
    ("line_km", "lines [km]", 2), ("longest_m", "longest path [m]", 0), ("n_transformers", "transformers", 0),
    ("trafo_kva", "transformer [kVA]", 0), ("fuse_kw", "fuse-rated [kW]", 0), ("planning_pct_trafo", "planning [% trafo]", 0),
    ("existing_pv_kw", "existing gen. [kW]", 1), ("located_pct", "located [%]", 0), ("checks", "checks", None)]
CSS = """
body { margin: 0; background: #f9f9f7; color: #0b0b0b; font: 14px/1.45 system-ui, -apple-system, "Segoe UI", sans-serif; }
main { max-width: 1280px; margin: 0 auto; padding: 16px; }
h1 { font-size: 22px; margin: 8px 0 4px; } h2 { font-size: 16px; margin: 0 0 4px; } .sub, .note { color: #52514e; } .note { font-size: 12px; }
.card { background: #fcfcfb; border: 1px solid rgba(11,11,11,0.10); border-radius: 8px; padding: 12px 16px; margin: 12px 0; overflow-x: auto; }
.kpis { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 12px; margin: 12px 0; }
.kpi { background: #fcfcfb; border: 1px solid rgba(11,11,11,0.10); border-radius: 8px; padding: 10px 14px; }
.kpi .v { font-size: 24px; font-weight: 600; } .kpi .l { color: #52514e; font-size: 12px; }
.row { display: grid; grid-template-columns: minmax(0,1fr) minmax(0,1fr); gap: 12px; } @media (max-width: 900px) { .row { grid-template-columns: 1fr; } }
.facts { border-collapse: collapse; } .facts td { padding: 3px 12px 3px 0; vertical-align: top; } .facts td:first-child { color: #52514e; white-space: nowrap; }
"""


# --------------------------------------------------------------------- data --
@dataclass
class Inventory:
    portfolio: Portfolio
    cfg: dict
    nets: pd.DataFrame                  # one row per network (index network_id): figures, check counts n_<key>, status
    nodes: pd.DataFrame                 # one row per (network_id, node) that ends a line: fuse rating, existing generation
    checks: pd.DataFrame                # one row per check: networks affected, items
    geo: dict[str, pd.DataFrame]        # network_id -> its rows of geo/node_coordinates.csv
    hvmv: pd.DataFrame                  # HV/MV substations (mv/hvmv.csv) with a display label


def _longest_path_m(net: Network) -> float:
    """Longest distance from the transformer to a node along the lines [m]."""
    N = net.n_nodes
    a, b = np.minimum(net.edge_from, net.edge_to), np.maximum(net.edge_from, net.edge_to)
    w = np.maximum(net.length_m, 1e-3)                  # zero-length edges (MV busbar) must still connect
    keep = a != b
    key, w = (a * N + b)[keep], w[keep]
    order = np.lexsort((w, key))                        # parallel branches: keep the shortest (csr would add them up)
    key, w = key[order], w[order]
    first = np.r_[True, key[1:] != key[:-1]]
    key, w = key[first], w[first]
    d = dijkstra(csr_matrix((w, (key // N, key % N)), shape=(N, N)), directed=False, indices=0)
    return float(d[np.isfinite(d)].max())


def build_inventory(cfg: dict, ids: list[str] | None = None) -> Inventory:
    """Per-network figures and data checks of the whole export (or of `ids`)."""
    P = load_portfolio()
    if ids is not None:
        P = Portfolio(P.lines[P.lines["network_id"].isin(ids)], P.subs[P.subs["network_id"].isin(ids)])
    L, S = P.lines, P.subs
    T = S[S["object"].str.startswith("T")]
    trafos = T.assign(reversed=T["from_kv"] < 1, tiny=T["rated_kva"] <= 10).groupby("network_id").agg(
        n_transformers=("object", "size"), trafo_kva=("rated_kva", "sum"), n_trafo_reversed=("reversed", "max"),
        n_tiny_trafo=("tiny", "max"),
        trafo_sizes=("rated_kva", lambda s: " + ".join(f"{v:,.0f}" for v in sorted(s, reverse=True))))

    nodes = L.drop_duplicates(["network_id", "to"])[["network_id", "to", "plmax_kw", "qlmax_kvar", "pg_kw"]]
    nodes = nodes.rename(columns={"to": "node"}).reset_index(drop=True)
    kva = nodes["network_id"].map(trafos["trafo_kva"])
    nodes["pv_over_trafo"] = nodes["pg_kw"] > kva
    per_node = nodes.assign(conn=nodes["plmax_kw"] > 0, pv=nodes["pg_kw"] > 0, fuse_over=nodes["plmax_kw"] > kva).groupby(
        "network_id").agg(n_connections=("conn", "sum"), fuse_kw=("plmax_kw", "sum"), existing_pv_kw=("pg_kw", "sum"),
                          n_pv=("pv", "sum"), n_fuse_over_trafo=("fuse_over", "sum"), n_pv_over_trafo=("pv_over_trafo", "sum"))

    sec = L["section_mm2"]
    per_line = L.assign(km=L["length_m"] / 1e3, cable_km=np.where(L["kind"] == "Cable", L["length_m"] / 1e3, 0.0),
                        placeholder=sec.isna() | sec.isin(SECTION_PLACEHOLDERS)).drop_duplicates(
        ["network_id", "from", "to", "line"]).groupby("network_id").agg(
        line_km=("km", "sum"), cable_km=("cable_km", "sum"), n_section_placeholder=("placeholder", "sum"))

    geo_nodes, geo_subs = load_geo()
    geo_nodes = geo_nodes[geo_nodes["network_id"].isin(P.ids)]
    per_geo = geo_nodes.assign(missing=geo_nodes["source"] == "missing").groupby("network_id").agg(
        n_unlocated=("missing", "sum"), n_geo=("missing", "size"))

    built = []
    for nid in P.ids:
        lines, subs = P.network(nid)
        try:
            net = build_network(nid, lines, subs, cfg)
        except Exception as e:      # NetworkError or an unexpected data problem: recorded, like the screening does
            built.append({"network_id": nid, "n_build_error": 1, "issues": str(e)})
            continue
        dropped = re.search(r"(\d+) duplicate line rows dropped", "; ".join(net.issues))    # found after switch collapsing
        built.append({"network_id": nid, "n_nodes": net.n_nodes, "n_lines": int((net.edge_type == EDGE_LINE).sum()),
                      "n_not_connected": int((~net.reachable_from_slack()).sum()),
                      "n_duplicate_rows": int(dropped.group(1)) if dropped else 0,
                      "n_self_loop": int((net.edge_from == net.edge_to).sum()), "n_meshed": int(not net.is_radial),
                      "topology_ok": topology_ok(net), "longest_m": _longest_path_m(net), "issues": "; ".join(net.issues)})

    lv_map = pd.read_csv(MV_DIR / "lv_to_hvmv.csv", dtype=str).set_index("network_id")
    hvmv = pd.read_csv(MV_DIR / "hvmv.csv", dtype={"hvmv": str, "code": str, "name": str})
    hvmv["label"] = [f"{h} {n.removeprefix('SST ').title() if isinstance(n, str) else c} ({city})"
                     for h, n, c, city in zip(hvmv["hvmv"], hvmv["name"], hvmv["code"], hvmv["city"])]

    nets = pd.DataFrame(index=pd.Index(P.ids, name="network_id")).join(
        [geo_subs.set_index("network_id")[["code", "name", "lat", "lon"]], trafos, per_node, per_line, per_geo,
         pd.DataFrame(built).set_index("network_id")])
    nets["name"] = nets["name"].fillna("")
    mapped = lv_map["status"].reindex(nets.index) == "ok"
    nets["hvmv"] = lv_map["hvmv"].reindex(nets.index).where(mapped)
    nets["hvmv_label"] = nets["hvmv"].map(dict(zip(hvmv["hvmv"], hvmv["label"]))).fillna("unknown")
    nets["n_hvmv_unmapped"] = (~mapped).astype(int)
    nets["planning_kw"] = cfg["demand_factor"] * nets["fuse_kw"]
    nets["planning_pct_trafo"] = 100 * nets["planning_kw"] / nets["trafo_kva"]
    nets["n_planning_over_trafo"] = nets["planning_kw"] > nets["trafo_kva"]
    nets["n_several_trafos"] = nets["n_transformers"] > 1
    nets["n_no_connections"] = nets["n_connections"].fillna(0) == 0
    nets["located_pct"] = 100 * (1 - nets["n_unlocated"] / nets["n_geo"])
    nets["cable_pct"] = 100 * nets["cable_km"] / nets["line_km"]
    counts = [f"n_{k}" for k, *_ in CHECKS] + ["n_transformers", "n_connections", "n_pv", "n_nodes", "n_lines"]
    nets[counts] = nets[counts].fillna(0).astype(int)

    flags = pd.DataFrame({k: nets[f"n_{k}"] > 0 for k, *_ in CHECKS})
    worst = {s: flags[[k for k, sev, *_ in CHECKS if sev == s]].any(axis=1) for s in ("error", "warning")}
    nets["status"] = np.select([worst["error"], worst["warning"]], ["errors", "warnings"], "ok")
    nets["status_label"] = nets["status"].map(STATUS_LABEL)
    nets["checks"] = [", ".join(flags.columns[row]) for row in flags.to_numpy()]
    checks = pd.DataFrame([{"id": k, "severity": SEVERITY_LABEL[sev], "check": label, "networks": int(flags[k].sum()),
                            "items": "" if unit == "network" else f"{int(nets[f'n_{k}'].sum()):,} {unit}", "meaning": meaning}
                           for k, sev, label, unit, meaning in CHECKS])
    return Inventory(P, cfg, nets, nodes, checks, {k: g for k, g in geo_nodes.groupby("network_id", sort=False)}, hvmv)


# ------------------------------------------------------------------ figures --
def _style(fig: go.Figure, title: str, height: int = 340) -> go.Figure:
    fig.update_layout(title=dict(text=title, x=0, font=dict(size=14)), template="plotly_white", height=height,
                      margin=dict(l=55, r=20, t=45, b=50), paper_bgcolor=C["surface"], plot_bgcolor=C["surface"],
                      font=dict(family='system-ui, -apple-system, "Segoe UI", sans-serif', color=C["ink"], size=12),
                      legend=dict(orientation="h", y=1.0, yanchor="bottom", x=1, xanchor="right", bgcolor="rgba(0,0,0,0)"),
                      hoverlabel=dict(bgcolor="#fff"), barcornerradius=4, bargap=0.15)
    fig.update_xaxes(gridcolor=C["grid"], zerolinecolor=C["axis"], linecolor=C["axis"])
    fig.update_yaxes(gridcolor=C["grid"], zerolinecolor=C["axis"], linecolor=C["axis"])
    return fig


def _empty(text: str, height: int = 220) -> go.Figure:
    fig = _style(go.Figure(), "", height)
    fig.add_annotation(text=text, showarrow=False, font=dict(color=C["ink2"]), xref="paper", yref="paper", x=0.5, y=0.5)
    fig.update_xaxes(visible=False)
    fig.update_yaxes(visible=False)
    return fig


def _bar(x, y, title: str, xtitle: str, ytitle: str, unit: str) -> go.Figure:
    fig = go.Figure(go.Bar(x=x, y=y, marker_color=C["demand"], hovertemplate=f"%{{x}}: %{{y:,}} {unit}<extra></extra>"))
    fig.update_xaxes(title=xtitle, type="category")
    fig.update_yaxes(title=ytitle)
    return _style(fig, title)


def kpis(inv: Inventory) -> list[tuple[str, str]]:
    n, nodes = inv.nets, inv.nodes
    st = n["status"].value_counts()
    pv_ok = nodes.loc[~nodes["pv_over_trafo"], "pg_kw"].sum() / 1e3
    return [(f"{len(n):,}", "LV networks (MV/LV substations)"),
            (f"{n['n_connections'].sum():,}", f"connections with a fuse rating, of {len(nodes):,} nodes"),
            (f"{n['line_km'].sum():,.0f} km", f"LV lines, {100 * n['cable_km'].sum() / n['line_km'].sum():.0f} % cable"),
            (f"{n['n_transformers'].sum():,}", f"transformers, {n['trafo_kva'].sum() / 1e3:,.0f} MVA"),
            (f"{n['fuse_kw'].sum() / 1e3:,.0f} MW", f"fuse-rated power; planning demand {n['planning_kw'].sum() / 1e3:,.0f} MW "
                                                    f"({100 * inv.cfg['demand_factor']:.0f} %)"),
            (f"{pv_ok:,.0f} MW", f"existing generation, without the {int(nodes['pv_over_trafo'].sum())} nodes above their "
                                 f"transformer rating ({nodes['pg_kw'].sum() / 1e3:,.0f} MW with them)"),
            (f"{100 * (1 - n['n_unlocated'].sum() / n['n_geo'].sum()):.0f} %", "nodes with coordinates"),
            (f"{(n['n_hvmv_unmapped'] == 0).sum():,}", f"networks traced to one of {len(inv.hvmv)} HV/MV substations"),
            (f"{st.get('errors', 0):,}", f"networks with {STATUS_LABEL['errors']}: no load flow (Checks tab)"),
            (f"{st.get('warnings', 0):,}", f"networks with {STATUS_LABEL['warnings']}: implausible data (Checks tab)")]


def overview_figures(inv: Inventory) -> dict[str, go.Figure]:
    nets, P = inv.nets, inv.portfolio
    T = P.subs[P.subs["object"].str.startswith("T")]
    vc = T["rated_kva"].value_counts().sort_index()
    trafos = _bar([f"{k:,.0f}" for k in vc.index], vc.to_numpy(), f"Transformers by rating ({len(T):,})",
                  "rating [kVA]", "transformers", "transformers")

    amps = (inv.nodes.loc[inv.nodes["plmax_kw"] > 0, "plmax_kw"] * FUSE_A_PER_KW).round().astype(int).value_counts()
    top, other = amps.head(10).sort_index(), int(amps.iloc[10:].sum())
    fuses = _bar([f"{a} A" for a in top.index] + (["other"] if other else []), list(top.to_numpy()) + ([other] if other else []),
                 "Connections by fuse size (fuse-rated power / (√3 · 400 V · 0.9))", "fuse", "connections", "connections")

    L = P.lines.drop_duplicates(["network_id", "from", "to", "line"])
    sec = L["section_mm2"]
    cat = np.where(sec.isna() | sec.isin(SECTION_PLACEHOLDERS), "missing", sec.map(lambda v: f"{v:g}"))
    km = L.assign(cat=cat, km=L["length_m"] / 1e3).groupby(["cat", "kind"])["km"].sum().unstack(fill_value=0.0)
    order = sorted((c for c in km.index if c != "missing"), key=float) + (["missing"] if "missing" in km.index else [])
    km = km.reindex(order)
    sections = go.Figure([go.Bar(x=km.index, y=km[kind], name=label, marker=dict(color=col, line=dict(color=C["surface"], width=1)),
                                 hovertemplate=f"%{{x}} mm²: %{{y:,.1f}} km {label}<extra></extra>")
                          for kind, label, col in (("Cable", "cable", C["demand"]), ("Line", "overhead line", C["pv"])) if kind in km])
    sections.update_layout(barmode="stack", legend_traceorder="normal")
    sections.update_xaxes(title="cross-section [mm²] (missing: empty, 0 or 999)", type="category")
    sections.update_yaxes(title="km")
    _style(sections, "LV lines by cross-section")

    x = nets["longest_m"].dropna()
    lengths = go.Figure(go.Histogram(x=x, xbins=dict(start=0, size=50), marker=dict(color=C["demand"], line=dict(color=C["surface"], width=1)),
                                     hovertemplate="%{x} m: %{y} networks<extra></extra>"))
    lengths.update_xaxes(title="longest distance from the transformer along the lines [m]")
    lengths.update_yaxes(title="networks")
    _style(lengths, f"Longest path from the transformer (median {x.median():.0f} m)")

    n = nets[(nets["planning_kw"] > 0) & (nets["trafo_kva"] > 0)]
    planning = go.Figure(go.Scatter(
        x=n["trafo_kva"], y=n["planning_kw"], mode="markers", customdata=n.index, showlegend=False,
        marker=dict(color=C["demand"], size=8, opacity=0.6, line=dict(color=C["surface"], width=1)),
        hovertemplate="%{customdata}<br>transformer %{x:,.0f} kVA<br>planning demand %{y:,.0f} kW<extra></extra>"))
    lo, hi = min(n["trafo_kva"].min(), n["planning_kw"].min()), max(n["trafo_kva"].max(), n["planning_kw"].max())
    planning.add_scatter(x=[lo, hi], y=[lo, hi], mode="lines", line=dict(color=C["muted"], width=1), hoverinfo="skip", showlegend=False)
    planning.add_annotation(x=np.log10(hi), y=np.log10(hi), text="= transformer rating", showarrow=False, xanchor="right",
                            yanchor="bottom", font=dict(color=C["ink2"]))
    planning.update_xaxes(type="log", title="transformer rating [kVA]")
    planning.update_yaxes(type="log", title=f"planning demand [kW] ({100 * inv.cfg['demand_factor']:.0f} % of fuse-rated)")
    _style(planning, f"Planning demand against transformer rating: {int(nets['n_planning_over_trafo'].sum())} above (click opens)")

    g = nets.groupby("hvmv_label").agg(networks=("status", "size"), connections=("n_connections", "sum"),
                                       fuse_mw=("fuse_kw", lambda s: s.sum() / 1e3)).sort_values("networks")
    g = pd.concat([g.loc[g.index == "unknown"], g.loc[g.index != "unknown"]])      # bottom to top: unknown, then by size
    feeders = go.Figure(go.Bar(
        y=g.index, x=g["networks"], orientation="h", customdata=np.c_[g["connections"], g["fuse_mw"]],
        marker_color=[C["muted"] if h == "unknown" else C["demand"] for h in g.index],
        hovertemplate="%{y}: %{x} networks, %{customdata[0]:,} connections, %{customdata[1]:,.0f} MW fuse-rated<extra></extra>"))
    feeders.update_xaxes(title="LV networks")
    _style(feeders, "LV networks per HV/MV substation (MV trace, mv.py)", 380)
    return {"trafos": trafos, "fuses": fuses, "sections": sections, "lengths": lengths, "planning": planning, "feeders": feeders}


def _zoom(lat: np.ndarray, lon: np.ndarray, width_px: float = 1100, height_px: float = 600) -> float:
    """Web-mercator zoom that fits the points in a map of about width x height pixels (MapLibre: 512 px tiles)."""
    dlon = max(np.ptp(lon), 1e-5)
    dlat = max(np.ptp(lat), 1e-5) / np.cos(np.radians(np.mean(lat)))
    return float(np.clip(np.log2(min(width_px / dlon, height_px / dlat) * 360 / 512) - 0.2, 1, 19))


def _map_layout(fig: go.Figure, lat, lon, height: int) -> go.Figure:
    lat, lon = np.asarray(lat, float), np.asarray(lon, float)
    fig.update_layout(map=dict(style="carto-positron", zoom=_zoom(lat, lon),
                               center=dict(lat=float(lat.min() + lat.max()) / 2, lon=float(lon.min() + lon.max()) / 2)),
                      height=height, margin=dict(l=0, r=0, t=0, b=0), paper_bgcolor=C["surface"],
                      font=dict(family='system-ui, -apple-system, "Segoe UI", sans-serif', color=C["ink"], size=12),
                      legend=dict(x=0.01, y=0.99, bgcolor="rgba(252,252,251,0.9)"), hoverlabel=dict(bgcolor="#fff"))
    return fig


def map_figure(inv: Inventory, by: str) -> go.Figure:
    """The substations, coloured by check status, a figure of COLOR_BY, or 'hvmv:<id>' (that substation's networks)."""
    n = inv.nets.dropna(subset=["lat", "lon"])
    text = pd.Series([f"{nid} {r.name}<br>{r.status_label}<br>{r.n_connections:,} connections, "
                      + (f"{r.trafo_kva:,.0f} kVA" if r.trafo_kva == r.trafo_kva else "no transformer") + f"<br>HV/MV {r.hvmv_label}"
                      for nid, r in zip(n.index, n.itertuples())], index=n.index)
    fig = go.Figure(go.Scattermap(lat=n["lat"], lon=n["lon"], mode="markers", hoverinfo="skip", showlegend=False,
                                  marker=dict(size=13, color=C["ink2"], opacity=0.7)))      # dark ring under every marker

    def add(sel, name, color, txt=text, size=9, **marker):
        fig.add_scattermap(lat=n.loc[sel, "lat"], lon=n.loc[sel, "lon"], mode="markers", name=name,
                           customdata=n.index[sel.to_numpy()], text=txt[sel], hovertemplate="%{text}<extra></extra>",
                           marker=dict(size=size, color=color, **marker))

    if by == "status":
        for st, size in (("ok", 8), ("warnings", 12), ("errors", 12)):
            add(n["status"] == st, STATUS_LABEL[st], STATUS_COLOR[st], size=size)
    elif by.startswith("hvmv:"):
        fed = n["hvmv"] == by[5:]
        add(~fed, "other networks", C["axis"])
        add(fed, f"fed by {inv.hvmv.set_index('hvmv')['label'].get(by[5:], by[5:])}", C["demand"])
    else:
        v = n[by]
        has = v.notna()
        add(~has, "no value", C["axis"])
        add(has, COLOR_BY[by], v[has], txt=text + f"<br>{COLOR_BY[by]}: " + v.map("{:,.1f}".format),
            colorscale=[[i / (len(MAP_RAMP) - 1), c] for i, c in enumerate(MAP_RAMP)],
            cmin=float(v.min()), cmax=float(v.quantile(0.98)), colorbar=dict(title=COLOR_BY[by], thickness=12, len=0.6))
    return _map_layout(fig, n["lat"], n["lon"], 640)


# ----------------------------------------------------------------- network --
def _line_attrs(lines: pd.DataFrame) -> pd.DataFrame:
    return lines.assign(line=lines["line"].astype(str)).drop_duplicates("line").set_index("line")


def topology_figure(inv: Inventory, net: Network, lines: pd.DataFrame) -> go.Figure:
    """Lines by ampacity, connections sized by fuse-rated power, existing generation ringed in orange, on the map
    when the network has coordinates, else on a force-directed layout."""
    names = np.array(net.node_names)
    geo_rows = inv.geo.get(net.id)
    lat, lon, located = (network_coordinates(net, geo_rows) if geo_rows is not None
                         else (np.full(net.n_nodes, np.nan),) * 2 + (np.zeros(net.n_nodes, bool),))
    on_map = bool(np.isfinite(lat).all() and np.ptp(lat) + np.ptp(lon) > 0)
    if on_map:
        x, y = lon, lat
    else:
        import networkx as nx
        G = nx.Graph()
        G.add_nodes_from(range(net.n_nodes))
        G.add_edges_from(zip(net.edge_from.tolist(), net.edge_to.tolist()))
        pos = nx.kamada_kawai_layout(G)
        x, y = np.array([pos[i][0] for i in range(net.n_nodes)]), np.array([pos[i][1] for i in range(net.n_nodes)])
    fig = go.Figure()

    def add(xs, ys, **kw):
        (fig.add_scattermap(lon=xs, lat=ys, **kw) if on_map else fig.add_scatter(x=xs, y=ys, **kw))

    lv = np.flatnonzero(net.edge_type == EDGE_LINE)
    ef, et, amp = net.edge_from, net.edge_to, net.ampacity_a
    for (lo, hi, label), col, width in zip(AMP_BUCKETS, AMP_COLORS, (2, 2.5, 3, 3.5)):
        sel = lv[(amp[lv] >= lo) & (amp[lv] < hi)]
        if len(sel):
            xs = np.c_[x[ef[sel]], x[et[sel]], np.full(len(sel), np.nan)].ravel()
            ys = np.c_[y[ef[sel]], y[et[sel]], np.full(len(sel), np.nan)].ravel()
            add(xs, ys, mode="lines", name=f"line {label}", line=dict(color=col, width=width), hoverinfo="skip")
    attrs = _line_attrs(lines)
    etext = []
    for e in lv:
        a = attrs.loc[net.edge_id[e]] if net.edge_id[e] in attrs.index else None
        detail = "" if a is None else (f"<br>{a['section_mm2']:g} mm² {a['material']} {a['kind']}, "
                                       f"r {a['r_ohm_km']:.3f} Ω/km, x {a['x_ohm_km']:.3f} Ω/km")
        etext.append(f"line {net.edge_id[e]}: {names[ef[e]]} → {names[et[e]]}<br>{net.length_m[e]:,.0f} m, "
                     f"ampacity {amp[e]:.0f} A{detail}")
    add((x[ef[lv]] + x[et[lv]]) / 2, (y[ef[lv]] + y[et[lv]]) / 2, mode="markers", text=etext, showlegend=False,
        hovertemplate="%{text}<extra></extra>", marker=dict(size=10, color=C["surface"], opacity=0))

    sub = np.zeros(net.n_nodes, bool)
    sub[0] = True
    sub[ef[net.edge_type != EDGE_LINE]] = sub[et[net.edge_type != EDGE_LINE]] = True
    conn, pv = net.plmax_kw > 0, net.pg_kw > 0
    size = np.clip(7 + 2.5 * np.sqrt(net.plmax_kw / 10), 7, 24)
    where = ["" if ok or not on_map else "<br>no coordinates: drawn at the nearest located node" for ok in located]
    ntext = np.array([f"{names[i]}<br>fuse-rated {net.plmax_kw[i]:,.1f} kW (≈ {net.plmax_kw[i] * FUSE_A_PER_KW:.0f} A), "
                      f"{net.qlmax_kvar[i]:,.1f} kvar" + (f"<br>existing generation {net.pg_kw[i]:,.1f} kW" if pv[i] else "")
                      + where[i]
                      for i in range(net.n_nodes)])
    other = ~conn & ~sub
    add(x[other], y[other], mode="markers", name="node without connection",
        text=[names[i] + where[i] for i in np.flatnonzero(other)], hovertemplate="%{text}<extra></extra>",
        marker=dict(size=5, color=C["muted"]))
    add(x[pv], y[pv], mode="markers", name="existing generation", text=ntext[pv], hovertemplate="%{text}<extra></extra>",
        marker=dict(size=size[pv] + 6, color=C["pv"]))
    add(x[conn], y[conn], mode="markers", name="connection (size: fuse-rated power)", text=ntext[conn],
        hovertemplate="%{text}<extra></extra>", marker=dict(size=size[conn], color=C["ink2"]))
    add(x[:1], y[:1], mode="markers", name="substation", hovertemplate=f"{names[0]} (transformer MV side)<extra></extra>",
        marker=dict(size=18, color=C["ink"]))
    if on_map:
        return _map_layout(fig, lat, lon, 620)
    _style(fig, "No coordinates for this network: force-directed layout", 620)
    fig.update_xaxes(visible=False)
    fig.update_yaxes(visible=False, scaleanchor="x", scaleratio=1)
    return fig


def network_facts(inv: Inventory, nid: str) -> list[tuple[str, str]]:
    r = inv.nets.loc[nid]
    if r["n_build_error"]:
        return [("substation", f"{r['code']} {r['name']}".strip()), ("status", r["status_label"]), ("cannot be built", r["issues"])]
    return [("substation", f"{r['code']} {r['name']}".strip()), ("status", r["status_label"]),
            ("HV/MV substation", r["hvmv_label"]),
            ("transformers", f"{r['n_transformers']}: {r['trafo_sizes']} kVA"),
            ("connections", f"{r['n_connections']:,} with a fuse rating, of {r['n_nodes']:,} nodes"),
            ("LV lines", f"{r['n_lines']:,}, {r['line_km']:,.2f} km, {r['cable_pct']:.0f} % cable; "
                         f"longest path from the transformer {r['longest_m']:,.0f} m"),
            ("fuse-rated power", f"{r['fuse_kw']:,.0f} kW; planning demand {r['planning_kw']:,.0f} kW = "
                                 f"{r['planning_pct_trafo']:.0f} % of the transformer rating"),
            ("existing generation", f"{r['existing_pv_kw']:,.1f} kW at {r['n_pv']} nodes (pg_kw: mostly PV)"),
            ("coordinates", f"{r['located_pct']:.0f} % of the nodes located"),
            ("network builder notes", r["issues"] or "none")]


def network_tables(inv: Inventory, nid: str) -> tuple[list[dict], list[dict]]:
    lines, _ = inv.portfolio.network(nid)
    lt = lines[["line", "from", "to", "length_m", "section_mm2", "material", "kind", "ampacity_a", "r_ohm_km", "x_ohm_km"]]
    n = inv.nodes[(inv.nodes["network_id"] == nid) & ((inv.nodes["plmax_kw"] > 0) | (inv.nodes["pg_kw"] > 0))]
    src = inv.geo[nid].set_index("node")["source"] if nid in inv.geo else pd.Series(dtype=str)
    ct = n.assign(fuse_a=(n["plmax_kw"] * FUSE_A_PER_KW).round(), coordinates=n["node"].map(src).fillna("missing"))
    return lt.to_dict("records"), ct[["node", "plmax_kw", "fuse_a", "qlmax_kvar", "pg_kw", "coordinates"]].to_dict("records")


# ---------------------------------------------------------------------- app --
def _table(tid: str, cols: list[tuple[str, str, int | None]], **kw) -> dash_table.DataTable:
    opts = dict(
        sort_action="native", filter_action="native", style_table={"overflowX": "auto"}, style_as_list_view=True,
        style_header={"fontWeight": 600, "color": C["ink2"], "backgroundColor": C["surface"]},
        style_cell={"fontFamily": "system-ui, sans-serif", "fontSize": 13, "padding": "4px 8px", "backgroundColor": C["surface"],
                    "textAlign": "right"},
        style_cell_conditional=[{"if": {"column_id": c}, "textAlign": "left"} for c, _, nd in cols if nd is None])
    return dash_table.DataTable(
        id=tid, columns=[{"name": label, "id": c, "type": "numeric" if nd is not None else "text",
                          **({"format": Format(precision=nd, scheme=Scheme.fixed, group=Group.yes)} if nd is not None else {})}
                         for c, label, nd in cols], **{**opts, **kw})


def _graph(gid: str, fig: go.Figure | None = None) -> html.Div:
    return html.Div(dcc.Graph(id=gid, figure=fig or {}, config={"displaylogo": False, "responsive": True}), className="card")


def _facts(rows: list[tuple[str, str]]) -> html.Table:
    return html.Table([html.Tr([html.Td(k), html.Td(v)]) for k, v in rows], className="facts")


def make_app(inv: Inventory) -> Dash:
    app = Dash(__name__, title="Grid data explorer")
    app.index_string = app.index_string.replace("{%css%}", "{%css%}<style>" + CSS + "</style>")
    nets = inv.nets
    ids = sorted(nets.index, key=network_number)
    figs = overview_figures(inv)
    hvmv_opts = [{"label": f"fed by {lab}", "value": f"hvmv:{h}"} for h, lab in zip(inv.hvmv["hvmv"], inv.hvmv["label"])]
    app.layout = html.Main([
        dcc.Location(id="url", refresh=False),
        html.H1("Grid data explorer"),
        html.P(f"What the LV grid export holds (data/lv_grids, data/geo, data/mv): {len(nets):,} networks, read at start-up. "
               "Read-only; independent of any scenario.", className="sub"),
        dcc.Tabs(id="tabs", value="overview", children=[
            dcc.Tab(label="Overview", value="overview", children=[
                html.Div([html.Div([html.Div(v, className="v"), html.Div(lab, className="l")], className="kpi")
                          for v, lab in kpis(inv)], className="kpis"),
                html.Div([_graph("g-trafos", figs["trafos"]), _graph("g-fuses", figs["fuses"])], className="row"),
                html.Div([_graph("g-sections", figs["sections"]), _graph("g-lengths", figs["lengths"])], className="row"),
                html.Div([_graph("g-planning", figs["planning"]), _graph("g-feeders", figs["feeders"])], className="row")]),
            dcc.Tab(label="Checks", value="checks", children=[html.Div([
                html.P("Errors stop the load flow of a network, warnings point at implausible data, info describes how the "
                       "data is shaped. Click a row to list its networks.", className="note"),
                _table("checks", [("severity", "severity", None), ("check", "check", None), ("networks", "networks", 0),
                                  ("items", "items", None), ("meaning", "meaning", None)],
                       data=inv.checks.to_dict("records"), sort_action="none", filter_action="none",
                       style_data={"whiteSpace": "normal", "height": "auto"},
                       style_data_conditional=[{"if": {"column_id": "severity"}, "whiteSpace": "nowrap"}])], className="card")]),
            dcc.Tab(label="Map", value="map", children=[
                dcc.Dropdown(id="color-by", value="status", clearable=False, style={"maxWidth": "420px", "marginTop": "12px"},
                             options=[{"label": f"colour by {lab}", "value": k} for k, lab in COLOR_BY.items()] + hvmv_opts),
                _graph("g-map"),
                html.P("Click a substation to open its network. Colours of figures stop at the 98th percentile.", className="note")]),
            dcc.Tab(label="Networks", value="networks", children=[html.Div([
                _table("table", TABLE_COLS, data=nets.reset_index().assign(id=nets.index)[[c for c, *_ in TABLE_COLS] + ["id"]]
                       .to_dict("records"), page_size=20, sort_by=[{"column_id": "n_connections", "direction": "desc"}]),
                html.P("Click a row to open the network. Filter under a header, e.g. > 300 or contains meshed; "
                       "a row of the Checks tab fills the checks filter.", className="note")], className="card")]),
            dcc.Tab(label="Network", value="network", children=[
                dcc.Dropdown(id="net", clearable=False, style={"maxWidth": "420px", "marginTop": "12px"},
                             options=[{"label": f"{n} {nets.at[n, 'name']}".strip(), "value": n} for n in ids]),
                html.Div(id="net-facts", className="card"),
                _graph("g-topology"),
                html.Div([html.H2("Lines"), _table("lines", [
                    ("line", "line", None), ("from", "from", None), ("to", "to", None), ("length_m", "length [m]", 1),
                    ("section_mm2", "section [mm²]", 0), ("material", "material", None), ("kind", "kind", None),
                    ("ampacity_a", "ampacity [A]", 0), ("r_ohm_km", "r [Ω/km]", 3), ("x_ohm_km", "x [Ω/km]", 3)],
                    page_size=12)], className="card"),
                html.Div([html.H2("Connections and existing generation"), _table("conns", [
                    ("node", "node", None), ("plmax_kw", "fuse-rated [kW]", 1), ("fuse_a", "≈ fuse [A]", 0),
                    ("qlmax_kvar", "fuse-rated [kvar]", 1), ("pg_kw", "existing generation [kW]", 1),
                    ("coordinates", "coordinates", None)],
                    page_size=12)], className="card")]),
        ]),
    ])

    @app.callback(Output("g-map", "figure"), Input("color-by", "value"))
    def show_map(by):
        return map_figure(inv, by)

    @app.callback(Output("net", "value"), Output("tabs", "value"), Output("table", "filter_query"),
                  Input("url", "search"), Input("table", "active_cell"), Input("checks", "active_cell"),
                  Input("g-map", "clickData"), Input("g-planning", "clickData"))
    def navigate(search, cell, check_cell, map_click, planning_click):
        trig = ctx.triggered_id
        if trig == "checks" and check_cell:
            return no_update, "networks", f'{{checks}} contains "{check_cell["row_id"]}"'
        if trig == "table" and cell:
            return cell["row_id"], "network", no_update
        click = {"g-map": map_click, "g-planning": planning_click}.get(trig)
        if click and click["points"][0].get("customdata"):
            return click["points"][0]["customdata"], "network", no_update
        query = parse_qs((search or "").lstrip("?"))
        wanted, tab = query.get("network", [""])[0], query.get("tab", [""])[0]
        tab = tab if tab in TABS else no_update
        if wanted in nets.index:
            return wanted, "network" if tab is no_update else tab, no_update
        return nets["n_connections"].idxmax(), tab, no_update

    @lru_cache(maxsize=32)
    def view(nid: str):
        lines, subs = inv.portfolio.network(nid)
        try:
            fig = topology_figure(inv, build_network(nid, lines, subs, inv.cfg), lines)
        except Exception as e:      # the network cannot be built: facts and tables still show the raw data
            fig = _empty(f"no topology: {e}")
        return fig, *network_tables(inv, nid)

    @app.callback(Output("net-facts", "children"), Output("g-topology", "figure"), Output("lines", "data"),
                  Output("conns", "data"), Input("net", "value"))
    def show_network(nid):
        if not nid:
            return [], _empty("pick a network"), [], []
        r = nets.loc[nid]
        found = [f"{SEVERITY_LABEL[sev]}: {label}" + (f" ({r[f'n_{k}']:,} {unit})" if unit != "network" else "") + f": {meaning}"
                 for k, sev, label, unit, meaning in CHECKS if r[f"n_{k}"] > 0]
        fig, lines, conns = view(nid)
        return ([html.H2(f"{nid} {r['name']}".strip()), _facts(network_facts(inv, nid)),
                 html.Ul([html.Li(s) for s in found], className="note") if found else None], fig, lines, conns)

    return app


def run(cfg: dict, host: str = "127.0.0.1", port: int = 8051) -> None:
    t0 = time.time()
    print("reading the grid data ...", flush=True)
    inv = build_inventory(cfg)
    print(f"{len(inv.nets)} networks in {time.time() - t0:.1f} s; grid data explorer on http://{host}:{port}  (Ctrl-C to stop)")
    make_app(inv).run(host=host, port=port)
