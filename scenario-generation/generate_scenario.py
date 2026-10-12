#!/usr/bin/env python3
"""Scenario generation for the OIKEN LV portfolio.

    python generate_scenario.py new sc1_2040 [--name my_case]   # scenarios/<name>/config.json from the SFOE table, then edit it
    python generate_scenario.py generate my_case               # -> output/my_case/ (allocation, daily/, yearly/)
    python generate_scenario.py fit-demand                     # once: fit and cache the household demand model
    python generate_scenario.py clearsky --tilt 30 --year 2025 # clear-sky PV profile for a location (pvlib)
"""
from __future__ import annotations

import argparse
import sys

from scengen.config import SCENARIOS_DIR, load_config, resolve


def cmd_new(a):
    from scengen.generate import new_scenario_config, write_scenario_config
    cfg = load_config(a.config)
    name = a.name or a.sfoe
    if (SCENARIOS_DIR / name / "config.json").exists() and not a.force:
        raise SystemExit(f"{SCENARIOS_DIR / name / 'config.json'} exists; use --force to overwrite or --name for another folder")
    path = write_scenario_config(new_scenario_config(cfg, a.sfoe, name))
    print(f"-> {path}  (edit it, then: python generate_scenario.py generate {name})")


def cmd_generate(a):
    from scengen.data import parse_ids
    from scengen.generate import generate
    generate(a.name, parse_ids(a.networks) if a.networks else None)


def cmd_fit_demand(a):
    from scengen.profiles import fit_demand_model, save_demand_model
    cfg = load_config(a.config)
    out = resolve(cfg["demand_model"]["model_file"])
    print(f"fitting the demand model from {resolve(cfg['demand_model']['train_file'])}")
    save_demand_model(fit_demand_model(cfg["demand_model"]), out)
    print(f"-> {out}")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="generate_scenario.py", description="Scenario generation (SFOE PV/EV allocation and injection time series)")
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--config", help="settings file (default: scenario-generation/config.json)")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("new", parents=[common], help="stage 1: write scenarios/<name>/config.json from an SFOE scenario")
    p.add_argument("sfoe", help="SFOE key: sc1_2030, sc2_2030, sc3_2030, sc1_2040, sc2_2040, sc3_2040")
    p.add_argument("--name", help="scenario name (default: the SFOE key)")
    p.add_argument("--force", action="store_true", help="overwrite an existing config.json")
    p.set_defaults(func=cmd_new)

    p = sub.add_parser("generate", parents=[common], help="stage 2: allocation + daily/yearly injections (CSV) -> output/<name>/")
    p.add_argument("name", help="scenario name under scenarios/")
    p.add_argument("--networks", help="id,id,... to generate a subset (tests); default all networks")
    p.set_defaults(func=cmd_generate)

    p = sub.add_parser("fit-demand", parents=[common], help="fit and cache the household demand model (needs the training .mat)")
    p.set_defaults(func=cmd_fit_demand)

    sub.add_parser("clearsky", help="clear-sky PV profile for a location (pvlib); `clearsky -h` for options", add_help=False)

    a, rest = ap.parse_known_args(argv)
    if a.cmd == "clearsky":
        from scengen.clearsky import main as clearsky_main
        return clearsky_main(rest)
    if rest:
        ap.error(f"unrecognized arguments: {' '.join(rest)}")
    return a.func(a) or 0


if __name__ == "__main__":
    sys.exit(main())
