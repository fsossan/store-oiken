"""Demand dashboard of the generated scenarios (Dash, local server, read-only).

    python generate_scenario.py dashboard [--port 8050]      ->  http://127.0.0.1:8050

Pick a scenario folder: its configuration, whether output/<name>/ still matches
it, and the household demand it produced (PV and EV are not shown yet):
  Portfolio  key figures; network peak against the fuse-rated power (the
             demand_factor ceiling); demand per connection; the regional year
             as mean day, heatmap and duration curve.
  Networks   one row per network (sortable, filterable); a row or a scatter
             point opens the network: every connection on the representative
             day in % of its fuse power, the yearly heatmap and duration curve.
The yearly files are read once per scenario (2-3 s for the portfolio) and kept
in memory. The dashboard never starts a generation.
"""
from __future__ import annotations

import json
from functools import lru_cache

import numpy as np
import pandas as pd
import plotly.graph_objects as go
from dash import Dash, Input, Output, ctx, dash_table, dcc, html, no_update
from dash.dash_table.Format import Format, Scheme

from . import __version__
from .config import DATA_DIR, OUTPUT_DIR, SCENARIOS_DIR
from .generate import _sha

FUSE_A_PER_KW = 1 / (np.sqrt(3) * 0.4 * 0.9)        # PLmax = sqrt(3) x 400 V x I_fuse x cos(phi) 0.9 (oiken-db-extraction)
C = {"demand": "#2a78d6", "band": "rgba(42,120,214,0.18)", "muted": "#898781", "ink": "#0b0b0b", "ink2": "#52514e",
     "grid": "#e1e0d9", "axis": "#c3c2b7", "surface": "#fcfcfb", "ok": "#0ca30c", "warning": "#fab219"}
BLUE_RAMP = ["#cde2fb", "#9ec5f4", "#6da7ec", "#3987e5", "#256abf", "#184f95", "#0d366b"]   # lv-screening palette
CSS = """
body { margin: 0; background: #f9f9f7; color: #0b0b0b; font: 14px/1.45 system-ui, -apple-system, "Segoe UI", sans-serif; }
main { max-width: 1280px; margin: 0 auto; padding: 16px; }
h1 { font-size: 22px; margin: 8px 0 4px; } .sub, .note { color: #52514e; } .note { font-size: 12px; }
.card { background: #fcfcfb; border: 1px solid rgba(11,11,11,0.10); border-radius: 8px; padding: 12px 16px; margin: 12px 0; overflow-x: auto; }
.kpis { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 12px; margin: 12px 0; }
.kpi { background: #fcfcfb; border: 1px solid rgba(11,11,11,0.10); border-radius: 8px; padding: 10px 14px; }
.kpi .v { font-size: 24px; font-weight: 600; font-variant-numeric: tabular-nums; } .kpi .l { color: #52514e; font-size: 12px; }
.row { display: grid; grid-template-columns: minmax(0,1fr) minmax(0,1fr); gap: 12px; } @media (max-width: 900px) { .row { grid-template-columns: 1fr; } }
.facts { border-collapse: collapse; } .facts td { padding: 3px 12px 3px 0; vertical-align: top; } .facts td:first-child { color: #52514e; }
.status { display: inline-block; padding: 2px 10px; border-radius: 10px; font-size: 13px; }
pre { font-size: 12px; margin: 6px 0 0; } summary { cursor: pointer; color: #52514e; }
"""


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
    """Output of a scenario with per-network demand statistics (cached until scenario.json changes)."""
    return _load(name, (OUTPUT_DIR / name / "scenario.json").stat().st_mtime)


