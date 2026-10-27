"""Household demand (stream `demand`, load): demand_factor x each node's fuse-rated power (P and Q, constant
power factor) times a synthetic household day.

Demand model (port of fit_load_gmm / sample_load_gmm, tech-selection): per
household cluster, each house is normalised by its own maximum, the days are
detrended by the cluster-mean day (log ratio), the residuals are bounded by
percentiles and one Gaussian mixture is fitted. Sampling: pick a cluster, pick
a component, draw a residual day, undo the detrending. The fit is cached as an
.npz so that only the first run needs the 163 MB training file.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd

from ..config import DATA_DIR, resolve
from .common import season_mask

NAME, SIGN = "demand", "load"


def fit_demand_model(dcfg: dict, verbose: bool = True) -> dict:
    import scipy.io as sio
    from sklearn.mixture import GaussianMixture

    train = resolve(dcfg["train_file"])
    m = sio.loadmat(train, squeeze_me=True, struct_as_record=False)["training_data"]
    X = np.asarray(m.X, float)                       # [S x days x houses]
    cl = np.asarray(m.cluster_idx).astype(int).ravel()
    S, n_days, n_houses = X.shape

    keep = np.ones(n_days, bool)
    if dcfg.get("weekday", "all") != "all" or dcfg.get("season", "all") != "all":
        days_file = DATA_DIR / "demand_train_days.csv"
        if not days_file.exists():
            raise FileNotFoundError(f"{days_file} is needed for weekday/season filters "
                                    "(write it with injection-scenarios/tools/export_demand_train_days.m)")
        dates = pd.to_datetime(pd.read_csv(days_file)["date"])
        if len(dates) != n_days:
            raise ValueError("demand_train_days.csv does not match the training data")
        wd = dates.dt.weekday.to_numpy()
        if dcfg["weekday"] == "weekday":
            keep &= wd < 5
        elif dcfg["weekday"] == "weekend":
            keep &= wd >= 5
        keep &= season_mask(dates.dt.month.to_numpy(), dcfg["season"])
    if not keep.any():
        raise ValueError("no training days match the weekday/season filter")

    K, G = dcfg["num_clusters"], dcfg["gmm_order"]
    model = {"n_clusters": K, "steps_per_day": S, "log_residuals": bool(dcfg["log_residuals"]),
             "clip_residuals": bool(dcfg["clip_residuals"]), "n_days_used": int(keep.sum()), "n_houses": n_houses}
    probs = np.zeros(K)
    means = np.zeros((K, S))
    lb = np.zeros((K, S))
    ub = np.zeros((K, S))
    for i in range(1, K + 1):
        sel = np.flatnonzero(cl == i)
        if len(sel) == 0:
            raise ValueError(f"cluster {i} has no households")
        Xi = X[:, :, sel]
        house_max = np.nanmax(Xi.reshape(S * n_days, len(sel)), axis=0)
        Xi = (Xi / house_max[None, None, :])[:, keep, :]
        Xi = Xi.reshape(S, -1, order="F")                       # one column per (day, house)
        Xi = Xi[:, ~np.isnan(Xi).any(axis=0)]
        pos = Xi > 0
        Xi = np.where(pos, Xi, Xi[pos].min())
        mu = Xi.mean(axis=1)
        det = np.log(Xi / mu[:, None]) if model["log_residuals"] else Xi / mu[:, None]
        probs[i - 1] = len(sel)
        means[i - 1] = mu
        lb[i - 1] = np.percentile(det, dcfg["p_lb"], axis=1)
        ub[i - 1] = np.percentile(det, dcfg["p_ub"], axis=1)
        g = GaussianMixture(n_components=G, covariance_type="full", reg_covar=1e-6,
                            random_state=dcfg["fit_seed"], max_iter=300).fit(det.T)
        if verbose:
            print(f"  cluster {i}: {len(sel)} houses, {det.shape[1]} days, "
                  f"{'converged' if g.converged_ else 'NOT converged'} in {g.n_iter_} iterations")
        model[f"c{i}_w"] = g.weights_
        model[f"c{i}_mu"] = g.means_                                       # [G x S]
        model[f"c{i}_L"] = np.stack([np.linalg.cholesky(c) for c in g.covariances_])   # [G x S x S]
    model["cluster_prob"] = probs / probs.sum()
    model["cluster_means"] = means
    model["cluster_lb"] = lb
    model["cluster_ub"] = ub
    return model


def save_demand_model(model: dict, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(path, **model)


def load_demand_model(path: Path) -> dict:
    with np.load(path) as z:
        return {k: (z[k].item() if z[k].ndim == 0 else z[k]) for k in z.files}


def sample_demand(model: dict, n_nodes: int, days, seed: int):
    """Dimensionless day shapes [n_nodes x len(days) x S] and the cluster of each node.

    `days` are calendar day indices (0..364). Clusters come from one generator
    seeded by (seed, 0) and each day from its own generator seeded by (seed,
    1 + day), so a given day is the same whatever other days are drawn."""
    K, S = int(model["n_clusters"]), int(model["steps_per_day"])
    days = [int(d) for d in days]
    clusters = np.random.default_rng([seed, 0]).choice(K, size=n_nodes, p=model["cluster_prob"]) + 1
    shape = np.zeros((n_nodes, len(days), S))
    members = {c: np.flatnonzero(clusters == c) for c in range(1, K + 1)}
    for j, d in enumerate(days):
        rng = np.random.default_rng([seed, 1 + d])
        for c, idx in members.items():
            if len(idx) == 0:
                continue
            w, mu, L = model[f"c{c}_w"], model[f"c{c}_mu"], model[f"c{c}_L"]
            comp = rng.choice(len(w), size=len(idx), p=w / w.sum())
            z = rng.standard_normal((len(idx), S))
            res = np.empty((len(idx), S))
            for g in range(len(w)):                      # x = mu_g + L_g z, per mixture component
                sel = comp == g
                res[sel] = mu[g] + z[sel] @ L[g].T
            if model["clip_residuals"]:
                res = np.clip(res, model["cluster_lb"][c - 1], model["cluster_ub"][c - 1])
            base = model["cluster_means"][c - 1]
            shape[idx, j] = base * (np.exp(res) if model["log_residuals"] else res)
    return shape, clusters


# ------------------------------------------------------------- interface ----
def allocate(nodes: pd.DataFrame, sfoe: dict, cfg: dict) -> dict:
    """Nothing to allocate: demand scales with each node's fuse rating."""
    return {}


