"""HTML dashboard of a results folder: static pages, plotly, no server.

    results/<run>/dashboard/index.html      portfolio overview + sortable table
    results/<run>/dashboard/net_<id>.html   one page per selected network
    results/<run>/dashboard/plotly.min.js   shared once

Colours follow the project's chart palette: three categorical series
(demand blue, PV orange, EV aqua), one sequential blue ramp for magnitudes,
and the reserved status colours (good / warning / critical), always paired
with a text label.
"""
from __future__ import annotations

import html
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import plotly.graph_objects as go
from plotly.offline import get_plotlyjs
from plotly.subplots import make_subplots

from .config import DATA_DIR

C = {"demand": "#2a78d6", "pv": "#eb6834", "ev": "#1baf7a", "net": "#52514e",
     "ok": "#0ca30c", "violation": "#d03b3b", "not_converged": "#fab219",
     "topology_error": "#898781", "build_error": "#898781",
     "ink": "#0b0b0b", "ink2": "#52514e", "muted": "#898781", "grid": "#e1e0d9", "axis": "#c3c2b7",
     "surface": "#fcfcfb", "page": "#f9f9f7"}
BLUE_RAMP = ["#cde2fb", "#9ec5f4", "#6da7ec", "#3987e5", "#256abf", "#184f95", "#0d366b"]
ORANGE_RAMP = ["#f9d3c2", "#f3a784", "#eb6834", "#b8441c"]
STATUS_LABEL = {"ok": "&#10003; ok", "violation": "&#10007; violation", "not_converged": "! not converged",
                "topology_error": "? topology error", "build_error": "? build error"}
STATUS_ORDER = ["ok", "violation", "not_converged", "topology_error", "build_error"]
VIOLATION_KINDS = ["undervoltage", "overvoltage", "line_overload", "trafo_overload"]

CSS = """
:root { color-scheme: light; }
body { margin: 0; background: #f9f9f7; color: #0b0b0b; font: 14px/1.45 system-ui, -apple-system, "Segoe UI", sans-serif; }
main { max-width: 1280px; margin: 0 auto; padding: 16px; }
h1 { font-size: 22px; margin: 8px 0 4px; } h2 { font-size: 16px; margin: 28px 0 8px; color: #0b0b0b; }
.sub { color: #52514e; margin: 0 0 12px; }
.card { background: #fcfcfb; border: 1px solid rgba(11,11,11,0.10); border-radius: 8px; padding: 12px 16px; margin: 12px 0; overflow-x: auto; }
.kpis { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 12px; }
.kpi { background: #fcfcfb; border: 1px solid rgba(11,11,11,0.10); border-radius: 8px; padding: 10px 14px; }
.kpi .v { font-size: 26px; font-weight: 600; } .kpi .l { color: #52514e; font-size: 12px; }
table { border-collapse: collapse; width: 100%; font-variant-numeric: tabular-nums; }
th, td { padding: 5px 8px; border-bottom: 1px solid #e1e0d9; text-align: right; white-space: nowrap; }
th:first-child, td:first-child { text-align: left; } th { position: sticky; top: 0; background: #fcfcfb; cursor: pointer; color: #52514e; font-weight: 600; }
.facts td:first-child { color: #52514e; } .facts th { text-align: left; }
.badge { display: inline-block; padding: 1px 8px; border-radius: 10px; font-size: 12px; color: #fff; }
a { color: #1c5cab; text-decoration: none; } a:hover { text-decoration: underline; }
.row { display: grid; grid-template-columns: minmax(0,1fr) minmax(0,1fr); gap: 12px; } @media (max-width: 900px) { .row { grid-template-columns: 1fr; } }
.note { color: #52514e; font-size: 12px; }
.controls { margin: 6px 0; color: #52514e; }
"""
JS = """
document.querySelectorAll('table.sortable th').forEach((th, i) => th.addEventListener('click', () => {
  const tb = th.closest('table').tBodies[0], rows = [...tb.rows], asc = th.dataset.asc !== 'true';
  th.closest('table').querySelectorAll('th').forEach(h => delete h.dataset.asc); th.dataset.asc = asc;
  const key = r => { const c = r.cells[i]; return c.dataset.v !== undefined ? c.dataset.v : c.textContent.trim(); };
  rows.sort((a, b) => { const x = key(a), y = key(b), nx = parseFloat(x), ny = parseFloat(y);
    const c = (!isNaN(nx) && !isNaN(ny)) ? nx - ny : String(x).localeCompare(String(y)); return asc ? c : -c; });
  rows.forEach(r => tb.appendChild(r)); }));
const flt = document.getElementById('only-flagged');
if (flt) flt.addEventListener('change', () => document.querySelectorAll('tr.status-ok').forEach(r => r.style.display = flt.checked ? 'none' : ''));
const map = document.getElementById('map');
if (map && map.on) map.on('plotly_click', d => { const u = d.points[0].customdata; if (u) window.location = u; });
"""


