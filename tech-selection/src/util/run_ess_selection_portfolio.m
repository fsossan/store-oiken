function run_dir = run_ess_selection_portfolio(ctx, network_id, horizon, enable_plots, run_opts)
% RUN_ESS_SELECTION_PORTFOLIO  Loop the single-stage ESS technology-selection
%                                pipeline over one or more networks, saving
%                                every result into one run folder.
%
%   run_dir = run_ess_selection_portfolio(ctx, network_id, horizon, enable_plots, run_opts)
%
%   Inputs
%   ------
%   ctx          : struct    output of load_ess_selection_context
%   network_id   : string    "ALL" -> ctx.sane_net_indices (honoring
%                            run_opts.allow_mult_instances 4-way split), or a
%                            string array of LV_Grid ids resolved via ismember
%   horizon      : vector    optional timestep indices (see build_temporal_profiles);
%                            [] -> full day
%   enable_plots : logical   enable diagnostic figures
%   run_opts     : struct    .verbose_debug .skip_solved .MAX_LIN_ITER
%                            .allow_mult_instances .instance_id
%                            .run_dir (optional, see below)
%
%   Output
%   ------
%   run_dir : char   the folder everything was written to
%
%   Run folder layout
%   -----------------
%   results/<yyyymmdd_HHMMSS>_<scenario>/        (or run_opts.run_dir)
%       config_snapshot.json        cfg + general config + run_opts + git commit
%       allocation_<scenario>.mat   data_SFOE as used (PV/EV allocation)
%       run_log.txt                 (run_log_<k>.txt per multi-instance session)
%       solved/<LV_Grid_id>.mat     full `out` struct (incl. out.cfg)
%       thresh/<LV_Grid_id>.mat     voltage guard failed
%       subopt/<LV_Grid_id>.mat     only Suboptimal CVX solutions
%       error/<LV_Grid_id>.mat      uncaught exception
%       figures/                    temporal-profile PNGs (enable_plots)
%       all_dispatch_logs.mat       (all_dispatch_logs_<k>.mat per instance)
%       split_<k>.mat               multi-instance network splits
%
%   A new timestamped folder is created on every call unless run_opts.run_dir
%   names a folder: pass one to resume a run (together with skip_solved) or
%   to make the 4 multi-instance sessions write into the same place. Nothing
%   is ever overwritten across runs.

network_id = string(network_id);

if isfield(ctx, 'paths')
    paths = ctx.paths;
else
    paths = project_paths();
end

% =========================================================================
%  RUN FOLDER
% =========================================================================
if isfield(run_opts, 'run_dir') && ~isempty(run_opts.run_dir)
    run_dir = char(run_opts.run_dir);
else
    stamp   = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
    run_dir = fullfile(paths.results, sprintf('%s_%s', stamp, ctx.scenario));
end
d_solved  = fullfile(run_dir, 'solved');
d_thresh  = fullfile(run_dir, 'thresh');
d_subopt  = fullfile(run_dir, 'subopt');
d_error   = fullfile(run_dir, 'error');
d_figures = fullfile(run_dir, 'figures');
dirs = {run_dir, d_solved, d_thresh, d_subopt, d_error, d_figures};
for k = 1:numel(dirs)
    if ~isfolder(dirs{k}); mkdir(dirs{k}); end
end
run_opts.run_dir = run_dir;
fprintf('Run folder: %s\n', run_dir);

write_config_snapshot(run_dir, ctx, paths, network_id, horizon, enable_plots, run_opts);

alloc_file = fullfile(run_dir, sprintf('allocation_%s.mat', ctx.scenario));
if ~isfile(alloc_file)
    data_SFOE = ctx.data_SFOE;   %#ok<NASGU>
    scenario  = ctx.scenario;    %#ok<NASGU>
    save(alloc_file, 'data_SFOE', 'scenario');
end

