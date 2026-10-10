function best_out = build_network_result(sol, sens, verif, gm_orig, dims, cfg, net_meta, lin_iter, v_err, i_err, prepros_time, solve_time_s)
% BUILD_NETWORK_RESULT  Assemble the single-stage ESS-selection output struct
%                        for one (improving) sequential-linearisation iteration.
%
%   best_out = build_network_result(sol, sens, verif, gm_orig, dims, cfg, ...
%                                    net_meta, lin_iter, v_err, i_err, ...
%                                    prepros_time, solve_time_s)
%
%   Inputs
%   ------
%   sol        : struct   output of solve_ess_milp for this iteration
%   sens       : struct   output of build_sensitivity_matrices for this iteration
%   verif      : struct   load-flow verification results
%                  .dP_mat, .dQ_mat, .P0_mat, .Q0_mat  [Nd x T]
%                  .V_lf, .I_lf, .S_lf
%   gm_orig    : struct   linear grid model at the ORIGINAL (unrelinearised)
%                         operating point, stored for downstream analysis
%   dims       : struct   .T .Nd .N .L .J .nodes_with_demand .CABLE_AMP
%   cfg        : struct   sizing/tech config (load_ess_selection_config)
%   net_meta   : struct   .scenario .net_id .net_num .tech_names .MAX_LIN_ITER
%   lin_iter   : scalar   current sequential-linearisation iteration index
%   v_err      : scalar   max voltage linearisation error for this iteration
%   i_err      : scalar   max current linearisation error for this iteration
%   prepros_time  : scalar  preprocessing wall time (s)
%   solve_time_s  : scalar  CVX solve wall time for this iteration (s)
%
%   Output
%   ------
%   best_out : struct   summary/sizing/injections/grid/diagnostics/meta/gm/selection
%              (field layout matches the pre-refactor main.m inline assembly —
%              consumed as-is by explain_tech_selection, analyze_tech_selection,
%              analyze_losses)

T = dims.T;   Nd = dims.Nd;   N = dims.N;   J = dims.J;
CABLE_AMP         = dims.CABLE_AMP;
nodes_with_demand = dims.nodes_with_demand;
nodes_with_PV     = dims.nodes_with_PV;

B_full = sol.B_plus - sol.B_minus;

C_rate_store = zeros(Nd, J);
for n = 1:Nd
    Idx = (n-1)*T + (1:T);
    for j = 1:J
        En = sol.E_nom(n,j);
        if En > 1e-9
            C_rate_store(n,j) = max(abs(B_full(Idx,j))) / En;
        end
    end
end

B_exc       = min(sol.B_plus, sol.B_minus);
tol_exc     = 1e-6;
cha_dis_vio = any(B_exc(:) > tol_exc);
Ts          = cfg.solver.Ts_h;

best_out = struct();

best_out.summary.network_id      = string(net_meta.net_num);
best_out.summary.cvx_status      = sol.status;
best_out.summary.cvx_optval      = sol.optval;
best_out.summary.E_nom_total_pu  = sum(sol.E_nom(:));
best_out.summary.S_conv_total_pu = sum(sol.S_conv(:));
best_out.summary.best_iter       = lin_iter;
best_out.summary.best_cost_iter  = [];
best_out.summary.n_iters_run     = [];
best_out.summary.volt_error      = v_err;
best_out.summary.curr_error      = i_err;
best_out.summary.C_rate_max      = max(C_rate_store(:));
best_out.summary.cha_dis_vio     = cha_dis_vio;
best_out.summary.prepros_time_s  = prepros_time;
best_out.summary.solve_time_s    = solve_time_s;
best_out.summary.Vmag0_min       = min(sens.Vmag0);
best_out.summary.Vmag0_max       = max(sens.Vmag0);
best_out.summary.curtailed_energy_pu = sum(sol.P_curt) * Ts;

best_out.sizing.E_nom_node_pu   = sol.E_nom;
best_out.sizing.S_conv_node_pu  = sol.S_conv;
best_out.sizing.Installation    = sol.Installation;
best_out.sizing.SOE_0_pu        = sol.SOE_0;
best_out.sizing.demand_node_id  = find(nodes_with_demand)+1;  % [Nd x 1], row k -> N-space node index; +1 for the slack
best_out.sizing.pv_node_id      = find(nodes_with_PV)+1;      % [Npv x 1], row k -> N-space node index; +1 for the slack
best_out.sizing.C_rate          = C_rate_store;
best_out.sizing.C_rate_node_max = max(C_rate_store, [], 2);
best_out.sizing.tech_names      = net_meta.tech_names;