# ------------------------------------------------------------------ helpers --
def _page(title: str, body: str) -> str:
    return (f"<!doctype html><html lang='en'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1'>"
            f"<title>{html.escape(title)}</title><style>{CSS}</style><script src='plotly.min.js'></script></head>"
            f"<body><main>{body}</main><script>{JS}</script></body></html>")


def _fig(fig: go.Figure, div_id: str | None = None, height: int = 380) -> str:
    fig.update_layout(template="plotly_white", height=height, margin=dict(l=50, r=20, t=50, b=85),
                      paper_bgcolor=C["surface"], plot_bgcolor=C["surface"],
                      font=dict(family='system-ui, -apple-system, "Segoe UI", sans-serif', color=C["ink"], size=12),
                      legend=dict(orientation="h", y=-0.22, yanchor="top", x=0, bgcolor="rgba(0,0,0,0)"),
                      hoverlabel=dict(bgcolor="#fff"))
    fig.update_xaxes(gridcolor=C["grid"], zerolinecolor=C["axis"], linecolor=C["axis"], tickcolor=C["axis"])
    fig.update_yaxes(gridcolor=C["grid"], zerolinecolor=C["axis"], linecolor=C["axis"], tickcolor=C["axis"])
    return fig.to_html(full_html=False, include_plotlyjs=False, div_id=div_id,
                       config={"displaylogo": False, "responsive": True})


def _badge(status: str) -> str:
    return f"<span class='badge' style='background:{C.get(status, C['muted'])}'>{STATUS_LABEL.get(status, status)}</span>"


def _num(x, nd=1, unit=""):
    if x is None or (isinstance(x, float) and not np.isfinite(x)) or (isinstance(x, str) and not x):
        return "<td>–</td>"
    v = float(x)
    s = f"{v:,.0f}" if nd == 0 else f"{v:.{nd}f}"
    return f"<td data-v='{v}'>{s}{unit}</td>"


def _facts(rows: list[tuple[str, str]]) -> str:
    return "<table class='facts'>" + "".join(f"<tr><td>{k}</td><td>{v}</td></tr>" for k, v in rows) + "</table>"


def _hline(fig, y, text, row=None, col=None):
    fig.add_hline(y=y, line=dict(color=C["muted"], width=1, dash="dash"), annotation_text=text,
                  annotation_position="top left", annotation_font_color=C["ink2"], row=row, col=col)


def _load_run(run_dir: Path):
    summary = pd.read_csv(run_dir / "summary.csv", dtype={"network_id": str, "case": str, "status": str})
    with open(run_dir / "run.json") as f:
        run = json.load(f)
    return summary, run


