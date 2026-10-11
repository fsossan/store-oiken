function sens = build_sensitivity_matrices(gm_curr, AUX_to_all_nodes, AUX_to_all_nodes_PV)
% BUILD_SENSITIVITY_MATRICES  Assemble block-diagonal sensitivity matrices
%   from the current linearisation point.
%
%   sens = build_sensitivity_matrices(gm_curr, AUX_to_all_nodes)
%   sens = build_sensitivity_matrices(gm_curr, AUX_to_all_nodes, AUX_to_all_nodes_PV)
%
%   Returns a struct with fields:
%     dVmagdP, dVmagdQ    — voltage magnitude sensitivity  [NT x T*Nd]
%     dImagdP, dImagdQ    — current magnitude sensitivity
%     dIdP,   dIdQ        — complex current sensitivity
%     dSsdP,  dSsdQ       — slack bus power sensitivity
%     P0, Q0              — base injections at demand nodes [T*Nd x 1]
%     Vmag0, Imag0, Ss0   — base state vectors
%
%   If AUX_to_all_nodes_PV is provided (PV-node block-diag aux, see
%   preprocess_network.m), also returns the PV-curtailment analogs, reduced
%   from the SAME full-node sensitivity cells with the PV node mask instead
%   of the demand-node mask — active power only, no reactive terms:
%     dVmagdP_PV, dImagdP_PV, dSsdP_PV   — [NT x T*Npv] / [LT x T*Npv]

tol = 1e-8;

sens.dVmagdP = blkdiag(gm_curr.lm.Vmag_dxdP{:}) * AUX_to_all_nodes;
sens.dVmagdQ = blkdiag(gm_curr.lm.Vmag_dxdQ{:}) * AUX_to_all_nodes;
sens.dImagdP = blkdiag(gm_curr.lm.Imag_dxdP{:}) * AUX_to_all_nodes;
sens.dImagdQ = blkdiag(gm_curr.lm.Imag_dxdQ{:}) * AUX_to_all_nodes;
sens.dIdP    = blkdiag(gm_curr.lm.I_dxdP{:})    * AUX_to_all_nodes;
sens.dIdQ    = blkdiag(gm_curr.lm.I_dxdQ{:})    * AUX_to_all_nodes;
sens.dSsdP   = blkdiag(gm_curr.lm.Ss_dxdP{:})   * AUX_to_all_nodes;
sens.dSsdQ   = blkdiag(gm_curr.lm.Ss_dxdQ{:})   * AUX_to_all_nodes;

sens.P0    = pinv(AUX_to_all_nodes) * vertcat(gm_curr.lm.P0{:});
sens.Q0    = pinv(AUX_to_all_nodes) * vertcat(gm_curr.lm.Q0{:});
sens.Vmag0 = vertcat(gm_curr.lm.Vmag0{:});
sens.Imag0 = vertcat(gm_curr.lm.Imag0{:});
sens.Ss0   = vertcat(gm_curr.lm.Ss0{:});

% Numerical clean-up: zero out sub-threshold entries in current sensitivities
sens.Imag0(abs(sens.Imag0) < tol)     = 0;
sens.dImagdP(abs(sens.dImagdP) < tol) = 0;
sens.dImagdQ(abs(sens.dImagdQ) < tol) = 0;
sens.dIdP(abs(sens.dIdP) < tol)       = 0;
sens.dIdQ(abs(sens.dIdQ) < tol)       = 0;

% -- PV curtailment sensitivities (active power only) --
if nargin >= 3 && ~isempty(AUX_to_all_nodes_PV)
    sens.dVmagdP_PV = blkdiag(gm_curr.lm.Vmag_dxdP{:}) * AUX_to_all_nodes_PV;
    sens.dImagdP_PV = blkdiag(gm_curr.lm.Imag_dxdP{:}) * AUX_to_all_nodes_PV;
    sens.dSsdP_PV   = blkdiag(gm_curr.lm.Ss_dxdP{:})   * AUX_to_all_nodes_PV;

    sens.dImagdP_PV(abs(sens.dImagdP_PV) < tol) = 0;
end

end
