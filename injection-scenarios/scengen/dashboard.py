"""Scenario browser (Dash, local server, read-only).

    python generate_scenario.py dashboard [--port 8050]      ->  http://127.0.0.1:8050

Pick a scenario folder, optionally a second one to compare with: its
configuration, whether output/<name>/ still matches it, and every stream it
produced (demand, PV, EV and any further model listed under `streams` in
scenario.json). Net load = loads - generation: positive, the network draws
from its transformer; negative, reverse flow.
  Overview   key figures; the regional day (representative, peak, reverse-flow
             or mean day), the hourly year, monthly energy, duration curves and
             the net-load heatmap.
  Networks   every network on two selectable axes (default: peak net load and
             largest reverse flow in % of the transformer) and a sortable,
             filterable table; a point or a row opens the network.
  Network    one network: facts, a day of its streams against the transformer
             rating (the representative day at the daily step), each connection
             in % of its fuse power, the hourly year, duration curves, heatmap.
  Compare    the two scenarios: key figures, regional net load, and every
             network's loading in one against the other.
The yearly files are hourly means (the screening uses the daily product); they
are read once per scenario (2-3 s for the portfolio) and kept in memory. The
page takes ?scenario=, ?compare=, ?tab= and ?network=. It never starts a
generation.
"""
from __future__ import annotations

import json
import threading
from functools import lru_cache
from urllib.parse import parse_qs

import numpy as np
import pandas as pd
import plotly.graph_objects as go
from dash import Dash, Input, Output, State, ctx, dash_table, dcc, html, no_update
from dash.dash_table.Format import Format, Group, Scheme

from . import __version__
from .config import DATA_DIR, OUTPUT_DIR, SCENARIOS_DIR
from .generate import _sha

FUSE_A_PER_KW = 1 / (np.sqrt(3) * 0.4 * 0.9)        # PLmax = sqrt(3) x 400 V x I_fuse x cos(phi) 0.9 (oiken-db-extraction)
SERIES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6", "#e34948"]   # categorical slots, fixed order
STREAMS = {"demand": "household demand", "pv": "PV", "ev": "EV charging"}   # label of the known streams; slot = position
C = {"net": "#0b0b0b", "other": "#898781", "muted": "#898781", "ink": "#0b0b0b", "ink2": "#52514e", "grid": "#e1e0d9",
     "axis": "#c3c2b7", "surface": "#fcfcfb", "ok": "#0ca30c", "warning": "#fab219", "critical": "#d03b3b"}
BLUE_RAMP = ["#cde2fb", "#9ec5f4", "#6da7ec", "#3987e5", "#256abf", "#184f95", "#0d366b"]   # lv-screening palette
RED_RAMP = ["#fbdcdb", "#f5aeac", "#ec7b7a", "#e34948", "#b8302f", "#7d1f1e"]
DIVERGING = [[i / 12, c] for i, c in enumerate(RED_RAMP[::-1] + ["#f0efec"] + BLUE_RAMP[1:])]   # reverse flow <- 0 -> draw
DAYS = {"rep": "representative day", "peak": "peak day", "reverse": "reverse-flow day", "mean": "mean day"}
TABS = ("overview", "networks", "network", "compare")
METRICS = {                                          # scatter axes: column -> (label, log axis)
    "import_pct_trafo": ("peak net load, % of transformer", False),
    "export_pct_trafo": ("largest reverse flow, % of transformer", False),
    "reverse_h": ("hours of reverse flow per year", False),
    "net_peak_kw": ("peak net load, kW", True),
    "demand_peak_pct_fuse": ("household demand peak, % of fuse power", False),
    "kwh_per_conn": ("household demand per connection, kWh/yr", False),
    "pv_per_conn": ("PV per connection, kWp", False),
    "ev_per_conn": ("EVs per connection", False),
    "n_nodes": ("connections", True),
    "trafo_kva": ("transformer, kVA", True)}
EXPLORER = "http://127.0.0.1:8051/?network="         # lv-screening grid data explorer (python3 -m lvgrid explore)
CSS = """
body { margin: 0; background: #f9f9f7; color: #0b0b0b; font: 14px/1.45 system-ui, -apple-system, "Segoe UI", sans-serif; }
header { background: #fcfcfb; border-bottom: 1px solid rgba(11,11,11,0.10); }
header .in, main { max-width: 1320px; margin: 0 auto; padding: 12px 16px; box-sizing: border-box; }
h1 { font-size: 20px; margin: 0; } h1 small { color: #52514e; font-weight: 400; font-size: 13px; margin-left: 10px; }
.controls { display: flex; flex-wrap: wrap; gap: 12px 16px; align-items: flex-end; margin: 10px 0 0; }
.controls label.l { display: block; font-size: 12px; color: #52514e; margin-bottom: 2px; } .ctl { width: 260px; max-width: 100%; }
.note { color: #52514e; font-size: 12px; margin: 6px 0; }
.card { background: #fcfcfb; border: 1px solid rgba(11,11,11,0.10); border-radius: 10px; padding: 12px 16px; margin: 12px 0; overflow-x: auto; }
.kpis { display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 12px; margin: 12px 0; }
.kpi { background: #fcfcfb; border: 1px solid rgba(11,11,11,0.10); border-radius: 10px; padding: 10px 14px; }
.kpi .v { font-size: 24px; font-weight: 600; font-variant-numeric: tabular-nums; } .kpi .k { font-size: 13px; } .kpi .d { color: #52514e; font-size: 12px; }
.sw { display: inline-block; width: 10px; height: 10px; border-radius: 2px; margin-right: 6px; }
.row { display: grid; grid-template-columns: minmax(0,1fr) minmax(0,1fr); gap: 12px; } @media (max-width: 900px) { .row { grid-template-columns: 1fr; } }
.bar { display: flex; flex-wrap: wrap; gap: 8px 16px; align-items: center; } .bar .t { color: #52514e; font-size: 13px; }
.facts { border-collapse: collapse; } .facts td { padding: 3px 16px 3px 0; vertical-align: top; } .facts td:first-child { color: #52514e; white-space: nowrap; }
.cmp { border-collapse: collapse; font-variant-numeric: tabular-nums; } .cmp th, .cmp td { padding: 5px 16px 5px 0; border-bottom: 1px solid #e1e0d9; text-align: right; }
.cmp th:first-child, .cmp td:first-child { text-align: left; } .cmp th { color: #52514e; font-weight: 600; }
.status { display: inline-block; padding: 4px 12px; border-radius: 14px; font-size: 13px; background: #fcfcfb; }
.seg label { display: inline-block; padding: 3px 11px; margin: 2px 4px 2px 0; border: 1px solid #c3c2b7; border-radius: 14px; cursor: pointer; font-size: 13px; color: #52514e; }
.seg input { display: none; } .seg label:has(input:checked) { background: #0b0b0b; border-color: #0b0b0b; color: #fff; }
details summary { cursor: pointer; } pre { font-size: 12px; margin: 6px 0 0; } a { color: #1c5cab; }
"""
TAB = {"padding": "8px 18px", "border": "none", "borderBottom": "2px solid transparent", "backgroundColor": "transparent", "color": C["ink2"]}
TAB_SELECTED = {**TAB, "borderBottom": f"2px solid {C['ink']}", "color": C["ink"], "fontWeight": 600}


# --------------------------------------------------------------------- data --
def scenario_names() -> list[str]:
    return sorted(p.parent.name for p in SCENARIOS_DIR.glob("*/config.json"))