# ---------------------------------------------------------- portfolio page --
def portfolio_page(summary: pd.DataFrame, run: dict, main_case: str, pages: dict[str, str]) -> str:
    s = summary[summary["case"] == main_case].set_index("network_id")
    cases = run["cases"]
    oneshot = run["mode"] == "oneshot"
    cfg = run["config"]
    lim = cfg["limits"]
    n = len(s)
    counts = s["status"].value_counts()
    title = "LV portfolio sanity check (one-shot)" if oneshot else f"LV portfolio screening, scenario {run['scenario']}"
    parts = [f"<h1>{html.escape(title)}</h1>",
             f"<p class='sub'>{n} networks, created {run['created'][:16].replace('T', ' ')}, {run['seconds']} s. "
             + (f"Snapshot: {cfg['demand_factor']:.0%} of fuse-rated peak at every connection, "
                f"{cfg['oneshot']['generation_factor']:.0%} of existing PV." if oneshot else
                f"Cases: {', '.join(cases)}; metrics below for <b>{main_case}</b>. "
                f"Scenario PV {run['allocation']['pv_region_kwp'] / 1e3:,.0f} MWp and {run['allocation']['ev_region']:,} EVs "
                f"for Sion+Sierre ({run['allocation']['population_ratio']:.2%} of the national figures), "
                f"PV day {run['allocation']['pv_date']} ({cfg['pv']['series']}), {run['n_days']} day(s) at {cfg['time']['step_min']} min.")
             + f" Limits: {lim['v_min_pu']}–{lim['v_max_pu']} pu, line and transformer loading ≤ {lim['line_loading_max']:.0%}.</p>"]

    # KPIs
    pv_col = "existing_pv_kw" if oneshot else "pv_kwp"
    dem = s["nominal_demand_kw"].fillna(0)
    viol = s["status"] == "violation"
    kpis = [(f"{counts.get('ok', 0)}", "networks ok"), (f"{counts.get('violation', 0)}", "with violations"),
            (f"{counts.get('not_converged', 0)}", "load flow not converged"),
            (f"{counts.get('topology_error', 0) + counts.get('build_error', 0)}", "topology / data errors"),
            (f"{dem.sum() / 1e3:,.1f} MW", f"nominal demand ({cfg['demand_factor']:.0%} of fuse-rated peak)"),
            (f"{s[pv_col].fillna(0).sum() / 1e3:,.1f} MWp", "existing PV" if oneshot else "scenario PV"),
            ]
    if not oneshot:
        kpis.append((f"{int(s['ev_count'].fillna(0).sum()):,}", "scenario EVs"))
    kpis.append((f"{100 * dem[viol].sum() / max(dem.sum(), 1e-9):.0f} %", "of nominal demand in networks with violations"))
    parts.append("<div class='kpis'>" + "".join(f"<div class='kpi'><div class='v'>{v}</div><div class='l'>{l}</div></div>" for v, l in kpis) + "</div>")

    # status per case (stacked) and violation kinds per case (grouped: the cases are nested, not additive)
    fig_a = go.Figure()
    for st in STATUS_ORDER:
        vals = [int((summary[summary["case"] == c]["status"] == st).sum()) for c in cases]
        if sum(vals):
            fig_a.add_bar(x=vals, y=cases, orientation="h", name=STATUS_LABEL[st].replace("&#10003;", "✓").replace("&#10007;", "✗"),
                          marker_color=C[st], marker_line=dict(color=C["surface"], width=2),
                          hovertemplate="%{y}: %{x} networks<extra>" + st + "</extra>")
    fig_a.update_layout(barmode="stack", bargap=0.35, title=dict(text="Network status per case", font_size=14), xaxis_title="networks")
    fig_b = go.Figure()
    series_colors = [C["demand"], C["pv"], C["ev"]]
    for i, c in enumerate(cases):
        v = summary[summary["case"] == c]["violation_types"].fillna("")
        fig_b.add_bar(x=VIOLATION_KINDS, y=[int(v.str.contains(k).sum()) for k in VIOLATION_KINDS], name=c,
                      marker_color=series_colors[i % 3], marker_line=dict(color=C["surface"], width=2),
                      hovertemplate="%{x}: %{y} networks<extra>" + c + "</extra>")
    fig_b.update_layout(barmode="group", bargap=0.3, title=dict(text="Networks with each violation kind", font_size=14), yaxis_title="networks")
    parts.append("<h2>Status</h2><div class='row'>" + _fig(fig_a, height=320) + _fig(fig_b, height=320) + "</div>")

    # distributions
    ok = s[s["status"].isin(["ok", "violation"])]
    fig = make_subplots(rows=1, cols=2, subplot_titles=("Lowest voltage per network [pu]", "Highest line loading per network [-]"),
                        horizontal_spacing=0.12)
    fig.add_histogram(x=ok["v_min"], nbinsx=40, marker_color=C["demand"], marker_line=dict(color=C["surface"], width=1),
                      name="networks", showlegend=False, row=1, col=1, hovertemplate="%{x}: %{y} networks<extra></extra>")
    fig.add_histogram(x=ok["line_max_loading"].clip(upper=3), nbinsx=40, marker_color=C["demand"],
                      marker_line=dict(color=C["surface"], width=1), name="networks", showlegend=False, row=1, col=2,
                      hovertemplate="%{x}: %{y} networks<extra></extra>")
    fig.add_vline(x=lim["v_min_pu"], line=dict(color=C["violation"], width=1, dash="dash"), row=1, col=1)
    fig.add_vline(x=lim["line_loading_max"], line=dict(color=C["violation"], width=1, dash="dash"), row=1, col=2)
    fig.update_yaxes(title_text="networks", row=1, col=1)
    fig.update_xaxes(title_text="loading clipped at 3", row=1, col=2)
    parts.append("<h2>Distributions</h2>" + _fig(fig, height=320))

    # penetration scatter
    fig = go.Figure()
    for st in STATUS_ORDER:
        g = s[s["status"] == st]
        if g.empty or g["nominal_demand_kw"].isna().all():
            continue
        fig.add_scatter(x=g["nominal_demand_kw"], y=g[pv_col], mode="markers", name=STATUS_LABEL[st].split(" ", 1)[-1],
                        marker=dict(color=C[st], size=np.clip(np.sqrt(g["trafo_kva"].fillna(100)) / 2.2, 5, 22), opacity=0.75,
                                    line=dict(color=C["surface"], width=1)),
                        customdata=np.stack([g.index, g["trafo_kva"], g["ev_count"] if "ev_count" in g else np.zeros(len(g))], axis=1),
                        hovertemplate="%{customdata[0]}<br>nominal demand %{x:.0f} kW<br>PV %{y:.0f} kWp<br>transformer %{customdata[1]:.0f} kVA<br>EVs %{customdata[2]}<extra></extra>")
    ylab = "existing PV [kW]" if oneshot else "scenario PV [kWp]"
    pv_pos = s[pv_col].dropna()
    pv_pos = pv_pos[pv_pos > 0]
    if len(pv_pos) and pv_pos.max() / max(pv_pos.min(), 1e-9) > 1e3:
        floor = float(pv_pos.min()) / 2
        for tr in fig.data:
            tr.y = np.where(np.asarray(tr.y, float) > 0, np.asarray(tr.y, float), floor)
        fig.update_yaxes(type="log")
        ylab += " (log scale; networks without PV at the bottom)"
    fig.update_layout(xaxis_title="nominal demand [kW]", yaxis_title=ylab,
                      title=dict(text="Penetration: PV capacity vs nominal demand (marker size ~ transformer rating)", font_size=14))
    parts.append("<h2>Penetration</h2>" + _fig(fig, height=420))

    # map
    if "lat" in s and s["lat"].notna().any():
        fig = go.Figure()
        for st in STATUS_ORDER:
            g = s[(s["status"] == st) & s["lat"].notna()]
            if g.empty:
                continue
            links = [pages.get(i, "") for i in g.index]
            fig.add_scattermap(lat=g["lat"], lon=g["lon"], mode="markers", name=STATUS_LABEL[st].split(" ", 1)[-1],
                               marker=dict(color=C[st], size=9, opacity=0.85),
                               customdata=links, text=[f"{i}<br>{g.at[i, 'trafo_kva']:.0f} kVA, {g.at[i, 'nominal_demand_kw']:.0f} kW nominal demand"
                                                       + (f"<br>min V {g.at[i, 'v_min']:.3f} pu, max loading {g.at[i, 'line_max_loading']:.2f}" if np.isfinite(g.at[i, "v_min"]) else "")
                                                       for i in g.index],
                               hovertemplate="%{text}<extra></extra>")
        fig.update_layout(map=dict(style="open-street-map", center=dict(lat=float(s["lat"].mean()), lon=float(s["lon"].mean())), zoom=10.5),
                          margin=dict(l=0, r=0, t=30, b=0))
        parts.append("<h2>Substations</h2><p class='note'>One marker per network at its substation; click a marker to open the network page (when generated). The background tiles need internet access and WebGL.</p>"
                     + _fig(fig, div_id="map", height=520))

    # table
    cols = [("network_id", "network"), ("n_nodes", "nodes"), ("n_lines", "lines"), ("trafo_kva", "trafo kVA"),
            ("nominal_demand_kw", "nominal demand kW"), (pv_col, "existing PV kW" if oneshot else "PV kWp")]
    if not oneshot:
        cols += [("ev_count", "EVs"), ("net_peak_import_kw", "peak import kW"), ("net_peak_export_kw", "peak export kW")]
    cols += [("v_min", "min V pu"), ("line_max_loading", "max line load"), ("trafo_max_loading", "trafo load"),
             ("n_undervolt_nodes", "UV nodes"), ("n_overloaded_lines", "overloaded lines")]
    head = "".join(f"<th>{h}</th>" for _, h in cols) + "".join(f"<th>{c}</th>" for c in cases) + "<th>issues</th>"
    body = []
    for nid, r in s.iterrows():
        link = f"<a href='{pages[nid]}'>{nid}</a>" if nid in pages else nid
        tds = [f"<td>{link}</td>"]
        for key, _ in cols[1:]:
            nd = 0 if key in ("n_nodes", "n_lines", "trafo_kva", "nominal_demand_kw", "ev_count", "n_undervolt_nodes",
                              "n_overloaded_lines", "net_peak_import_kw", "net_peak_export_kw", pv_col) else (3 if key == "v_min" else 2)
            tds.append(_num(r.get(key), nd))
        for c in cases:
            st = summary[(summary["network_id"] == nid) & (summary["case"] == c)]["status"]
            tds.append(f"<td data-v='{STATUS_ORDER.index(st.iloc[0]) if len(st) else 9}'>{_badge(st.iloc[0]) if len(st) else '–'}</td>")
        issues = r.get("issues") if isinstance(r.get("issues"), str) else (r.get("error") if isinstance(r.get("error"), str) else "")
        tds.append(f"<td style='white-space:normal;text-align:left;max-width:320px'>{html.escape(issues)}</td>")
        body.append(f"<tr class='status-{r['status']}'>{''.join(tds)}</tr>")
    parts.append("<h2>Networks</h2><div class='controls'><label><input type='checkbox' id='only-flagged'> show only flagged networks</label>"
                 " · click a column header to sort</div><div class='card' style='overflow:auto;max-height:70vh;padding:0'>"
                 f"<table class='sortable'><thead><tr>{head}</tr></thead><tbody>{''.join(body)}</tbody></table></div>")
    return _page(title, "".join(parts))


