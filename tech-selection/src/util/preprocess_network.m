function [gm, dims, coeffs] = preprocess_network(data_SFOE, n_idx, config, cfg, horizon, D)
% PREPROCESS_NETWORK  Build grid model and extract all dimensions/coefficients
%                     needed by the LP and MILP solvers.
%
%   [gm, dims, coeffs] = preprocess_network(data_SFOE, n_idx, config, cfg)
%   [gm, dims, coeffs] = preprocess_network(data_SFOE, n_idx, config, cfg, horizon)
%
%   Inputs
%   ------
%   data_SFOE : struct   full portfolio struct (output of allocate_PV_EV_SFOE)
%   n_idx     : int      index into data_SFOE for this network
%   config    : struct   general_config.json  (PU values, demand factors)
%   cfg       : struct   output of load_ess_selection_config
%   horizon   : vector   optional timestep indices (see build_temporal_profiles).
%                        [] or omitted -> full day.
%   D         : scalar   optional synthetic-day count (see build_temporal_profiles).
%                        [] or omitted -> cfg.horizon.days.
%
%   Outputs
%   -------
%   gm     : struct   full linear grid model (output of linear_grid_model)
%   dims   : struct   pre-computed dimension and matrix fields (see below)
%   coeffs : struct   pu-scaled cost coefficients
%
%   dims fields
%   -----------
%   N                scalar      total nodes excl. slack
%   Nd               scalar      nodes with demand > 0
%   L                scalar      number of branches
%   T                scalar      number of timesteps  (96 for 15-min day)
%   J                scalar      number of technologies
%   nodes_with_demand [N x 1]   logical mask
%   CABLE_AMP         [L x 1]   ampacity in pu
%   slack_S_mag_pu    scalar     transformer per-phase rating in pu
%   AUX_to_all_nodes  [TN x TNd] sparse block-diag of to_all_nodes_D x T
%   R_TNd_toNdT       [NdT x TNd] reshape permutation matrix
%   Npv                  scalar      nodes with PV > 0
%   nodes_with_PV        [N x 1]     logical mask
%   AUX_to_all_nodes_PV  [TN x TNpv] sparse block-diag of to_all_nodes_PV x T
%   R_TNpv_toNpvT        [NpvT x TNpv] reshape permutation matrix (PV curtailment)
%   PV_avail_pu_stacked  [T*Npv x 1] available PV per PV-node per timestep, pu,
%                        node-major stacked (same convention as B_plus/B_minus)

if nargin < 5
    horizon = [];
end
if nargin < 6 || isempty(D)
    D = cfg.horizon.days;
end
steps_per_day = cfg.horizon.steps_per_day;

