"""Portfolio runs: the one-shot sanity check and the scenario screening.

Both loop over networks, run the load flow, score each network and write one
results folder:

    results/<timestamp>_<label>/
        run.json          settings snapshot, selection, timing
        summary.csv       one row per network and case (metrics + static data)
        details/<id>.npz  per-step voltages, line loadings, aggregate series
                          (consumed by the dashboard)

Cases of the scenario screening: 'demand', 'demand+pv', 'demand+pv+ev', so a
violation can be attributed to its driver. The one-shot run has one case,
'oneshot': demand_factor x fuse-rated peak at every node at the same instant
(and generation_factor x existing PV), the DSO's planning snapshot.
"""
from __future__ import annotations

import json
import sys
import time
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd

from . import __version__
from .allocation import allocate_pv_ev, apply_allocation
from .config import RESULTS_DIR, base_current_A, kw_per_pu
from .data import Portfolio
from .geo import load_geo, network_coordinates
from .injections import CASES, ProfileSource, build_injections, case_injection_pu
from .loadflow import LoadflowResult, solve
from .network import EDGE_LINE, Network, NetworkError, build_network, topology_ok

STATUSES = ["ok", "violation", "not_converged", "topology_error", "build_error"]


# ------------------------------------------------------------------ scoring --
def evaluate(net: Network, lf: LoadflowResult, cfg: dict) -> tuple[dict, dict]:
    """Metrics of one load-flow run (T steps) and the arrays kept for the dashboard."""
    lim = cfg["limits"]
    kW = kw_per_pu(cfg)
    T = len(lf.converged)
    conv = lf.converged
    vmag = lf.vmag.copy()
    vmag[~conv] = np.nan
    amp = np.where(net.ampacity_a > 0, net.ampacity_a, np.nan)
    loading = (lf.imag * base_current_A(cfg)) / amp[None, :]
    loading[~conv] = np.nan
    slack_kw = lf.S_slack.real * kW
    slack_kw[~conv] = np.nan

    m: dict = {"n_steps": T, "converged_steps": int(conv.sum()), "n_iter": lf.n_iter}
    if conv.any():
        vv = np.where(np.isnan(vmag), np.inf, vmag)
        k = np.unravel_index(np.argmin(vv), vv.shape)
        m.update(v_min=float(vmag[k]), v_min_node=net.node_names[k[1]], v_min_step=int(k[0]))
        vv = np.where(np.isnan(vmag), -np.inf, vmag)
        k = np.unravel_index(np.argmax(vv), vv.shape)
        m.update(v_max=float(vmag[k]), v_max_node=net.node_names[k[1]], v_max_step=int(k[0]))
        under = vmag < lim["v_min_pu"]
        over = vmag > lim["v_max_pu"]
        m.update(n_undervolt_nodes=int(under.any(axis=0).sum()), undervolt_steps=int(under.any(axis=1).sum()),
                 n_overvolt_nodes=int(over.any(axis=0).sum()), overvolt_steps=int(over.any(axis=1).sum()))
        lines = net.edge_type == EDGE_LINE
        ll = np.where(np.isnan(loading), -np.inf, loading)
        ll_lines = ll[:, lines]
        if ll_lines.size and np.isfinite(ll_lines).any():
            k = np.unravel_index(np.argmax(ll_lines), ll_lines.shape)
            m.update(line_max_loading=float(ll_lines[k]), line_max_id=net.edge_id[np.flatnonzero(lines)[k[1]]])
        else:
            m.update(line_max_loading=np.nan, line_max_id="")
        over_l = loading[:, lines] > lim["line_loading_max"]
        m.update(n_overloaded_lines=int(over_l.any(axis=0).sum()), overload_steps=int(over_l.any(axis=1).sum()))
        tl = loading[:, net.trafo_edges]
        m.update(trafo_max_loading=float(np.nanmax(tl)) if np.isfinite(tl).any() else np.nan,
                 trafo_overload_steps=int((tl > lim["trafo_loading_max"]).any(axis=1).sum()))
        m.update(slack_peak_import_kw=float(np.nanmax(np.r_[slack_kw, 0.0])),
                 slack_peak_export_kw=float(np.nanmax(np.r_[-slack_kw, 0.0])))
        loss_kw = (lf.imag ** 2 @ net.r_pu) * kW                       # I^2 R over all branches, per step
        m["losses_kw_mean"] = float(loss_kw[conv].mean())
        kinds = []
        if m["n_undervolt_nodes"]:
            kinds.append("undervoltage")
        if m["n_overvolt_nodes"]:
            kinds.append("overvoltage")
        if m["n_overloaded_lines"]:
            kinds.append("line_overload")
        if m["trafo_overload_steps"]:
            kinds.append("trafo_overload")
        m["violation_types"] = ",".join(kinds)
    else:
        m["violation_types"] = ""
    if not conv.all():
        m["status"] = "not_converged"
    elif m["violation_types"]:
        m["status"] = "violation"
    else:
        m["status"] = "ok"
    arrays = {"vmag": vmag.astype(np.float32), "loading": loading.astype(np.float32),
              "converged": conv, "slack_kw": slack_kw.astype(np.float32)}
    return m, arrays