# ------------------------------------------------------------ network page --
def _topology_figure(det: dict, case: str, lim: dict) -> go.Figure:
    """Plan view of the network: nodes coloured by their lowest voltage over the
    day, lines by their highest loading. Positions are metres east/north of the
    substation when coordinates exist, else a force-directed layout."""
    names = det["node_names"]
    ef, et = det["edge_from"], det["edge_to"]
    vmag = det[f"{case}:vmag"]
    loading = det[f"{case}:loading"]
    with np.errstate(all="ignore"):
        vmin = np.nanmin(vmag, axis=0) if np.isfinite(vmag).any() else np.full(len(names), np.nan)
        lmax = np.nanmax(loading, axis=0) if np.isfinite(loading).any() else np.full(len(ef), np.nan)
    geo = bool("lat" in det and np.isfinite(det["lat"]).all() and (np.ptp(det["lat"]) + np.ptp(det["lon"])) > 0)
    if geo:
        lat0, lon0 = det["lat"][0], det["lon"][0]
        x = (det["lon"] - lon0) * np.cos(np.radians(lat0)) * 111_320
        y = (det["lat"] - lat0) * 111_320
        axis_title = ("metres east of the substation", "metres north")
    else:
        import networkx as nx
        G = nx.Graph()
        G.add_nodes_from(range(len(names)))
        G.add_edges_from(zip(ef.tolist(), et.tolist()))
        pos = nx.kamada_kawai_layout(G)
        x = np.array([pos[i][0] for i in range(len(names))])
        y = np.array([pos[i][1] for i in range(len(names))])
        axis_title = ("layout (no coordinates for this network)", "")
    fig = go.Figure()
    buckets = [(0.0, 0.5, ORANGE_RAMP[0], 2, "loading < 50 %"), (0.5, 0.8, ORANGE_RAMP[1], 2.5, "50–80 %"),
               (0.8, lim["line_loading_max"], ORANGE_RAMP[2], 3, "80–100 %"),
               (lim["line_loading_max"], np.inf, C["violation"], 4, "overloaded")]
    lm = np.nan_to_num(lmax, nan=0.0)
    for lo, hi, col, w, label in buckets:
        sel = np.flatnonzero((lm >= lo) & (lm < hi))
        if len(sel) == 0:
            continue
        xs, ys = [], []
        for e in sel:
            xs += [x[ef[e]], x[et[e]], None]
            ys += [y[ef[e]], y[et[e]], None]
        fig.add_scatter(x=xs, y=ys, mode="lines", name=label, line=dict(color=col, width=w), hoverinfo="skip")
    etext = [f"{det['edge_id'][e]}: {names[ef[e]]} → {names[et[e]]}<br>max loading {lmax[e]:.2f} (ampacity {det['ampacity_a'][e]:.0f} A)"
             for e in range(len(ef))]
    fig.add_scatter(x=(x[ef] + x[et]) / 2, y=(y[ef] + y[et]) / 2, mode="markers", marker=dict(size=7, color="rgba(0,0,0,0)"),
                    text=etext, hovertemplate="%{text}<extra></extra>", showlegend=False, name="lines")
    under = vmin < lim["v_min_pu"]
    scen = det["pv_kwp"].sum() > 0 or det["ev_count"].sum() > 0
    ntext = [f"{names[i]}<br>min V {vmin[i]:.3f} pu<br>fuse-rated peak {det['plmax_kw'][i]:.0f} kW, existing PV {det['pg_kw'][i]:.0f} kW"
             + (f"<br>scenario PV {det['pv_kwp'][i]:.1f} kWp, EVs {int(det['ev_count'][i])}" if scen else "")
             + ("" if not geo else ("<br>own coordinates" if det["located"][i] else "<br>position: nearest located node"))
             for i in range(len(names))]
    cmin = float(min(np.nanmin(vmin), lim["v_min_pu"] - 0.05)) if np.isfinite(vmin).any() else 0.8
    fig.add_scatter(x=x, y=y, mode="markers", name="nodes", showlegend=False, text=ntext, hovertemplate="%{text}<extra></extra>",
                    marker=dict(size=np.where(np.arange(len(names)) == 0, 18, 9), color=np.nan_to_num(vmin, nan=1.0),
                                colorscale=[[0, BLUE_RAMP[-1]], [1, BLUE_RAMP[0]]], cmin=cmin, cmax=1.0,
                                colorbar=dict(title="min V [pu]", thickness=12, len=0.6),
                                line=dict(color=np.where(under, C["violation"], C["surface"]), width=np.where(under, 3, 1))))
    if under.any():
        fig.add_scatter(x=x[under], y=y[under], mode="markers", name="undervoltage node", hoverinfo="skip",
                        marker=dict(size=16, color="rgba(0,0,0,0)", line=dict(color=C["violation"], width=2)))
    fig.add_scatter(x=[x[0]], y=[y[0]], mode="markers", name="slack (transformer MV side)", hoverinfo="skip",
                    marker=dict(size=18, color="rgba(0,0,0,0)", line=dict(color=C["ink"], width=2)))
    fig.update_layout(xaxis=dict(title=axis_title[0], showgrid=geo, zeroline=False, visible=True),
                      yaxis=dict(title=axis_title[1], showgrid=geo, zeroline=False, scaleanchor="x", scaleratio=1),
                      title=dict(text=f"Topology, case {case}: nodes by lowest voltage, lines by highest loading", font_size=13))
    return fig