@lru_cache(maxsize=3)
def _load(name: str, _stamp: float) -> dict:
    folder = OUTPUT_DIR / name
    meta = json.loads((folder / "scenario.json").read_text())
    alloc = pd.read_csv(folder / "allocation.csv", dtype={"network_id": str, "node": str})
    nets = pd.read_csv(folder / "networks.csv", dtype={"network_id": str}).set_index("network_id")
    ids = [n for n in nets.index if (folder / "daily" / f"{n}.csv").exists()]   # the generated networks (--networks: a subset)
    nets, alloc = nets.loc[ids].copy(), alloc[alloc["network_id"].isin(ids)]
    subs = pd.read_csv(DATA_DIR / "lv_grids" / "substations.csv", dtype={"network_id": str})
    nets["trafo_kva"] = subs[subs["object"].str.startswith("T")].groupby("network_id")["rated_kva"].sum().reindex(nets.index)
    d = {"name": name, "meta": meta, "alloc": alloc, "nets": nets, "Y": None}
    ydir = folder / "yearly"
    if not (ids and meta.get("yearly", {}).get("enabled") and all((ydir / f"{n}.csv").exists() for n in ids)):
        return d
    time = pd.to_datetime(pd.read_csv(ydir / f"{ids[0]}.csv", usecols=["time"])["time"], utc=True).dt.tz_convert("Etc/GMT-1")
    P, S = [], []
    for n in ids:
        y = pd.read_csv(ydir / f"{n}.csv", usecols=["demand_kw", "demand_kvar"])
        P.append(y["demand_kw"].to_numpy(np.float32))
        S.append(np.hypot(y["demand_kw"], y["demand_kvar"]).max())
    Y = np.vstack(P)                                                        # [networks x T] kW
    dt_h = (time.iloc[1] - time.iloc[0]).total_seconds() / 3600
    nets = nets.loc[ids].copy()
    nets["annual_mwh"] = Y.sum(axis=1) * dt_h / 1e3
    nets["mwh_per_conn"] = nets["annual_mwh"] / nets["n_nodes"]
    nets["peak_kw"] = Y.max(axis=1)
    nets["peak_pct_fuse"] = 100 * nets["peak_kw"] / nets["plmax_sum_kw"]
    nets["peak_pct_trafo"] = 100 * np.array(S) / nets["trafo_kva"]
    nets["peak_time"] = time.iloc[Y.argmax(axis=1)].dt.strftime("%Y-%m-%d %H:%M").to_numpy()
    d.update(nets=nets, Y=Y, row={n: i for i, n in enumerate(ids)}, time=time, dt_h=dt_h, per_day=int(round(24 / dt_h)))
    return d


def demand_factor(d: dict) -> float | None:
    """The demand_factor the output was generated with (nominal / fuse-rated power in networks.csv)."""
    n = d["nets"]
    return float((n["nominal_demand_kw"] / n["plmax_sum_kw"]).median()) if len(n) else None


# ------------------------------------------------------------------ figures --
def _style(fig: go.Figure, title: str, height: int = 360) -> go.Figure:
    fig.update_layout(title=dict(text=title, x=0, font=dict(size=14)), template="plotly_white", height=height,
                      margin=dict(l=55, r=20, t=45, b=50), paper_bgcolor=C["surface"], plot_bgcolor=C["surface"],
                      font=dict(family='system-ui, -apple-system, "Segoe UI", sans-serif', color=C["ink"], size=12),
                      legend=dict(orientation="h", y=1.0, yanchor="bottom", x=1, xanchor="right", bgcolor="rgba(0,0,0,0)"),
                      hoverlabel=dict(bgcolor="#fff"))
    fig.update_xaxes(gridcolor=C["grid"], zerolinecolor=C["axis"], linecolor=C["axis"])
    fig.update_yaxes(gridcolor=C["grid"], zerolinecolor=C["axis"], linecolor=C["axis"])
    return fig


def _empty(title: str, text: str) -> go.Figure:
    fig = _style(go.Figure(), title, 220)
    fig.add_annotation(text=text, showarrow=False, font=dict(color=C["ink2"]), xref="paper", yref="paper", x=0.5, y=0.5)
    fig.update_xaxes(visible=False)
    fig.update_yaxes(visible=False)
    return fig


def _ref_line(fig: go.Figure, y: float, text: str) -> None:
    fig.add_hline(y=y, line=dict(color=C["muted"], width=1, dash="dash"), annotation_text=text,
                  annotation_position="top right", annotation_font_color=C["ink2"])


def _heatmap(z: np.ndarray, days, unit: str, title: str) -> go.Figure:
    """z [days x steps] on a day-of-year x hour grid."""
    hours = np.arange(z.shape[1]) * 24 / z.shape[1]
    fig = go.Figure(go.Heatmap(z=z, x=hours, y=days, colorscale=[[i / 6, c] for i, c in enumerate(BLUE_RAMP)],
                               colorbar=dict(title=unit, thickness=12),
                               hovertemplate=f"%{{y}} %{{x:.0f}}:00<br>%{{z:.2f}} {unit}<extra></extra>"))
    fig.update_xaxes(title="hour", dtick=3)
    return _style(fig, title, 420)


