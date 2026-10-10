function out = assemble_output_struct(milp_iters, best_iter_idx, ...
                                       lp_out, cand_info, ...
                                       gm, dims, coeffs, cfg, net_meta)
% ASSEMBLE_OUTPUT_STRUCT  Build the final output struct from the best MILP
%                         iteration, folding in LP provenance fields.
%
%   Preserves all existing field names (summary, sizing, injections, grid,
%   diagnostics, meta, gm) so downstream analysis functions are unaffected.
%   Adds:  out.lp.*  and  out.sizing.candidates / cand_info
%
%   Inputs
%   ------
%   milp_iters    : struct array [n_ran x 1]  from run_seq_lin_loop
%   best_iter_idx : int      index of best iteration
%   lp_out        : struct   from solve_lp_relaxation
%   cand_info     : struct   from extract_lp_candidates
%   gm            : struct   gm_orig
%   dims          : struct
%   coeffs        : struct
%   cfg           : struct
%   net_meta      : struct
%       .net_id         string   e.g. 'LV_Grid_302'
%       .net_num        double   e.g. 302
%       .scenario       string   e.g. 'sc1_2040'
%       .prepros_time_s double

bi   = best_iter_idx;
best = milp_iters(bi);

N  = dims.N;   Nd = dims.Nd;   L = dims.L;
T  = dims.T;   J  = dims.J;
CAMP = dims.CABLE_AMP;
Ts   = cfg.solver.Ts_h;

% ---- C-rate computation ----
B_full = best.B_plus - best.B_minus;
E_full = best.E_nom_node_pu;
C_rate = zeros(Nd, J);
for n = 1:Nd
    Idx = (n-1)*T + (1:T);
    for j = 1:J
        En = E_full(n,j);
        if En > 1e-9
            C_rate(n,j) = max(abs(B_full(Idx,j))) / En;
        end
    end
end

% ---- charge/discharge simultaneity diagnostics ----
B_exc           = min(best.B_plus, best.B_minus);
tol_exc         = 1e-6;
cha_dis_vio     = any(B_exc(:) > tol_exc);
cha_dis_vio_max = max(B_exc(:));
cha_dis_vio_energy = sum(B_exc(:)) * Ts;
B_sum = sum(best.B_plus(:)) + sum(best.B_minus(:));
cha_dis_vio_frac   = sum(B_exc(:)) / (B_sum + eps);

n_ran = numel(milp_iters);

% ---- determine best-cost iteration ----
costs = arrayfun(@(s) s.cvx_optval, milp_iters);
[~, best_cost_iter] = min(costs);

% =========================================================
%  BUILD OUTPUT STRUCT
% =========================================================

% --- summary ---
out.summary.network_id      = string(net_meta.net_num);
out.summary.cvx_status      = best.cvx_status;
out.summary.cvx_optval      = best.cvx_optval;
out.summary.E_nom_total_pu  = sum(E_full(:));
out.summary.S_conv_total_pu = sum(best.S_conv_node_pu(:));
out.summary.best_iter       = bi;
out.summary.best_cost_iter  = best_cost_iter;
out.summary.n_iters_run     = n_ran;
out.summary.volt_error      = best.volt_error;
out.summary.curr_error      = best.curr_error;
out.summary.C_rate_max      = max(C_rate(:));
out.summary.cha_dis_vio     = cha_dis_vio;
out.summary.prepros_time_s  = net_meta.prepros_time_s;
out.summary.solve_time_s    = best.solve_time_s;
out.summary.Vmag0_min       = min(vertcat(gm.lm.Vmag0{:}));
out.summary.Vmag0_max       = max(vertcat(gm.lm.Vmag0{:}));
out.summary.Nc              = cand_info.Nc;
out.summary.lp_fallback     = cand_info.fallback_triggered;