def network_page(nid: str, det: dict, rows: pd.DataFrame, run: dict, main_case: str, sub_info: dict | None) -> str:
    cfg = run["config"]
    lim = cfg["limits"]
    cases = run["cases"]
    oneshot = run["mode"] == "oneshot"
    r = rows[rows["case"] == main_case].iloc[0]
    parts = [f"<p><a href='index.html'>← portfolio</a></p><h1>{nid}</h1>"]
    sub = f"{html.escape(str(sub_info.get('code', '')))} {html.escape(str(sub_info.get('name', '')))}".strip() if sub_info else ""
    parts.append("<p class='sub'>" + (f"Substation {sub}. " if sub else "") + " ".join(
        f"{c}: {_badge(rows[rows['case'] == c]['status'].iloc[0])}" for c in cases) + "</p>")
    if isinstance(r.get("issues"), str) and r["issues"]:
        parts.append(f"<p class='note'>Data notes: {html.escape(r['issues'])}</p>")

    trafo = float(r["trafo_kva"])
    nd = float(r["nominal_demand_kw"])
    facts = [("nodes / lines / length", f"{int(r['n_nodes'])} / {int(r['n_lines'])} / {r['line_length_km']:.2f} km"),
             ("transformer", f"{trafo:.0f} kVA" + (f" ({int(r['n_transformers'])} units)" if r["n_transformers"] > 1 else "")),
             ("fuse-rated peak (sum)", f"{r['plmax_sum_kw']:.0f} kW at {int(r['n_demand_nodes'])} connections"),
             (f"nominal demand ({cfg['demand_factor']:.0%})", f"{nd:.0f} kW = {100 * nd / trafo:.0f} % of the transformer"),
             ("existing PV", f"{r['existing_pv_kw']:.0f} kW")]
    if not oneshot:
        facts += [("scenario PV", f"{r['pv_kwp']:.0f} kWp = {100 * r['pv_kwp'] / max(nd, 1e-9):.0f} % of nominal demand, {100 * r['pv_kwp'] / trafo:.0f} % of the transformer"),
                  ("scenario EVs", f"{int(r['ev_count'])} vehicles, {r['ev_peak_kw']:.0f} kW coincident peak"),
                  ("demand peak / energy", f"{r['demand_peak_kw']:.0f} kW / {r['demand_kwh_day']:.0f} kWh per day"),
                  ("PV peak / energy", f"{r['pv_peak_kw']:.0f} kW / {r['pv_kwh_day']:.0f} kWh per day (day {r['pv_date']})"),
                  ("transformer peak import / export", f"{r['net_peak_import_kw']:.0f} / {r['net_peak_export_kw']:.0f} kW")]
    parts.append("<div class='row'><div class='card'><h2 style='margin-top:0'>Network</h2>" + _facts(facts) + "</div>")

    # case comparison
    head = "<tr><th>case</th><th>status</th><th>converged steps</th><th>min V [pu] (node)</th><th>UV nodes</th><th>max line loading (line)</th><th>overloaded lines</th><th>trafo loading</th><th>mean losses kW</th></tr>"
    body = ""
    for c in cases:
        q = rows[rows["case"] == c].iloc[0]
        body += (f"<tr><td>{c}</td><td>{_badge(q['status'])}</td><td>{int(q['converged_steps'])}/{int(q['n_steps'])}</td>"
                 f"<td>{q['v_min']:.3f} ({html.escape(str(q['v_min_node']))})</td><td>{int(q['n_undervolt_nodes'])}</td>"
                 f"<td>{q['line_max_loading']:.2f} ({html.escape(str(q['line_max_id']))})</td><td>{int(q['n_overloaded_lines'])}</td>"
                 f"<td>{q['trafo_max_loading']:.2f}</td><td>{q['losses_kw_mean']:.1f}</td></tr>"
                 if np.isfinite(q.get("v_min", np.nan)) else f"<tr><td>{c}</td><td>{_badge(q['status'])}</td><td colspan='7'>no converged step</td></tr>")
    parts.append(f"<div class='card'><h2 style='margin-top:0'>Cases</h2><table>{head}{body}</table></div></div>")

    parts.append("<h2>Topology</h2>" + _fig(_topology_figure(det, main_case, lim), height=600))

    T = int(r["n_steps"])
    if T > 1:
        t = det["time_h"]
        fig = go.Figure()
        fig.add_scatter(x=t, y=det["demand_kw"], name="demand", line=dict(color=C["demand"], width=2), hovertemplate="%{y:.0f} kW<extra>demand</extra>")
        fig.add_scatter(x=t, y=det["pv_kw"], name="PV", line=dict(color=C["pv"], width=2), hovertemplate="%{y:.0f} kW<extra>PV</extra>")
        fig.add_scatter(x=t, y=det["ev_kw"], name="EV", line=dict(color=C["ev"], width=2), hovertemplate="%{y:.0f} kW<extra>EV</extra>")
        fig.add_scatter(x=t, y=det[f"{main_case}:slack_kw"], name=f"transformer import ({main_case}, load flow)",
                        line=dict(color=C["net"], width=2, dash="dot"), hovertemplate="%{y:.0f} kW<extra>transformer import</extra>")
        _hline(fig, trafo, f"transformer {trafo:.0f} kVA")
        _hline(fig, -trafo, "")
        fig.update_layout(xaxis_title="hour of day", yaxis_title="3-phase kW (consumption positive)", hovermode="x unified",
                          title=dict(text="Aggregate injections", font_size=14))
        parts.append("<h2>Injections</h2>" + _fig(fig, height=380))

        fig = make_subplots(rows=1, cols=3, subplot_titles=("Lowest node voltage [pu]", "Highest line loading [-]", "Transformer loading [-]"),
                            horizontal_spacing=0.08)
        colors = [C["demand"], C["pv"], C["ev"]]
        for i, c in enumerate(cases):
            vm, ld = det[f"{c}:vmag"], det[f"{c}:loading"]
            lines = det["edge_type"] == 0
            with np.errstate(all="ignore"):
                v = np.nanmin(vm, axis=1) if vm.size else np.full(T, np.nan)
                lmax = np.nanmax(np.where(lines[None, :], ld, np.nan), axis=1)
                tr = np.nanmax(ld[:, det["trafo_edges"]], axis=1)
            fig.add_scatter(x=t, y=v, name=c, line=dict(color=colors[i % 3], width=2), legendgroup=c, row=1, col=1, hovertemplate="%{y:.3f}<extra>" + c + "</extra>")
            fig.add_scatter(x=t, y=lmax, name=c, line=dict(color=colors[i % 3], width=2), legendgroup=c, showlegend=False, row=1, col=2, hovertemplate="%{y:.2f}<extra>" + c + "</extra>")
            fig.add_scatter(x=t, y=tr, name=c, line=dict(color=colors[i % 3], width=2), legendgroup=c, showlegend=False, row=1, col=3, hovertemplate="%{y:.2f}<extra>" + c + "</extra>")
        _hline(fig, lim["v_min_pu"], "limit", row=1, col=1)
        _hline(fig, lim["line_loading_max"], "limit", row=1, col=2)
        _hline(fig, lim["trafo_loading_max"], "limit", row=1, col=3)
        fig.update_xaxes(title_text="hour of day")
        fig.update_layout(hovermode="x unified")
        parts.append("<h2>Operating envelope per case</h2>" + _fig(fig, height=340))
    else:
        vm = det[f"{main_case}:vmag"][0]
        ld = det[f"{main_case}:loading"][0]
        fig = make_subplots(rows=1, cols=2, subplot_titles=("Node voltages [pu]", "Line loadings [-], sorted"), horizontal_spacing=0.1)
        fig.add_bar(x=list(range(len(vm))), y=vm, marker_color=C["demand"], name="voltage", showlegend=False, row=1, col=1,
                    text=det["node_names"], hovertemplate="%{text}: %{y:.3f} pu<extra></extra>")
        order = np.argsort(-np.nan_to_num(ld, nan=-1))
        fig.add_bar(x=list(range(len(ld))), y=ld[order], marker_color=C["pv"], name="loading", showlegend=False, row=1, col=2,
                    text=det["edge_id"][order], hovertemplate="%{text}: %{y:.2f}<extra></extra>")
        _hline(fig, lim["v_min_pu"], "limit", row=1, col=1)
        _hline(fig, lim["line_loading_max"], "limit", row=1, col=2)
        fig.update_xaxes(title_text="node index (0 = slack)", row=1, col=1)
        fig.update_xaxes(title_text="line rank", row=1, col=2)
        parts.append("<h2>Snapshot</h2>" + _fig(fig, height=340))

    # penetration bars
    items = [("nominal demand", nd, C["demand"]), ("existing PV", float(r["existing_pv_kw"]), C["pv"])]
    if not oneshot:
        items += [("scenario PV (kWp)", float(r["pv_kwp"]), C["pv"]), ("EV coincident peak", float(r["ev_peak_kw"]), C["ev"])]
    fig = go.Figure(go.Bar(x=[v for _, v, _ in items], y=[k for k, _, _ in items], orientation="h",
                           marker_color=[c for _, _, c in items], marker_line=dict(color=C["surface"], width=2),
                           hovertemplate="%{y}: %{x:.0f} kW<extra></extra>"))
    fig.add_vline(x=trafo, line=dict(color=C["muted"], width=1, dash="dash"), annotation_text=f"transformer {trafo:.0f} kVA", annotation_position="top")
    fig.update_layout(xaxis_title="kW", title=dict(text="Installed capacity and nominal demand vs transformer rating", font_size=14),
                      yaxis=dict(autorange="reversed"))
    parts.append("<h2>Penetration</h2>" + _fig(fig, height=260))
    return _page(f"{nid} – screening", "".join(parts))


