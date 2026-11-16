"""Scenario browser (Dash, local server, read-only).

    python generate_scenario.py dashboard [--port 8050]      ->  http://127.0.0.1:8050

Pick a scenario folder, optionally a second one to compare with: its
configuration, whether output/<name>/ still matches it, and every stream it
produced (demand, PV, EV and any further model listed under `streams` in
scenario.json). Net load = loads - generation: positive, the network draws
from its transformer; negative, reverse flow.
  Overview   key figures; energy per season and over the year (PV also at the
             realistic capacity factor of config.json, pv_realistic); the regional
             day (representative, one per season, peak, reverse-flow or mean
             day), the hourly year, monthly energy, duration curves and the
             net-load heatmap.
  Networks   every network on two selectable axes (default: peak net load and
             largest reverse flow in % of the transformer) and a sortable,
             filterable table; a point or a row opens the network.
  Network    one network: facts, a day of its streams against the transformer
             rating (the representative day at the daily step; the season, peak,
             reverse-flow and mean days hourly), each connection
             in % of its fuse power, the hourly year, duration curves, heatmap.
  Compare    the two scenarios: key figures, regional net load, and every
             network's loading in one against the other.
The yearly files are hourly means (the screening uses the daily product); they
are read once per scenario (2-3 s for the portfolio) and kept in memory. The
page takes ?scenario=, ?compare=, ?tab= and ?network=. It never starts a
generation.

Modules: constants (labels, colours, CSS), data (output/<name>/ read once and cached), figures (figures, key
figures, tables), app (layout, callbacks, `run`).
"""
from ..output import output_status  # noqa: F401
from .app import make_app, run  # noqa: F401
from .constants import DAYS, METRICS  # noqa: F401
from .data import load_output  # noqa: F401
from .figures import (  # noqa: F401
    compare_figures, compare_rows, connections_figure, energy_table, kpis, network_day, network_facts, network_year_figures,
    overview_figures, regional_day, scatter_figure, shift_figure, summary)