def output_status(name: str) -> tuple[str, str]:
    """('ok' | 'stale' | 'missing', text) of output/<name>/ against scenarios/<name>/config.json and the code version."""
    meta_file = OUTPUT_DIR / name / "scenario.json"
    if not meta_file.exists():
        return "missing", f"not generated: python3 generate_scenario.py generate {name}"
    meta = json.loads(meta_file.read_text())
    when = meta.get("created", "?").replace("T", " ")
    if meta.get("config_sha256") != _sha(SCENARIOS_DIR / name / "config.json"):
        return "stale", f"config.json changed after this output was generated ({when}): figures show the old output"
    if meta.get("scengen_version") != __version__:
        return "stale", (f"generated ({when}) by an older generator ({meta.get('scengen_version', 'lvgrid')}, now {__version__}): "
                         "regenerate to see the current models")
    return "ok", f"output matches config.json (generated {when})"


def load_output(name: str) -> dict:
    """Output of a scenario with per-network statistics (cached until scenario.json changes)."""
    with _LOADING.setdefault(name, threading.Lock()):   # parallel callbacks wait for one read instead of each reading
        return _load(name, (OUTPUT_DIR / name / "scenario.json").stat().st_mtime)


_LOADING: dict[str, threading.Lock] = {}


@lru_cache(maxsize=2)
def _load(name: str, _stamp: float) -> dict:
    folder = OUTPUT_DIR / name
    meta = json.loads((folder / "scenario.json").read_text())
    streams = meta.get("streams") or {"demand": "load"}
    alloc = pd.read_csv(folder / "allocation.csv", dtype={"network_id": str, "node": str})
    nets = pd.read_csv(folder / "networks.csv", dtype={"network_id": str}).set_index("network_id")
    ids = [n for n in nets.index if (folder / "daily" / f"{n}.csv").exists()]   # the generated networks (--networks: a subset)
    nets, alloc = nets.loc[ids].copy(), alloc[alloc["network_id"].isin(ids)]
    subs = pd.read_csv(DATA_DIR / "lv_grids" / "substations.csv", dtype={"network_id": str})
    nets["trafo_kva"] = subs[subs["object"].str.startswith("T")].groupby("network_id")["rated_kva"].sum().reindex(nets.index)
    for col, per in (("pv_kwp", "pv_per_conn"), ("ev_count", "ev_per_conn")):
        if col in nets:
            nets[per] = nets[col] / nets["n_nodes"]
    d = {"name": name, "meta": meta, "streams": streams, "sign": {s: 1 if k == "load" else -1 for s, k in streams.items()},
         "alloc": alloc, "nets": nets, "Y": None}
    ydir = folder / "yearly"
    if not (ids and meta.get("yearly", {}).get("enabled") and all((ydir / f"{n}.csv").exists() for n in ids)):
        return d
    time = pd.to_datetime(pd.read_csv(ydir / f"{ids[0]}.csv", usecols=["time"])["time"], utc=True)
    time = time.dt.tz_convert("Etc/GMT-1").dt.tz_localize(None)            # local standard time (UTC+1)
    cols = [c for c in pd.read_csv(ydir / f"{ids[0]}.csv", nrows=0).columns if c != "time"]
    raw = {c: np.empty((len(ids), len(time)), np.float32) for c in cols}
    for i, n in enumerate(ids):
        y = pd.read_csv(ydir / f"{n}.csv", usecols=cols, engine="pyarrow")
        for c in cols:
            raw[c][i] = y[c].to_numpy()
    Y = {s: raw[f"{s}_kw"] for s in streams if f"{s}_kw" in raw}               # stream -> [networks x T] kW
    P = net_of(d, Y)
    Q = sum((d["sign"][s] * raw[f"{s}_kvar"] for s in streams if f"{s}_kvar" in raw), np.zeros_like(P))
    S = np.hypot(P, Q)
    dt_h = (time.iloc[1] - time.iloc[0]).total_seconds() / 3600
    for s, y in Y.items():
        nets[f"mwh_{s}"] = y.sum(axis=1) * dt_h / 1e3
    nets["net_peak_kw"] = P.max(axis=1)
    nets["net_peak_time"] = time.iloc[P.argmax(axis=1)].dt.strftime("%Y-%m-%d %H:%M").to_numpy()
    nets["net_min_kw"] = P.min(axis=1)
    nets["reverse_h"] = (P < 0).sum(axis=1) * dt_h
    nets["import_pct_trafo"] = 100 * np.where(P >= 0, S, 0).max(axis=1) / nets["trafo_kva"]
    nets["export_pct_trafo"] = 100 * np.where(P < 0, S, 0).max(axis=1) / nets["trafo_kva"]
    if "demand" in Y:
        nets["demand_peak_pct_fuse"] = 100 * Y["demand"].max(axis=1) / nets["plmax_sum_kw"]
        nets["kwh_per_conn"] = 1e3 * nets["mwh_demand"] / nets["n_nodes"]
    d.update(nets=nets, Y=Y, R={s: y.sum(axis=0, dtype=np.float64) for s, y in Y.items()},
             row={n: i for i, n in enumerate(ids)}, time=time, dt_h=dt_h, per_day=int(round(24 / dt_h)))
    return d


@lru_cache(maxsize=16)
def _daily_file(name: str, nid: str, _stamp: float) -> pd.DataFrame:
    return pd.read_csv(OUTPUT_DIR / name / "daily" / f"{nid}.csv")


def daily(d: dict, nid: str) -> pd.DataFrame:
    """The network's daily product: one row per step, `<node>:<stream>_kw` columns."""
    return _daily_file(d["name"], nid, (OUTPUT_DIR / d["name"] / "scenario.json").stat().st_mtime)


def demand_factor(d: dict) -> float | None:
    """The demand_factor the output was generated with (nominal / fuse-rated power in networks.csv)."""
    n = d["nets"]
    return float((n["nominal_demand_kw"] / n["plmax_sum_kw"]).median()) if len(n) and "nominal_demand_kw" in n else None


def label(s: str) -> str:
    return STREAMS.get(s, s)


def colour(s: str, streams) -> str:
    """A stream keeps its colour in every scenario and view: known streams first, then in the order of `streams`."""
    order = list(STREAMS) + [k for k in streams if k not in STREAMS]
    return SERIES[order.index(s)] if order.index(s) < len(SERIES) else C["muted"]


def net_of(d: dict, series: dict):
    """Loads minus generation, element-wise over the streams' arrays."""
    return sum(d["sign"][s] * y for s, y in series.items())


def network_series(d: dict, nid: str) -> dict[str, np.ndarray]:
    return {s: y[d["row"][nid]] for s, y in d["Y"].items()}


def daily_series(d: dict, nid: str) -> tuple[dict[str, np.ndarray], pd.Series]:
    """Per-stream network sums of the daily product and their times."""
    df = daily(d, nid)
    series = {s: df[[c for c in df.columns if c.endswith(f":{s}_kw")]].sum(axis=1).to_numpy() for s in d["streams"]}
    return series, pd.Timestamp(d["meta"].get("pv_date", "2000-01-01")) + pd.to_timedelta(df["hour"], unit="h")