def _duration(y: np.ndarray, dt_h: float, unit: str, title: str) -> go.Figure:
    s = np.sort(y)[::-1]
    fig = go.Figure(go.Scatter(x=np.arange(len(s)) * dt_h, y=s, mode="lines", line=dict(color=C["demand"], width=2),
                               hovertemplate=f"%{{y:.2f}} {unit} or more for %{{x:.0f}} h<extra></extra>"))
    fig.update_xaxes(title="hours per year")
    fig.update_yaxes(title=unit, rangemode="tozero")
    return _style(fig, title)


def kpis(d: dict) -> list[tuple[str, str]]:
    nets, alloc, f = d["nets"], d["alloc"], demand_factor(d)
    out = [(f"{len(alloc):,}", f"connections in {len(d['nets']):,} networks"),
           (f"{100 * f:.1f} %" if f is not None else "–", "demand_factor (ceiling, % of fuse power)")]
    if d["Y"] is None:
        return out
    R = d["Y"].sum(axis=0)
    gwh = R.sum() * d["dt_h"] / 1e6
    fuse_mw = nets["plmax_sum_kw"].sum() / 1e3
    return out + [(f"{gwh:,.0f} GWh", "annual demand"),
                  (f"{gwh * 1e6 / nets['n_nodes'].sum():,.0f} kWh", "per connection and year"),
                  (f"{R.max() / 1e3:,.1f} MW", f"regional peak, {100 * R.max() / 1e3 / fuse_mw:.2f} % of fuse power"),
                  (f"{nets['peak_pct_fuse'].median():.2f} %", "median network peak, % of fuse power"),
                  (f"{R.mean() / R.max():.2f}", "regional load factor (mean / peak)")]


def portfolio_figures(d: dict) -> dict[str, go.Figure]:
    if d["Y"] is None:
        msg = "no yearly files in this output (time.yearly.enabled is false)"
        return {k: _empty("", msg) for k in ("scatter", "hist", "day", "heat", "duration")}
    nets, Y, f = d["nets"], d["Y"], demand_factor(d)
    fig = go.Figure(go.Scatter(
        x=nets["n_nodes"], y=nets["peak_pct_fuse"], mode="markers", customdata=nets.index,
        marker=dict(color=C["demand"], size=8, opacity=0.6, line=dict(color=C["surface"], width=1)),
        hovertemplate="%{customdata}<br>%{x} connections<br>peak %{y:.2f} % of fuse power<extra></extra>"))
    _ref_line(fig, 100 * f, f"demand_factor {100 * f:.0f} %")
    fig.update_xaxes(title="connections in the network", type="log", tickvals=[1, 2, 5, 10, 20, 50, 100, 200, 500],
                     range=[np.log10(0.8), np.log10(nets["n_nodes"].max() * 1.25)])
    fig.update_yaxes(title="yearly peak, % of fuse power", rangemode="tozero")
    figs = {"scatter": _style(fig, "Network demand peak against network size (click a point to open it)")}

    cap = float(np.percentile(nets["mwh_per_conn"], 99))
    shown = nets["mwh_per_conn"][nets["mwh_per_conn"] <= cap]
    fig = go.Figure(go.Histogram(x=shown, nbinsx=40, marker=dict(color=C["demand"], line=dict(color=C["surface"], width=2)),
                                 hovertemplate="%{x} MWh/yr: %{y} networks<extra></extra>"))
    fig.update_xaxes(title="annual demand per connection, MWh (network average)")
    fig.update_yaxes(title="networks")
    figs["hist"] = _style(fig, f"Demand per connection ({len(nets) - len(shown)} networks above {cap:.0f} MWh not shown)")

    days = d["time"].dt.strftime("%Y-%m-%d").to_numpy()[::d["per_day"]]
    Z = Y.sum(axis=0).reshape(-1, d["per_day"]) / 1e3                      # [days x steps] MW
    h = np.arange(d["per_day"]) * d["dt_h"]
    lo, hi = np.percentile(Z, [5, 95], axis=0)
    fig = go.Figure([
        go.Scatter(x=h, y=hi, mode="lines", line=dict(width=0), hoverinfo="skip", showlegend=False),
        go.Scatter(x=h, y=lo, mode="lines", line=dict(width=0), fill="tonexty", fillcolor=C["band"], name="5-95 % of days",
                   hoverinfo="skip"),
        go.Scatter(x=h, y=Z.mean(axis=0), mode="lines", line=dict(color=C["demand"], width=2), name="mean day",
                   hovertemplate="%{x:.0f}:00  %{y:.1f} MW<extra></extra>")])
    fig.update_xaxes(title="hour", dtick=3)
    fig.update_yaxes(title="MW", rangemode="tozero")
    figs["day"] = _style(fig, "Regional demand over the day")
    figs["heat"] = _heatmap(Z, days, "MW", "Regional demand over the year")
    figs["duration"] = _duration(Z.ravel(), d["dt_h"], "MW", "Regional demand duration curve")
    return figs