def prepare(cfg: dict, step_min: int) -> dict:
    model = load_demand_model(resolve(cfg["model_file"]))
    if int(model["steps_per_day"]) != 24 * 60 // step_min:
        raise ValueError("demand model resolution differs from time.step_min")
    return {"cfg": cfg, "model": model}


def series(state: dict, rows: pd.DataFrame, days: list[int], net_num: int) -> dict[str, np.ndarray]:
    cfg = state["cfg"]
    # TODO: demand too low. The 6 % is already a coincident planning value but is used here as each household's own
    # max, and independent sampling diversifies again: 1,550 kWh/yr and ~1 % of fuse power at the network peak for a
    # 40 A connection. Scale per node on metered energy instead (ceiling = kWh/yr / (8760 x 0.118 mean shape)), from
    # coffretIntroduction_COF.clientConsommationAnnuelCompteur_COF in the .bak (parse it like data/tools/extract_nodes_from_bak.py).
    nominal = cfg["demand_factor"] * (rows["plmax_kw"].to_numpy() + 1j * rows["qlmax_kvar"].to_numpy())
    shape, _ = sample_demand(state["model"], len(rows), days, net_num + cfg["seed_offset"])     # [n x D x S]
    demand = shape * nominal[:, None, None]
    return {"demand_kw": demand.real, "demand_kvar": demand.imag}
