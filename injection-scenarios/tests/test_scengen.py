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
from scengen.demand_check import demand_check, energy_bounds  # noqa: E402
from scengen.grid import load_grid  # noqa: E402
from scengen.injections import allocate, prepare  # noqa: E402
from scengen.models.common import largest_remainder  # noqa: E402
from scengen.models.demand import load_demand_model, sample_demand  # noqa: E402
from scengen.models.ev import ev_node_profiles, ev_samplers, truncated_sampler  # noqa: E402
from scengen.output import write  # noqa: E402
from scengen.scenario import load_scenario, new_scenario, scenario_hash, write_scenario  # noqa: E402

warnings.filterwarnings("ignore")
NAME = "_test_sc1_2030"


def generate(name, ids=None):
    """What `generate_scenario.py generate` does."""
    return write(prepare(load_grid(), load_scenario(name)), ids)


@pytest.fixture(scope="module")
def generated():
    cfg = load_config()
    for d in (SCENARIOS_DIR / NAME, OUTPUT_DIR / NAME):
        shutil.rmtree(d, ignore_errors=True)
    scenario = new_scenario(cfg, "sc1_2030", NAME)
    scenario["time"] = {"step_min": 15, "days": 2, "yearly": {"enabled": True, "step_min": 60}}
    write_scenario(scenario)
    folder = generate(NAME, ["LV_Grid_101", "LV_Grid_412", "LV_Grid_230"])
    yield folder
    for d in (SCENARIOS_DIR / NAME, OUTPUT_DIR / NAME):
        shutil.rmtree(d, ignore_errors=True)


def test_largest_remainder():
    out = largest_remainder(10, np.array([1.0, 1.0, 1.0]))
    assert out.sum() == 10 and out.tolist() == [4, 3, 3]
    assert largest_remainder(0, np.array([1.0])).tolist() == [0]


def test_allocation_matches_matlab_report():
    cfg = load_config()
    grid = load_grid()
    nodes, totals = allocate(grid, new_scenario(cfg, "sc1_2030"))
    assert np.isclose(totals["population_ratio"], 105042 / 9462900) and (nodes["plmax_kw"] > 0).all()
    assert len(nodes) == len(grid.connections) == grid.networks["connections"].sum() and "pv_kwp" not in grid.connections
    assert totals["ev_allocated"] == totals["ev_region"] and abs(totals["pv_allocated_kwp"] - totals["pv_region_kwp"]) < 1e-6
    rows = nodes[nodes["network_id"] == "LV_Grid_101"]
    assert abs(rows["pv_kwp"].sum() - 85.0247) < 0.01 and rows["ev_count"].sum() == 8      # tech-selection report values
    assert totals["to_region"] == "population" and totals["region_share"] == totals["population_ratio"]
    assert totals["pv_split"] == totals["ev_split"] == "fuse"


def test_split_methods():
    """pv.split / ev.split: 'connections' gives every connection the same share; unknown methods are rejected."""
    cfg = load_config()
    grid = load_grid()
    scenario = new_scenario(cfg, "sc1_2030")
    scenario["pv"]["split"] = scenario["ev"]["split"] = "connections"
    nodes, totals = allocate(grid, scenario)
    assert np.allclose(nodes["pv_kwp"], totals["pv_region_kwp"] / len(nodes)) and totals["pv_split"] == "connections"
    assert totals["ev_allocated"] == totals["ev_region"] and nodes["ev_count"].max() - nodes["ev_count"].min() <= 1
    fuse, _ = allocate(grid, new_scenario(cfg, "sc1_2030"))
    assert np.isclose(fuse["pv_kwp"].sum(), nodes["pv_kwp"].sum()) and not np.allclose(fuse["pv_kwp"], nodes["pv_kwp"])
    scenario["pv"]["split"] = "fuze"
    with pytest.raises(ValueError, match="pv.split: unknown split 'fuze'; known: fuse, connections"):
        allocate(grid, scenario)
    scenario = new_scenario(cfg, "sc1_2030")
    scenario["sfoe"]["to_region"] = "households"
    with pytest.raises(ValueError, match="sfoe.to_region: unknown 'households'"):
        allocate(grid, scenario)
    for block, key in (("sfoe", "to_region"), ("pv", "split"), ("ev", "split")):     # required: no hidden default
        scenario = new_scenario(cfg, "sc1_2030")
        del scenario[block][key]
        with pytest.raises(KeyError, match=f"{block}: missing {key}"):
            prepare(grid, scenario)


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
    assert list(alloc.columns) == ["network_id", "node", "plmax_kw", "qlmax_kvar", "nominal_demand_kw", "pv_kwp", "ev_count"]
    assert np.allclose(alloc["nominal_demand_kw"], 0.22 * alloc["plmax_kw"])
    nets = pd.read_csv(generated / "networks.csv")
    assert list(nets.columns) == ["network_id", "n_nodes", "plmax_sum_kw", "nominal_demand_kw", "pv_kwp", "ev_count"]
    assert meta["grid"] == {"region": "Sion+Sierre", "population": 105042} and "population_sion_sierre" not in meta["sfoe"]
    assert meta["demand_factor"] == 0.22 and meta["n_nodes"] == len(alloc)
    assert meta["sfoe"]["to_region"] == meta["to_region"] == "population" and meta["pv_split"] == meta["ev_split"] == "fuse"
    assert list(meta["pv_season_days"]) == ["winter", "spring", "summer", "autumn"]          # their representative days
    assert all(0 <= k < 365 for k in meta["pv_season_days"].values()) and len(set(meta["pv_season_days"].values())) == 4


