"""Command line entry point: python -m lvgrid <command> [options]"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import pandas as pd

from .config import RESULTS_DIR, load_config


def _networks_arg(portfolio, spec: str | None) -> list[str]:
    """'all' | comma-separated ids | @<run folder or summary.csv> (networks with status ok in that run)."""
    from .data import select_networks
    if spec and spec.startswith("@"):
        path = Path(spec[1:])
        if not path.exists() and (RESULTS_DIR / spec[1:]).exists():
            path = RESULTS_DIR / spec[1:]
        if path.is_dir():
            path = path / "summary.csv"
        s = pd.read_csv(path, dtype={"network_id": str})
        ok = s.groupby("network_id")["status"].apply(lambda x: (x == "ok").all())
        ids = [i for i in portfolio.ids if ok.get(i, False)]
        print(f"{len(ids)} networks with status ok in {path}")
        return ids
    return select_networks(portfolio, spec)


def cmd_oneshot(a):
    from .data import load_portfolio
    from .screening import run
    cfg = load_config(a.config)
    P = load_portfolio()
    ids = _networks_arg(P, a.networks)
    run(P, cfg, ids, out_dir=a.out, save_details=not a.no_details)


def cmd_screen(a):
    from .data import load_portfolio
    from .scenario import load_scenario
    from .screening import run
    cfg = load_config(a.config)
    P = load_portfolio()
    ids = _networks_arg(P, a.networks)
    cases = a.cases.split(",") if a.cases else None
    run(P, cfg, ids, scenario=load_scenario(a.scenario), cases=cases, out_dir=a.out, save_details=not a.no_details)


def cmd_dashboard(a):
    from .dashboard import build_dashboard
    run_dir = Path(a.run_dir)
    if not run_dir.exists() and (RESULTS_DIR / a.run_dir).exists():
        run_dir = RESULTS_DIR / a.run_dir
    out = build_dashboard(run_dir, networks=a.networks, max_pages=a.max_pages)
    print(f"-> {out}")


def cmd_mv_map(a):
    from .data import load_portfolio
    from .mv import write_mv_map
    write_mv_map(load_portfolio())


def cmd_aggregate(a):
    from .mv import aggregate_run
    run_dir = Path(a.run_dir)
    if not run_dir.exists() and (RESULTS_DIR / a.run_dir).exists():
        run_dir = RESULTS_DIR / a.run_dir
    print(f"-> {aggregate_run(run_dir)}")


def cmd_geo(a):
    from .data import load_portfolio
    from .geo import write_geo
    write_geo(load_portfolio())


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="python -m lvgrid", description="Load-flow screening of the OIKEN LV portfolio")
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--config", help="settings file (default: lv-screening/config.json)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sp = lambda name, **kw: sub.add_parser(name, parents=[common], **kw)   # noqa: E731

    p = sp("oneshot", help="data sanity check: one load flow per network at the planning snapshot")
    p.add_argument("--networks", default="all", help="all | id,id,... | @<run folder of a previous run> (its ok networks)")
    p.add_argument("--out", help="results folder (default results/<timestamp>_oneshot)")
    p.add_argument("--no-details", action="store_true", help="skip the per-network .npz files (no dashboard pages)")
    p.set_defaults(func=cmd_oneshot)

    p = sp("screen", help="daily load flow of every network with a generated scenario's injections")
    p.add_argument("--scenario", required=True, help="scenario name (../scenario-generation/output/<name>) or a path to a generated folder")
    p.add_argument("--networks", default="all", help="all | id,id,... | @<oneshot run folder> (its ok networks)")
    p.add_argument("--cases", help="comma list among demand,demand+pv,demand+pv+ev (default all three)")
    p.add_argument("--out", help="results folder (default results/<timestamp>_<scenario>)")
    p.add_argument("--no-details", action="store_true")
    p.set_defaults(func=cmd_screen)

    p = sp("dashboard", help="HTML dashboard for a results folder")
    p.add_argument("run_dir", help="results folder (or its name under results/)")
    p.add_argument("--networks", default="flagged", help="per-network pages: flagged (default) | all | none | id,id,...")
    p.add_argument("--max-pages", type=int, default=300)
    p.set_defaults(func=cmd_dashboard)

    p = sp("geo", help="match nodes to coordinates (needs data/geo/nodes_db.csv)")
    p.set_defaults(func=cmd_geo)

    p = sp("mv-map", help="which HV/MV substation feeds each LV network (closed-switch trace of the MV grid)")
    p.set_defaults(func=cmd_mv_map)

    p = sp("aggregate", help="sum a run's injections and transformer imports per HV/MV substation")
    p.add_argument("run_dir", help="results folder (or its name under results/)")
    p.set_defaults(func=cmd_aggregate)

    a = ap.parse_args(argv)
    return a.func(a) or 0


if __name__ == "__main__":
    sys.exit(main())
