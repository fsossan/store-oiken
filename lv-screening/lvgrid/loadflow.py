"""Fixed-point (Z-bus) AC load flow for constant-power loads, vectorised over
time steps. Port of the MATLAB `loadflow_FPIs_convergance` (damped version):

    V_{k+1} = w + YLL^-1 * conj(S) / conj(V_k),    w = -YLL^-1 YL0 V0

with relaxation `damping` and per-step convergence tracking. A step counts as
not converged when it has not met the tolerance after max_iter iterations or
produced a non-finite voltage (the MATLAB code also aborted on a growing error,
which stops heavily loaded but solvable networks such as LV_Grid_442). All quantities are
single-phase per unit; S is the net injection at the non-slack nodes
(positive = generation, negative = consumption).
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from scipy.linalg import lu_factor, lu_solve

from .network import Network

V_FLOOR = 0.05


@dataclass
class LoadflowResult:
    V: np.ndarray          # [T x N] complex nodal voltages incl. slack (pu)
    I: np.ndarray          # [T x L] complex branch currents from->to (pu)
    S_slack: np.ndarray    # [T] complex power supplied by the slack (pu, positive = import from MV)
    converged: np.ndarray  # [T] bool
    n_iter: int

    @property
    def vmag(self) -> np.ndarray:
        return np.abs(self.V)

    @property
    def imag(self) -> np.ndarray:
        return np.abs(self.I)


def solve(net: Network, s_inj_pu: np.ndarray, cfg: dict) -> LoadflowResult:
    """Run the load flow for every row of `s_inj_pu` ([T x N-1], complex pu)."""
    lf = cfg["loadflow"]
    V0 = complex(cfg["per_unit"]["V_slack_pu"])
    S = np.atleast_2d(np.asarray(s_inj_pu, complex)).T          # [N-1 x T]
    Y = net.Y
    Y00, Y0L, YL0, YLL = Y[0, 0], Y[0, 1:], Y[1:, 0], Y[1:, 1:]
    lu = lu_factor(YLL)
    w = -lu_solve(lu, YL0 * V0)                                 # zero-load voltages
    T = S.shape[1]
    V = np.repeat(w[:, None], T, axis=1)
    converged = np.zeros(T, bool)
    alpha = lf["damping"]
    n_iter = 0
    for it in range(1, lf["max_iter"] + 1):
        n_iter = it
        Vs = V.copy()
        small = np.abs(Vs) < V_FLOOR
        if small.any():
            ang = np.angle(Vs[small])
            Vs[small] = V_FLOOR * np.exp(1j * np.where(np.isfinite(ang), ang, 0.0))
        Iinj = np.conj(S) / np.conj(Vs)
        V1 = w[:, None] + lu_solve(lu, Iinj)
        if alpha < 1:
            V1 = alpha * V1 + (1 - alpha) * V
        err = np.max(np.abs(V1 - V), axis=0)
        bad = ~np.isfinite(V1).all(axis=0)
        active = ~converged
        just = active & ~bad & ((err < lf["tol_pu"]) | (err / np.maximum(1, np.abs(V1).max(axis=0)) < lf["tol_pu"]))
        converged |= just
        V = np.where(np.isfinite(V1), V1, w[:, None])
        if bad.any():
            V[:, bad] = np.nan
        if (converged | bad).all():
            break
    V_all = np.vstack([np.full((1, T), V0), V])                 # [N x T]
    I0 = Y00 * V0 + Y0L @ V
    S_slack = V0 * np.conj(I0)                                 # positive = supplied to the network
    I_br = net.y_edge[:, None] * (V_all[net.edge_from] - V_all[net.edge_to])
    return LoadflowResult(V=V_all.T, I=I_br.T, S_slack=S_slack, converged=converged, n_iter=n_iter)
