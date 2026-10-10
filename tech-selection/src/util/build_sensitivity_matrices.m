function sens = build_sensitivity_matrices(gm_curr, AUX_to_all_nodes, AUX_to_all_nodes_PV, dims)
% BUILD_SENSITIVITY_MATRICES  Assemble block-diagonal sensitivity matrices
%   from the current linearisation point.
%
%   sens = build_sensitivity_matrices(gm_curr, AUX_to_all_nodes, [], dims)
%   sens = build_sensitivity_matrices(gm_curr, AUX_to_all_nodes, AUX_to_all_nodes_PV, dims)
%
%   Returns a struct with fields:
%     dVmagdP, dVmagdQ    — voltage magnitude sensitivity  [N*T x Nd*T] sparse
%     dImagdP, dImagdQ    — current magnitude sensitivity  [L*T x Nd*T] sparse
%     dIdP,   dIdQ        — complex current sensitivity (only if gm_curr.lm
%                            carries I_dxdP/I_dxdQ, i.e. keep_complex_I was set)
%     dSsdP,  dSsdQ       — slack bus power sensitivity     [T x Nd*T] sparse
%     P0, Q0              — base injections at demand nodes  [Nd*T x 1]
%     Vmag0, Imag0, Ss0   — base state vectors              [N*T x 1] / [L*T x 1] / [T x 1]
%
%   If AUX_to_all_nodes_PV is non-empty, also returns the PV-curtailment
%   analogs (reduced from the SAME per-timestep sensitivity arrays with the
%   PV-node projection), active power only:
%     dVmagdP_PV, dImagdP_PV, dSsdP_PV
%
%   gm_curr.lm.* is the post-restructure array layout (see linear_grid_model):
%   the per-timestep sensitivities are [rows x N x T] arrays, projected
%   N->Nd (or N->Npv) here with a single batched matmul (pagemtimes) and
%   scattered onto one sparse block-diagonal -- no dense [N*T x N*T]
%   intermediate, no T-element cell array.

tol = 1e-8;
lm  = gm_curr.lm;
T   = dims.T;

% Per-timestep node-space projections (first diagonal block of each AUX).
P_D = full(AUX_to_all_nodes(1:dims.N, 1:dims.Nd));          % [N x Nd]  (Nd -> N expansion)
if nargin >= 3 && ~isempty(AUX_to_all_nodes_PV)
    P_PV = full(AUX_to_all_nodes_PV(1:dims.N, 1:dims.Npv)); % [N x Npv]
else
    P_PV = [];
end

% ---- sensitivity block-diagonals ----
sens.dVmagdP = bd_reduce(lm.Vmag_dxdP, P_D, T);
sens.dVmagdQ = bd_reduce(lm.Vmag_dxdQ, P_D, T);
sens.dImagdP = bd_reduce(lm.Imag_dxdP, P_D, T);
sens.dImagdQ = bd_reduce(lm.Imag_dxdQ, P_D, T);
sens.dSsdP   = bd_reduce(lm.Ss_dxdP,   P_D, T);
sens.dSsdQ   = bd_reduce(lm.Ss_dxdQ,   P_D, T);

has_cplx_I = isfield(lm, 'I_dxdP') && ~isempty(lm.I_dxdP);
if has_cplx_I
    sens.dIdP = bd_reduce(lm.I_dxdP, P_D, T);
    sens.dIdQ = bd_reduce(lm.I_dxdQ, P_D, T);
end

% ---- base state vectors ----
D_pinv     = full(dims.D_pinv);                             % [Nd x N]
sens.P0    = reshape(D_pinv * lm_stack(lm.P0), [], 1);      % [Nd*T x 1]
sens.Q0    = reshape(D_pinv * lm_stack(lm.Q0), [], 1);
sens.Vmag0 = reshape(lm_stack(lm.Vmag0), [], 1);            % [N*T x 1]
sens.Imag0 = reshape(lm_stack(lm.Imag0), [], 1);            % [L*T x 1] complex phasor
sens.Ss0   = reshape(lm_stack(lm.Ss0),   [], 1);            % [T x 1] complex

% ---- numerical clean-up (sparsity-preserving; see note below) ----
% "X(abs(X)<tol)=0" on a sparse X matches every structural zero too (0 < tol),
% forcing a dense logical mask and reintroducing the O(T^2) blowup. spfun
% only touches explicitly-stored nonzeros.
clean_sp = @(X) spfun(@(v) v .* (abs(v) >= tol), X);
sens.Imag0(abs(sens.Imag0) < tol) = 0;
sens.dImagdP = clean_sp(sens.dImagdP);
sens.dImagdQ = clean_sp(sens.dImagdQ);
if has_cplx_I
    sens.dIdP = clean_sp(sens.dIdP);
    sens.dIdQ = clean_sp(sens.dIdQ);
end

% ---- PV curtailment sensitivities (active power only) ----
if ~isempty(P_PV)
    sens.dVmagdP_PV = bd_reduce(lm.Vmag_dxdP, P_PV, T);
    sens.dImagdP_PV = bd_reduce(lm.Imag_dxdP, P_PV, T);
    sens.dSsdP_PV   = bd_reduce(lm.Ss_dxdP,   P_PV, T);
    sens.dImagdP_PV = clean_sp(sens.dImagdP_PV);
end

end

% =========================================================================
function BD = bd_reduce(A, P, T)
% Block-diagonal of  A(:,:,t) * P  over t = 1..T, as one sparse matrix.
%   A : [r x c x T] real/complex, single/double   (may be [] -> empty result)
%   P : [c x k]     node-space projection
%   BD: sparse [r*T x k*T]
if isempty(A)
    BD = sparse(0, 0);
    return
end
[r, ~, nT] = size(A);
if nT == 1 && T > 1        % 2-D A passed for a T>1 model -> shouldn't happen
    nT = T;
end
k = size(P, 2);

if isa(A, 'single')
    P = single(P);
end
Ar = pagemtimes(A, P);                       % [r x k x nT]

[gi, gj] = ndgrid(1:r, 1:k);                 % [r x k]
toff = reshape(0:nT-1, 1, nT);
rows = gi(:) + r * toff;                     % [r*k x nT]
cols = gj(:) + k * toff;
BD   = sparse(rows(:), cols(:), double(Ar(:)), r*nT, k*nT);
end
