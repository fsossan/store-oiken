"""MV level: which HV/MV substation feeds each LV network, and aggregation of
a run's injections per HV/MV substation (subtransmission view).

The OIKEN export has, besides the LV networks, the MV lines (one sheet per
HV/MV substation area), the MV switching stations and the 11 HV/MV
substations (65/16 kV transformers with their switchgear). A graph of all MV
lines plus every *closed* switch (MV stations, HV/MV substations and the MV
side of the LV substations) connects each LV transformer's MV node to exactly
one HV/MV transformer for 1098 of the 1116 networks; the rest have gaps in
the MV data and stay "unmapped". Sheet membership alone would not do: a third
of the LV substations have switches into two MV areas (normally open ties).
"""
from __future__ import annotations

import html
from collections import defaultdict, deque
from pathlib import Path

import numpy as np
import pandas as pd

from .config import DATA_DIR
from .data import Portfolio
from .injections import DEFAULT_STREAMS

MV_DIR = DATA_DIR / "mv"
STR = {"from": str, "to": str, "object": str, "mv_grid": str, "station": str, "hvmv": str, "network_id": str}


def load_mv_tables() -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """(mv_lines, mv_stations, hvmv_substations) from data/mv (tools/export_mv_tables.py)."""
    return (pd.read_csv(MV_DIR / "mv_lines.csv", dtype=STR), pd.read_csv(MV_DIR / "mv_stations.csv", dtype=STR),
            pd.read_csv(MV_DIR / "hvmv_substations.csv", dtype=STR))


def _is_trafo(df: pd.DataFrame) -> pd.Series:
    return df["object"].str.startswith("T")


def _trafo_node(df: pd.DataFrame, side: str) -> list[str]:
    """Node of each transformer row on its 'high' or 'low' voltage side."""
    t = df[_is_trafo(df)]
    hi = [a if fk >= tk else b for a, b, fk, tk in zip(t["from"], t["to"], t["from_kv"], t["to_kv"])]
    lo = [b if fk >= tk else a for a, b, fk, tk in zip(t["from"], t["to"], t["from_kv"], t["to_kv"])]
    return hi if side == "high" else lo


def map_networks(portfolio: Portfolio) -> tuple[pd.DataFrame, pd.DataFrame]:
    """(lv_to_hvmv, hvmv): the feeding HV/MV substation of every LV network and
    a table of the HV/MV substations (transformers, MVA, networks fed, position)."""
    lines, stations, hvmv = load_mv_tables()
    adj: dict[str, set] = defaultdict(set)

    def add(a, b):
        adj[a].add(b)
        adj[b].add(a)

    for a, b in zip(lines["from"], lines["to"]):
        add(a, b)
    for df in (stations, hvmv):
        closed = df[(df["on_off"] == 1) & ~_is_trafo(df)]
        for a, b in zip(closed["from"], closed["to"]):
            add(a, b)
    subs = portfolio.subs
    mv_side = (np.minimum(subs["from_kv"], subs["to_kv"]) >= 1) & (subs["on_off"] == 1) & ~_is_trafo(subs)
    for a, b in zip(subs.loc[mv_side, "from"], subs.loc[mv_side, "to"]):
        add(a, b)

    # connected components of the closed MV graph
    comp: dict[str, int] = {}
    for start in list(adj):
        if start in comp:
            continue
        cid = len(comp)
        comp[start] = cid
        q = deque([start])
        while q:
            u = q.popleft()
            for v in adj[u]:
                if v not in comp:
                    comp[v] = cid
                    q.append(v)
    comp_hvmv: dict[int, set] = defaultdict(set)
    for h, g in hvmv.groupby("hvmv"):
        for n in _trafo_node(g, "low"):                      # 16 kV side of the HV/MV transformers
            if n in comp:
                comp_hvmv[comp[n]].add(h)

    rows = []
    for nid, g in subs.groupby("network_id", sort=False):
        feeds = set()
        for n in _trafo_node(g, "high"):                     # 16 kV side of the LV transformers
            feeds |= comp_hvmv.get(comp.get(n, -1), set())
        if len(feeds) == 1:
            status, h = "ok", next(iter(feeds))
        elif feeds:
            status, h = "ambiguous", ",".join(sorted(feeds))
        else:
            status, h = "unmapped", ""
        rows.append({"network_id": nid, "hvmv": h, "status": status})
    lv_map = pd.DataFrame(rows)

    # HV/MV substation table
    t = hvmv[_is_trafo(hvmv)]
    tab = t.groupby("hvmv").agg(city=("city", "first"), n_transformers=("object", "size"), mva=("rated_kva", lambda s: s.sum() / 1e3)).reset_index()
    counts = lv_map[lv_map["status"] == "ok"].groupby("hvmv").size()
    tab["n_networks"] = tab["hvmv"].map(counts).fillna(0).astype(int)
    geo = DATA_DIR / "geo" / "nodes_db.csv"
    if geo.exists():
        from .geo import lv95_to_wgs84
        db = pd.read_csv(geo, dtype={"code": str, "name": str}, low_memory=False).set_index("id_nod")
        ids = tab["hvmv"].astype(int)
        tab["code"] = db["code"].reindex(ids).fillna("").to_numpy()
        tab["name"] = db["name"].reindex(ids).fillna("").to_numpy()
        lat, lon = lv95_to_wgs84(db["E_lv95"].reindex(ids).to_numpy(), db["N_lv95"].reindex(ids).to_numpy())
        tab["lat"], tab["lon"] = lat, lon
    return lv_map, tab


