"""Smoke tests: python -m pytest tests  (a few seconds; needs ../data and the demand model)."""
import json

import numpy as np
import pytest

from lvgrid.config import base_current_A, kw_per_pu, load_config
from lvgrid.data import load_portfolio, select_networks
from lvgrid.loadflow import solve
from lvgrid.network import build_network
from lvgrid.scenario import load_scenario
from lvgrid.screening import run


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


def test_scenario_injections(portfolio, cfg, test_scenario_folder):
    sc = load_scenario(test_scenario_folder)
    net = net_of(portfolio, cfg, "LV_Grid_101")
    sc.apply(net)
    assert abs(net.pv_kwp.sum() - 85.0247) < 0.01 and net.ev_count.sum() == 8
    inj = sc.injections(net)
    assert list(inj.streams) == ["demand", "pv", "ev"] and sc.default_cases() == ["demand", "demand+pv", "demand+pv+ev"]
    assert inj.streams["demand"].shape == (192, 78) and inj.time_h[-1] == 47.75
    assert inj.streams["pv"].real.max() > 0 and inj.streams["ev"].real.sum() > 0 and inj.streams["demand"].imag.max() > 0
    assert not sc.provenance()["allocation_edited_after_generation"]


def test_runs_and_outputs(portfolio, cfg, test_scenario_folder, tmp_path):
    ids = select_networks(portfolio, "101,412")
    summary, out = run(portfolio, cfg, ids, out_dir=tmp_path / "oneshot", verbose=False)
    assert set(summary["status"]) == {"ok"} and (summary["losses_kw_mean"] > 0).all()
    sc = load_scenario(test_scenario_folder)
    summary, out = run(portfolio, cfg, ids, scenario=sc, out_dir=tmp_path / "sc", verbose=False)
    assert len(summary) == 6 and summary["n_steps"].eq(192).all()
    info = json.load(open(out / "run.json"))["scenario_info"]
    assert info["name"] == sc.name
    with np.load(out / "details" / "LV_Grid_412.npz") as z:
        assert z["demand+pv+ev:vmag"].shape == (192, 197)
    from lvgrid.dashboard import build_dashboard
    index = build_dashboard(out, networks="all")
    assert index.exists() and (out / "dashboard" / "net_LV_Grid_412.html").exists()


def test_empty_selection_rejected(portfolio, cfg, tmp_path):
    with pytest.raises(ValueError):
        run(portfolio, cfg, [], out_dir=tmp_path / "x", verbose=False)


def test_stream_and_case_checks():
    from lvgrid.injections import check_cases, check_streams, default_cases
    signs = {"demand": "load", "pv": "generation", "ev": "load", "heat_pump": "load"}
    assert default_cases(signs)[-1] == "demand+pv+ev+heat_pump"
    check_cases(["demand+heat_pump", "pv"], signs)
    for bad in (["demand+demand"], ["demand+heat"]):
        with pytest.raises(KeyError):
            check_cases(bad, signs)
    with pytest.raises(ValueError):
        check_streams({"demand": "load", "pv": "gen"})
