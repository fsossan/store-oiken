"""The Dash app of the scenario browser: layout, callbacks and `run`."""
from __future__ import annotations

import json
from urllib.parse import parse_qs

from dash import Dash, Input, Output, State, ctx, dash_table, dcc, html, no_update
from dash.dash_table.Format import Format, Group, Scheme

from ..config import SCENARIOS_DIR, output_folder
from ..output import output_status
from .constants import C, CSS, DAYS, EXPLORER, METRICS, SERIES, TAB, TABS, TAB_SELECTED
from .data import label, load_output, scenario_names
from .figures import (
    compare_figures, compare_rows, connections_figure, empty_figure, energy_table, kpis, network_day, network_facts,
    network_year_figures, overview_figures, regional_day, scatter_figure, shift_figure)


def table_columns(d: dict) -> list[tuple[str, str, int | None]]:
    nets = d["nets"]
    cols = [("network_id", "network", None), ("n_nodes", "connections", 0), ("plmax_sum_kw", "fuse power kW", 0),
            ("trafo_kva", "transformer kVA", 0), ("pv_kwp", "PV kWp", 1), ("ev_count", "EVs", 0)]
    cols += [(f"mwh_{s}", f"{label(s)} MWh", 1) for s in d["streams"]]
    cols += [("net_peak_kw", "peak net load kW", 1), ("import_pct_trafo", "peak % transformer", 0),
             ("net_min_kw", "lowest net load kW", 1), ("export_pct_trafo", "reverse flow % transformer", 0),
             ("reverse_h", "reverse-flow hours", 0), ("net_peak_time", "peak time", None)]
    return [c for c in cols if c[0] == "network_id" or c[0] in nets]


def _energy(d: dict) -> list:
    """The card of energy per season and over the year (figures.energy_table)."""
    table = energy_table(d)
    if table is None:
        return [html.P("Energy per season: needs the yearly files (time.yearly.enabled).", className="note")]
    columns, rows = table
    return [html.Div("Energy per season and over the year, GWh", className="card-title"),
            html.Table([html.Tr([html.Th("")] + [html.Th(c) for c in columns])]
                       + [html.Tr([html.Td(lab)] + [html.Td(f"{v:,.1f}") for v in values]) for lab, values in rows], className="cmp"),
            html.P("All connections, from the yearly files; winter is December, January and February of the same year. The "
                   "demand and EV models have no seasons, so their seasons differ by their number of days. The PV profile is "
                   "an ideal system; the last line scales it to the realistic capacity factor of config.json (pv_realistic).",
                   className="note")]


def _facts(rows: list[tuple[str, str]]) -> html.Table:
    return html.Table([html.Tr([html.Td(k), html.Td(v)]) for k, v in rows], className="facts")