% Only store the complex line-current sensitivities (gm.lm.I_dxdP/I_dxdQ,
% ~half of gm.lm's memory) when solve_ess_milp will actually use them, i.e.
% when the current constraint is the complex/diamond form (current_mag_cstr
% == false). With the default magnitude constraint they are never read.
keep_complex_I = ~cfg.solver.current_mag_cstr;

% Profile-generation knobs (demand/PV/EV), sourced from sizing_cfg.json's
% demand_profile/pv_profile/ev_profile blocks when present; each generator
% falls back to its own defaults for any field left unset (see
% generate_load_profile / load_pv_profile / generate_ev_profile).
profile_params = struct();
if isfield(cfg, 'demand_profile'); profile_params.demand = cfg.demand_profile; end
if isfield(cfg, 'pv_profile');     profile_params.pv     = cfg.pv_profile;     end
if isfield(cfg, 'ev_profile');     profile_params.ev     = cfg.ev_profile;     end

grid_data = get_grid_SFOE(data_SFOE, n_idx, config);
gm        = linear_grid_model(grid_data, horizon, D, steps_per_day, keep_complex_I, profile_params);

% ------- basic dimensions -------
[N, ~] = size(gm.to_all_nodes);      % to_all_nodes is [N x Nd] pinv(M)
L      = size(gm.grid.ampacities, 1);
T      = size(gm.nodal_injections_D_pu, 1);
J      = cfg.J;

nodes_with_demand = gm.grid.nodal_nominal_power > 0;
Nd                = sum(nodes_with_demand);

% ------- mapping matrices -------
to_all_nodes_D   = pinv(make_M(nodes_with_demand));   % [N x Nd]
AUX_to_all_nodes = repeat_block_diag(to_all_nodes_D, T);  % [TN x TNd]
R_TNd_toNdT      = linear_reshape_test(T, Nd);            % [NdT x TNd]

% Replacement for pinv(AUX_to_all_nodes): since pinv(pinv(X)) == X exactly
% for any X, and to_all_nodes_D == pinv(make_M(nodes_with_demand)), the
% correct N-space -> Nd-space projection is just make_M(...) itself --
% computing it as pinv(to_all_nodes_D) (i.e. pinv(pinv(make_M(...)))) wastes
% two pseudo-inverse calls on a result already available for free, and adds
% two rounds of avoidable floating-point rounding to sens.P0/Q0 downstream.
D_pinv           = full(make_M(nodes_with_demand));

% ------- PV curtailment node-space (mirrors the demand-node block above) -------
nodes_with_PV       = gm.grid.nodal_PV_SFOE > 0;
Npv                 = sum(nodes_with_PV);

% The MILP's base injections sens.P0 are the N->Nd projection of the full
% operating point (build_sensitivity_matrices drops injections at nodes
% without demand), and OPF_verification only re-adds PV curtailment. Every
% PV- or EV-bearing node must therefore also be a demand node.
% allocate_PV_EV_SFOE guarantees it (it only allocates to nodes with
% PLmax > 0) -- check rather than assume, since a violation would corrupt
% results silently.
nodes_with_EV = gm.grid.nodal_N_EV > 0;
orphan = find((nodes_with_PV | nodes_with_EV) & ~nodes_with_demand);
if ~isempty(orphan)
    error('preprocess_network:pvEvNotSubsetOfDemand', ...
        ['Network %s: PV/EV at %d node(s) without demand (topology node id(s) %s). ' ...
         'Their injections would be dropped from the MILP base point; see build_sensitivity_matrices.'], ...
        string(grid_data.net_id), numel(orphan), mat2str(orphan(:).' + 1));
end
to_all_nodes_PV     = pinv(make_M(nodes_with_PV));            % [N x Npv]
AUX_to_all_nodes_PV = repeat_block_diag(to_all_nodes_PV, T);   % [TN x TNpv]
R_TNpv_toNpvT       = linear_reshape_test(T, Npv);             % [NpvT x TNpv]
PV_avail_pu_stacked = gm.injectinos_PV_pu(:);   % [T x Npv] -> [T*Npv x 1], node-major (col-major reshape)

% ------- electrical limits -------
bp           = gm.grid.basepower / 1000;
CABLE_AMP    = gm.grid.ampacities ./ gm.grid.basecurrent;   % [L x 1] pu
% transformer rating: graph_data.T_rat_kVA is 3-phase kVA
slack_S_mag_pu = (grid_data.graph_data.T_rat_kVA / 3) / bp; % per-phase pu

% ------- pack dims -------
dims.N                = N;
dims.Nd               = Nd;
dims.L                = L;
dims.T                = T;
dims.J                = J;
dims.nodes_with_demand = nodes_with_demand;
dims.CABLE_AMP        = CABLE_AMP;
dims.slack_S_mag_pu   = slack_S_mag_pu;
dims.AUX_to_all_nodes = AUX_to_all_nodes;
dims.R_TNd_toNdT      = R_TNd_toNdT;
dims.D_pinv           = D_pinv;

dims.Npv                 = Npv;
dims.nodes_with_PV       = nodes_with_PV;
dims.AUX_to_all_nodes_PV = AUX_to_all_nodes_PV;
dims.R_TNpv_toNpvT       = R_TNpv_toNpvT;
dims.PV_avail_pu_stacked = PV_avail_pu_stacked;

% ------- cost coefficients (pu-scaled) -------
coeffs.bp = bp;
coeffs.cE = cfg.costs.cE;
coeffs.cS = cfg.costs.cS;
coeffs.cI = cfg.costs.cI;

end