% =========================================================================
%  RESOLVE NETWORKS  (+ optional 4-way multi-instance split)
% =========================================================================
if isscalar(network_id) && strcmpi(network_id, "ALL")
    net_indices = ctx.sane_net_indices;

    if run_opts.allow_mult_instances
        n      = numel(net_indices);
        splits = round(linspace(0, n, 5));
        for k = 1:4
            idx_chunk = net_indices(splits(k)+1 : splits(k+1)); %#ok<NASGU>
            save(fullfile(run_dir, sprintf('split_%d.mat', k)), 'idx_chunk');
        end
        S = load(fullfile(run_dir, sprintf('split_%d.mat', run_opts.instance_id)), 'idx_chunk');
        net_indices = S.idx_chunk;
    end
else
    net_indices = find(ismember(ctx.data_SFOE.LV_grid_id, network_id));
end

% =========================================================================
%  LOG FILE
% =========================================================================
if run_opts.allow_mult_instances
    log_fname = fullfile(run_dir, sprintf('run_log_%d.txt', run_opts.instance_id));
else
    log_fname = fullfile(run_dir, 'run_log.txt');
end
log_fid = fopen(log_fname, 'a');   % append: a resumed run keeps its history
if log_fid < 0
    error('run_ess_selection_portfolio:logOpen', 'Cannot open log file %s', log_fname);
end
fprintf(log_fid, '=== %s  scenario=%s  networks=%d ===\n', ...
    char(datetime('now')), ctx.scenario, numel(net_indices));
run_opts.log_fid = log_fid;

% =========================================================================
%  MAIN LOOP
% =========================================================================
t_tot             = tic;
iter_count        = 0;
all_dispatch_logs = {};
all_dispatch_ids  = {};

for n_idx = net_indices(:).'
    iter_count = iter_count + 1;
    net_id  = string(ctx.data_SFOE.LV_grid_id{n_idx});
    net_num = str2double(regexp(net_id, '\d+', 'match', 'once'));

    fprintf('Running network %d / %d : %s\n', iter_count, numel(net_indices), net_id);
    fprintf(log_fid, 'START  %s\n', net_id);

    fname_solved = fullfile(d_solved, net_id + ".mat");
    if run_opts.skip_solved && isfile(fname_solved)
        fprintf(log_fid, 'SKIP  %s  (already solved)\n', net_id);
        continue
    end

    try
        [status, result] = solve_network_tech_selection( ...
            ctx, n_idx, horizon, enable_plots, run_opts);

        switch status
            case 'thresh'
                msg = sprintf('  [THRESH] Voltage out of bounds (%.3f - %.3f pu)', ...
                    result.Vmag0_min, result.Vmag0_max);
                if run_opts.verbose_debug; fprintf('%s\n', msg); end
                thresh_out.network_id = string(net_num);
                thresh_out.Vmag0_min  = result.Vmag0_min;
                thresh_out.Vmag0_max  = result.Vmag0_max;
                save(fullfile(d_thresh, net_id + ".mat"), 'thresh_out');
                fprintf(log_fid, 'THRESH  %s  Vmin=%.4f  Vmax=%.4f\n', ...
                    net_id, result.Vmag0_min, result.Vmag0_max);

            case 'subopt'
                subopt_out.network_id  = string(net_num);
                subopt_out.iter_status = result.iter_status;
                subopt_out.error_msg   = 'All iterations Suboptimal';
                save(fullfile(d_subopt, net_id + ".mat"), 'subopt_out');
                fprintf(log_fid, 'SUBOPTIMAL  %s\n', net_id);

            case 'solved'
                out     = result.out;
                out.cfg = ctx.cfg;   % embed the exact cfg used, so saved
                                     % results are reusable by analyze_*
                                     % without depending on the live state
                                     % of the JSON config files
                out.meta.run_dir = run_dir;

                % cfg.flags.save_opf_output (default true if absent) gates
                % writing the full `out` struct (incl. out.gm, which dominates
                % file size). false is for e.g. a fast sweep over many
                % networks/seeds where only the log-line summary matters.
                save_output = ~isfield(ctx.cfg.flags, 'save_opf_output') || ctx.cfg.flags.save_opf_output;
                if save_output
                    save(fname_solved, '-struct', 'out');
                    save_note = '';
                else
                    save_note = '  (not saved: save_opf_output=false)';
                end

                fprintf(log_fid, ...
                    'SOLVED  %s  status=%s  E=%.4f  S=%.4f  best_iter=%d  cost_iter=%d  n_iter=%d  v_err=%.2e  t=%.1fs%s\n', ...
                    net_id, out.summary.cvx_status, ...
                    out.summary.E_nom_total_pu, out.summary.S_conv_total_pu, ...
                    out.summary.best_iter, out.summary.best_cost_iter, ...
                    out.summary.n_iters_run, out.summary.volt_error, ...
                    out.summary.solve_time_s, save_note);

                all_dispatch_logs{end+1} = result.dispatch_log; %#ok<AGROW>
                all_dispatch_ids{end+1}  = net_id;              %#ok<AGROW>
        end

    catch ME
        fprintf(2, 'FAILED %s: %s\n', net_id, ME.message);
        fail_out.network_id = string(net_num);
        fail_out.error_msg  = ME.message;
        fail_out.error_id   = ME.identifier;
        fail_out.stack      = ME.stack;
        fail_out.cvx_status = "none";
        save(fullfile(d_error, net_id + ".mat"), 'fail_out');
        fprintf(log_fid, 'FAILED  %s  %s\n', net_id, ME.message);
        cvx_clear;
        continue
    end

