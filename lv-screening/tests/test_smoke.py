"""Smoke tests: python -m pytest tests  (about 20 s; needs data/ and the demand model)."""
import json
import warnings

import numpy as np
import pytest

from lvgrid.config import base_current_A, kw_per_pu, load_config, resolve
from lvgrid.data import load_portfolio, select_networks
from lvgrid.loadflow import solve
from lvgrid.network import build_network
from lvgrid.profiles import load_demand_model, sample_demand
from lvgrid.scenario import SCENARIOS_DIR, generate, largest_remainder, new_scenario_config, write_scenario_config
from lvgrid.screening import run

warnings.filterwarnings("ignore")
TEST_SCENARIO = "_test_sc1_2030"


@pytest.fixture(scope="module")
def cfg():
    return load_config()


@pytest.fixture(scope="module")
def portfolio():
    return load_portfolio()


@pytest.fixture(scope="module")
def scenario(portfolio, cfg):
    """A small generated scenario (3 networks, daily + yearly) under scenarios/_test_sc1_2030."""
    import shutil
    folder = SCENARIOS_DIR / TEST_SCENARIO
    shutil.rmtree(folder, ignore_errors=True)
    scfg = new_scenario_config(cfg, "sc1_2030", TEST_SCENARIO)
    scfg["time"] = {"step_min": 15, "days": 2, "yearly": {"enabled": True, "step_min": 60}}
    write_scenario_config(scfg)
    sc = generate(portfolio, TEST_SCENARIO, ["LV_Grid_101", "LV_Grid_412", "LV_Grid_230"], verbose=False)
    yield sc
    shutil.rmtree(folder, ignore_errors=True)


def net_of(portfolio, cfg, nid):
    lines, subs = portfolio.network(nid)
    return build_network(nid, lines, subs, cfg)


def test_network_matches_matlab_report(portfolio, cfg):
    net = net_of(portfolio, cfg, "LV_Grid_101")           # row of tech-selection's portfolio report
    assert net.n_nodes == 78 and (net.edge_type == 0).sum() == 76
    assert net.trafo_kva.tolist() == [300.0]
    assert abs(net.plmax_kw.sum() - 1068.12) < 0.01
    assert net.node_names[0] == "N_TrM_19" and net.is_radial


def test_slack_first_even_when_row_is_reversed(portfolio, cfg):
    net = net_of(portfolio, cfg, "LV_Grid_92713")
    assert net.node_names[0].startswith("N_TrM_") and "LV->MV" in "; ".join(net.issues)


def test_parallel_transformers_share_load(portfolio, cfg):
    net = net_of(portfolio, cfg, "LV_Grid_92584")
    s = -cfg["demand_factor"] * (net.plmax_kw + 1j * net.qlmax_kvar)
    lf = solve(net, (s[1:] / kw_per_pu(cfg))[None, :], cfg)
    loading = lf.i_mag[0, net.trafo_edges] * base_current_A(cfg) / net.ampacity_a[net.trafo_edges]
    assert len(loading) == 2 and abs(loading[0] - loading[1]) < 0.01


def test_loadflow_power_balance(portfolio, cfg):
    net = net_of(portfolio, cfg, "LV_Grid_101")
    s = -cfg["demand_factor"] * (net.plmax_kw + 1j * net.qlmax_kvar)
    lf = solve(net, (s[1:] / kw_per_pu(cfg))[None, :], cfg)
    assert lf.converged.all()
    load_kw = -s.real.sum()
    loss_kw = float((lf.i_mag[0] ** 2 @ net.r_pu) * kw_per_pu(cfg))
    slack_kw = lf.S_slack[0].real * kw_per_pu(cfg)
    assert abs(slack_kw - (load_kw + loss_kw)) < 0.05 and loss_kw > 0
    assert abs(lf.v_mag[0, 1:].min() - 0.9406) < 0.001


def test_largest_remainder():
    out = largest_remainder(10, np.array([1.0, 1.0, 1.0]))
    assert out.sum() == 10 and out.tolist() == [4, 3, 3]
    assert largest_remainder(0, np.array([1.0])).tolist() == [0]


def test_demand_sampler_is_nested_per_day(cfg):
    model = load_demand_model(resolve(cfg["demand_model"]["model_file"]))
    a, ca = sample_demand(model, 20, [5, 6], 101)
    b, cb = sample_demand(model, 20, [6], 101)
    assert a.shape == (20, 2, 96) and np.allclose(a[:, 1], b[:, 0]) and (ca == cb).all()
    assert 0.02 < a.mean() < 0.5 and a.min() >= 0        # a household day averages ~10 % of its own peak


def test_generated_scenario(scenario, portfolio, cfg):
    m = scenario.meta
    assert m["ev_allocated"] == m["ev_region"] and abs(m["pv_allocated_kwp"] - m["pv_region_kwp"]) < 1e-6
    rows = scenario.allocation[scenario.allocation["network_id"] == "LV_Grid_101"]
    assert abs(rows["pv_kwp"].sum() - 85.0247) < 0.01 and rows["ev_count"].sum() == 8   # MATLAB report values
    folder = scenario.folder
    assert (folder / "daily" / "LV_Grid_101.csv").exists() and (folder / "yearly" / "LV_Grid_101.csv").exists()
    net = net_of(portfolio, cfg, "LV_Grid_101")
    scenario.apply(net)
    inj = scenario.injections(net)
    assert inj.demand_kw.shape == (192, 78) and inj.time_h[-1] == 47.75
    assert abs(inj.pv_kw.sum(axis=1).max() - net.pv_kwp.sum() * scenario.meta.get("pv_peak_norm", 0.9)) < 40
    assert inj.ev_kw.max() <= 11 * net.ev_count.max() + 1e-9 and inj.ev_kw.sum() > 0
    import pandas as pd
    y = pd.read_csv(folder / "yearly" / "LV_Grid_101.csv")
    assert len(y) == 8760 and y["pv_kw"].max() > 0
    # the daily product is the yearly series on the PV day: compare hourly means of day 0
    k = m["pv_day_index"]
    hourly_daily = inj.demand_kw.real.sum(axis=1)[:96].reshape(24, 4).mean(axis=1)
    assert np.allclose(hourly_daily, y["demand_kw"].to_numpy()[k * 24:(k + 1) * 24], rtol=1e-3, atol=0.01)


def test_runs_and_outputs(portfolio, cfg, scenario, tmp_path):
    ids = select_networks(portfolio, "101,412")
    summary, out = run(portfolio, cfg, ids, out_dir=tmp_path / "oneshot", verbose=False)
    assert set(summary["status"]) == {"ok"} and (summary["losses_kw_mean"] > 0).all()
    summary, out = run(portfolio, cfg, ids, scenario=scenario, out_dir=tmp_path / "sc", verbose=False)
    assert len(summary) == 6 and summary["n_steps"].eq(192).all()
    info = json.load(open(out / "run.json"))["scenario_info"]
    assert info["name"] == TEST_SCENARIO and not info["edited_after_generation"]
    with np.load(out / "details" / "LV_Grid_412.npz") as z:
        assert z["demand+pv+ev:vmag"].shape == (192, 197)
    from lvgrid.dashboard import build_dashboard
    index = build_dashboard(out, networks="all")
    assert index.exists() and (out / "dashboard" / "net_LV_Grid_412.html").exists()


def test_empty_selection_rejected(portfolio, cfg, tmp_path):
    with pytest.raises(ValueError):
        run(portfolio, cfg, [], out_dir=tmp_path / "x", verbose=False)
