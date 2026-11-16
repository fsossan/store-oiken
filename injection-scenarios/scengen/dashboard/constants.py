"""Labels, colours and CSS of the scenario browser."""
from __future__ import annotations

import numpy as np

FUSE_A_PER_KW = 1 / (np.sqrt(3) * 0.4 * 0.9)        # PLmax = sqrt(3) x 400 V x I_fuse x cos(phi) 0.9 (oiken-db-extraction)
SERIES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6", "#e34948"]   # categorical slots, fixed order
STREAMS = {"demand": "household demand", "pv": "PV", "ev": "EV charging"}   # label of the known streams; slot = position
C = {"net": "#0b0b0b", "other": "#898781", "muted": "#898781", "ink": "#0b0b0b", "ink2": "#52514e", "grid": "#e1e0d9",
     "axis": "#c3c2b7", "surface": "#fcfcfb", "ok": "#0ca30c", "warning": "#fab219", "critical": "#d03b3b"}
BLUE_RAMP = ["#cde2fb", "#9ec5f4", "#6da7ec", "#3987e5", "#256abf", "#184f95", "#0d366b"]   # lv-screening palette
RED_RAMP = ["#fbdcdb", "#f5aeac", "#ec7b7a", "#e34948", "#b8302f", "#7d1f1e"]
DIVERGING = [[i / 12, c] for i, c in enumerate(RED_RAMP[::-1] + ["#f0efec"] + BLUE_RAMP[1:])]   # reverse flow <- 0 -> draw
DAYS = {"rep": "representative day", "winter": "winter", "spring": "spring", "summer": "summer", "autumn": "autumn",
        "peak": "peak day", "reverse": "reverse-flow day", "mean": "mean day"}          # seasons: their representative days
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
.card-title { font-size: 14px; font-weight: 600; margin: 0 0 8px; }
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
