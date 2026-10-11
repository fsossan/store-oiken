"""Smoke tests: python -m pytest tests  (about 15 s; needs data/ and the demand model)."""
import json
import warnings

import numpy as np
import pytest

from lvgrid.config import base_current_A, kw_per_pu, load_config, resolve
from lvgrid.data import load_portfolio, select_networks
from lvgrid.loadflow import solve
from lvgrid.network import build_network
from lvgrid.profiles import load_demand_model, sample_demand
from lvgrid.scenario import build_scenario, largest_remainder, load_scenario, save_scenario
from lvgrid.screening import run

warnings.filterwarnings("ignore")


@pytest.fixture(scope="module")
def cfg():
    return load_config()


@pytest.fixture(scope="module")
def portfolio():
    return load_portfolio()


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


def test_scenario_roundtrip(portfolio, cfg, tmp_path):
    sc = build_scenario(portfolio, cfg, "sc1_2030")
    assert sc.meta["ev_allocated"] == sc.meta["ev_region"]
    assert abs(sc.meta["pv_allocated_kwp"] - sc.meta["pv_region_kwp"]) < 1e-6
    rows = sc.allocation[sc.allocation["network_id"] == "LV_Grid_101"]
    assert abs(rows["pv_kwp"].sum() - 85.0247) < 0.01 and rows["ev_count"].sum() == 8   # MATLAB report values
    folder = save_scenario(sc, tmp_path / "sc")
    back = load_scenario(folder)
    assert back.meta["allocation_sha256"] == sc.meta["allocation_sha256"]
    assert np.allclose(back.pv_day, sc.pv_day) and len(back.allocation) == len(sc.allocation)


def test_demand_sampler_shapes_and_energy(cfg):
    model = load_demand_model(resolve(cfg["demand"]["model_file"]))
    shape, clusters = sample_demand(model, 50, 2, np.random.default_rng(1))
    assert shape.shape == (50, 2, 96) and clusters.min() >= 1 and clusters.max() <= model["n_clusters"]
    assert 0.02 < shape.mean() < 0.5 and shape.min() >= 0        # a household day averages ~10 % of its own peak


def test_runs_and_outputs(portfolio, cfg, tmp_path):
    ids = select_networks(portfolio, "101,412")
    summary, out = run(portfolio, cfg, ids, out_dir=tmp_path / "oneshot", verbose=False)
    assert set(summary["status"]) == {"ok"} and (summary["losses_kw_mean"] > 0).all()
    sc = build_scenario(portfolio, cfg, "sc1_2030")
    summary, out = run(portfolio, cfg, ids, scenario=sc, n_days=2, out_dir=tmp_path / "sc", verbose=False)
    assert len(summary) == 6 and summary["n_steps"].eq(192).all()
    info = json.load(open(out / "run.json"))["scenario_info"]
    assert info["name"] == "sc1_2030" and info["ev_applied"] == int(summary.drop_duplicates("network_id")["ev_count"].sum())
    with np.load(out / "details" / "LV_Grid_412.npz") as z:
        assert z["demand+pv+ev:vmag"].shape == (192, 197)
    from lvgrid.dashboard import build_dashboard
    index = build_dashboard(out, networks="all")
    assert index.exists() and (out / "dashboard" / "net_LV_Grid_412.html").exists()


def test_empty_selection_rejected(portfolio, cfg, tmp_path):
    with pytest.raises(ValueError):
        run(portfolio, cfg, [], out_dir=tmp_path / "x", verbose=False)
