function [status, best_out, dispatch_log, iter_status] = run_seq_lin_loop_ess( ...
    gm, dims, grid_params, opts, cfg, net_meta, prepros_time, run_opts)
% RUN_SEQ_LIN_LOOP_ESS  Single-stage ESS technology-selection sequential
%                        linearisation loop.
%
%   [status, best_out, dispatch_log, iter_status] = run_seq_lin_loop_ess( ...
%       gm, dims, grid_params, opts, cfg, net_meta, prepros_time, run_opts)
%
%   Inputs
%   ------
%   gm            : struct   linear grid model (gm_orig)
%   dims          : struct   T, Nd, N, L, J, nodes_with_demand, CABLE_AMP, ...
%   grid_params   : struct   R_TNd_toNdT, CABLE_AMP, slack_S_mag_pu
%   opts          : struct   solve_ess_milp behavior flags
%   cfg           : struct   sizing/tech config
%   net_meta      : struct   .scenario .net_id .net_num .tech_names .MAX_LIN_ITER
%   prepros_time  : scalar   preprocessing wall time (s)
%   run_opts      : struct   .MAX_LIN_ITER .verbose_debug .enable_plots .log_fid
%                            (.log_fid may be [] to skip file logging)
%
%   Outputs
%   -------
%   status       : 'solved' | 'subopt'   ('error' is signalled by throwing,
%                   caught by the caller's try/catch, matching the original
%                   main.m behaviour)
%   best_out     : struct   finalised result (only when status == 'solved')
%   dispatch_log : struct   per-iteration dispatch diagnostics
%   iter_status  : cell     per-iteration CVX status strings

T = dims.T;   Nd = dims.Nd;   J = dims.J;   Npv = dims.Npv;
kW_per_pu = kw_per_pu_of(cfg);   % pu -> real 3-phase kW/kWh for the log lines (cfg.units.kW_per_pu)

MAX_LIN_ITER  = run_opts.MAX_LIN_ITER;
verbose_debug = run_opts.verbose_debug;
enable_plots  = run_opts.enable_plots;
log_fid       = run_opts.log_fid;

prev = struct( ...
    'B_plus_prev',  zeros(T*Nd, J), ...
    'B_minus_prev', zeros(T*Nd, J), ...
    'Q_ess_prev',   zeros(T*Nd, J), ...
    'P_curt_prev',  zeros(T*Npv, 1));

iter_volt_error = nan(MAX_LIN_ITER, 1);
iter_curr_error = nan(MAX_LIN_ITER, 1);
iter_cost       = nan(MAX_LIN_ITER, 1);
iter_status     = cell(MAX_LIN_ITER, 1);
iter_solve_time = nan(MAX_LIN_ITER, 1);

best_volt_err  = Inf;
best_cost_iter = 0;
best_cost      = Inf;
best_out       = [];
dispatch_log   = struct();
gm_orig        = gm;
gm_curr        = gm;

