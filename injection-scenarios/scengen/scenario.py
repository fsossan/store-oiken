"""The scenario: what is assumed, whatever the grid. A dict, exactly as in scenarios/<name>/config.json:

    name     the folder under scenarios/ and output/
    sfoe     national figures of the SFOE scenario: year, PV MW, EV fleet, population; and to_region, how they are
             scaled to the region ('population': by its share of the national population)
    time     step_min, days of the daily product, yearly files
    demand, pv, ev, ...   one block per model (models/); demand and pv are required; pv and ev carry `split`, how
             their regional total is split over the connections (models/common.SPLITS: 'fuse' | 'connections')

`new_scenario` builds one from the SFOE table and the defaults of config.json (scenario_defaults.sfoe adds to_region
to the SFOE figures); it is then edited (by hand, or in scenario.ipynb) and written. `check_scenario` rejects unknown
blocks and unknown or missing keys inside a block (typos), before anything is computed; keys starting with "_" are
comments.
"""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path

from .config import SCENARIOS_DIR
from .models import MODELS

REQUIRED = ("sfoe", "time", "demand", "pv")
SFOE = ("key", "year", "population_national", "to_region"), ("description",)   # (required, optional) keys, besides the models' NATIONAL
TIME = ("step_min",), ("days", "yearly")
YEARLY = ("enabled",), ("step_min",)


def new_scenario(cfg: dict, sfoe_key: str, name: str | None = None) -> dict:
    if sfoe_key not in cfg["sfoe"]:
        raise KeyError(f"unknown SFOE scenario {sfoe_key}; known: {', '.join(cfg['sfoe'])}")
    d = copy.deepcopy(cfg["scenario_defaults"])          # a copy: editing one scenario must not change the next
    return {"name": name or sfoe_key, "sfoe": {"key": sfoe_key, **cfg["sfoe"][sfoe_key], **d["sfoe"]}, "time": d["time"],
            **{m.NAME: d[m.NAME] for m in MODELS if m.NAME in d}}


def write_scenario(scenario: dict) -> Path:
    folder = SCENARIOS_DIR / scenario["name"]
    folder.mkdir(parents=True, exist_ok=True)
    with open(folder / "config.json", "w") as f:
        json.dump(scenario, f, indent=2)
    return folder / "config.json"


def load_scenario(name: str) -> dict:
    path = SCENARIOS_DIR / name / "config.json"
    if not path.exists():
        raise FileNotFoundError(f"{path} missing: create it with `python generate_scenario.py new <sfoe key> --name {name}`")
    scenario = _read(name)
    check_scenario(scenario, str(path))
    return scenario


def check_scenario(scenario: dict, where: str = "scenario") -> None:
    """The required blocks are there, every other block is a model's, each block has its keys and no others, and
    the scenario holds no grid facts."""
    for key in REQUIRED:
        if key not in scenario:
            raise KeyError(f"{where}: missing block '{key}'")
    known = {"name", *REQUIRED, *(m.NAME for m in MODELS)}
    unknown = [k for k in scenario if k not in known and not k.startswith("_")]
    if unknown:
        raise KeyError(f"{where}: unknown block(s) {', '.join(unknown)}; known: {', '.join(sorted(known - {'name'}))}")
    if "population_sion_sierre" in scenario["sfoe"]:
        raise KeyError(f"{where}: delete sfoe.population_sion_sierre; the region's population now comes with the grid "
                       "(data/lv_grids/region.json)")
    models = active_models(scenario)
    _check_keys(scenario["sfoe"], SFOE[0] + tuple(k for m in models for k in m.NATIONAL),
                SFOE[1] + tuple(k for m in MODELS for k in m.NATIONAL), f"{where}: sfoe")
    _check_keys(scenario["time"], *TIME, f"{where}: time")
    _check_keys(scenario["time"].get("yearly", {"enabled": False}), *YEARLY, f"{where}: time.yearly")
    for m in models:
        _check_keys(scenario[m.NAME], m.REQUIRED, m.OPTIONAL, f"{where}: {m.NAME}")


def _check_keys(block: dict, required: tuple, optional: tuple, where: str) -> None:
    known = list(dict.fromkeys(required + optional))
    keys = [k for k in block if not k.startswith("_")]
    missing = [k for k in required if k not in keys]
    if missing:
        raise KeyError(f"{where}: missing {', '.join(missing)}")
    unknown = [k for k in keys if k not in known]
    if unknown:
        raise KeyError(f"{where}: unknown key(s) {', '.join(unknown)}; known: {', '.join(known)}")


def active_models(scenario: dict) -> list:
    """The models whose block is in the scenario, in MODELS order."""
    return [m for m in MODELS if m.NAME in scenario]


def scenario_hash(scenario: dict) -> str:
    """Identifies the content of a scenario, whatever the layout of its file (recorded in output/<name>/<level>/scenario.json)."""
    return hashlib.sha256(json.dumps(scenario, sort_keys=True).encode()).hexdigest()[:12]


def file_hash(name: str) -> str:
    """`scenario_hash` of scenarios/<name>/config.json as it is on disk."""
    return scenario_hash(_read(name))


def _read(name: str) -> dict:
    with open(SCENARIOS_DIR / name / "config.json") as f:
        return {**json.load(f), "name": name}            # the folder names the scenario
