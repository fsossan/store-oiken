function gm = linear_grid_model(grid, horizon, D, steps_per_day, keep_complex_I, profile_params)
%LINEAR_GRID_MODEL  Per-timestep load-flow linearization of the grid.
%
%   gm = linear_grid_model(grid)
%   gm = linear_grid_model(grid, horizon)
%   gm = linear_grid_model(grid, horizon, D)
%   gm = linear_grid_model(grid, horizon, D, steps_per_day)
%   gm = linear_grid_model(grid, horizon, D, steps_per_day, keep_complex_I)
%   gm = linear_grid_model(grid, horizon, D, steps_per_day, keep_complex_I, profile_params)
%
%   horizon        : optional vector of timestep indices into the daily grid
%                    (see build_temporal_profiles). [] or omitted -> full day.
%   D              : optional synthetic-day count, see build_temporal_profiles.
%   steps_per_day  : optional, expected steps per day (= 24 / Ts_h). Checked
%                    against the native resolution of the input data.
%   keep_complex_I : optional logical, default true. When false, the complex
%                    line-current sensitivities gm.lm.I_dxdP / I_dxdQ are NOT
%                    stored (set to []). They are only used by solve_ess_milp
%                    when opts.current_mag_cstr == false; with the default
%                    current-magnitude constraint they are dead weight
%                    (~half of gm.lm's memory at year-scale horizons).
%   profile_params : optional struct, forwarded to build_temporal_profiles
%                    (fields .demand/.pv/.ev -- see generate_load_profile /
%                    load_pv_profile / generate_ev_profile). [] or omitted ->
%                    each generator's own defaults.
%
%   gm.lm.* LAYOUT (post-restructure):
%     Per-timestep quantities are stored as contiguous arrays, NOT {1 x T}
%     cells. This turns ~10*T small allocations into ~14 large ones, which is
%     what removes the O(T^2) slowdown in this loop at large T (the cost grew
%     with the live-allocation count, not the byte count).
%       P0, Q0, Vmag0, Vmag_dxdVsmag   : [N x T] double
%       Vsmag0, Ss_dxdVsmag            : [1 x T] double
%       Imag0                          : [L x T] complex double
%       Ss0                            : [1 x T] complex double
%       Vmag_dxdP, Vmag_dxdQ           : [N x N x T] single
%       Imag_dxdP, Imag_dxdQ           : [L x N x T] single
%       I_dxdP, I_dxdQ                 : [L x N x T] single complex, or []
%       Ss_dxdP, Ss_dxdQ              : [1 x N x T] complex double
%     Read 0-order fields with lm_stack() + reshape; build_sensitivity_matrices
%     consumes the 3-D sensitivity arrays directly via pagemtimes.

if nargin < 2
    horizon = [];
end
if nargin < 3
    D = [];
end
if nargin < 4
    steps_per_day = [];
end
if nargin < 5 || isempty(keep_complex_I)
    keep_complex_I = true;
end
if nargin < 6
    profile_params = struct();
end

profiles = build_nodal_injections(grid, horizon, D, steps_per_day, profile_params);

T  = profiles.T;
Nd = profiles.Nd;

nodal_injections_D_pu  = profiles.nodal_injections_D_pu;
nodal_injections_PV_pu = profiles.nodal_injections_PV_pu;
nodal_injections_EV_pu = profiles.nodal_injections_EV_pu;

to_all_nodes_D  = profiles.to_all_nodes_D;
to_all_nodes_PV = profiles.to_all_nodes_PV;
to_all_nodes_EV = profiles.to_all_nodes_EV;

% Number of samples, nodes and lines
N = numel(grid.nodal_nominal_power);
L = numel(grid.ampacities);

% -------------------------------------------------------------------------
%  Preallocate: contiguous arrays (see gm.lm.* LAYOUT note above).
% -------------------------------------------------------------------------
P0            = zeros(N, T);
Q0            = zeros(N, T);
Vsmag0        = ones(1, T);
Vmag0         = zeros(N, T);
Imag0         = complex(zeros(L, T));          % complex phasor (docs/DEVELOPMENT_NOTES.md gotcha)
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

% Local per-timestep diagnostics (Vml/Iml/Sl/Vm/Im/Vmp/Imp/Sp are NOT
% returned in gm -- kept as a faithful port of the original loop; the
% perturbed load flow below can be deleted for a ~1/3 loop speedup if these
% are confirmed unused).
Vm  = zeros(T, N);   Im  = zeros(T, L);
Vmp = zeros(T, N);   Imp = zeros(T, L);
Vml = zeros(T, N);   Iml = zeros(T, L);
Sp  = complex(zeros(1, T));
Sl  = complex(zeros(1, T));

% Base operating-point load-flow convergence, one entry per timestep (see
% loadflow_FPIs' converged/num_iter outputs and summarize_lf_convergence).
lf_converged = false(1, T);
lf_num_iter  = nan(1, T);

% YLL depends only on grid.Y (slack = row/col 1, n_phases = 1 here), so
% invert it once instead of once per loadflow_FPIs call (2 per timestep).
YLLi = inv(grid.Y(2:end, 2:end));

tim_colec = nan(1, T);
for t = 1:T
    tic
    % Operating point = demand + PV + EV. For the current portfolio, PV and
    % EV nodes are both subsets of demand nodes (verified across the tested
    % networks), so both injections survive the N->Nd projection in
    % build_sensitivity_matrices (sens.P0) and the LF verification stays
    % consistent; a network with PV-only or EV-only nodes would also need
    % that stream passed explicitly into OPF_verification (it currently
    % only takes an explicit PV argument, for curtailment).
    injections = to_all_nodes_D  * nodal_injections_D_pu(t, :).' ...
               + to_all_nodes_PV * nodal_injections_PV_pu(t, :).' ...
               + to_all_nodes_EV * nodal_injections_EV_pu(t, :).';
    p0 = real(injections);
    q0 = imag(injections);
    P0(:, t)   = p0;
    Q0(:, t)   = q0;
    Vsmag0(t)  = 1;

    [V, I, S, lf_converged(t), lf_num_iter(t)] = loadflow_FPIs(grid.Y, 1, injections, 1, ...
        grid.voltageToBranchCurrent_pu, YLLi);

    Vm(t, :) = abs(V).';
    Im(t, :) = abs(I).';

    % Sensitivity coefficients at this operating point
    [vdp, vdq, vdvs, sdp, sdq, sdvs, idp_m, idq_m, idp_c, idq_c, ~] = ...
        getSCs(grid.Y, [1; injections], [1; V], I, grid.N1N2Y, grid.n_of_phases);

    % Drop the slack-bus row from the voltage sensitivities
    % (was gm.lm.Vmag_dxdP{t}(1,:) = [] etc.)
    vdp(1, :)  = [];
    vdq(1, :)  = [];
    vdvs(1, :) = [];

    Vmag_dxdP(:, :, t)   = vdp;
    Vmag_dxdQ(:, :, t)   = vdq;
    Vmag_dxdVsmag(:, t)  = vdvs;
    Imag_dxdP(:, :, t)   = idp_m;
    Imag_dxdQ(:, :, t)   = idq_m;
    Ss_dxdP(1, :, t)     = sdp;
    Ss_dxdQ(1, :, t)     = sdq;
    Ss_dxdVsmag(t)       = sdvs;
    if keep_complex_I
        I_dxdP(:, :, t) = idp_c;
        I_dxdQ(:, :, t) = idq_c;
    end

    % Operating point
    Vmag0(:, t) = abs(V);
    Imag0(:, t) = I;          % complex, not abs (matches original)
    Ss0(t)      = S;

    % --- local diagnostics: perturbed load flow + linear check ---
    % injections_p = injections + real(injections) * 0.5;
    % [Vp, Ip, S_] = loadflow_FPIs(grid.Y, 1, injections_p, 1, ...
    %     grid.voltageToBranchCurrent_pu, YLLi);
    % Vmp(t, :) = abs(Vp).';
    % Imp(t, :) = abs(Ip).';
    % Sp(t)     = S_;
    % 
    % dP = real(injections_p) - p0;
    % dQ = imag(injections_p) - q0;
    % Vabslin  = abs(V) + vdp * dP + vdq * (dQ + vdvs * 0);
    % Sl(t)    = S - sdp * dP + sdq * dQ + sdvs * 0;
    % Iabslin  = abs(I) + abs(idp_m * dP) + real(idq_m * abs(dQ));
    % Vml(t, :) = Vabslin.';
    % Iml(t, :) = Iabslin.';

    tim_colec(t) = toc;
end

% -------------------------------------------------------------------------
%  Store
% -------------------------------------------------------------------------
gm.grid = grid;
gm.to_all_nodes = to_all_nodes_D;

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

gm.lm.keep_complex_I = keep_complex_I;   % provenance: were I_dxd* stored?
gm.lm.tim_colec      = tim_colec;        % per-timestep loop wall time (s)

gm.lm.lf_converged = lf_converged;
gm.lm.lf_num_iter  = lf_num_iter;
gm.lm.lf_summary   = summarize_lf_convergence(lf_converged, lf_num_iter);
if ~gm.lm.lf_summary.all_converged
    % HARD STOP (temporary, pending the loadflow_FPIs damping/robustness
    % merge -- see loadflow_FPIs_convergance.m): a non-converged base
    % operating point feeds garbage into getSCs/the sensitivity matrices at
    % those timesteps, so refuse to proceed rather than let a bad MILP
    % result through silently. Caught by run_ess_selection_portfolio.m's
    % per-network try/catch (-> out_dir_error), so this only stops THIS
    % network, not a whole "ALL" portfolio run.
    error('linear_grid_model:lfNotConverged', ...
        ['Base operating-point load flow failed to converge at %d/%d timesteps ' ...
         '(%.2f%%). Stopping before any MILP work. First failed timestep(s): %s'], ...
        T - gm.lm.lf_summary.n_converged, T, 100 - gm.lm.lf_summary.pct_converged, ...
        mat2str(gm.lm.lf_summary.failed_idx(1:min(5, numel(gm.lm.lf_summary.failed_idx)))));
end

gm.nodal_injections_D_pu = nodal_injections_D_pu;
%gm.nodal_injections_PV_pu = nodal_injections_PV_pu;
gm.Vs = 1;
gm.to_all_nodes_D = to_all_nodes_D;
gm.to_all_nodes_PV = to_all_nodes_PV;
gm.to_all_nodes_EV = to_all_nodes_EV;
gm.injections_D_pu = nodal_injections_D_pu;
gm.injections_EV_pu = nodal_injections_EV_pu;
gm.injectinos_PV_pu = nodal_injections_PV_pu;
gm.injections_meta = struct('calendar', profiles.calendar, 'seeds', profiles.seeds, ...
    'magnitudes', profiles.magnitudes);   % provenance of the operating point (see build_nodal_injections)

end
