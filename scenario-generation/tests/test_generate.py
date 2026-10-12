"""python -m pytest tests  (a few seconds; needs ../data and the demand model)."""
import json
import shutil
import sys
import warnings
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from scengen.config import OUTPUT_DIR, SCENARIOS_DIR, load_config, resolve  # noqa: E402
from scengen.data import load_lines, nodal_ratings  # noqa: E402
from scengen.generate import allocate, generate, largest_remainder, new_scenario_config, write_scenario_config  # noqa: E402
from scengen.profiles import load_demand_model, sample_demand  # noqa: E402

warnings.filterwarnings("ignore")
NAME = "_test_sc1_2030"


@pytest.fixture(scope="module")
def generated():
    cfg = load_config()
    for d in (SCENARIOS_DIR / NAME, OUTPUT_DIR / NAME):
        shutil.rmtree(d, ignore_errors=True)
    scfg = new_scenario_config(cfg, "sc1_2030", NAME)
    scfg["time"] = {"step_min": 15, "days": 2, "yearly": {"enabled": True, "step_min": 60}}
    write_scenario_config(scfg)
    folder = generate(NAME, ["LV_Grid_101", "LV_Grid_412", "LV_Grid_230"], verbose=False)
    yield folder
    for d in (SCENARIOS_DIR / NAME, OUTPUT_DIR / NAME):
        shutil.rmtree(d, ignore_errors=True)


def test_largest_remainder():
    out = largest_remainder(10, np.array([1.0, 1.0, 1.0]))
    assert out.sum() == 10 and out.tolist() == [4, 3, 3]
    assert largest_remainder(0, np.array([1.0])).tolist() == [0]


def test_allocation_matches_matlab_report():
    cfg = load_config()
    nodes, totals = allocate(nodal_ratings(load_lines()), cfg["sfoe"]["sc1_2030"])
    assert totals["ev_allocated"] == totals["ev_region"] and abs(totals["pv_allocated_kwp"] - totals["pv_region_kwp"]) < 1e-6
    rows = nodes[nodes["network_id"] == "LV_Grid_101"]
    assert abs(rows["pv_kwp"].sum() - 85.0247) < 0.01 and rows["ev_count"].sum() == 8      # tech-selection report values


def test_demand_sampler_is_nested_per_day():
    cfg = load_config()
    model = load_demand_model(resolve(cfg["demand_model"]["model_file"]))
    a, ca = sample_demand(model, 20, [5, 6], 101)
    b, cb = sample_demand(model, 20, [6], 101)
    assert a.shape == (20, 2, 96) and np.allclose(a[:, 1], b[:, 0]) and (ca == cb).all()
    assert 0.02 < a.mean() < 0.5 and a.min() >= 0        # a household day averages ~10 % of its own peak


def test_generated_files(generated):
    meta = json.load(open(generated / "scenario.json"))
    assert meta["networks_written"] == 3 and meta["days"] == 2
    daily = pd.read_csv(generated / "daily" / "LV_Grid_101.csv")
    assert len(daily) == 192 and daily["hour"].iloc[-1] == 47.75
    pv_cols = [c for c in daily.columns if c.endswith(":pv_kw")]
    assert daily[pv_cols].sum(axis=1).max() > 0 and (daily[pv_cols] >= 0).all().all()
    ev_cols = [c for c in daily.columns if c.endswith(":ev_kw")]
    assert daily[ev_cols].to_numpy().max() <= 11 * 10 and daily[ev_cols].to_numpy().sum() > 0
    yearly = pd.read_csv(generated / "yearly" / "LV_Grid_101.csv")
    assert len(yearly) == 8760
    # the daily product is the yearly series on the PV day (hourly means of day 0)
    k = meta["pv_day_index"]
    d_cols = [c for c in daily.columns if c.endswith(":demand_kw")]
    hourly = daily[d_cols].sum(axis=1).to_numpy()[:96].reshape(24, 4).mean(axis=1)
    assert np.allclose(hourly, yearly["demand_kw"].to_numpy()[k * 24:(k + 1) * 24], rtol=1e-3, atol=0.01)
    alloc = pd.read_csv(generated / "allocation.csv")
    assert set(alloc.columns) == {"network_id", "node", "plmax_kw", "qlmax_kvar", "pv_kwp", "ev_count"}
