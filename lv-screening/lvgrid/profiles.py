"""Dimensionless daily shapes: household demand (GMM), PV (representative day), EV.

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

from .config import resolve

SEASON_MONTHS = {
    "winter": (12, 1, 2), "spring": (3, 4, 5), "summer": (6, 7, 8), "autumn": (9, 10, 11), "all": tuple(range(1, 13)),
}


def season_mask(months: np.ndarray, season: str) -> np.ndarray:
    return np.isin(months, SEASON_MONTHS[season])


# ---------------------------------------------------------------- demand ----
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
        days_file = resolve("data/demand_train_days.csv")
        if not days_file.exists():
            raise FileNotFoundError(f"{days_file} is needed for weekday/season filters "
                                    "(write it with tools/export_demand_train_days.m)")
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


# -------------------------------------------------------------------- PV ----
def load_pv_year(path: Path) -> pd.DataFrame:
    """The yearly PV profile CSV (a '#' JSON header line is skipped)."""
    df = pd.read_csv(path, comment="#")
    offsets = df["time"].str[-5:].unique()
    if len(offsets) != 1:
        raise ValueError(f"{path}: timestamps must share one fixed UTC offset (found {list(offsets)}); "
                         "days are cut by position, daylight-saving shifts would misalign them")
    df["time"] = pd.to_datetime(df["time"], utc=True).dt.tz_convert("Etc/GMT-1")
    return df


def pv_year_series(pv_year: pd.DataFrame, series: str, step_min: int) -> np.ndarray:
    """The normalised yearly PV series [n_days x S]."""
    S = 24 * 60 // step_min
    col = f"pv_norm_{series}"
    if col not in pv_year:
        raise KeyError(f"no column {col} in the PV profile file")
    y = pv_year[col].to_numpy(float)
    if len(y) % S:
        raise ValueError(f"PV profile has {len(y)} samples, not a whole number of {S}-step days")
    return y.reshape(-1, S)


def pv_representative_day(pv_year: pd.DataFrame, series: str, season: str, step_min: int):
    """Normalised PV of the real day closest (RMSE) to the mean shape of the season.

    Returns (profile [S], date string, day index)."""
    S = 24 * 60 // step_min
    days = pv_year_series(pv_year, series, step_min)
    months = pv_year["time"].dt.month.to_numpy()[::S]
    cand = np.flatnonzero(season_mask(months, season))
    mean_day = days[cand].mean(axis=0)
    k = cand[np.argmin(np.sqrt(((days[cand] - mean_day) ** 2).mean(axis=1)))]
    date = str(pv_year["time"].iloc[k * S].date())
    return days[k], date, int(k)


# -------------------------------------------------------------------- EV ----
def ev_node_profiles(ev_counts: np.ndarray, ecfg: dict, step_min: int, rng: np.random.Generator) -> np.ndarray:
    """Charging power per node [n x S], 3-phase kW: each vehicle charges at
    charger_kw for duration_h after a truncated-normal arrival time."""
    S = 24 * 60 // step_min
    t = np.arange(S) * step_min / 60.0
    counts = np.asarray(ev_counts, int)
    out = np.zeros((len(counts), S))
    total = int(counts.sum())
    if total == 0:
        return out
    lo, hi = ecfg["arrival_min_h"], ecfg["arrival_max_h"]
    arrivals = []
    while len(arrivals) < total:
        a = rng.normal(ecfg["arrival_mean_h"], ecfg["arrival_std_h"], size=2 * total)
        arrivals.extend(a[(a >= lo) & (a <= hi)].tolist())
    arrivals = np.array(arrivals[:total])
    on = (t[None, :] >= arrivals[:, None]) & (t[None, :] < arrivals[:, None] + ecfg["duration_h"])
    owner = np.repeat(np.arange(len(counts)), counts)
    np.add.at(out, owner, on * ecfg["charger_kw"])
    return out