% --- sizing ---
out.sizing.E_nom_node_pu   = E_full;
out.sizing.S_conv_node_pu  = best.S_conv_node_pu;
out.sizing.Installation    = best.Installation;
out.sizing.C_rate          = C_rate;
out.sizing.C_rate_node_max = max(C_rate, [], 2);
out.sizing.tech_names      = cfg.tech.names;
out.sizing.candidates      = cand_info.candidate_idx;   % [Nc x 1] indices
out.sizing.cand_info       = cand_info;

% --- injections ---
out.injections.delta_P = best.dP_mat;
out.injections.delta_Q = best.dQ_mat;
out.injections.Q_ess   = best.Q_ess;
out.injections.B_bat   = B_full;
out.injections.B_plus  = best.B_plus;
out.injections.B_minus = best.B_minus;
out.injections.B_exc   = B_exc;
% slack bus injections: recompute from best iter sensitivity
% (stored in best.dP_mat / dQ_mat — slack powers not separately stored,
%  leave as empty for now; can be added if needed)
out.injections.Sl_P    = [];
out.injections.Sl_Q    = [];

% --- grid ---
out.grid.vmag_lin    = best.vmag_lin;
out.grid.V_lf        = best.V_lf;
out.grid.Imag_lin    = best.Imag_lin;
out.grid.Imag_lin_pu = best.Imag_lin ./ repmat(CAMP, T, 1);
out.grid.I_lf        = best.I_lf;
out.grid.I_lf_pu     = best.I_lf     ./ repmat(CAMP, T, 1);
out.grid.CABLE_AMP   = CAMP;
out.grid.S_lf        = [];   % available from OPF_verification if needed
out.grid.Vmag0_min   = out.summary.Vmag0_min;
out.grid.Vmag0_max   = out.summary.Vmag0_max;
out.grid.N           = N;
out.grid.Nd          = Nd;

% --- diagnostics ---
out.diagnostics.cha_dis_vio        = cha_dis_vio;
out.diagnostics.cha_dis_vio_max    = cha_dis_vio_max;
out.diagnostics.cha_dis_vio_energy = cha_dis_vio_energy;
out.diagnostics.cha_dis_vio_frac   = cha_dis_vio_frac;
out.diagnostics.iter_volt_error    = arrayfun(@(s) s.volt_error,  milp_iters);
out.diagnostics.iter_curr_error    = arrayfun(@(s) s.curr_error,  milp_iters);
out.diagnostics.iter_cost          = arrayfun(@(s) s.cvx_optval,  milp_iters);
out.diagnostics.iter_status        = {milp_iters.cvx_status};
out.diagnostics.iter_solve_time    = arrayfun(@(s) s.solve_time_s, milp_iters);

% --- LP provenance (new) ---
out.lp.E_nom_node_pu  = lp_out.E_nom_node_pu;
out.lp.S_conv_node_pu = lp_out.S_conv_node_pu;
out.lp.cvx_status     = lp_out.cvx_optval;   % optval as proxy (string from caller)
out.lp.volt_error     = lp_out.volt_error;
out.lp.curr_error     = lp_out.curr_error;
out.lp.solve_time_s   = lp_out.solve_time_s;

% --- meta ---
out.meta.scenario         = net_meta.scenario;
out.meta.network_id_str   = net_meta.net_id;
out.meta.net_num          = net_meta.net_num;
out.meta.tech_names       = cfg.tech.names;
out.meta.MAX_LIN_ITER_lp  = cfg.solver.MAX_LIN_ITER_lp;
out.meta.MAX_LIN_ITER_milp= cfg.solver.MAX_LIN_ITER_milp;
out.meta.VOLT_CONV_THRESH = cfg.solver.VOLT_CONV_THRESH;
out.meta.kP               = cfg.converter.kP;
out.meta.kQ_conv          = cfg.converter.kQ_conv;
out.meta.c_rate_j         = cfg.tech.c_rate;
out.meta.eta_ch           = cfg.tech.eta_ch;
out.meta.eta_dis          = cfg.tech.eta_dis;

% --- gm (large — keep last for .mat save efficiency) ---
out.gm = gm;

end