def static_info(net: Network, cfg: dict) -> dict:
    lines = net.edge_type == EDGE_LINE
    return {
        "network_id": net.id, "net_num": net.num, "n_nodes": net.n_nodes, "n_lines": int(lines.sum()),
        "n_transformers": len(net.trafo_kva), "trafo_kva": float(net.trafo_kva.sum()),
        "line_length_km": float(net.length_m[lines].sum() / 1000), "is_radial": net.is_radial,
        "plmax_sum_kw": float(net.plmax_kw.sum()),
        "nominal_demand_kw": float(cfg["demand_factor"] * net.plmax_kw.sum()),
        "n_demand_nodes": int((net.plmax_kw > 0).sum()),
        "existing_pv_kw": float(net.pg_kw.sum()),
        "pv_kwp": float(net.pv_kwp.sum()), "ev_count": int(net.ev_count.sum()),
        "slack_node": net.node_names[0], "issues": "; ".join(net.issues),
    }


def error_row(network_id: str, status: str, message: str, case: str) -> dict:
    return {"network_id": network_id, "net_num": int("".join(c for c in network_id if c.isdigit())),
            "case": case, "status": status, "error": message}


# --------------------------------------------------------------------- run --
def run(portfolio: Portfolio, cfg: dict, ids: list[str], mode: str, scenario: str | None = None,
        cases: list[str] | None = None, n_days: int = 1, out_dir: Path | None = None,
        save_details: bool = True, verbose: bool = True) -> tuple[pd.DataFrame, Path]:
    """mode 'oneshot' (data sanity check) or 'scenario' (SFOE screening)."""
    t0 = time.time()
    if mode == "oneshot":
        cases = ["oneshot"]
        label = "oneshot"
        alloc = None
        src = None
    elif mode == "scenario":
        if scenario not in cfg["scenarios"]:
            raise KeyError(f"unknown scenario {scenario}; known: {', '.join(cfg['scenarios'])}")
        cases = cases or list(CASES)
        label = scenario
        alloc = allocate_pv_ev(portfolio, scenario, cfg)
        src = ProfileSource(cfg)
    else:
        raise ValueError(mode)
    out_dir = Path(out_dir) if out_dir else RESULTS_DIR / f"{datetime.now():%Y%m%d_%H%M%S}_{label}"
    out_dir.mkdir(parents=True, exist_ok=True)
    details_dir = out_dir / "details"
    if save_details:
        details_dir.mkdir(exist_ok=True)
    geo = load_geo()
    geo_nodes, geo_subs = geo if geo else (None, None)
    sub_pos = geo_subs.set_index("network_id")[["lat", "lon"]] if geo_subs is not None else None

    rows: list[dict] = []
    tty = sys.stdout.isatty()
    for k, nid in enumerate(ids, 1):
        if verbose and (tty or k % 100 == 0 or k == len(ids)):
            print(f"[{k:4d}/{len(ids)}] {nid}", end="\r" if tty else "\n", flush=True)
        lines, subs = portfolio.network(nid)
        try:
            net = build_network(nid, lines, subs, cfg)
        except NetworkError as e:
            rows.extend(error_row(nid, "build_error", str(e), c) for c in cases)
            continue
        except Exception as e:  # unexpected data problem: record, keep going
            rows.extend(error_row(nid, "build_error", f"{type(e).__name__}: {e}", c) for c in cases)
            continue
        apply_allocation(net, alloc)
        info = static_info(net, cfg)
        if sub_pos is not None and nid in sub_pos.index:
            info["lat"], info["lon"] = float(sub_pos.at[nid, "lat"]), float(sub_pos.at[nid, "lon"])
        if not topology_ok(net):
            for c in cases:
                rows.append({**info, "case": c, "status": "topology_error", "error": "; ".join(net.issues)})
            continue

        detail = {"node_names": np.array(net.node_names), "edge_from": net.edge_from, "edge_to": net.edge_to,
                  "edge_id": np.array(net.edge_id), "edge_type": net.edge_type, "ampacity_a": net.ampacity_a,
                  "plmax_kw": net.plmax_kw, "pg_kw": net.pg_kw, "pv_kwp": net.pv_kwp, "ev_count": net.ev_count,
                  "trafo_kva": net.trafo_kva, "trafo_edges": net.trafo_edges, "cases": np.array(cases)}
        if geo_nodes is not None:
            lat, lon, located = network_coordinates(net, geo_nodes)
            detail.update(lat=lat, lon=lon, located=located)

        if mode == "oneshot":
            gf = cfg["oneshot"]["generation_factor"]
            s_kw = -cfg["demand_factor"] * (net.plmax_kw + 1j * net.qlmax_kvar) + gf * net.pg_kw
            lf = solve(net, (s_kw[1:] / kw_per_pu(cfg))[None, :], cfg)
            m, arrays = evaluate(net, lf, cfg)
            rows.append({**info, "case": "oneshot", **m, "pv_kw": float(gf * net.pg_kw.sum())})
            detail.update({f"oneshot:{k}": v for k, v in arrays.items()})
        else:
            inj = build_injections(net, src, n_days)
            agg = inj.aggregate()
            detail.update(time_h=inj.time_h, demand_kw=agg["demand_kw"], pv_kw=agg["pv_kw"], ev_kw=agg["ev_kw"],
                          demand_clusters=inj.meta["demand_clusters"])
            dt_h = cfg["time"]["step_min"] / 60.0
            base = {**info, "pv_date": inj.meta["pv_date"], "n_days": n_days,
                    "demand_peak_kw": float(agg["demand_kw"].max()), "demand_kwh_day": float(agg["demand_kw"].sum() * dt_h / n_days),
                    "pv_peak_kw": float(agg["pv_kw"].max()), "pv_kwh_day": float(agg["pv_kw"].sum() * dt_h / n_days),
                    "ev_peak_kw": float(agg["ev_kw"].max()), "ev_kwh_day": float(agg["ev_kw"].sum() * dt_h / n_days)}
            for c in cases:
                s_pu = case_injection_pu(inj, c, cfg)
                lf = solve(net, s_pu, cfg)
                p_net = -(s_pu.real.sum(axis=1)) * kw_per_pu(cfg)               # net consumption of the nodes
                m, arrays = evaluate(net, lf, cfg)
                rows.append({**base, "case": c, **m,
                             "net_peak_import_kw": float(np.max(np.r_[p_net, 0])),
                             "net_peak_export_kw": float(np.max(np.r_[-p_net, 0]))})
                detail.update({f"{c}:{k}": v for k, v in arrays.items()})
        if save_details:
            np.savez_compressed(details_dir / f"{nid}.npz", **detail)
    if verbose and tty:
        print()

    summary = pd.DataFrame(rows)
    front = ["network_id", "case", "status"]
    summary = summary[front + [c for c in summary.columns if c not in front]]
    summary.to_csv(out_dir / "summary.csv", index=False, float_format="%.6g")
    run_info = {"created": datetime.now().isoformat(timespec="seconds"), "lvgrid_version": __version__,
                "mode": mode, "scenario": scenario, "cases": cases, "n_days": n_days, "n_networks": len(ids),
                "selection": ids if len(ids) < 50 else f"{len(ids)} networks", "seconds": round(time.time() - t0, 1),
                "config": cfg}
    if alloc is not None:
        run_info["allocation"] = {"pv_region_kwp": alloc.pv_region_kwp, "ev_region": alloc.ev_region,
                                  "population_ratio": alloc.pop_ratio, "pv_date": src.pv_date}
    with open(out_dir / "run.json", "w") as f:
        json.dump(run_info, f, indent=2, default=str)
    if verbose:
        print_summary(summary, cases)
        print(f"-> {out_dir}  ({run_info['seconds']} s)")
    return summary, out_dir


def print_summary(summary: pd.DataFrame, cases: list[str]) -> None:
    for c in cases:
        s = summary[summary["case"] == c]
        counts = s["status"].value_counts()
        parts = ", ".join(f"{counts.get(st, 0)} {st}" for st in STATUSES if counts.get(st, 0))
        print(f"{c:14s}: {len(s)} networks: {parts}")
        if "violation_types" in s:
            v = s["violation_types"].fillna("")
            kinds = {k: int(v.str.contains(k).sum()) for k in ("undervoltage", "overvoltage", "line_overload", "trafo_overload")}
            print(f"{'':14s}  " + ", ".join(f"{n} {k}" for k, n in kinds.items() if n))