def write_mv_map(portfolio: Portfolio) -> None:
    lv_map, tab = map_networks(portfolio)
    lv_map.to_csv(MV_DIR / "lv_to_hvmv.csv", index=False)
    tab.to_csv(MV_DIR / "hvmv.csv", index=False, float_format="%.6f")
    c = lv_map["status"].value_counts()
    print(f"{len(lv_map)} LV networks: {c.get('ok', 0)} fed by one HV/MV substation, {c.get('ambiguous', 0)} ambiguous, "
          f"{c.get('unmapped', 0)} unmapped (gaps in the MV data) -> {MV_DIR / 'lv_to_hvmv.csv'}")
    print(tab[["hvmv", "city", "n_transformers", "mva", "n_networks"] + (["name"] if "name" in tab else [])].to_string(index=False))


# -------------------------------------------------------------- aggregation --
def aggregate_run(run_dir: Path, main_case: str | None = None) -> Path:
    """Sum the per-network injections and transformer imports of a run per HV/MV
    substation. Writes aggregate_hvmv_series.csv (one row per substation, case
    and step), aggregate_hvmv.csv (peaks, energies, loading of the HV/MV
    transformers) and aggregate_hvmv.html (daily curves)."""
    import json

    run_dir = Path(run_dir)
    summary = pd.read_csv(run_dir / "summary.csv", dtype={"network_id": str, "case": str, "status": str})
    with open(run_dir / "run.json") as f:
        run = json.load(f)
    cases = run["cases"]
    lv_map = pd.read_csv(MV_DIR / "lv_to_hvmv.csv", dtype=str).set_index("network_id")
    tab = pd.read_csv(MV_DIR / "hvmv.csv", dtype={"hvmv": str, "code": str, "name": str})
    details = run_dir / "details"
    dt_h = (run.get("step_min") or 15) / 60.0
    streams = run.get("streams") or DEFAULT_STREAMS                  # name -> 'load' | 'generation'

    series: dict[tuple, dict] = {}        # (hvmv, case) -> arrays
    counts: dict[tuple, dict] = {}
    for nid, g in summary.groupby("network_id", sort=False):
        f = details / f"{nid}.npz"
        if not f.exists():
            continue
        h = lv_map["hvmv"].get(nid, "") or "unmapped"
        if lv_map["status"].get(nid, "unmapped") != "ok":
            h = "unmapped"
        with np.load(f) as z:
            det = {k: z[k] for k in z.files}
        r = g.iloc[0]
        if "demand_kw" in det:
            x = {name: det[f"{name}_kw"] for name in streams}
        else:                                                        # one-shot: constant snapshot
            x = {name: np.zeros(1) for name in streams}
            x.update(demand=np.array([r["nominal_demand_kw"]]), pv=np.array([r.get("pv_kw", 0.0)]))
        for c in cases:
            key = (h, c)
            s = series.setdefault(key, {**{f"{name}_kw": 0.0 for name in streams}, "import_kw": 0.0, "missing_steps": 0})
            cnt = counts.setdefault(key, {"n_networks": 0, "nominal_demand_kw": 0.0, "pv_kwp": 0.0, "ev_count": 0})
            inc = list(streams) if c == "oneshot" else c.split("+")
            v = {name: x[name] if name in inc else np.zeros_like(x["demand"]) for name in streams}
            imp = (sum((v[n] for n in streams if streams[n] == "load"), 0.0)
                   - sum((v[n] for n in streams if streams[n] == "generation"), 0.0))   # injections seen by the transformer
            slack = det.get(f"{c}:slack_kw")
            if slack is not None:
                ok = np.isfinite(slack)
                imp = np.where(ok, slack, imp)                         # load-flow import where it converged
                s["missing_steps"] += int((~ok).sum())
            for name in streams:
                s[f"{name}_kw"] = s[f"{name}_kw"] + v[name]
            s["import_kw"] = s["import_kw"] + imp
            cnt["n_networks"] += 1
            cnt["nominal_demand_kw"] += float(r["nominal_demand_kw"])
            cnt["pv_kwp"] += float(r.get("pv_kwp", 0.0) or 0.0)
            cnt["ev_count"] += int(r.get("ev_count", 0) or 0)

    T = max(len(np.atleast_1d(s["demand_kw"])) for s in series.values())
    t_h = np.arange(T) * dt_h
    mva = dict(zip(tab["hvmv"], tab["mva"]))
    long_rows, sum_rows = [], []
    for (h, c), s in sorted(series.items()):
        x = {name: np.atleast_1d(np.asarray(s[f"{name}_kw"], float)) for name in streams}
        imp = np.atleast_1d(np.asarray(s["import_kw"], float))
        d = x["demand"]
        for k in range(len(d)):
            long_rows.append({"hvmv": h, "case": c, "step": k, "hour": t_h[k], **{f"{n}_kw": x[n][k] for n in streams}, "import_kw": imp[k]})
        cnt = counts[(h, c)]
        mv = mva.get(h, np.nan)
        sum_rows.append({"hvmv": h, "case": c, **cnt, "hvmv_mva": mv, **{f"{n}_peak_kw": float(x[n].max()) for n in streams},
                         "import_peak_kw": float(max(imp.max(), 0)), "export_peak_kw": float(max(-imp.min(), 0)),
                         "import_kwh_day": float(np.clip(imp, 0, None).sum() * dt_h / run.get("n_days", 1)) if len(d) > 1 else np.nan,
                         "export_kwh_day": float(np.clip(-imp, 0, None).sum() * dt_h / run.get("n_days", 1)) if len(d) > 1 else np.nan,
                         "import_peak_over_mva": float(max(imp.max(), -imp.min(), 0) / (mv * 1e3)) if mv == mv else np.nan,
                         "missing_loadflow_steps": s["missing_steps"]})
    long_df = pd.DataFrame(long_rows)
    sum_df = pd.DataFrame(sum_rows)
    long_df.to_csv(run_dir / "aggregate_hvmv_series.csv", index=False, float_format="%.6g")
    sum_df.to_csv(run_dir / "aggregate_hvmv.csv", index=False, float_format="%.6g")
    if T > 1:
        _aggregate_page(run_dir, long_df, sum_df, tab, main_case or cases[-1], streams)
    return run_dir / "aggregate_hvmv.csv"