def test_in_memory_injections_match_generated_files(generated):
    """What scenario.ipynb previews (prepare, nothing written) is what `write` writes."""
    scenario = load_scenario(NAME)
    sc = prepare(load_grid(), scenario)
    ids = ["LV_Grid_101", "LV_Grid_230"]
    sums = sc.network_sums(ids)
    cal = sc.calendar
    assert len(cal.days) == 2 and sums["pv_kw"].shape == (2, 2, 96) and len(cal.hours) == 192
    assert len(cal.year) == 365 and cal.yearly_factor == 4 and len(cal.yearly_time) == 8760 and sc.streams["pv"] == "generation"
    for i, nid in enumerate(ids):
        daily = pd.read_csv(generated / "daily" / f"{nid}.csv")
        for column, x in sums.items():
            cols = [c for c in daily.columns if c.endswith(f":{column}")]
            assert np.allclose(daily[cols].sum(axis=1), x[i].ravel(), rtol=1e-3, atol=0.01)
    p, q = sc.net_load(sums)
    assert np.allclose(p, sums["demand_kw"] + sums["ev_kw"] - sums["pv_kw"]) and np.allclose(q, sums["demand_kvar"])
    assert len(sc.ids) == sc.allocation["network_id"].nunique() and len(sc.network("LV_Grid_101")) == sc.series("LV_Grid_101")["pv_kw"].shape[0]
    assert np.allclose(pd.read_csv(generated / "pv_day.csv")["pv_norm"], sc.state["pv"].day)      # the typed model states
    assert sc.state["ev"].charger_kw == 11 and sc.state["demand"].seed_offset == scenario["demand"]["seed_offset"]
    with pytest.raises(KeyError, match="unknown network"):
        sc.series("LV_Grid_none")
    with pytest.raises(KeyError, match="unknown block"):
        prepare(sc.grid, {**sc.scenario, "EV": {}})
    scenario["sfoe"]["PV_national_MW"] *= 2                      # editing the caller's dict afterwards does not reach the injections
    assert sc.scenario["sfoe"]["PV_national_MW"] * 2 == scenario["sfoe"]["PV_national_MW"]
    with pytest.raises(KeyError, match="no population"):
        prepare(sc.grid, {**sc.scenario, "sfoe": {**sc.scenario["sfoe"], "year": 2035}})
    with pytest.raises(KeyError, match="pv: unknown key.*sesaon"):          # a typo inside a block, before anything is computed
        prepare(sc.grid, {**sc.scenario, "pv": {**sc.scenario["pv"], "sesaon": "summer"}})
    with pytest.raises(KeyError, match="demand: missing demand_factor"):
        prepare(sc.grid, {**sc.scenario, "demand": {"model_file": "x", "seed_offset": 0}})
    with pytest.raises(KeyError, match="sfoe: missing EV_national_thousands"):
        prepare(sc.grid, {**sc.scenario, "sfoe": {k: v for k, v in sc.scenario["sfoe"].items() if k != "EV_national_thousands"}})
    no_ev = {k: v for k, v in sc.scenario.items() if k != "ev"}                # a model's block is optional, and so is its figure
    no_ev["sfoe"] = {k: v for k, v in no_ev["sfoe"].items() if k != "EV_national_thousands"}
    assert list(prepare(sc.grid, no_ev).streams) == ["demand", "pv"]
    with pytest.raises(ValueError, match="yearly.step_min"):
        prepare(sc.grid, {**sc.scenario, "time": {"step_min": 15, "yearly": {"enabled": True, "step_min": 50}}})