best_out.injections.delta_P = verif.dP_mat;
best_out.injections.delta_Q = verif.dQ_mat;
best_out.injections.Q_ess   = sol.Q_ess;
best_out.injections.B_bat   = B_full;
best_out.injections.B_plus  = sol.B_plus;
best_out.injections.B_minus = sol.B_minus;
best_out.injections.B_exc   = B_exc;
best_out.injections.Sl_P    = sol.P_sl;
best_out.injections.Sl_Q    = sol.Q_sl;
best_out.injections.P0_mat  = verif.P0_mat;
best_out.injections.Q0_mat  = verif.Q0_mat;
best_out.injections.Ss0     = sens.Ss0;
best_out.injections.P_curt  = sol.P_curt;   % [T*Npv x 1], node-major, pu
best_out.injections.P_sloss = sol.P_sloss;  % [T x 1], transformer/feeder loss proxy, pu

best_out.costs = sol.costs;   % .E .S .I .L .Curt .total (objective cost terms, CHF)

best_out.grid.vmag_lin    = sol.vmag;
best_out.grid.V_lf        = verif.V_lf;
best_out.grid.Imag_lin    = sol.Imag;
best_out.grid.Imag_lin_pu = sol.Imag ./ repmat(CABLE_AMP, T, 1);
best_out.grid.I_lf        = verif.I_lf;
best_out.grid.I_lf_pu     = verif.I_lf ./ repmat(CABLE_AMP, T, 1);
best_out.grid.CABLE_AMP   = CABLE_AMP;
best_out.grid.S_lf        = verif.S_lf;
best_out.grid.Vmag0_min   = min(sens.Vmag0);
best_out.grid.Vmag0_max   = max(sens.Vmag0);
best_out.grid.N           = N;
best_out.grid.Nd          = Nd;

best_out.diagnostics.cha_dis_vio        = cha_dis_vio;
best_out.diagnostics.cha_dis_vio_max    = max(B_exc(:));
best_out.diagnostics.cha_dis_vio_energy = sum(B_exc(:)) * Ts;
best_out.diagnostics.cha_dis_vio_frac   = sum(B_exc(:)) / ...
    (sum(sol.B_plus(:)) + sum(sol.B_minus(:)) + eps);

% Solved-dispatch verification load-flow convergence (see loadflow_FPIs /
% summarize_lf_convergence). The base operating point's own convergence
% record is separately available at best_out.gm.lm.lf_summary.
if isfield(verif, 'lf_converged')
    best_out.diagnostics.lf_converged = verif.lf_converged;
    best_out.diagnostics.lf_num_iter  = verif.lf_num_iter;
    best_out.diagnostics.lf_summary   = summarize_lf_convergence(verif.lf_converged, verif.lf_num_iter);
end
best_out.diagnostics.iter_volt_error    = [];
best_out.diagnostics.iter_curr_error    = [];
best_out.diagnostics.iter_cost          = [];
best_out.diagnostics.iter_status        = [];

best_out.meta.scenario         = net_meta.scenario;
best_out.meta.network_id_str   = net_meta.net_id;
best_out.meta.net_num          = net_meta.net_num;
best_out.meta.tech_names       = net_meta.tech_names;
best_out.meta.MAX_LIN_ITER     = net_meta.MAX_LIN_ITER;
best_out.meta.VOLT_CONV_THRESH = cfg.solver.VOLT_CONV_THRESH;
best_out.meta.Ts_h             = cfg.solver.Ts_h;
best_out.meta.horizon_days     = cfg.horizon.days;
best_out.meta.steps_per_day    = cfg.horizon.steps_per_day;
best_out.meta.kW_per_pu        = kw_per_pu_of(cfg);   % pu -> real 3-phase kW/kWh; analyze_* read it back via kw_per_pu_of(out)
best_out.meta.kP               = cfg.converter.kP;
best_out.meta.kQ_conv          = cfg.converter.kQ_conv;
best_out.meta.c_rate_j         = cfg.tech.c_rate;
best_out.meta.eta_ch           = cfg.tech.eta_ch;
best_out.meta.eta_dis          = cfg.tech.eta_dis;
best_out.meta.Emax_j           = cfg.tech.Emax_pu;
best_out.meta.Smax_j           = cfg.tech.Smax_pu;
best_out.meta.cE_per_kWh       = cfg.tech.cE_per_kWh;
best_out.meta.cS_per_kW        = cfg.tech.cS_per_kW;
best_out.meta.cI_fixed         = cfg.tech.cI_fixed;

best_out.gm        = gm_orig;
best_out.selection = explain_tech_selection(best_out, cfg);

end
