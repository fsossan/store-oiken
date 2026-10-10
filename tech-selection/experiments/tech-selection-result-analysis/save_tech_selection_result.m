function out = save_tech_selection_result(network_id, horizon, enable_plots, run_opts, scenario, results_dir)
% SAVE_TECH_SELECTION_RESULT  Solve one network's ESS technology-selection
%                              problem and save a self-contained per-network
%                              result file for the standalone analysis
%                              directory (experiments/tech-selection-result-analysis).
%
%   out = save_tech_selection_result(network_id, horizon, enable_plots, run_opts, scenario, results_dir)
%
%   Same single-network call chain as util/run_ess_selection_portfolio.m
%   (load_ess_selection_context -> solve_network_tech_selection), but:
%     - runs exactly one network, no log file, no portfolio loop
%     - embeds the exact cfg used (ctx.cfg) as out.cfg before saving, so
%       analyze_*(out, cfg) functions can be re-run later without depending
%       on the live state of sizing_cfg.json / technology_cfg.json
%     - saves via save(fname, '-struct', out), the same pattern already used
%       for output/OPF_result/out_dir_solved/<net_num>-tech-selec-res.mat --
%       every field of
%       `out` (including the new .cfg) becomes its own top-level variable in
%       the .mat file, so a later load(fname, 'sizing', 'costs', ...) can
%       selectively skip the large out.gm field instead of loading it every time.
%
%   Inputs
%   ------
%   network_id   : string    e.g. "LV_Grid_230"
%   horizon      : vector    [] = full day; see build_temporal_profiles
%   enable_plots : logical   forwarded to solve_network_tech_selection (the
%                            pipeline's own temporal-profile figure only --
%                            use run_analysis.m for the analyze_* figures)
%   run_opts     : struct    .verbose_debug .MAX_LIN_ITER (see solve_network_tech_selection)
%   scenario     : string    optional, default 'sc1_2040'
%   results_dir  : string    optional, default
%                            results/experiments/tech-selection-result-analysis/results/
%
%   Output
%   ------
%   out : struct   the same result struct written to disk (out.cfg included)

if nargin < 5 || isempty(scenario)
    scenario = 'sc1_2040';
end
if nargin < 6 || isempty(results_dir)
    proj        = project_paths();
    results_dir = fullfile(proj.results, 'experiments', 'tech-selection-result-analysis', 'results');
end
if ~exist(results_dir, 'dir')
    mkdir(results_dir);
end

net_id  = string(network_id);
net_num = str2double(regexp(net_id, '\d+', 'match', 'once'));
fname   = fullfile(results_dir, sprintf('%d-tech-selec-res.mat', net_num));

if ~isfield(run_opts, 'log_fid')
    % run_seq_lin_loop_ess.m reads run_opts.log_fid unconditionally; the
    % portfolio wrapper (run_ess_selection_portfolio.m) normally sets this to
    % an open file handle, but a standalone caller has no log file -- []
    % skips file logging (see solve_network_tech_selection.m's docstring).
    run_opts.log_fid = [];
end

ctx   = load_ess_selection_context(scenario);
n_idx = find(ismember(ctx.data_SFOE.LV_grid_id, net_id));
if isempty(n_idx)
    error('save_tech_selection_result:netNotFound', ...
        'Network %s not found in ctx.data_SFOE.LV_grid_id.', net_id);
end

[status, result] = solve_network_tech_selection(ctx, n_idx, horizon, enable_plots, run_opts);

if ~strcmp(status, 'solved')
    error('save_tech_selection_result:notSolved', ...
        'Network %s did not reach a solved state (status=%s).', net_id, status);
end

out     = result.out;
out.cfg = ctx.cfg;

save(fname, '-struct', 'out');
fprintf('Saved %s\n', fname);

end