def network_facts(d: dict, nid: str) -> list[tuple[str, str]]:
    n = d["nets"].loc[nid]
    rows = d["alloc"][d["alloc"]["network_id"] == nid]
    fuses = (rows["plmax_kw"] * FUSE_A_PER_KW).round().astype(int).value_counts().sort_index()
    out = [("connections", f"{int(n['n_nodes'])}"),
           ("fuses", ", ".join(f"{a} A × {k}" for a, k in fuses.items())),
           ("fuse-rated power", f"{n['plmax_sum_kw']:,.0f} kW"),
           ("ceiling (demand_factor × fuse power)", f"{n['nominal_demand_kw']:,.1f} kW"),
           ("transformer", f"{n['trafo_kva']:,.0f} kVA" if np.isfinite(n["trafo_kva"]) else "none in the data")]
    if d["Y"] is not None:
        out += [("annual demand", f"{n['annual_mwh']:,.1f} MWh, {1e3 * n['mwh_per_conn']:,.0f} kWh per connection"),
                ("yearly peak", f"{n['peak_kw']:,.1f} kW on {n['peak_time']}, {n['peak_pct_fuse']:.2f} % of fuse power"
                                + (f", {n['peak_pct_trafo']:.0f} % of the transformer (apparent power)" if np.isfinite(n["peak_pct_trafo"]) else ""))]
    return out


def network_figures(d: dict, nid: str) -> tuple[dict[str, go.Figure], str]:
    """Figures of one network and the coincidence of its connections on the daily product."""
    figs = {}
    daily = pd.read_csv(OUTPUT_DIR / d["name"] / "daily" / f"{nid}.csv")
    rows = d["alloc"][d["alloc"]["network_id"] == nid].set_index("node")
    cols = [c for c in daily.columns if c.endswith(":demand_kw")]
    nodes = [c.split(":")[0] for c in cols]
    P = daily[cols].to_numpy()                                             # [T x nodes] kW
    pct = 100 * P / rows.loc[nodes, "plmax_kw"].to_numpy()
    total = 100 * P.sum(axis=1) / rows["plmax_kw"].sum()
    h = daily["hour"].to_numpy()
    x = np.concatenate([np.append(h, np.nan) for _ in nodes])
    y = np.concatenate([np.append(pct[:, j], np.nan) for j in range(len(nodes))])
    names = np.concatenate([[nd] * (len(h) + 1) for nd in nodes])
    f = demand_factor(d)
    fig = go.Figure([
        go.Scattergl(x=x, y=y, mode="lines", line=dict(color=C["muted"], width=1), opacity=0.45, name="each connection",
                     text=names, hovertemplate="%{text}  %{x:.2f} h  %{y:.2f} %<extra></extra>"),
        go.Scatter(x=h, y=total, mode="lines", line=dict(color=C["demand"], width=2.5), name="network",
                   hovertemplate="network  %{x:.2f} h  %{y:.2f} %<extra></extra>")])
    _ref_line(fig, 100 * f, f"demand_factor {100 * f:.0f} %")
    fig.update_xaxes(title="hour of the daily product", dtick=3)
    fig.update_yaxes(title="% of the connection's fuse power", rangemode="tozero")
    figs["nodes"] = _style(fig, f"{nid}: representative day, demand in % of fuse power", 420)
    coinc = P.sum(axis=1).max() / P.max(axis=0).sum()
    note = (f"Daily product ({len(h) * (h[1] - h[0]):.0f} h from {d['meta'].get('pv_date', '?')}): the network peak is "
            f"{100 * coinc:.0f} % of the sum of the connections' own peaks (coincidence factor {coinc:.2f}).")
    if d["Y"] is None:
        figs["heat"] = figs["duration"] = _empty("", "no yearly file for this network")
        return figs, note
    yk = d["Y"][d["row"][nid]]
    days = d["time"].dt.strftime("%Y-%m-%d").to_numpy()[::d["per_day"]]
    figs["heat"] = _heatmap(yk.reshape(-1, d["per_day"]), days, "kW", f"{nid}: demand over the year")
    figs["duration"] = _duration(yk, d["dt_h"], "kW", f"{nid}: demand duration curve")
    return figs, note


