function [status, result] = solve_network_tech_selection(ctx, n_idx, horizon, enable_plots, run_opts)
% SOLVE_NETWORK_TECH_SELECTION  Run the single-stage ESS technology-selection
%                                pipeline for one network. No file I/O.
%
%   [status, result] = solve_network_tech_selection(ctx, n_idx, horizon, enable_plots, run_opts)
%
%   Inputs
%   ------
%   ctx          : struct   output of load_ess_selection_context
%   n_idx        : int      index into ctx.data_SFOE for this network
%   horizon      : vector   optional timestep indices (see build_temporal_profiles);
%                           [] -> full day
%   enable_plots : logical  enable temporal-profile / tech-selection / losses figures
%   run_opts     : struct   .MAX_LIN_ITER .verbose_debug .log_fid .run_dir
%                           (.run_dir: run folder; temporal-profile PNGs go to
%                           <run_dir>/figures, or results/figures_adhoc if absent)
%                           (.log_fid may be [] to skip file logging)
%
%   Outputs
%   -------
%   status : 'thresh' | 'subopt' | 'solved'
%   result : struct, contents depend on status
%       'thresh' : .net_id .net_num .Vmag0_min .Vmag0_max
%       'subopt' : .net_id .net_num .iter_status
%       'solved' : .net_id .net_num .out .dispatch_log
%
%   Uncaught errors (e.g. no valid CVX solution at all) propagate to the
%   caller, matching the pre-refactor main.m behaviour where the per-network
%   try/catch lived at the portfolio-loop level.

net_id  = string(ctx.data_SFOE.LV_grid_id{n_idx});
net_num = str2double(regexp(net_id, '\d+', 'match', 'once'));
rng(1234 + net_num);

% -----------------------------------------------------------------
%  PREPROCESSING
% -----------------------------------------------------------------
t_prepros     = tic;
[gm, dims, ~] = preprocess_network(ctx.data_SFOE, n_idx, ctx.config, ctx.cfg, horizon);

if enable_plots
    if isfield(run_opts, 'run_dir') && ~isempty(run_opts.run_dir)
        fig_dir = fullfile(run_opts.run_dir, 'figures');
    else
        % standalone call (e.g. from experiments/): keep figures out of the source tree
        pp      = project_paths();
        fig_dir = fullfile(pp.results, 'figures_adhoc');
    end
    plot_gm_temporal_profiles(gm, net_id, ctx.scenario, fig_dir);
end
prepros_time = toc(t_prepros);

grid_params = struct( ...
    'R_TNd_toNdT',         dims.R_TNd_toNdT, ...
    'CABLE_AMP',           dims.CABLE_AMP, ...
    'slack_S_mag_pu',      dims.slack_S_mag_pu, ...
    'R_TNpv_toNpvT',       dims.R_TNpv_toNpvT, ...
    'PV_avail_pu_stacked', dims.PV_avail_pu_stacked);

opts = struct( ...
    'current_mag_cstr',     ctx.cfg.solver.current_mag_cstr, ...
    'siting_activate',      ctx.cfg.flags.siting_activate, ...
    'cha_dis_bin_activate', ctx.cfg.flags.cha_dis_bin_activate, ...
    'min_loss',             ctx.cfg.flags.min_loss, ...
    'curtailment_activate', ctx.cfg.flags.curtailment_activate, ...
    'throughput_penalty',   ctx.cfg.flags.throughput_penalty, ...
    'one_tech_per_node',    ctx.cfg.flags.one_tech_per_node, ...
    'lossless_bess',        ctx.cfg.flags.lossless_bess);

% -----------------------------------------------------------------
%  VOLTAGE GUARD
% -----------------------------------------------------------------
vguard = check_voltage_guard(gm, ctx.cfg);
if ~vguard.passed
    status = 'thresh';
    result.net_id    = net_id;
    result.net_num   = net_num;
    result.Vmag0_min = vguard.Vmag0_min;
    result.Vmag0_max = vguard.Vmag0_max;
    return
end

% -----------------------------------------------------------------
%  BASE OPERATING POINT VIOLATIONS (no ESS) -- what storage must fix
% -----------------------------------------------------------------
log_fid = [];
if isfield(run_opts, 'log_fid'), log_fid = run_opts.log_fid; end
report_violations(lm_stack(gm.lm.Vmag0), lm_stack(gm.lm.Imag0), gm.grid, ctx.cfg, ...
    "base operating point, " + net_id, log_fid);

% -----------------------------------------------------------------
%  SEQUENTIAL LINEARISATION LOOP
% -----------------------------------------------------------------
net_meta.scenario     = ctx.scenario;
net_meta.net_id       = net_id;
net_meta.net_num      = net_num;
net_meta.tech_names   = ctx.tech_names;
net_meta.MAX_LIN_ITER = run_opts.MAX_LIN_ITER;

loop_run_opts              = run_opts;
loop_run_opts.enable_plots = enable_plots;

[status, best_out, dispatch_log, iter_status] = run_seq_lin_loop_ess( ...
    gm, dims, grid_params, opts, ctx.cfg, net_meta, prepros_time, loop_run_opts);

switch status
    case 'solved'
        result.net_id       = net_id;
        result.net_num      = net_num;
        result.out          = best_out;
        result.dispatch_log = dispatch_log;
    case 'subopt'
        result.net_id       = net_id;
        result.net_num      = net_num;
        result.iter_status  = iter_status;
end

end
