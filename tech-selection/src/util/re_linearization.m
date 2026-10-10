function gm = re_linearization(grid, updated_injections, T, keep_complex_I)
%RE_LINEARIZATION  Re-linearize the grid model around an updated operating point.
%
%   gm = re_linearization(grid, updated_injections, T)
%   gm = re_linearization(grid, updated_injections, T, keep_complex_I)
%
%   Inputs
%   ------
%   grid               : grid struct (from get_grid_SFOE / linear_grid_model)
%   updated_injections : complex nodal power injections (Nd x T), pu
%                        typically: complex(P0 + delta_P, Q0 + delta_Q)
%                        from the previous OPF iteration
%   T                  : number of time steps
%   keep_complex_I     : optional logical, default true. Must match how the
%                        original gm was built (gm.lm.keep_complex_I) so the
%                        re-linearised gm has the same field set.
%
%   Output
%   ------
%   gm : updated grid model with the same gm.lm.* array layout as
%        linear_grid_model -- drop-in replacement for gm_curr.
%        (Only exercised when MAX_LIN_ITER > 1.)

if nargin < 4 || isempty(keep_complex_I)
    keep_complex_I = true;
end

N  = numel(grid.nodal_nominal_power);
L  = numel(grid.ampacities);

nodes_with_demand = grid.nodal_nominal_power > 0;
to_all_nodes_D    = pinv(make_M(nodes_with_demand));

% updated_injections is (Nd x T) -> transpose to (T x Nd) for per-timestep indexing
nodal_injections_D_pu = updated_injections.';   % T x Nd

% -------------------------------------------------------------------------
%  Preallocate: contiguous arrays (matches linear_grid_model gm.lm layout)
% -------------------------------------------------------------------------
P0            = zeros(N, T);
Q0            = zeros(N, T);
Vsmag0        = ones(1, T);
Vmag0         = zeros(N, T);
Imag0         = complex(zeros(L, T));
Ss0           = complex(zeros(1, T));

Vmag_dxdP     = zeros(N, N, T, 'single');
Vmag_dxdQ     = zeros(N, N, T, 'single');
Vmag_dxdVsmag = zeros(N, T);
Imag_dxdP     = zeros(L, N, T, 'single');
Imag_dxdQ     = zeros(L, N, T, 'single');
Ss_dxdP       = complex(zeros(1, N, T));
Ss_dxdQ       = complex(zeros(1, N, T));
Ss_dxdVsmag   = zeros(1, T);

if keep_complex_I
    I_dxdP = complex(zeros(L, N, T, 'single'));
    I_dxdQ = complex(zeros(L, N, T, 'single'));
else
    I_dxdP = [];
    I_dxdQ = [];
end

YLLi = inv(grid.Y(2:end, 2:end));   % constant across timesteps

% Re-linearized operating-point load-flow convergence, one entry per
% timestep (mirrors linear_grid_model.m -- see loadflow_FPIs' converged/
% num_iter outputs and summarize_lf_convergence).
lf_converged = false(1, T);
lf_num_iter  = nan(1, T);

for t = 1:T
    injections = to_all_nodes_D * nodal_injections_D_pu(t, :).';
    P0(:, t)  = real(injections);
    Q0(:, t)  = imag(injections);
    Vsmag0(t) = 1;

    [V, I, S, lf_converged(t), lf_num_iter(t)] = loadflow_FPIs(grid.Y, 1, injections, 1, ...
        grid.voltageToBranchCurrent_pu, YLLi);

    [vdp, vdq, vdvs, sdp, sdq, sdvs, idp_m, idq_m, idp_c, idq_c, ~] = ...
        getSCs(grid.Y, [1; injections], [1; V], I, grid.N1N2Y, grid.n_of_phases);

    vdp(1, :)  = [];
    vdq(1, :)  = [];
    vdvs(1, :) = [];

    Vmag_dxdP(:, :, t)  = vdp;
    Vmag_dxdQ(:, :, t)  = vdq;
    Vmag_dxdVsmag(:, t) = vdvs;
    Imag_dxdP(:, :, t)  = idp_m;
    Imag_dxdQ(:, :, t)  = idq_m;
    Ss_dxdP(1, :, t)    = sdp;
    Ss_dxdQ(1, :, t)    = sdq;
    Ss_dxdVsmag(t)      = sdvs;
    if keep_complex_I
        I_dxdP(:, :, t) = idp_c;
        I_dxdQ(:, :, t) = idq_c;
    end

    Vmag0(:, t) = abs(V);
    Imag0(:, t) = I;          % complex, matches linear_grid_model
    Ss0(t)      = S;
end

% -------------------------------------------------------------------------
%  Output struct
% -------------------------------------------------------------------------
gm.grid = grid;

gm.to_all_nodes    = to_all_nodes_D;
gm.to_all_nodes_D  = to_all_nodes_D;

gm.lm.P0     = P0;
gm.lm.Q0     = Q0;
gm.lm.Vsmag0 = Vsmag0;

gm.lm.Vmag_dxdP     = Vmag_dxdP;
gm.lm.Vmag_dxdQ     = Vmag_dxdQ;
gm.lm.Imag_dxdP     = Imag_dxdP;
gm.lm.Imag_dxdQ     = Imag_dxdQ;
gm.lm.I_dxdP        = I_dxdP;
gm.lm.I_dxdQ        = I_dxdQ;
gm.lm.Vmag_dxdVsmag = Vmag_dxdVsmag;
gm.lm.Vmag0         = Vmag0;
gm.lm.Imag0         = Imag0;

gm.lm.Ss_dxdP     = Ss_dxdP;
gm.lm.Ss_dxdQ     = Ss_dxdQ;
gm.lm.Ss_dxdVsmag = Ss_dxdVsmag;
gm.lm.Ss0         = Ss0;

gm.lm.keep_complex_I = keep_complex_I;

gm.lm.lf_converged = lf_converged;
gm.lm.lf_num_iter  = lf_num_iter;
gm.lm.lf_summary   = summarize_lf_convergence(lf_converged, lf_num_iter);
if ~gm.lm.lf_summary.all_converged
    % HARD STOP -- same reasoning/temporariness as linear_grid_model.m's
    % identical guard; only exercised when MAX_LIN_ITER > 1.
    error('re_linearization:lfNotConverged', ...
        ['Re-linearized operating-point load flow failed to converge at %d/%d ' ...
         'timesteps (%.2f%%). Stopping. First failed timestep(s): %s'], ...
        T - gm.lm.lf_summary.n_converged, T, 100 - gm.lm.lf_summary.pct_converged, ...
        mat2str(gm.lm.lf_summary.failed_idx(1:min(5, numel(gm.lm.lf_summary.failed_idx)))));
end

gm.nodal_injections_D_pu = nodal_injections_D_pu;
gm.Vs                    = 1;

end