for lin_iter = 1:MAX_LIN_ITER

    % -- sensitivity matrices at current operating point ----------
    sens = build_sensitivity_matrices(gm_curr, dims.AUX_to_all_nodes, dims.AUX_to_all_nodes_PV,dims);

    % -- solve MILP -----------------------------------------------
    t_solve = tic;
    sol     = solve_ess_milp(sens, prev, dims, cfg, grid_params, opts);
    iter_solve_time(lin_iter) = toc(t_solve);

    if verbose_debug
        fprintf('  Q_ess: max=%.4f  mean=%.4f  nonzero_frac=%.2f\n', ...
            max(abs(sol.Q_ess(:))), mean(abs(sol.Q_ess(:))), ...
            mean(abs(sol.Q_ess(:)) > 1e-6));
        fprintf('  B_plus  max=%.4f  mean=%.4f\n', ...
            max(sol.B_plus(:)), mean(sol.B_plus(:)));
        fprintf('  B_minus max=%.4f  mean=%.4f\n', ...
            max(sol.B_minus(:)), mean(sol.B_minus(:)));
    end

    % -- check solver status ---------------------------------------
    if ~strcmp(sol.status, 'Solved') && ~strcmp(sol.status, 'Inaccurate/Solved')
        msg = sprintf('  [iter %d] CVX status: %s — stopping.', ...
            lin_iter, sol.status);
        if verbose_debug; fprintf('%s\n', msg); end
        if ~isempty(log_fid); fprintf(log_fid, '%s\n', msg); end
        iter_status{lin_iter} = sol.status;
        break
    end
    iter_status{lin_iter} = sol.status;

    % -- load-flow verification ------------------------------------
    dP_mat = reshape(grid_params.R_TNd_toNdT * sol.delta_P, Nd, T);
    dQ_mat = reshape(grid_params.R_TNd_toNdT * sol.delta_Q, Nd, T);
    P0_mat = reshape(sens.P0, Nd, T);
    Q0_mat = reshape(sens.Q0, Nd, T);
    P_inj  = complex(P0_mat + dP_mat, Q0_mat + dQ_mat);

    if opts.curtailment_activate && Npv > 0
        % [T x Npv]; node-major stacking of sol.P_curt matches Idx=(n-1)*T+(1:T)
        % elsewhere, so a plain reshape (not R_TNpv_toNpvT) recovers [T x Npv].
        P_curt_TxNpv = reshape(sol.P_curt, T, Npv);
    else
        P_curt_TxNpv = [];
    end
    [I_lf, V_lf, S_lf, lf_converged, lf_num_iter] = OPF_verification(P_inj.', gm_curr.grid, -P_curt_TxNpv);
    lf_summary = summarize_lf_convergence(lf_converged, lf_num_iter);
    if ~lf_summary.all_converged
        % HARD STOP (temporary, pending the loadflow_FPIs damping/robustness
        % merge) -- refuse to report/save a result whose "ground truth"
        % verification load flow didn't actually converge everywhere. The
        % MILP solve for this iteration already ran (its cost is sunk), but
        % nothing gets saved past this point. Caught by
        % run_ess_selection_portfolio.m's per-network try/catch
        % (-> out_dir_error), so this only stops THIS network.
        msg_lf = sprintf(['  [iter %d] Solved-dispatch verification load flow failed to ' ...
            'converge at %d/%d timesteps (%.2f%%). First failed timestep(s): %s'], ...
            lin_iter, T - lf_summary.n_converged, T, 100 - lf_summary.pct_converged, ...
            mat2str(lf_summary.failed_idx(1:min(5, numel(lf_summary.failed_idx)))));
        if verbose_debug; fprintf('%s\n', msg_lf); end
        if ~isempty(log_fid); fprintf(log_fid, '%s\n', msg_lf); end
        error('run_seq_lin_loop_ess:lfNotConverged', '%s', msg_lf);
    end

    v_err = max(abs(sol.vmag - V_lf));
    % Current linearisation error per (line, step), pu of the base current.
    % abs(sol.Imag) so the complex-current branch (current_mag_cstr = false)
    % compares magnitudes too; I_lf is already a magnitude, stacked
    % time-major [L*T] like repmat(CABLE_AMP, T, 1).
    i_err_vec = abs(abs(sol.Imag) - I_lf);
    i_err     = max(i_err_vec);
    % Worst entry relative to that line's own ampacity, located so the
    % printout can name the line, its rating (A) and the step.
    L_lines = numel(grid_params.CABLE_AMP);
    [i_err_amp, k_amp] = max(i_err_vec ./ repmat(grid_params.CABLE_AMP, T, 1));
    l_amp = mod(k_amp - 1, L_lines) + 1;
    t_amp = floor((k_amp - 1) / L_lines) + 1;
    Ib_A  = gm_curr.grid.basecurrent;
    iter_volt_error(lin_iter) = v_err;
    iter_curr_error(lin_iter) = i_err;
    iter_cost(lin_iter)       = sol.optval;

    % -- dispatch log ----------------------------------------------
    B_full = sol.B_plus - sol.B_minus;
    C_rate_iter = zeros(Nd, J);
    for n = 1:Nd
        Idx = (n-1)*T + (1:T);
        for j = 1:J
            En = sol.E_nom(n,j);
            if En > 1e-9
                C_rate_iter(n,j) = max(abs(B_full(Idx,j))) / En;
            end
        end
    end
    P_mag = max(abs(B_full(:)));
    Q_mag = max(abs(sol.Q_ess(:)));
    PF_iter = P_mag / max(sqrt(P_mag^2 + Q_mag^2), eps);

    dispatch_log.C_rate_max(lin_iter)     = max(C_rate_iter(:));
    dispatch_log.PF_min(lin_iter)         = PF_iter;
    dispatch_log.B_plus_max(lin_iter)     = max(sol.B_plus(:));
    dispatch_log.B_minus_max(lin_iter)    = max(sol.B_minus(:));
    dispatch_log.Q_ess_max(lin_iter)      = max(abs(sol.Q_ess(:)));
    dispatch_log.Q_nonzero_frac(lin_iter) = mean(abs(sol.Q_ess(:)) > 1e-6);
    dispatch_log.E_nom_total(lin_iter)    = sum(sol.E_nom(:)) * kW_per_pu;
    dispatch_log.S_conv_total(lin_iter)   = sum(sol.S_conv(:)) * kW_per_pu;
    dispatch_log.volt_err(lin_iter)       = v_err;
    dispatch_log.curr_err(lin_iter)       = i_err;
    dispatch_log.cost(lin_iter)           = sol.optval;
    dispatch_log.num_batt(lin_iter)       = nnz(sol.Installation(:) > 1e-4);
    dispatch_log.solve_time(lin_iter)     = iter_solve_time(lin_iter);
    dispatch_log.lf_pct_converged(lin_iter) = lf_summary.pct_converged;

    % -- iteration summary -----------------------------------------
    tech_lines = '';
    for j = 1:J
        n_sel = nnz(sol.Installation(:,j) > 1e-4);
        if n_sel > 0
            tech_lines = [tech_lines, sprintf('    [%s] N=%d  E=%.2fkWh  S=%.2fkVA\n', ...
                net_meta.tech_names{j}, n_sel, ...
                sum(sol.E_nom(:,j))*kW_per_pu, sum(sol.S_conv(:,j))*kW_per_pu)]; %#ok<AGROW>
        end
    end
    msg = sprintf(['  [iter %d/%d] E=%.2fkWh  S=%.2fkVA  N_batt=%d  cost=%.4f' ...
        '  v_err=%.1f%%  t=%.1fs  status=%s\n' ...
        '    i_err: max %.2e pu (%.2f A)  |  worst vs. rating: %.1f%% of %.1f A' ...
        '  (line %d: node %d -> node %d, t=%d)\n%s'], ...
        lin_iter, MAX_LIN_ITER, ...
        sum(sol.E_nom(:))*kW_per_pu, sum(sol.S_conv(:))*kW_per_pu, ...
        nnz(sol.Installation(:) > 1e-4), sol.optval, ...
        v_err*100, iter_solve_time(lin_iter), sol.status, ...
        i_err, i_err*Ib_A, ...
        i_err_amp*100, ...
        grid_params.CABLE_AMP(l_amp)*Ib_A, l_amp, ...
        gm_curr.grid.N1N2Y(l_amp,1), gm_curr.grid.N1N2Y(l_amp,2), t_amp, tech_lines);
    if verbose_debug; fprintf('%s\n', msg); end
    if ~isempty(log_fid); fprintf(log_fid, '%s\n', msg); end

    if sol.optval < best_cost
        best_cost      = sol.optval;
        best_cost_iter = lin_iter;
    end

    % -- track best solution (min linearisation error) ------------
    if v_err < best_volt_err
        best_volt_err = v_err;

        verif = struct( ...
            'dP_mat', dP_mat, 'dQ_mat', dQ_mat, ...
            'P0_mat', P0_mat, 'Q0_mat', Q0_mat, ...
            'V_lf',   V_lf,   'I_lf',   I_lf,   'S_lf', S_lf, ...
            'lf_converged', lf_converged, 'lf_num_iter', lf_num_iter);

        best_out = build_network_result(sol, sens, verif, gm_orig, dims, ...
            cfg, net_meta, lin_iter, v_err, i_err, prepros_time, ...
            iter_solve_time(lin_iter));

        if enable_plots
            analyze_tech_selection(best_out, cfg);
            analyze_losses(best_out, cfg)
            analyze_voltage_current(best_out);
            if opts.curtailment_activate
                analyze_curtailment(best_out, cfg);
            end
            analyze_charge_discharge_exclusivity(best_out, cfg);
            analyze_loadflow_convergence(best_out);
        end
    end

    % -- early exit if converged ----------------------------------
    if v_err < cfg.solver.VOLT_CONV_THRESH
        msg = sprintf('  Converged at iter %d (v_err=%.2e).', lin_iter, v_err);
        if verbose_debug; fprintf('%s\n', msg); end
        if ~isempty(log_fid); fprintf(log_fid, '%s\n', msg); end
        break
    end

    % -- re-linearise around updated operating point --------------
    % NOTE: re_linearization only re-derives the operating point from the
    % Nd-space (demand-node) injection P_inj; it does not fold PV curtailment
    % (or any Npv-only node) back in. Harmless while MAX_LIN_ITER stays 1
    % (the default), but a multi-iteration run would re-linearize around the
    % PRE-curtailment PV output on iteration 2+. Extending re_linearization.m
    % to accept an Npv-space update is out of scope here.
    if lin_iter < MAX_LIN_ITER
        P_inj   = complex(P0_mat + dP_mat, Q0_mat + dQ_mat);
        gm_curr = re_linearization(gm_curr.grid, P_inj, T, gm_curr.lm.keep_complex_I);
        prev.B_plus_prev  = round(sol.B_plus,  4);
        prev.B_minus_prev = round(sol.B_minus, 4);
        prev.Q_ess_prev   = round(sol.Q_ess,   4);
        prev.P_curt_prev  = round(sol.P_curt,  4);
    end

end  % sequential linearisation loop

% -----------------------------------------------------------------
%  FINALISE
% -----------------------------------------------------------------
if isempty(best_out)
    all_statuses = string(iter_status(~cellfun(@isempty, iter_status)));
    if any(all_statuses == "Suboptimal")
        status = 'subopt';
    else
        error('No valid CVX solution. Statuses: %s', ...
            strjoin(all_statuses, ', '));
    end
    return
end

n_ran = find(~isnan(iter_volt_error), 1, 'last');
if isempty(n_ran); n_ran = 0; end
best_out.summary.n_iters_run         = n_ran;
best_out.summary.best_cost_iter      = best_cost_iter;
best_out.diagnostics.iter_volt_error = iter_volt_error(1:n_ran);
best_out.diagnostics.iter_curr_error = iter_curr_error(1:n_ran);
best_out.diagnostics.iter_cost       = iter_cost(1:n_ran);
best_out.diagnostics.iter_status     = iter_status(1:n_ran);

status = 'solved';

end