def pick_day(d: dict, series: dict[str, np.ndarray], which: str, k: int | None = None) -> tuple[dict, pd.Series, str, int | None]:
    """One day of yearly series: (series, times, description, day index); k forces the day (to show another scenario)."""
    n = d["per_day"]
    if which == "mean":
        x = pd.Timestamp("2000-01-01") + pd.to_timedelta(np.arange(n) * d["dt_h"], unit="h")
        return {s: y.reshape(-1, n).mean(axis=0) for s, y in series.items()}, pd.Series(x), "mean day of the year", None
    net = net_of(d, series)
    if k is None:
        k = {"rep": d["meta"].get("pv_day_index", 0), "peak": int(net.argmax()) // n, "reverse": int(net.argmin()) // n}[which]
    sl = slice(k * n, (k + 1) * n)
    what = {"rep": "representative day", "peak": "day of the peak net load",
            "reverse": "day of the largest reverse flow" if net.min() < 0 else "no reverse flow; day of the lowest net load"}[which]
    return {s: y[sl] for s, y in series.items()}, d["time"].iloc[sl], f"{what}, {d['time'].iloc[k * n]:%a %d %b}", k


# ------------------------------------------------------------------ figures --
def _rgba(hex_colour: str, a: float) -> str:
    r, g, b = (int(hex_colour[i:i + 2], 16) for i in (1, 3, 5))
    return f"rgba({r},{g},{b},{a})"


def _style(fig: go.Figure, title: str, height: int = 360) -> go.Figure:
    fig.update_layout(title=dict(text=title, x=0, font=dict(size=14)), template="plotly_white", height=height,
                      margin=dict(l=60, r=20, t=50, b=50), paper_bgcolor=C["surface"], plot_bgcolor=C["surface"],
                      font=dict(family='system-ui, -apple-system, "Segoe UI", sans-serif', color=C["ink"], size=12),
                      legend=dict(orientation="h", y=1.0, yanchor="bottom", x=1, xanchor="right", bgcolor="rgba(0,0,0,0)"),
                      hoverlabel=dict(bgcolor="#fff", bordercolor=C["axis"], font=dict(color=C["ink"])), barcornerradius=3)
    fig.update_xaxes(gridcolor=C["grid"], zerolinecolor=C["axis"], linecolor=C["axis"])
    fig.update_yaxes(gridcolor=C["grid"], zerolinecolor=C["axis"], linecolor=C["axis"])
    return fig


def _empty(title: str, text: str) -> go.Figure:
    fig = _style(go.Figure(), title, 220)
    fig.add_annotation(text=text, showarrow=False, font=dict(color=C["ink2"]), xref="paper", yref="paper", x=0.5, y=0.5)
    fig.update_xaxes(visible=False)
    fig.update_yaxes(visible=False)
    return fig


def _ref_line(fig: go.Figure, y: float, text: str, position: str = "top right") -> None:
    fig.add_hline(y=y, line=dict(color=C["muted"], width=1, dash="dash"), annotation_text=text,
                  annotation_position=position, annotation_font_color=C["ink2"])


def _rating(fig: go.Figure, rating: float | None, hi: float, lo: float) -> str:
    """Transformer rating lines when the curves come within half of it; else a note for the title."""
    if rating is None or not np.isfinite(rating):
        return ""
    shown = False
    if hi >= 0.5 * rating:
        _ref_line(fig, rating, f"transformer {rating:,.0f} kVA")
        shown = True
    if lo <= -0.5 * rating:
        _ref_line(fig, -rating, f"transformer {rating:,.0f} kVA", "bottom right")
        shown = True
    return "" if shown else f" (transformer {rating:,.0f} kVA, off scale)"


def day_figure(d: dict, series: dict, x, title: str, unit: str, rating: float | None = None, other=None) -> go.Figure:
    """Stacked streams (loads up, generation down) and the net load over a day; other = (name, times, net) of a second scenario."""
    fig = go.Figure()
    for s, y in series.items():
        c, up = colour(s, d["streams"]), d["sign"][s] > 0
        fig.add_trace(go.Scatter(x=x, y=d["sign"][s] * y, customdata=y, name=label(s), mode="lines", stackgroup="load" if up else "gen",
                                 line=dict(color=c, width=1.5), fillcolor=_rgba(c, 0.32),
                                 hovertemplate=f"{label(s)}: %{{customdata:,.1f}} {unit}<extra></extra>"))
    net = net_of(d, series)
    fig.add_trace(go.Scatter(x=x, y=net, name="net load", mode="lines", line=dict(color=C["net"], width=2.5),
                             hovertemplate=f"net load: %{{y:,.1f}} {unit}<extra></extra>"))
    nets = [net]
    if other is not None:
        oname, ox, onet = other
        fig.add_trace(go.Scatter(x=ox, y=onet, name=f"net load, {oname}", mode="lines", line=dict(color=C["other"], width=2, dash="dash"),
                                 hovertemplate=f"net load, {oname}: %{{y:,.1f}} {unit}<extra></extra>"))
        nets.append(onet)
    stack = {k: np.max(np.sum([y for s, y in series.items() if d["sign"][s] == k], axis=0), initial=0) for k in (1, -1)}
    hi = max(max(float(np.max(n)) for n in nets), float(stack[1]))
    lo = min(min(float(np.min(n)) for n in nets), -float(stack[-1]))
    title += _rating(fig, rating, hi, lo)
    fig.update_xaxes(tickformat="%H:%M", hoverformat="%H:%M")
    fig.update_yaxes(title=unit)
    fig.update_layout(hovermode="x unified")
    return _style(fig, title, 400)


def year_figure(d: dict, series: dict, title: str, unit: str, rating: float | None = None) -> go.Figure:
    """The hourly year of each stream (generation negative) and the net load, with a range slider."""
    fig = go.Figure()
    x = dict(x0=d["time"].iloc[0].isoformat(), dx=d["dt_h"] * 3.6e6)       # date axis: dx in ms, no time array per trace
    for s, y in series.items():
        fig.add_trace(go.Scatter(**x, y=(d["sign"][s] * y).astype(np.float32), customdata=y.astype(np.float32), name=label(s), mode="lines",
                                 line=dict(color=colour(s, d["streams"]), width=1),
                                 hovertemplate=f"{label(s)}: %{{customdata:,.1f}} {unit}<extra></extra>"))
    net = net_of(d, series)
    fig.add_trace(go.Scatter(**x, y=net.astype(np.float32), name="net load", mode="lines", line=dict(color=C["net"], width=1.5),
                             hovertemplate=f"net load: %{{y:,.1f}} {unit}<extra></extra>"))
    lo = min(float(net.min()), min((-float(y.max()) for s, y in series.items() if d["sign"][s] < 0), default=0.0))
    title += _rating(fig, rating, float(max(net.max(), max(y.max() for y in series.values()))), lo)
    fig.update_xaxes(type="date", rangeslider=dict(visible=True, thickness=0.08), hoverformat="%a %d %b %H:%M",
                     rangeselector=dict(buttons=[dict(count=7, label="week", step="day", stepmode="backward"),
                                                 dict(count=1, label="month", step="month", stepmode="backward"),
                                                 dict(step="all", label="year")], bgcolor=C["surface"], activecolor=C["grid"]))
    fig.update_yaxes(title=unit)
    fig.update_layout(hovermode="x unified")
    return _style(fig, title, 430)


def month_figure(d: dict, series: dict, title: str, unit: str, div: float) -> go.Figure:
    m = d["time"].dt.month.to_numpy() - 1
    names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    fig = go.Figure([go.Bar(x=names, y=np.bincount(m, weights=y, minlength=12) * d["dt_h"] / div, name=label(s),
                            marker=dict(color=colour(s, d["streams"])), hovertemplate=f"{label(s)} %{{x}}: %{{y:,.2f}} {unit}<extra></extra>")
                     for s, y in series.items()])
    fig.update_layout(barmode="group", bargap=0.25, bargroupgap=0.08)
    fig.update_yaxes(title=unit)
    return _style(fig, title)


def duration_figure(d: dict, series: dict, title: str, unit: str, other=None) -> go.Figure:
    """Duration curve of each stream and of the net load (below zero: reverse flow); other = (name, net) of a second scenario."""
    x = dict(x0=0, dx=d["dt_h"])

    def desc(y):
        return np.sort(y)[::-1].astype(np.float32)
    fig = go.Figure([go.Scatter(**x, y=desc(y), name=label(s), mode="lines", line=dict(color=colour(s, d["streams"]), width=1.5),
                                hovertemplate=f"{label(s)}: %{{y:,.1f}} {unit} or more for %{{x:,.0f}} h<extra></extra>")
                     for s, y in series.items()])
    net = net_of(d, series)
    fig.add_trace(go.Scatter(**x, y=desc(net), name="net load", mode="lines", line=dict(color=C["net"], width=2.5),
                             hovertemplate=f"net load: %{{y:,.1f}} {unit} or more for %{{x:,.0f}} h<extra></extra>"))
    if other is not None:
        fig.add_trace(go.Scatter(**x, y=desc(other[1]), name=f"net load, {other[0]}", mode="lines",
                                 line=dict(color=C["other"], width=2, dash="dash"),
                                 hovertemplate=f"net load, {other[0]}: %{{y:,.1f}} {unit} or more for %{{x:,.0f}} h<extra></extra>"))
    rev = (net < 0).sum() * d["dt_h"]
    if rev:
        fig.add_vline(x=len(net) * d["dt_h"] - rev, line=dict(color=C["muted"], width=1, dash="dot"),
                      annotation_text=f"reverse flow {rev:,.0f} h", annotation_position="top left", annotation_font_color=C["ink2"])
    fig.update_xaxes(title="hours per year")
    fig.update_yaxes(title=unit)
    return _style(fig, title)


def heat_figure(d: dict, net: np.ndarray, title: str, unit: str) -> go.Figure:
    """Net load, day x hour, diverging around zero (red: reverse flow, blue: drawn from the transformer)."""
    z = net.reshape(-1, d["per_day"])
    m = float(np.abs(z).max()) or 1.0
    t = d["time"].iloc[:d["per_day"]].dt.strftime("%H:%M").to_numpy()
    fig = go.Figure(go.Heatmap(z=z, x=t, y=d["time"].dt.strftime("%Y-%m-%d").to_numpy()[::d["per_day"]],
                               colorscale=DIVERGING, zmin=-m, zmax=m, colorbar=dict(title=dict(text=f"{unit}<br>&lt; 0 reverse"), thickness=12),
                               hovertemplate=f"%{{y}} %{{x}}<br>net load %{{z:,.1f}} {unit}<extra></extra>"))
    fig.update_xaxes(title="hour", type="category", tickvals=t[::max(1, d["per_day"] // 8)])
    fig.update_yaxes(autorange="reversed")
    return _style(fig, title, 460)


def summary(d: dict) -> dict[str, tuple[str, float, str]]:
    """Key figures of a scenario, key -> (label, value, format); the tiles and the comparison read them."""
    nets = d["nets"]
    out = {"connections": ("connections", len(d["alloc"]), "{:,.0f}"), "networks": ("networks", len(nets), "{:,.0f}")}
    if "pv_kwp" in nets:
        out["pv_mwp"] = ("PV installed, MWp", nets["pv_kwp"].sum() / 1e3, "{:,.1f}")
    if "ev_count" in nets:
        out["evs"] = ("electric vehicles", nets["ev_count"].sum(), "{:,.0f}")
    if (f := demand_factor(d)) is not None:
        out["demand_factor"] = ("demand_factor", f, "{:.3f}")
    if d["Y"] is None:
        return out
    for s, y in d["R"].items():
        out[f"gwh_{s}"] = (f"{label(s)}, GWh per year", y.sum() * d["dt_h"] / 1e6, "{:,.1f}")
    net = net_of(d, d["R"])
    out.update(gwh_net=("net energy drawn, GWh per year", net.sum() * d["dt_h"] / 1e6, "{:,.1f}"),
               peak_mw=("regional peak net load, MW", net.max() / 1e3, "{:,.1f}"),
               reverse_mw=("largest regional reverse flow, MW", max(0.0, -net.min()) / 1e3, "{:,.1f}"),
               reverse_h=("hours of regional reverse flow", (net < 0).sum() * d["dt_h"], "{:,.0f}"),
               nets_over=("networks above the transformer rating", int((nets["import_pct_trafo"] > 100).sum()), "{:,.0f}"),
               nets_reverse=("networks with reverse flow", int((nets["net_min_kw"] < 0).sum()), "{:,.0f}"),
               nets_over_reverse=("networks with reverse flow above the rating", int((nets["export_pct_trafo"] > 100).sum()), "{:,.0f}"),
               median_load=("median network peak, % of transformer", nets["import_pct_trafo"].median(), "{:.0f}"))
    return out


def kpis(d: dict) -> list[tuple[str, str, str, str | None]]:
    """Tiles: (value, what, detail, colour swatch or None)."""
    s = {k: v for k, (_, v, _) in summary(d).items()}
    out = [(f"{s['connections']:,.0f}", "connections", f"in {s['networks']:,.0f} networks", None)]
    if d["Y"] is None:
        if "pv_mwp" in s:
            out.append((f"{s['pv_mwp']:,.1f} MWp", "PV installed", "", colour("pv", d["streams"])))
        if "evs" in s:
            out.append((f"{s['evs']:,.0f}", "electric vehicles", "", colour("ev", d["streams"])))
        if "demand_factor" in s:
            out.append((f"{s['demand_factor']:.2f}", "demand_factor", "P_max per connection / its fuse-rated power", None))
        return out
    for st in d["R"]:
        gwh, detail = s[f"gwh_{st}"], ""
        if st == "demand":
            detail = f"{1e6 * gwh / s['connections']:,.0f} kWh per connection" + (
                f", demand_factor {s['demand_factor']:.2f}" if "demand_factor" in s else "")
        elif st == "pv" and s.get("pv_mwp"):
            detail = f"{s['pv_mwp']:,.1f} MWp installed, {1e3 * gwh / s['pv_mwp']:,.0f} full-load hours"
        elif st == "ev" and s.get("evs"):
            detail = f"{s['evs']:,.0f} vehicles, {1e6 * gwh / s['evs']:,.0f} kWh each"
        out.append((f"{gwh:,.1f} GWh", f"{label(st)} per year", detail, colour(st, d["streams"])))
    net, t = net_of(d, d["R"]), d["time"]
    fuse_mw = d["nets"]["plmax_sum_kw"].sum() / 1e3
    out += [(f"{s['peak_mw']:,.1f} MW", "regional peak net load",
             f"{t.iloc[int(net.argmax())]:%d %b %H:%M}, {100 * s['peak_mw'] / fuse_mw:.1f} % of the fuse-rated power", None),
            (f"{s['reverse_mw']:,.1f} MW", "largest regional reverse flow",
             f"{t.iloc[int(net.argmin())]:%d %b %H:%M}, {s['reverse_h']:,.0f} h per year" if s["reverse_mw"] > 0 else "the region never feeds back", None),
            (f"{s['nets_over']:,.0f}", "networks above the transformer rating",
             f"{100 * s['nets_over'] / max(s['networks'], 1):.1f} % of the networks (peak net load, hourly means)", None),
            (f"{s['nets_reverse']:,.0f}", "networks with reverse flow", f"{s['nets_over_reverse']:,.0f} of them above the transformer rating", None)]
    return out


def overview_figures(d: dict) -> dict[str, go.Figure]:
    if d["Y"] is None:
        msg = "no yearly files in this output (time.yearly.enabled is false)"
        return {k: _empty("", msg) for k in ("year", "month", "duration", "heat")}
    R = {s: y / 1e3 for s, y in d["R"].items()}
    return {"year": year_figure(d, R, "Regional power over the year, hourly (drag the slider or pick a span)", "MW"),
            "month": month_figure(d, d["R"], "Energy per month", "GWh", 1e6),
            "duration": duration_figure(d, R, "Duration curves", "MW"),
            "heat": heat_figure(d, net_of(d, R), "Regional net load over the year", "MW")}


def regional_day(d: dict, which: str, other: dict | None = None) -> go.Figure:
    if d["Y"] is None:
        return _empty("", "no yearly files in this output")
    R = {s: y / 1e3 for s, y in d["R"].items()}
    series, x, what, k = pick_day(d, R, which)
    o = None
    if other is not None and other["Y"] is not None:
        oseries, ox, _, _ = pick_day(other, {s: y / 1e3 for s, y in other["R"].items()}, which, k)
        o = (other["name"], x, net_of(other, oseries))                    # same calendar day, plotted on this scenario's times
    return day_figure(d, series, x, f"Regional power: {what} (hourly)", "MW", other=o)


def scatter_figure(d: dict, x: str, y: str) -> go.Figure:
    nets = d["nets"]
    if x not in nets or y not in nets:
        return _empty("", "this axis needs the yearly files")
    ok = nets[[x, y]].notna().all(axis=1)
    for m in (x, y):
        if METRICS[m][1]:
            ok &= nets[m] > 0
    sub = nets[ok]
    fig = go.Figure(go.Scatter(
        x=sub[x], y=sub[y], mode="markers", customdata=np.column_stack([sub.index, sub["n_nodes"]]),
        marker=dict(color=SERIES[0], size=8, opacity=0.6, line=dict(color=C["surface"], width=1)),
        hovertemplate=(f"<b>%{{customdata[0]}}</b> (%{{customdata[1]}} connections)<br>{METRICS[x][0]}: %{{x:,.1f}}"
                       f"<br>{METRICS[y][0]}: %{{y:,.1f}}<extra></extra>")))
    over = []
    for axis, m in (("x", x), ("y", y)):
        if m.endswith("pct_trafo"):
            over.append(f"{(sub[m] > 100).sum():,} above 100 % on {axis}")
            (fig.add_hline if axis == "y" else fig.add_vline)(100, line=dict(color=C["muted"], width=1, dash="dash"))
    fig.update_xaxes(title=METRICS[x][0], type="log" if METRICS[x][1] else "linear")
    fig.update_yaxes(title=METRICS[y][0], type="log" if METRICS[y][1] else "linear")
    hidden = f", {len(nets) - len(sub):,} without a value not shown" if len(sub) < len(nets) else ""
    return _style(fig, f"{len(sub):,} networks{hidden}" + (f"; {', '.join(over)}" if over else "") + " (click a point to open it)", 480)


def network_facts(d: dict, nid: str) -> list[tuple[str, str]]:
    n = d["nets"].loc[nid]
    rows = d["alloc"][d["alloc"]["network_id"] == nid]
    fuses = (rows["plmax_kw"] * FUSE_A_PER_KW).round().astype(int).value_counts().sort_index()
    out = [("connections", f"{int(n['n_nodes'])}"),
           ("fuses", ", ".join(f"{a} A × {k}" for a, k in fuses.items())),
           ("fuse-rated power", f"{n['plmax_sum_kw']:,.0f} kW"
            + (f"; demand ceiling {n['nominal_demand_kw']:,.1f} kW (demand_factor × fuse power)" if "nominal_demand_kw" in n else "")),
           ("transformer", f"{n['trafo_kva']:,.0f} kVA" if np.isfinite(n["trafo_kva"]) else "none in the data")]
    if "pv_kwp" in n:
        out.append(("PV", f"{n['pv_kwp']:,.1f} kWp on {(rows['pv_kwp'] > 0).sum()} connections"))
    if "ev_count" in n:
        out.append(("EVs", f"{int(n['ev_count'])} on {(rows['ev_count'] > 0).sum()} connections"))
    if d["Y"] is None:
        return out
    trafo = np.isfinite(n["trafo_kva"])
    out += [("energy per year", ", ".join(f"{label(s)} {n[f'mwh_{s}']:,.1f} MWh" for s in d["Y"])),
            ("peak net load", f"{n['net_peak_kw']:,.1f} kW on {n['net_peak_time']}"
             + (f", {n['import_pct_trafo']:.0f} % of the transformer (apparent power)" if trafo else "")),
            ("reverse flow", "none" if n["net_min_kw"] >= 0 else
             f"up to {-n['net_min_kw']:,.1f} kW" + (f", {n['export_pct_trafo']:.0f} % of the transformer" if trafo else "")
             + f"; {n['reverse_h']:,.0f} h per year")]
    return out


def network_day(d: dict, nid: str, which: str, other: dict | None = None) -> go.Figure:
    n = d["nets"].loc[nid]
    o = None
    if which == "rep":
        series, x = daily_series(d, nid)
        what = f"representative day {d['meta'].get('pv_date', '')}, {d['meta'].get('step_min', '?')} min steps"
        if other is not None and nid in other["nets"].index:
            oseries, ox = daily_series(other, nid)
            o = (other["name"], ox, net_of(other, oseries))
    elif d["Y"] is None:
        return _empty("", "no yearly files: only the representative day")
    else:
        series, x, what, k = pick_day(d, network_series(d, nid), which)
        what += " (hourly)"
        if other is not None and other["Y"] is not None and nid in other["row"]:
            oseries, _, _, _ = pick_day(other, network_series(other, nid), which, k)
            o = (other["name"], x, net_of(other, oseries))
    return day_figure(d, series, x, f"{nid}: {what}", "kW", rating=n["trafo_kva"], other=o)


def connections_figure(d: dict, nid: str, stream: str) -> tuple[go.Figure, str]:
    """Each connection's stream on the daily product in % of its fuse power, and the coincidence of their peaks."""
    df = daily(d, nid)
    rows = d["alloc"][d["alloc"]["network_id"] == nid].set_index("node")
    cols = [c for c in df.columns if c.endswith(f":{stream}_kw")]
    if not cols:
        return _empty("", f"no {label(stream)} in {nid}"), ""
    nodes = [c.split(":")[0] for c in cols]
    P = df[cols].to_numpy()                                                # [T x nodes] kW
    pct = 100 * P / rows.loc[nodes, "plmax_kw"].to_numpy()
    total = 100 * P.sum(axis=1) / rows["plmax_kw"].sum()
    x0 = pd.Timestamp(d["meta"].get("pv_date", "2000-01-01")) + pd.to_timedelta(df["hour"], unit="h")
    x = np.concatenate([np.append(x0.to_numpy(), np.datetime64("NaT")) for _ in nodes])
    y = np.concatenate([np.append(pct[:, j], np.nan) for j in range(len(nodes))])
    names = np.concatenate([[nd] * (len(x0) + 1) for nd in nodes])
    c = colour(stream, d["streams"])
    fig = go.Figure([
        go.Scattergl(x=x, y=y, mode="lines", line=dict(color=C["muted"], width=1), opacity=0.45, name="each connection",
                     text=names, hovertemplate="%{text}  %{x|%H:%M}  %{y:.1f} %<extra></extra>"),
        go.Scatter(x=x0, y=total, mode="lines", line=dict(color=c, width=2.5), name="network (sum / sum of fuse power)",
                   hovertemplate="network  %{x|%H:%M}  %{y:.2f} %<extra></extra>")])
    if stream == "demand" and (f := demand_factor(d)) is not None:
        _ref_line(fig, 100 * f, f"demand_factor {100 * f:.0f} %")
    fig.update_xaxes(tickformat="%H:%M")
    fig.update_yaxes(title="% of the connection's fuse power", rangemode="tozero")
    peaks = P.max(axis=0).sum()
    coinc = P.sum(axis=1).max() / peaks if peaks > 0 else float("nan")
    note = (f"{len(cols)} of {len(rows)} connections have {label(stream)}. On this day the network's {label(stream)} peak is "
            f"{100 * coinc:.0f} % of the sum of the connections' own peaks (coincidence factor {coinc:.2f}).")
    return _style(fig, f"{nid}: {label(stream)} of each connection on the representative day", 400), note


def network_year_figures(d: dict, nid: str, other: dict | None = None) -> dict[str, go.Figure]:
    if d["Y"] is None:
        return {k: _empty("", "no yearly file for this network") for k in ("year", "duration", "heat")}
    series = network_series(d, nid)
    o = (other["name"], net_of(other, network_series(other, nid))) if other is not None and other["Y"] is not None and nid in other["row"] else None
    return {"year": year_figure(d, series, f"{nid}: the year, hourly", "kW", rating=d["nets"].loc[nid, "trafo_kva"]),
            "duration": duration_figure(d, series, f"{nid}: duration curves", "kW", other=o),
            "heat": heat_figure(d, net_of(d, series), f"{nid}: net load over the year", "kW")}


def compare_rows(a: dict, b: dict) -> list[tuple[str, str, str, str]]:
    """(figure, value in a, value in b, change) for the key figures of either scenario."""
    sa, sb = summary(a), summary(b)
    out = []
    for k in list(sa) + [k for k in sb if k not in sa]:
        lab, fmt = (sa.get(k) or sb[k])[0], (sa.get(k) or sb[k])[2]
        va, vb = (sa[k][1] if k in sa else None), (sb[k][1] if k in sb else None)
        change = ""
        if va is not None and vb is not None:
            change = ("+" if vb - va > 0 else "") + fmt.format(vb - va) + (f" ({100 * (vb - va) / abs(va):+.0f} %)" if va else "")
        out.append((lab, "–" if va is None else fmt.format(va), "–" if vb is None else fmt.format(vb), change))
    return out


def compare_figures(a: dict, b: dict) -> dict[str, go.Figure]:
    if a["Y"] is None or b["Y"] is None:
        return {k: _empty("", "both scenarios need yearly files") for k in ("day", "duration")}
    fig = go.Figure()
    for d, c, dash in ((a, C["net"], None), (b, C["other"], "dash")):
        net = net_of(d, d["R"]).reshape(-1, d["per_day"]) / 1e3
        h = pd.Timestamp("2000-01-01") + pd.to_timedelta(np.arange(d["per_day"]) * d["dt_h"], unit="h")
        lo, hi = np.percentile(net, [5, 95], axis=0)
        fig.add_trace(go.Scatter(x=h, y=hi, mode="lines", line=dict(width=0), hoverinfo="skip", showlegend=False))
        fig.add_trace(go.Scatter(x=h, y=lo, mode="lines", line=dict(width=0), fill="tonexty", fillcolor=_rgba(c, 0.10),
                                 hoverinfo="skip", name=f"{d['name']}, 5-95 % of days"))
        fig.add_trace(go.Scatter(x=h, y=net.mean(axis=0), mode="lines", line=dict(color=c, width=2.5, dash=dash), name=f"{d['name']}, mean day",
                                 hovertemplate=f"{d['name']}: %{{y:,.1f}} MW<extra></extra>"))
    fig.update_xaxes(tickformat="%H:%M", hoverformat="%H:%M")
    fig.update_yaxes(title="MW")
    fig.update_layout(hovermode="x unified")
    figs = {"day": _style(fig, "Regional net load over the day", 400)}
    fig = go.Figure()
    for d, c, dash in ((a, C["net"], None), (b, C["other"], "dash")):
        net = net_of(d, d["R"]) / 1e3
        fig.add_trace(go.Scatter(x0=0, dx=d["dt_h"], y=np.sort(net)[::-1].astype(np.float32), mode="lines", name=d["name"],
                                 line=dict(color=c, width=2.5, dash=dash),
                                 hovertemplate=f"{d['name']}: %{{y:,.1f}} MW or more for %{{x:,.0f}} h<extra></extra>"))
    fig.update_xaxes(title="hours per year")
    fig.update_yaxes(title="MW")
    figs["duration"] = _style(fig, "Regional net load duration curve (below zero: reverse flow)", 400)
    return figs


def shift_figure(a: dict, b: dict, metric: str) -> go.Figure:
    """Every network's metric in scenario a (x) against b (y)."""
    if metric not in a["nets"] or metric not in b["nets"]:
        return _empty("", "this figure needs the yearly files of both scenarios")
    common = a["nets"].index.intersection(b["nets"].index)
    xa, yb = a["nets"].loc[common, metric], b["nets"].loc[common, metric]
    ok = xa.notna() & yb.notna()
    xa, yb = xa[ok], yb[ok]
    top = float(max(xa.max(), yb.max(), 1)) * 1.05
    fig = go.Figure([
        go.Scatter(x=[0, top], y=[0, top], mode="lines", line=dict(color=C["muted"], width=1, dash="dot"), hoverinfo="skip", showlegend=False),
        go.Scatter(x=xa, y=yb, mode="markers", customdata=np.column_stack([xa.index, a["nets"].loc[xa.index, "n_nodes"]]),
                   marker=dict(color=SERIES[0], size=8, opacity=0.6, line=dict(color=C["surface"], width=1)), showlegend=False,
                   hovertemplate=(f"<b>%{{customdata[0]}}</b> (%{{customdata[1]}} connections)<br>{a['name']}: %{{x:,.1f}}"
                                  f"<br>{b['name']}: %{{y:,.1f}}<extra></extra>"))])
    if metric.endswith("pct_trafo"):
        fig.add_hline(y=100, line=dict(color=C["muted"], width=1, dash="dash"))
        fig.add_vline(x=100, line=dict(color=C["muted"], width=1, dash="dash"))
    fig.update_xaxes(title=f"{a['name']}: {METRICS[metric][0]}", range=[0, top])
    fig.update_yaxes(title=f"{b['name']}: {METRICS[metric][0]}", range=[0, top])
    eps = 1e-6 * top
    return _style(fig, f"{(yb > xa + eps).sum():,} networks higher in {b['name']}, {(yb < xa - eps).sum():,} lower "
                       f"(above the diagonal: higher; click a point to open it)", 520)


# ---------------------------------------------------------------------- app --
def table_columns(d: dict) -> list[tuple[str, str, int | None]]:
    nets = d["nets"]
    cols = [("network_id", "network", None), ("n_nodes", "connections", 0), ("plmax_sum_kw", "fuse power kW", 0),
            ("trafo_kva", "transformer kVA", 0), ("pv_kwp", "PV kWp", 1), ("ev_count", "EVs", 0)]
    cols += [(f"mwh_{s}", f"{label(s)} MWh", 1) for s in d["streams"]]
    cols += [("net_peak_kw", "peak net load kW", 1), ("import_pct_trafo", "peak % transformer", 0),
             ("net_min_kw", "lowest net load kW", 1), ("export_pct_trafo", "reverse flow % transformer", 0),
             ("reverse_h", "reverse-flow hours", 0), ("net_peak_time", "peak time", None)]
    return [c for c in cols if c[0] == "network_id" or c[0] in nets]


def _facts(rows: list[tuple[str, str]]) -> html.Table:
    return html.Table([html.Tr([html.Td(k), html.Td(v)]) for k, v in rows], className="facts")


def _config(name: str) -> list:
    scfg = json.loads((SCENARIOS_DIR / name / "config.json").read_text())
    sf, t, dm = scfg.get("sfoe", {}), scfg.get("time", {}), scfg.get("demand", {})
    yearly = t.get("yearly", {})
    head = [f"{sf.get('description', name)}, {sf.get('year', '')}", f"demand_factor {dm.get('demand_factor')}",
            f"{t.get('step_min')} min steps", "hourly yearly files" if yearly.get("enabled") and yearly.get("step_min") == 60
            else (f"yearly files at {yearly.get('step_min')} min" if yearly.get("enabled") else "no yearly files")]
    rows = [("SFOE scenario", f"{sf.get('key', '')}: {sf.get('description', '')}, {sf.get('year', '')}: "
                              f"{sf.get('PV_national_MW', '?')} MW PV and {sf.get('EV_national_thousands', '?')}k EVs in Switzerland"),
            ("time", f"{t.get('step_min')} min steps, daily product {t.get('days')} day(s), "
                     + (f"yearly files at {yearly.get('step_min')} min" if yearly.get("enabled") else "no yearly files")),
            ("demand", f"demand_factor {dm.get('demand_factor')}, model {dm.get('model_file')}, seed offset {dm.get('seed_offset')}")]
    if "pv" in scfg:
        rows.append(("PV", ", ".join(f"{k} {v}" for k, v in scfg["pv"].items() if not k.startswith("_"))))
    if "ev" in scfg:
        ev = scfg["ev"]
        rows.append(("EV", f"{ev.get('charger_kw')} kW chargers, arrival {json.dumps(ev.get('arrival_h'))}, energy {json.dumps(ev.get('energy_kwh'))}"))
    return [html.Summary(" · ".join(head)), html.Div(style={"marginTop": "8px"}, children=[
        _facts(rows), html.Details([html.Summary(f"scenarios/{name}/config.json"), html.Pre(json.dumps(scfg, indent=2))])])]


def _graph(gid: str) -> dcc.Graph:
    return dcc.Graph(id=gid, config={"displaylogo": False, "responsive": True})


def _card(*children, **kw) -> html.Div:
    return html.Div(className="card", children=list(children), **kw)


def _seg(cid: str, options: dict, value: str) -> dcc.RadioItems:
    return dcc.RadioItems(id=cid, options=[{"label": v, "value": k} for k, v in options.items()], value=value, inline=True, className="seg")


def _metric_dropdown(cid: str, value: str) -> dcc.Dropdown:
    return dcc.Dropdown(id=cid, options=[{"label": lab, "value": k} for k, (lab, _) in METRICS.items()], value=value,
                        clearable=False, className="ctl")


def make_app() -> Dash:
    app = Dash(__name__, title="Scenario browser")
    app.index_string = app.index_string.replace("{%css%}", "{%css%}<style>" + CSS + "</style>")

    def layout():
        names = scenario_names()
        generated = [n for n in names if (OUTPUT_DIR / n / "scenario.json").exists()]
        options = [{"label": n if n in generated else f"{n} (not generated)", "value": n} for n in names]
        return html.Div([
            dcc.Location(id="url"),
            html.Header(html.Div(className="in", children=[
                html.H1(["Scenario browser", html.Small("injections of injection-scenarios/output, local and read-only; "
                                                        "reload the page after a generation")]),
                html.Div(className="controls", children=[
                    html.Div([html.Label("scenario", className="l"),
                              dcc.Dropdown(id="scenario", options=options, clearable=False, className="ctl")]),
                    html.Div([html.Label("compare with", className="l"),
                              dcc.Dropdown(id="compare", options=[o for o in options if o["value"] in generated],
                                           placeholder="(none)", className="ctl")]),
                    html.Div(id="status")])])),
            html.Main([
                html.Details(id="config", className="card"),
                dcc.Tabs(id="tabs", value="overview", style={"borderBottom": f"1px solid {C['grid']}"},
                         children=[
                    dcc.Tab(label="Overview", value="overview", style=TAB, selected_style=TAB_SELECTED, children=dcc.Loading(type="dot", color=SERIES[0], children=[
                        html.Div(id="kpis", className="kpis"),
                        _card(html.Div(className="bar", children=[html.Span("day", className="t"), _seg("day", DAYS, "rep")]), _graph("g-day")),
                        _card(_graph("g-year")),
                        html.Div(className="row", children=[_card(_graph("g-month")), _card(_graph("g-duration"))]),
                        _card(_graph("g-heat")),
                        html.P("Yearly files are hourly means: peaks within the hour are higher. The screening (lv-screening) runs "
                               "the daily product at its own step.", className="note")])),
                    dcc.Tab(label="Networks", value="networks", style=TAB, selected_style=TAB_SELECTED, children=[
                        _card(html.Div(className="bar", children=[html.Span("x", className="t"), _metric_dropdown("sx", "export_pct_trafo"),
                                                                  html.Span("y", className="t"), _metric_dropdown("sy", "import_pct_trafo")]),
                              dcc.Loading(type="dot", color=SERIES[0], children=_graph("g-scatter"))),
                        _card(dash_table.DataTable(
                            id="table", sort_action="native", filter_action="native", page_size=15,
                            sort_by=[{"column_id": "import_pct_trafo", "direction": "desc"}],
                            style_table={"overflowX": "auto"}, style_as_list_view=True,
                            style_header={"fontWeight": 600, "color": C["ink2"], "backgroundColor": C["surface"], "whiteSpace": "normal"},
                            style_cell={"fontFamily": "system-ui, sans-serif", "fontSize": 13, "padding": "4px 8px", "backgroundColor": C["surface"]},
                            style_cell_conditional=[{"if": {"column_id": c}, "textAlign": "left"} for c in ("network_id", "net_peak_time")],
                            style_data_conditional=[{"if": {"filter_query": f"{{{c}}} > 100", "column_id": c}, "color": C["critical"], "fontWeight": 600}
                                                    for c in ("import_pct_trafo", "export_pct_trafo")]),
                              html.P("Click a row to open the network; filter with e.g. > 100 under a column. Red: above the transformer "
                                     "rating (apparent power, hourly means).", className="note"))]),
                    dcc.Tab(label="Network", value="network", style=TAB, selected_style=TAB_SELECTED, children=[
                        html.Div(className="controls", children=[
                            html.Div([html.Label("network", className="l"),
                                      dcc.Dropdown(id="net", clearable=False, className="ctl")]),
                            html.A(id="explorer", target="_blank", style={"marginBottom": "8px"})]),
                        dcc.Loading(type="dot", color=SERIES[0], children=[
                            html.Div(id="net-facts", className="card"),
                            _card(html.Div(className="bar", children=[html.Span("day", className="t"), _seg("net-day", DAYS, "rep")]),
                                  _graph("g-net-day")),
                            _card(html.Div(className="bar", children=[html.Span("stream", className="t"), _seg("conn-stream", {"demand": label("demand")}, "demand")]),
                                  _graph("g-net-conns"), html.P(id="net-note", className="note")),
                            _card(_graph("g-net-year")),
                            html.Div(className="row", children=[_card(_graph("g-net-duration")), _card(_graph("g-net-heat"))])])]),
                    dcc.Tab(label="Compare", value="compare", style=TAB, selected_style=TAB_SELECTED, children=dcc.Loading(type="dot", color=SERIES[0], children=[
                        html.Div(id="cmp-table", className="card"),
                        html.Div(className="row", children=[_card(_graph("g-cmp-day")), _card(_graph("g-cmp-duration"))]),
                        _card(html.Div(className="bar", children=[html.Span("per network", className="t"), _metric_dropdown("shift-metric", "import_pct_trafo")]),
                              _graph("g-shift"))]))])])])
    app.layout = layout

    def _other(name, other):
        if not other or other == name or output_status(other)[0] == "missing":
            return None
        return load_output(other)

    @app.callback(Output("scenario", "value"), Output("compare", "value"), Output("tabs", "value", allow_duplicate=True),
                  Output("net", "value", allow_duplicate=True), Input("url", "search"), prevent_initial_call="initial_duplicate")
    def from_url(search):
        """?scenario=&compare=&tab=&network= on page load; the first generated scenario otherwise."""
        q = parse_qs((search or "").lstrip("?"))
        q = {k: v[0] for k, v in q.items()}
        names = scenario_names()
        generated = [n for n in names if (OUTPUT_DIR / n / "scenario.json").exists()]
        return (q["scenario"] if q.get("scenario") in names else (generated or names or [None])[0],
                q["compare"] if q.get("compare") in generated else None,
                q["tab"] if q.get("tab") in TABS else no_update, q.get("network", no_update))

    @app.callback(Output("status", "children"), Output("config", "children"), Output("kpis", "children"),
                  Output("g-year", "figure"), Output("g-month", "figure"), Output("g-duration", "figure"), Output("g-heat", "figure"),
                  Output("table", "columns"), Output("table", "data"), Output("net", "options"), Output("conn-stream", "options"),
                  Input("scenario", "value"))
    def show_scenario(name):
        if not name:
            return "no scenario folders: python3 generate_scenario.py new <sfoe key>" if not scenario_names() else no_update, *[no_update] * 10
        state, text = output_status(name)
        col = {"ok": C["ok"], "stale": C["warning"], "missing": C["muted"]}[state]
        icon = {"ok": "✓", "stale": "!", "missing": "–"}[state]
        status = html.Span(f"{icon} {text}", className="status", style={"border": f"1.5px solid {col}"})
        if state == "missing":
            blank = _empty("", "no output yet")
            return status, _config(name), [], blank, blank, blank, blank, [], [], [], []
        d = load_output(name)
        figs = overview_figures(d)
        tiles = [html.Div([html.Div(v, className="v"),
                           html.Div([html.Span(className="sw", style={"background": c}) if c else None, k], className="k"),
                           html.Div(detail, className="d")], className="kpi") for v, k, detail, c in kpis(d)]
        cols = table_columns(d)
        columns = [{"name": lab, "id": c, "type": "numeric" if nd is not None else "text",
                    **({"format": Format(precision=nd, scheme=Scheme.fixed, group=Group.yes)} if nd is not None else {})} for c, lab, nd in cols]
        nets = d["nets"].reset_index()
        table = nets[[c for c, _, _ in cols]].assign(id=nets["network_id"]).to_dict("records")
        streams = [{"label": label(s), "value": s} for s in d["streams"]]
        return (status, _config(name), tiles, figs["year"], figs["month"], figs["duration"], figs["heat"], columns, table,
                [{"label": n, "value": n} for n in sorted(d["nets"].index, key=lambda s: (len(s), s))], streams)

    @app.callback(Output("g-day", "figure"), Input("scenario", "value"), Input("compare", "value"), Input("day", "value"))
    def show_day(name, other, which):
        if not name or output_status(name)[0] == "missing":
            return _empty("", "no output yet")
        return regional_day(load_output(name), which, _other(name, other))

    @app.callback(Output("g-scatter", "figure"), Input("scenario", "value"), Input("sx", "value"), Input("sy", "value"))
    def show_scatter(name, x, y):
        if not name or output_status(name)[0] == "missing":
            return _empty("", "no output yet")
        return scatter_figure(load_output(name), x, y)

    @app.callback(Output("net", "value"), Output("tabs", "value"),
                  Input("scenario", "value"), Input("table", "active_cell"), Input("g-scatter", "clickData"), Input("g-shift", "clickData"),
                  State("net", "value"))
    def pick_network(name, cell, click, shift, current):
        if ctx.triggered_id == "table" and cell:
            return cell["row_id"], "network"
        if ctx.triggered_id in ("g-scatter", "g-shift") and (click or shift):
            return (click if ctx.triggered_id == "g-scatter" else shift)["points"][0]["customdata"][0], "network"
        if not name or output_status(name)[0] == "missing":
            return None, no_update
        nets = load_output(name)["nets"]
        if current in nets.index:
            return current, no_update
        key = "import_pct_trafo" if "import_pct_trafo" in nets and nets["import_pct_trafo"].notna().any() else "n_nodes"
        return nets[key].idxmax(), no_update                               # start on the most loaded network

    @app.callback(Output("net-facts", "children"), Output("g-net-year", "figure"), Output("g-net-duration", "figure"),
                  Output("g-net-heat", "figure"), Output("explorer", "children"), Output("explorer", "href"),
                  Input("net", "value"), Input("scenario", "value"), Input("compare", "value"))
    def show_network(nid, name, other):
        if not nid or not name or output_status(name)[0] == "missing":
            blank = _empty("", "pick a network")
            return [], blank, blank, blank, "", None
        d = load_output(name)
        if nid not in d["nets"].index:
            return no_update, no_update, no_update, no_update, no_update, no_update
        figs = network_year_figures(d, nid, _other(name, other))
        return (_facts(network_facts(d, nid)), figs["year"], figs["duration"], figs["heat"],
                "grid data of this network in the explorer ↗ (python3 -m lvgrid explore)", EXPLORER + nid)

    @app.callback(Output("g-net-day", "figure"), Input("net", "value"), Input("scenario", "value"), Input("compare", "value"),
                  Input("net-day", "value"))
    def show_network_day(nid, name, other, which):
        if not nid or not name or output_status(name)[0] == "missing":
            return _empty("", "pick a network")
        d = load_output(name)
        return network_day(d, nid, which, _other(name, other)) if nid in d["nets"].index else no_update

    @app.callback(Output("g-net-conns", "figure"), Output("net-note", "children"),
                  Input("net", "value"), Input("scenario", "value"), Input("conn-stream", "value"))
    def show_connections(nid, name, stream):
        if not nid or not name or output_status(name)[0] == "missing":
            return _empty("", "pick a network"), ""
        d = load_output(name)
        if nid not in d["nets"].index:
            return no_update, no_update
        return connections_figure(d, nid, stream if stream in d["streams"] else "demand")

    @app.callback(Output("cmp-table", "children"), Output("g-cmp-day", "figure"), Output("g-cmp-duration", "figure"),
                  Input("scenario", "value"), Input("compare", "value"))
    def show_compare(name, other):
        if not name or output_status(name)[0] == "missing" or (b := _other(name, other)) is None:
            blank = _empty("", "pick a second scenario under 'compare with'")
            return html.P("Pick a second, generated scenario under 'compare with' (top of the page).", className="note"), blank, blank
        a = load_output(name)
        figs = compare_figures(a, b)
        rows = compare_rows(a, b)
        table = html.Table([html.Tr([html.Th(""), html.Th(a["name"]), html.Th(b["name"]), html.Th("change")])]
                           + [html.Tr([html.Td(c) for c in r]) for r in rows], className="cmp")
        return table, figs["day"], figs["duration"]

    @app.callback(Output("g-shift", "figure"), Input("scenario", "value"), Input("compare", "value"), Input("shift-metric", "value"))
    def show_shift(name, other, metric):
        if not name or output_status(name)[0] == "missing" or (b := _other(name, other)) is None:
            return _empty("", "pick a second scenario under 'compare with'")
        return shift_figure(load_output(name), b, metric)

    return app


def run(host: str = "127.0.0.1", port: int = 8050, debug: bool = False) -> None:
    print(f"scenario browser on http://{host}:{port}  (Ctrl-C to stop)")
    make_app().run(host=host, port=port, debug=debug)