# ---------------------------------------------------------------------- app --
TABLE_COLS = [("network_id", "network", None), ("n_nodes", "connections", 0), ("plmax_sum_kw", "fuse power kW", 0),
              ("nominal_demand_kw", "ceiling kW", 1), ("annual_mwh", "annual MWh", 1), ("mwh_per_conn", "MWh / connection", 2),
              ("peak_kw", "peak kW", 1), ("peak_pct_fuse", "peak % fuse", 2), ("trafo_kva", "transformer kVA", 0),
              ("peak_pct_trafo", "peak % transformer", 1), ("peak_time", "peak time", None)]


def _facts(rows: list[tuple[str, str]]) -> html.Table:
    return html.Table([html.Tr([html.Td(k), html.Td(v)]) for k, v in rows], className="facts")


def _config_card(name: str) -> list:
    scfg = json.loads((SCENARIOS_DIR / name / "config.json").read_text())
    sf, t, dm = scfg.get("sfoe", {}), scfg.get("time", {}), scfg.get("demand", {})
    yearly = t.get("yearly", {})
    rows = [("SFOE scenario", f"{sf.get('key', '')} {sf.get('year', '')}: {sf.get('description', '')}"),
            ("time", f"{t.get('step_min')} min steps, daily product {t.get('days')} day(s), "
                     + (f"yearly files at {yearly.get('step_min')} min" if yearly.get("enabled") else "no yearly files")),
            ("demand", f"demand_factor {dm.get('demand_factor')}, model {dm.get('model_file')}, seed offset {dm.get('seed_offset')}")]
    return [_facts(rows), html.Details([html.Summary(f"scenarios/{name}/config.json"), html.Pre(json.dumps(scfg, indent=2))])]


def _graph(gid: str) -> dcc.Graph:
    return dcc.Graph(id=gid, config={"displaylogo": False, "responsive": True})


