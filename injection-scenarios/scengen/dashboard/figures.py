"""The figures, key figures and tables of the scenario browser, each from the loaded output of a scenario."""
from __future__ import annotations

import numpy as np
import pandas as pd
import plotly.graph_objects as go

from .constants import C, DIVERGING, FUSE_A_PER_KW, METRICS, SERIES
from ..models.common import SEASON_MONTHS, SEASONS
from .data import colour, daily, daily_series, demand_factor, label, net_of, network_series, pick_day, pv_factors, season_day


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


def empty_figure(title: str, text: str) -> go.Figure:
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
    if (f := pv_factors(d)) is not None:
        out["gwh_pv_realistic"] = (f"PV at a capacity factor of {f[1]:.0%}, GWh per year", out["gwh_pv"][1] * f[1] / f[0], "{:,.1f}")
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
            if (f := pv_factors(d)) is not None:
                detail += f"; {s['gwh_pv_realistic']:,.1f} GWh at a capacity factor of {f[1]:.0%} ({f[1] * 8760:,.0f} h)"
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
        return {k: empty_figure("", msg) for k in ("year", "month", "duration", "heat")}
    R = {s: y / 1e3 for s, y in d["R"].items()}
    return {"year": year_figure(d, R, "Regional power over the year, hourly (drag the slider or pick a span)", "MW"),
            "month": month_figure(d, d["R"], "Energy per month", "GWh", 1e6),
            "duration": duration_figure(d, R, "Duration curves", "MW"),
            "heat": heat_figure(d, net_of(d, R), "Regional net load over the year", "MW")}


def energy_table(d: dict) -> tuple[list[str], list[tuple[str, list[float]]]] | None:
    """Energy of all connections per season and over the year, GWh, from the yearly files: (column labels, rows of
    (label, values)). Rows: each load, the total load, each generation stream, and PV at the realistic capacity factor
    (pv_realistic in config.json). None without yearly files."""
    if d["Y"] is None:
        return None
    month = d["time"].dt.month.to_numpy()
    masks = [np.isin(month, SEASON_MONTHS[q]) for q in SEASONS]

    def gwh(y: np.ndarray) -> list[float]:
        v = [float(y[m].sum()) * d["dt_h"] / 1e6 for m in masks]
        return v + [sum(v)]

    loads = [s for s in d["R"] if d["sign"][s] == 1]
    rows = [(label(s), gwh(d["R"][s])) for s in loads] + [("total load", gwh(sum(d["R"][s] for s in loads)))]
    f = pv_factors(d)
    for s in (s for s in d["R"] if d["sign"][s] == -1):
        if s == "pv" and f is not None:
            rows.append((f"PV, {d['meta'].get('pv_series', '')} profile (capacity factor {f[0]:.1%})", gwh(d["R"]["pv"])))
            rows.append((f"PV at a capacity factor of {f[1]:.0%}", gwh(d["R"]["pv"] * f[1] / f[0])))
        else:
            rows.append((label(s), gwh(d["R"][s])))
    return list(SEASONS) + ["year"], rows


def _no_season_day(d: dict, which: str) -> go.Figure | None:
    """A message instead of a figure for a season day that the output does not record (written before 0.5.0)."""
    if which in SEASONS and season_day(d, which) is None:
        return empty_figure("", "this output does not record the season days: regenerate it")
    return None


def regional_day(d: dict, which: str, other: dict | None = None) -> go.Figure:
    if d["Y"] is None:
        return empty_figure("", "no yearly files in this output")
    if (msg := _no_season_day(d, which)) is not None:
        return msg
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
        return empty_figure("", "this axis needs the yearly files")
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
        return empty_figure("", "no yearly files: only the representative day")
    elif (msg := _no_season_day(d, which)) is not None:
        return msg
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
        return empty_figure("", f"no {label(stream)} in {nid}"), ""
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
        return {k: empty_figure("", "no yearly file for this network") for k in ("year", "duration", "heat")}
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
        return {k: empty_figure("", "both scenarios need yearly files") for k in ("day", "duration")}
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
        return empty_figure("", "this figure needs the yearly files of both scenarios")
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