def _aggregate_page(run_dir: Path, long_df: pd.DataFrame, sum_df: pd.DataFrame, tab: pd.DataFrame, case: str,
                    streams: dict[str, str]) -> None:
    from plotly.subplots import make_subplots
    from .dashboard import C, _fig, _page, stream_color, stream_label

    s = long_df[long_df["case"] == case]
    ids = [h for h in tab["hvmv"] if h in set(s["hvmv"])] + (["unmapped"] if "unmapped" in set(s["hvmv"]) else [])
    cols = 3
    rows = -(-len(ids) // cols)
    names = dict(zip(tab["hvmv"], tab.get("name", tab["hvmv"])))
    fig = make_subplots(rows=rows, cols=cols, shared_xaxes=False, vertical_spacing=0.09, horizontal_spacing=0.06,
                        subplot_titles=[f"{h} {html.escape(str(names.get(h, '')))}".strip() for h in ids])
    for i, h in enumerate(ids):
        r, c = divmod(i, cols)
        g = s[s["hvmv"] == h]
        show = i == 0
        for name in streams:
            fig.add_scatter(x=g["hour"], y=g[f"{name}_kw"] / 1e3, name=stream_label(name), line=dict(color=stream_color(name, streams), width=2),
                            showlegend=show, legendgroup=name, row=r + 1, col=c + 1)
        fig.add_scatter(x=g["hour"], y=g["import_kw"] / 1e3, name="import at the LV transformers", line=dict(color=C["net"], width=2, dash="dot"), showlegend=show, legendgroup="i", row=r + 1, col=c + 1)
        mva = dict(zip(tab["hvmv"], tab["mva"])).get(h)
        if mva:
            fig.add_hline(y=mva, line=dict(color=C["muted"], width=1, dash="dash"), row=r + 1, col=c + 1)
            fig.add_hline(y=-mva, line=dict(color=C["muted"], width=1, dash="dash"), row=r + 1, col=c + 1)
    fig.update_yaxes(title_text="MW")
    fig.update_xaxes(title_text="hour")
    fig.update_layout(title=dict(text=f"Injections per HV/MV substation, case {case} (dashed: HV/MV transformer rating)", font_size=14))
    body = [f"<h1>Subtransmission view, {html.escape(run_dir.name)}</h1>",
            "<p class='sub'>Sum of the LV networks fed by each HV/MV substation (closed-switch trace of the MV grid). "
            "The import curve is the load-flow import of the LV transformers (losses included) where the load flow converged, "
            "the injection sum elsewhere. MV lines, MV losses and MV-connected customers are not modelled.</p>",
            _fig(fig, height=max(320 * rows, 500)), "<h2>Per substation and case</h2><div class='card' style='overflow:auto'>",
            sum_df.to_html(index=False, float_format=lambda x: f"{x:,.1f}", border=0), "</div>"]
    (run_dir / "aggregate_hvmv.html").write_text(_page("Subtransmission view", "".join(body), plotly_src="dashboard/plotly.min.js"))