def make_app() -> Dash:
    app = Dash(__name__, title="Scenario demand")
    app.index_string = app.index_string.replace("{%css%}", "{%css%}<style>" + CSS + "</style>")

    def layout():
        names = scenario_names()
        options = [{"label": n if (OUTPUT_DIR / n / "scenario.json").exists() else f"{n} (not generated)", "value": n} for n in names]
        generated = [n for n in names if (OUTPUT_DIR / n / "scenario.json").exists()]
        return html.Main([
            html.H1("Scenario demand"),
            html.P("Household demand of the generated scenarios (injection-scenarios/output). Read-only; "
                   "reload the page to pick up new scenario folders.", className="sub"),
            dcc.Dropdown(id="scenario", options=options, value=(generated or names or [None])[0], clearable=False,
                         style={"maxWidth": "420px"}),
            html.Div(id="status", style={"margin": "10px 0"}),
            html.Div(id="config", className="card"),
            dcc.Tabs(id="tabs", value="portfolio", children=[
                dcc.Tab(label="Portfolio", value="portfolio", children=dcc.Loading([
                    html.Div(id="kpis", className="kpis"),
                    html.Div(className="card", children=_graph("g-scatter")),
                    html.Div(className="row", children=[html.Div(className="card", children=_graph("g-hist")),
                                                        html.Div(className="card", children=_graph("g-day"))]),
                    html.Div(className="row", children=[html.Div(className="card", children=_graph("g-heat")),
                                                        html.Div(className="card", children=_graph("g-duration"))])])),
                dcc.Tab(label="Networks", value="networks", children=[
                    html.Div(className="card", children=dash_table.DataTable(
                        id="table", columns=[{"name": label, "id": c, "type": "numeric" if nd is not None else "text",
                                              **({"format": Format(precision=nd, scheme=Scheme.fixed)} if nd is not None else {})}
                                             for c, label, nd in TABLE_COLS],
                        sort_action="native", filter_action="native", page_size=15,
                        sort_by=[{"column_id": "peak_pct_trafo", "direction": "desc"}],
                        style_table={"overflowX": "auto"}, style_as_list_view=True,
                        style_header={"fontWeight": 600, "color": C["ink2"], "backgroundColor": C["surface"]},
                        style_cell={"fontFamily": "system-ui, sans-serif", "fontSize": 13, "padding": "4px 8px",
                                    "backgroundColor": C["surface"]},
                        style_cell_conditional=[{"if": {"column_id": c}, "textAlign": "left"} for c in ("network_id", "peak_time")])),
                    html.P("Click a row (or a point in the Portfolio scatter) to open a network; "
                           "filter with e.g. > 500 under a column.", className="note"),
                    dcc.Dropdown(id="net", clearable=False, style={"maxWidth": "320px"}),
                    dcc.Loading([
                        html.Div(id="net-facts", className="card"),
                        html.Div(className="card", children=_graph("g-nodes")),
                        html.Div(className="row", children=[html.Div(className="card", children=_graph("g-net-heat")),
                                                            html.Div(className="card", children=_graph("g-net-duration"))])])])])])
    app.layout = layout

    @app.callback(Output("status", "children"), Output("config", "children"), Output("kpis", "children"),
                  Output("g-scatter", "figure"), Output("g-hist", "figure"), Output("g-day", "figure"),
                  Output("g-heat", "figure"), Output("g-duration", "figure"),
                  Output("table", "data"), Output("net", "options"), Input("scenario", "value"))
    def show_scenario(name):
        if not name:
            return "no scenario folders: python3 generate_scenario.py new <sfoe key>", *[no_update] * 9
        state, text = output_status(name)
        colour = {"ok": C["ok"], "stale": C["warning"], "missing": C["muted"]}[state]
        icon = {"ok": "✓", "stale": "!", "missing": "–"}[state]
        status = html.Span(f"{icon} {text}", className="status", style={"border": f"1.5px solid {colour}"})
        if state == "missing":
            blank = _empty("", "no output yet")
            return status, _config_card(name), [], blank, blank, blank, blank, blank, [], []
        d = load_output(name)
        figs = portfolio_figures(d)
        tiles = [html.Div([html.Div(v, className="v"), html.Div(lab, className="l")], className="kpi") for v, lab in kpis(d)]
        nets = d["nets"].reset_index()
        table = nets[[c for c, _, _ in TABLE_COLS if c in nets]].assign(id=nets["network_id"]).to_dict("records")
        return (status, _config_card(name), tiles, figs["scatter"], figs["hist"], figs["day"], figs["heat"], figs["duration"],
                table, [{"label": n, "value": n} for n in sorted(d["nets"].index, key=lambda s: (len(s), s))])

    @app.callback(Output("net", "value"), Output("tabs", "value"),
                  Input("scenario", "value"), Input("table", "active_cell"), Input("g-scatter", "clickData"))
    def pick_network(name, cell, click):
        if ctx.triggered_id == "table" and cell:
            return cell["row_id"], no_update
        if ctx.triggered_id == "g-scatter" and click:
            return click["points"][0]["customdata"], "networks"
        if not name or output_status(name)[0] == "missing":
            return None, no_update
        nets = load_output(name)["nets"]
        key = "peak_pct_trafo" if "peak_pct_trafo" in nets else "n_nodes"
        return nets[key].idxmax(), no_update                               # start on the most loaded network

    @app.callback(Output("net-facts", "children"), Output("g-nodes", "figure"), Output("g-net-heat", "figure"),
                  Output("g-net-duration", "figure"), Input("net", "value"), Input("scenario", "value"))
    def show_network(nid, name):
        if not nid or not name or output_status(name)[0] == "missing":
            blank = _empty("", "pick a network")
            return [], blank, blank, blank
        d = load_output(name)
        if nid not in d["nets"].index:
            return no_update, no_update, no_update, no_update
        figs, note = network_figures(d, nid)
        return [_facts(network_facts(d, nid)), html.P(note, className="note")], figs["nodes"], figs["heat"], figs["duration"]

    return app


def run(host: str = "127.0.0.1", port: int = 8050, debug: bool = False) -> None:
    print(f"scenario demand dashboard on http://{host}:{port}  (Ctrl-C to stop)")
    make_app().run(host=host, port=port, debug=debug)