def test_new_scenario_configs_are_independent():
    """Editing one configuration (as scenario.ipynb does) changes neither the defaults nor the next one."""
    cfg = load_config()
    a = new_scenario(cfg, "sc1_2040", "a")
    a["pv"]["season"], a["time"]["yearly"]["enabled"] = "summer", False
    b = new_scenario(cfg, "sc1_2030", "b")
    assert b["pv"]["season"] == "all" and b["time"]["yearly"]["enabled"] and cfg["scenario_defaults"]["pv"]["season"] == "all"


def test_levels_have_their_own_folder(generated):
    """output/<name>/<level>/: the nl7 product of the fixture sits in its level folder and nl4 is not generated."""
    from scengen.output import output_status
    assert generated == OUTPUT_DIR / NAME / "nl7" and json.load(open(generated / "scenario.json"))["level"] == "nl7"
    assert output_status(NAME, "nl4")[0] == "missing"


def test_substation_level(generated):
    """Level nl4: the allocation summed per HV/MV substation; PV exactly the sum of its networks' series, demand and
    EV their expectation (here within a few % of the drawn sum over two days of the smallest substation)."""
    from scengen.output import output_status
    inj = prepare(load_grid(), load_scenario(NAME))
    folder = write(inj, level="nl4", samples=20000, verbose=False)
    assert folder == OUTPUT_DIR / NAME / "nl4" and output_status(NAME, "nl4")[0] == "ok"
    with pytest.raises(ValueError):
        write(inj, ["LV_Grid_101"], level="nl4", verbose=False)                # subsets are for nl7 only
    rows = pd.read_csv(folder / "allocation.csv", dtype={"hvmv": str})
    meta = json.load(open(folder / "scenario.json"))
    assert meta["level"] == "nl4" and meta["n_substations"] == len(rows) and meta["expectation_samples"] == 20000
    for c in ("nominal_demand_kw", "pv_kwp", "ev_count"):                    # nothing lost: substations + unmapped
        assert np.isclose(rows[c].sum() + meta["unmapped"][c], inj.allocation[c].sum())
    cal = inj.calendar
    daily = pd.read_csv(folder / "daily.csv", dtype={"hvmv": str})
    assert len(daily) == len(rows) * len(cal.days) * cal.steps
    assert np.allclose(daily["net_kw"], daily["demand_kw"] + daily["ev_kw"] - daily["pv_kw"], rtol=1e-4, atol=1e-2)
    assert len(pd.read_csv(folder / "yearly.csv", usecols=["hvmv"])) == len(rows) * len(cal.year) * 24 * 60 // cal.yearly_step_min
    h = rows.loc[rows["n_networks"].idxmin(), "hvmv"]
    ids = [nid for nid in inj.grid.networks.index[inj.grid.networks["hvmv"] == h] if nid in inj.ids]
    drawn = {c: a.sum(axis=0).ravel() for c, a in inj.network_sums(ids).items()}    # [days x steps] -> flat
    mine = daily[daily["hvmv"] == h]
    assert np.allclose(mine["pv_kw"].to_numpy(), drawn["pv_kw"], rtol=1e-4, atol=1e-2)
    for c in ("demand_kw", "demand_kvar", "ev_kw"):
        assert abs(mine[c].sum() / drawn[c].sum() - 1) < 0.05, c


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
    for which in db.DAYS:                                                  # including one representative day per season
        assert len(db.regional_day(d, which, d).data) == 5                  # 3 streams, net load, the other scenario's net load
        assert len(db.network_day(d, "LV_Grid_101", which).data) == 4
    old = {**d, "meta": {k: v for k, v in d["meta"].items() if k != "pv_season_days"}}        # an output written before 0.5.0
    assert not db.regional_day(old, "winter").data and "regenerate" in str(db.network_day(old, "LV_Grid_101", "winter").layout)
    columns, rows = db.energy_table(d)
    table = dict(rows)
    cf = load_config()["pv_realistic"]["capacity_factor"]
    pv = next(v for k, v in table.items() if k.startswith("PV, clearsky profile"))
    assert columns == ["winter", "spring", "summer", "autumn", "year"] and np.isclose(table["total load"][4], s["gwh_net"][1] + s["gwh_pv"][1])
    assert all(np.isclose(sum(v[:4]), v[4]) for v in table.values()) and np.isclose(pv[4], s["gwh_pv"][1])
    own = d["R"]["pv"].mean() / d["nets"]["pv_kwp"].sum()                   # the profile's capacity factor, ~0.28 for clear sky
    assert 0.25 < own < 0.31 and np.allclose(table[f"PV at a capacity factor of {cf:.0%}"], np.array(pv) * cf / own)
    assert np.isclose(s["gwh_pv_realistic"][1], pv[4] * cf / own) and "capacity factor of 11%" in db.kpis(d)[2][2]
    fig, note = db.connections_figure(d, "LV_Grid_101", "pv")
    assert "coincidence factor" in note and db.network_facts(d, "LV_Grid_101")
    assert set(db.network_year_figures(d, "LV_Grid_101", d)) == {"year", "duration", "heat"}
    for m in db.METRICS:
        db.scatter_figure(d, m, "import_pct_trafo")
        db.shift_figure(d, d, m)
    assert all(r[1] == r[2] and r[3].startswith("0") for r in db.compare_rows(d, d))
    db.make_app()