# ------------------------------------------------------------------- build --
def build_dashboard(run_dir: Path, networks: str = "flagged", max_pages: int = 300) -> Path:
    run_dir = Path(run_dir)
    summary, run = _load_run(run_dir)
    cases = run["cases"]
    main_case = cases[-1]
    out = run_dir / "dashboard"
    out.mkdir(exist_ok=True)
    js = out / "plotly.min.js"
    if not js.exists():
        js.write_text(get_plotlyjs())
    details = run_dir / "details"
    have = {p.stem for p in details.glob("*.npz")} if details.exists() else set()

    if networks == "none":
        ids = []
    elif networks == "all":
        ids = [i for i in summary["network_id"].unique() if i in have]
    elif networks == "flagged":
        flagged = summary.groupby("network_id")["status"].apply(lambda x: (x != "ok").any())
        ids = [i for i in flagged[flagged].index if i in have]
    else:
        ids = [i if i.startswith("LV") else f"LV_Grid_{i}" for i in networks.split(",") if i.strip()]
        missing = [i for i in ids if i not in have]
        if missing:
            raise KeyError(f"no details for {', '.join(missing)} (run without --no-details)")
    if len(ids) > max_pages:
        print(f"{len(ids)} network pages requested, keeping the {max_pages} worst (raise --max-pages for more)")
        worst = summary[summary["case"] == main_case].set_index("network_id").reindex(ids)
        ids = list(worst.sort_values(["status", "v_min"], ascending=[False, True]).index[:max_pages])
    pages = {i: f"net_{i}.html" for i in ids}

    subs_file = DATA_DIR / "geo" / "substations.csv"
    sub_info = pd.read_csv(subs_file, dtype=str).set_index("network_id").to_dict("index") if subs_file.exists() else {}
    tty = sys.stdout.isatty()
    for k, nid in enumerate(ids, 1):
        if tty:
            print(f"[{k:4d}/{len(ids)}] {nid}", end="\r", flush=True)
        with np.load(details / f"{nid}.npz", allow_pickle=False) as z:
            det = {key: z[key] for key in z.files}
        rows = summary[summary["network_id"] == nid]
        (out / pages[nid]).write_text(network_page(nid, det, rows, run, main_case, sub_info.get(nid)))
    if ids and tty:
        print()
    (out / "index.html").write_text(portfolio_page(summary, run, main_case, pages))
    return out / "index.html"