def _config(name: str) -> list:
    scenario = json.loads((SCENARIOS_DIR / name / "config.json").read_text())
    sf, t, dm = scenario.get("sfoe", {}), scenario.get("time", {}), scenario.get("demand", {})
    yearly = t.get("yearly", {})
    head = [f"{sf.get('description', name)}, {sf.get('year', '')}", f"demand_factor {dm.get('demand_factor')}",
            f"{t.get('step_min')} min steps", "hourly yearly files" if yearly.get("enabled") and yearly.get("step_min") == 60
            else (f"yearly files at {yearly.get('step_min')} min" if yearly.get("enabled") else "no yearly files")]
    rows = [("SFOE scenario", f"{sf.get('key', '')}: {sf.get('description', '')}, {sf.get('year', '')}: "
                              f"{sf.get('PV_national_MW', '?')} MW PV and {sf.get('EV_national_thousands', '?')}k EVs in Switzerland, "
                              f"scaled to the region by {sf.get('to_region', 'population')}"),
            ("time", f"{t.get('step_min')} min steps, daily product {t.get('days')} day(s), "
                     + (f"yearly files at {yearly.get('step_min')} min" if yearly.get("enabled") else "no yearly files")),
            ("demand", f"demand_factor {dm.get('demand_factor')}, model {dm.get('model_file')}, seed offset {dm.get('seed_offset')}")]
    if "pv" in scenario:
        rows.append(("PV", ", ".join(f"{k} {v}" for k, v in scenario["pv"].items() if not k.startswith("_"))))
    if "ev" in scenario:
        ev = scenario["ev"]
        rows.append(("EV", f"split by {ev.get('split', 'fuse')}, {ev.get('charger_kw')} kW chargers, arrival {json.dumps(ev.get('arrival_h'))}, energy {json.dumps(ev.get('energy_kwh'))}"))
    return [html.Summary(" · ".join(head)), html.Div(style={"marginTop": "8px"}, children=[
        _facts(rows), html.Details([html.Summary(f"scenarios/{name}/config.json"), html.Pre(json.dumps(scenario, indent=2))])])]


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
        generated = [n for n in names if (output_folder(n) / "scenario.json").exists()]
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
                        html.Div(id="energy", className="card"),
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
        generated = [n for n in names if (output_folder(n) / "scenario.json").exists()]
        return (q["scenario"] if q.get("scenario") in names else (generated or names or [None])[0],
                q["compare"] if q.get("compare") in generated else None,
                q["tab"] if q.get("tab") in TABS else no_update, q.get("network", no_update))

    @app.callback(Output("status", "children"), Output("config", "children"), Output("kpis", "children"), Output("energy", "children"),
                  Output("g-year", "figure"), Output("g-month", "figure"), Output("g-duration", "figure"), Output("g-heat", "figure"),
                  Output("table", "columns"), Output("table", "data"), Output("net", "options"), Output("conn-stream", "options"),
                  Input("scenario", "value"))
    def show_scenario(name):
        if not name:
            return "no scenario folders: python3 generate_scenario.py new <sfoe key>" if not scenario_names() else no_update, *[no_update] * 11
        state, text = output_status(name)
        col = {"ok": C["ok"], "stale": C["warning"], "missing": C["muted"]}[state]
        icon = {"ok": "✓", "stale": "!", "missing": "–"}[state]
        status = html.Span(f"{icon} {text}", className="status", style={"border": f"1.5px solid {col}"})
        if state == "missing":
            blank = empty_figure("", "no output yet")
            return status, _config(name), [], [html.P("no output yet", className="note")], blank, blank, blank, blank, [], [], [], []
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
        return (status, _config(name), tiles, _energy(d), figs["year"], figs["month"], figs["duration"], figs["heat"], columns, table,
                [{"label": n, "value": n} for n in sorted(d["nets"].index, key=lambda s: (len(s), s))], streams)

    @app.callback(Output("g-day", "figure"), Input("scenario", "value"), Input("compare", "value"), Input("day", "value"))
    def show_day(name, other, which):
        if not name or output_status(name)[0] == "missing":
            return empty_figure("", "no output yet")
        return regional_day(load_output(name), which, _other(name, other))

    @app.callback(Output("g-scatter", "figure"), Input("scenario", "value"), Input("sx", "value"), Input("sy", "value"))
    def show_scatter(name, x, y):
        if not name or output_status(name)[0] == "missing":
            return empty_figure("", "no output yet")
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
            blank = empty_figure("", "pick a network")
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
            return empty_figure("", "pick a network")
        d = load_output(name)
        return network_day(d, nid, which, _other(name, other)) if nid in d["nets"].index else no_update

    @app.callback(Output("g-net-conns", "figure"), Output("net-note", "children"),
                  Input("net", "value"), Input("scenario", "value"), Input("conn-stream", "value"))
    def show_connections(nid, name, stream):
        if not nid or not name or output_status(name)[0] == "missing":
            return empty_figure("", "pick a network"), ""
        d = load_output(name)
        if nid not in d["nets"].index:
            return no_update, no_update
        return connections_figure(d, nid, stream if stream in d["streams"] else "demand")

    @app.callback(Output("cmp-table", "children"), Output("g-cmp-day", "figure"), Output("g-cmp-duration", "figure"),
                  Input("scenario", "value"), Input("compare", "value"))
    def show_compare(name, other):
        if not name or output_status(name)[0] == "missing" or (b := _other(name, other)) is None:
            blank = empty_figure("", "pick a second scenario under 'compare with'")
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
            return empty_figure("", "pick a second scenario under 'compare with'")
        return shift_figure(load_output(name), b, metric)

    return app


def run(host: str = "127.0.0.1", port: int = 8050, debug: bool = False) -> None:
    print(f"scenario browser on http://{host}:{port}  (Ctrl-C to stop)")
    make_app().run(host=host, port=port, debug=debug)