end  % main loop

% =========================================================================
%  POST-LOOP
% =========================================================================
if run_opts.allow_mult_instances
    dl_name = sprintf('all_dispatch_logs_%d.mat', run_opts.instance_id);
else
    dl_name = 'all_dispatch_logs.mat';
end
save(fullfile(run_dir, dl_name), 'all_dispatch_logs', 'all_dispatch_ids');
fprintf('\nsaved %s\n', fullfile(run_dir, dl_name));
fclose(log_fid);
fprintf('\nTotal elapsed time: %.1f s\n', toc(t_tot));
fprintf('Results in: %s\n', run_dir);

end

% =========================================================================
function write_config_snapshot(run_dir, ctx, paths, network_id, horizon, enable_plots, run_opts)
% Freeze everything that determined this run next to its results.
snap = struct();
snap.created        = char(datetime('now'));
snap.scenario       = ctx.scenario;
snap.network_id     = cellstr(network_id);
snap.horizon        = horizon;
snap.enable_plots   = enable_plots;
snap.run_opts       = rmfield_if(run_opts, 'log_fid');
snap.cfg            = ctx.cfg;        % sizing_cfg.json + technology_cfg.json, normalized
snap.general_config = ctx.config;     % general_config.json
snap.matlab_version = version;
snap.git_commit     = git_commit_hash(paths.root);

fname = fullfile(run_dir, 'config_snapshot.json');
if isfile(fname)
    % Resumed / multi-instance run: keep the first snapshot, add this call's.
    fname = fullfile(run_dir, sprintf('config_snapshot_%s.json', ...
        char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'))));
end
fid = fopen(fname, 'w');
if fid < 0
    warning('run_ess_selection_portfolio:snapshot', 'Could not write %s', fname);
    return
end
fprintf(fid, '%s\n', jsonencode(snap, 'PrettyPrint', true));
fclose(fid);
end

function s = rmfield_if(s, f)
if isfield(s, f); s = rmfield(s, f); end
end

function h = git_commit_hash(root)
% Short commit hash of the code that produced the run, '' if git/repo unavailable.
h = '';
try
    [st, txt] = system(sprintf('git -C "%s" rev-parse --short HEAD', root));
    if st == 0; h = strtrim(txt); end
    [st, txt] = system(sprintf('git -C "%s" status --porcelain --untracked-files=no', root));
    if st == 0 && ~isempty(strtrim(txt)); h = [h ' (dirty)']; end
catch
end
end