def test_unknown_network_leaves_the_output(generated):
    """A typo in --networks is rejected before the previous files are deleted."""
    with pytest.raises(KeyError, match="LV_Grid_nope"):
        generate(NAME, ["LV_Grid_101", "LV_Grid_nope"])
    assert len(list((generated / "daily").glob("*.csv"))) == 3 and len(list((generated / "yearly").glob("*.csv"))) == 3


def test_config_checks():
    name = "_test_typo"
    scenario = new_scenario(load_config(), "sc1_2030", name)
    scenario["EV"] = scenario.pop("ev")
    write_scenario(scenario)
    try:
        with pytest.raises(KeyError, match="unknown block"):
            load_scenario(name)
        scenario["ev"] = scenario.pop("EV")
        scenario["sfoe"]["population_sion_sierre"] = 105042        # a configuration written before the grid had the population
        write_scenario(scenario)
        with pytest.raises(KeyError, match="region.json"):
            load_scenario(name)
    finally:
        shutil.rmtree(SCENARIOS_DIR / name, ignore_errors=True)


def test_demand_factor_rule_and_sanity_check():
    """What scenario.ipynb prints: the median networks near the planning value, the energy between its two bounds."""
    cfg = load_config()
    basis = cfg["demand_factor_basis"]
    region, low, high = energy_bounds(basis, 0.01)
    assert np.isclose(region, 570) and np.isclose(low, 0.35 * 570) and np.isclose(high, 0.62 * 570)
    check = demand_check(prepare(load_grid(), new_scenario(cfg, "sc1_2030")), basis)
    assert check.median_size == 27 and check.n_networks > 10 and check.plausible
    assert basis["planning_peak"] <= check.peak < 1.25 * basis["planning_peak"]
    assert check.households_gwh < check.energy_gwh < check.households_services_gwh and 280 < check.energy_gwh < 340
    text = str(check)
    assert "sanity check" in text and "between the two bounds" in text and "households (35%)" in text


def test_output_status_follows_the_content_of_the_configuration(generated):
    from scengen.output import output_status
    path = SCENARIOS_DIR / NAME / "config.json"
    text = path.read_text()
    scenario = json.loads(text)
    try:
        path.write_text(json.dumps(scenario, indent=4, sort_keys=True))        # another layout, the same scenario
        assert output_status(NAME)[0] == "ok" and scenario_hash(load_scenario(NAME)) == json.load(open(generated / "scenario.json"))["config_sha256"]
        scenario["pv"]["scale"] = 1.5
        path.write_text(json.dumps(scenario, indent=2))
        assert output_status(NAME)[0] == "stale"
    finally:
        path.write_text(text)


def test_subset_without_yearly():
    """A rerun leaves only its own networks; the dashboard works without yearly files."""
    from scengen.dashboard import connections_figure, kpis, load_output, network_day, network_year_figures
    name = "_test_subset"
    try:
        scenario = new_scenario(load_config(), "sc1_2030", name)
        scenario["time"] = {"step_min": 15, "days": 1, "yearly": {"enabled": False}}
        write_scenario(scenario)
        generate(name, ["LV_Grid_101", "LV_Grid_230"])
        folder = generate(name, ["LV_Grid_230"])
        assert [f.stem for f in (folder / "daily").glob("*.csv")] == ["LV_Grid_230"]
        d = load_output(name)
        assert list(d["nets"].index) == ["LV_Grid_230"] and d["Y"] is None and kpis(d)[0][2] == "in 1 networks"
        assert len(network_day(d, "LV_Grid_230", "rep").data) == 4 and connections_figure(d, "LV_Grid_230", "demand")[1]
        assert set(network_year_figures(d, "LV_Grid_230")) == {"year", "duration", "heat"}
    finally:
        for d in (SCENARIOS_DIR / name, OUTPUT_DIR / name):
            shutil.rmtree(d, ignore_errors=True)
