"""python -m pytest tests  (a few seconds; needs ../data and the demand model)."""
import json
import shutil
import sys
import warnings
from pathlib import Path

import numpy as np
import pandas as pd
import pytest
from scipy import stats

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from scengen.config import OUTPUT_DIR, SCENARIOS_DIR, load_config, resolve  # noqa: E402
from scengen.data import load_lines, nodal_ratings  # noqa: E402
from scengen.generate import allocate, generate, load_scenario_config, new_scenario_config, write_scenario_config  # noqa: E402
from scengen.models.common import largest_remainder  # noqa: E402
from scengen.models.demand import load_demand_model, sample_demand  # noqa: E402
from scengen.models.ev import ev_node_profiles, ev_samplers, truncated_sampler  # noqa: E402

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
    nodes, totals = allocate(nodal_ratings(load_lines()), new_scenario_config(cfg, "sc1_2030"))
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


def test_truncated_sampler():
    rng = np.random.default_rng(0)
    x = truncated_sampler({"dist": "normal", "mean": 18, "std": 0.6, "min": 17, "max": 21})(rng, 10000)
    assert x.min() >= 17 and x.max() <= 21 and abs(x.mean() - stats.truncnorm(-1 / 0.6, 3 / 0.6, 18, 0.6).mean()) < 0.02
    assert (truncated_sampler({"dist": "normal", "mean": 44, "std": 0, "min": 0, "max": 100})(rng, 3) == 44).all()
    # GEV shape xi as in MATLAB gevrnd: quantile loc + scale ((-ln p)^-xi - 1) / xi
    xi, loc, scale = 0.2, 10.0, 2.0
    x = truncated_sampler({"dist": "gev", "shape": xi, "loc": loc, "scale": scale, "min": 0, "max": 1e9})(rng, 200000)
    q99 = loc + scale * ((-np.log(0.99)) ** -xi - 1) / xi
    assert abs(np.quantile(x, 0.99) / q99 - 1) < 0.03
    x = truncated_sampler({"dist": "gev", "shape": xi, "loc": loc, "scale": scale, "min": 9, "max": 14})(rng, 1000)
    assert x.min() >= 9 and x.max() <= 14
    x = truncated_sampler({"dist": "normal", "mean": 18, "std": 0.6, "min": 23, "max": 24})(rng, 1000)   # far upper tail
    assert x.min() >= 23 and x.max() <= 24 and abs(x.mean() - stats.truncnorm(5 / 0.6, 6 / 0.6, 18, 0.6).mean()) < 0.01


def test_ev_sessions_deliver_their_energy():
    ecfg = {"arrival_h": {"dist": "gev", "shape": -0.1, "loc": 18, "scale": 1, "min": 16, "max": 19},
            "energy_kwh": {"dist": "normal", "mean": 15, "std": 8, "min": 1, "max": 40}}
    arrival, energy = ev_samplers(ecfg)
    counts = np.array([3, 0, 1, 7])
    out = ev_node_profiles(counts, 11, arrival, energy, 15, np.random.default_rng(1))
    rng = np.random.default_rng(1)
    arrival(rng, counts.sum())
    e = energy(rng, counts.sum())                  # every session ends before 19 + 40 / 11 h, so nothing is cut
    assert np.isclose(out.sum() * 0.25, e.sum()) and (out.max(axis=1) <= 11 * counts + 1e-9).all() and not out[1].any()


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


def test_dashboard(generated):
    from scengen import dashboard as db
    assert db.output_status(NAME)[0] == "ok"
    d = db.load_output(NAME)
    ceiling = 100 * load_config()["scenario_defaults"]["demand"]["demand_factor"]
    assert len(d["nets"]) == 3 and set(d["Y"]) == {"demand", "pv", "ev"} and d["Y"]["pv"].shape == (3, 8760)
    assert (d["nets"]["demand_peak_pct_fuse"] < ceiling + 0.01).all()
    net = d["Y"]["demand"] + d["Y"]["ev"] - d["Y"]["pv"]
    assert np.allclose(d["nets"]["net_peak_kw"], net.max(axis=1)) and np.allclose(d["nets"]["net_min_kw"], net.min(axis=1))
    s = db.summary(d)
    assert np.isclose(s["gwh_net"][1], s["gwh_demand"][1] + s["gwh_ev"][1] - s["gwh_pv"][1])
    assert len(db.kpis(d)) == 8 and set(db.overview_figures(d)) == {"year", "month", "duration", "heat"}
    for which in db.DAYS:
        assert len(db.regional_day(d, which, d).data) == 5                  # 3 streams, net load, the other scenario's net load
        assert len(db.network_day(d, "LV_Grid_101", which).data) == 4
    fig, note = db.connections_figure(d, "LV_Grid_101", "pv")
    assert "coincidence factor" in note and db.network_facts(d, "LV_Grid_101")
    assert set(db.network_year_figures(d, "LV_Grid_101", d)) == {"year", "duration", "heat"}
    for m in db.METRICS:
        db.scatter_figure(d, m, "import_pct_trafo")
        db.shift_figure(d, d, m)
    assert all(r[1] == r[2] and r[3].startswith("0") for r in db.compare_rows(d, d))
    db.make_app()


def test_config_checks():
    from scengen.models import ev
    with pytest.raises(KeyError, match="format before"):
        ev.prepare({"charger_kw": 11, "duration_h": 4, "arrival_mean_h": 18}, 15)
    name = "_test_typo"
    scfg = new_scenario_config(load_config(), "sc1_2030", name)
    scfg["EV"] = scfg.pop("ev")
    write_scenario_config(scfg)
    try:
        with pytest.raises(KeyError, match="unknown block"):
            load_scenario_config(name)
    finally:
        shutil.rmtree(SCENARIOS_DIR / name, ignore_errors=True)


def test_subset_without_yearly():
    """A rerun leaves only its own networks; the dashboard works without yearly files."""
    from scengen.dashboard import connections_figure, kpis, load_output, network_day, network_year_figures
    name = "_test_subset"
    try:
        scfg = new_scenario_config(load_config(), "sc1_2030", name)
        scfg["time"] = {"step_min": 15, "days": 1, "yearly": {"enabled": False}}
        write_scenario_config(scfg)
        generate(name, ["LV_Grid_101", "LV_Grid_230"], verbose=False)
        folder = generate(name, ["LV_Grid_230"], verbose=False)
        assert [f.stem for f in (folder / "daily").glob("*.csv")] == ["LV_Grid_230"]
        d = load_output(name)
        assert list(d["nets"].index) == ["LV_Grid_230"] and d["Y"] is None and kpis(d)[0][2] == "in 1 networks"
        assert len(network_day(d, "LV_Grid_230", "rep").data) == 4 and connections_figure(d, "LV_Grid_230", "demand")[1]
        assert set(network_year_figures(d, "LV_Grid_230")) == {"year", "duration", "heat"}
    finally:
        for d in (SCENARIOS_DIR / name, OUTPUT_DIR / name):
            shutil.rmtree(d, ignore_errors=True)
