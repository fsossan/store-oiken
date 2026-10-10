function results = find_small_multitech_network(nd_range, max_candidates, scenario)
% FIND_SMALL_MULTITECH_NETWORK  Scan the sane portfolio for a network small
%   enough (Nd in nd_range) to solve quickly, where technology selection
%   actually picks NaIon somewhere (i.e. high C-rate is genuinely needed,
%   not just LiIon everywhere) -- a good fast test case for future
%   tech-selection studies.
%
%   results = find_small_multitech_network()                    % Nd in [10,20]
%   results = find_small_multitech_network(nd_range, max_candidates, scenario)
%
%   Two-stage scan to keep this fast:
%     Stage 1 (cheap): get_grid_SFOE per network (one load flow, no MILP) to
%       read Nd = sum(nodal_nominal_power>0) -- filters the sane portfolio
%       down to the size range before doing anything expensive.
%     Stage 2 (real solve): for up to max_candidates size-matching networks,
%       run the actual tech-selection MILP (demand+PV+EV, 1 day, LiIon+NaIon
%       both available, live sizing_cfg.json settings otherwise) and check
%       whether NaIon appears in the solved Installation matrix.
%
%   Output
%   ------
%   results : struct array over stage-2 candidates, fields:
%       .net_id .Nd .status .solve_time_s .naion_selected .installed_techs
%       .n_installed_nodes .total_cost_kCHF (NaN if not solved)

if nargin < 1 || isempty(nd_range);       nd_range = [10 20]; end
if nargin < 2 || isempty(max_candidates); max_candidates = 15; end
if nargin < 3 || isempty(scenario);       scenario = 'sc1_2040'; end

this_dir  = fileparts(mfilename('fullpath'));
repo_root = fileparts(this_dir);
addpath(repo_root);
proj = setup_paths();   % src/ on the path + project folder layout (proj.results, ...)

ctx = load_ess_selection_context(scenario);
net_indices = ctx.sane_net_indices(:).';
fprintf('Scanning %d sane networks for Nd in [%d, %d]...\n', numel(net_indices), nd_range(1), nd_range(2));

% ---- Stage 1: cheap size filter ----
candidate_idx = [];
candidate_Nd  = [];
t0 = tic;
for n_idx = net_indices
    try
        g = get_grid_SFOE(ctx.data_SFOE, n_idx, ctx.config);
        Nd = sum(g.nodal_nominal_power > 0);
        if Nd >= nd_range(1) && Nd <= nd_range(2)
            candidate_idx(end+1) = n_idx; %#ok<AGROW>
            candidate_Nd(end+1)  = Nd;    %#ok<AGROW>
        end
    catch
        continue
    end
end
fprintf('Stage 1 done in %.1fs: %d candidates in size range (out of %d scanned)\n', ...
    toc(t0), numel(candidate_idx), numel(net_indices));

if isempty(candidate_idx)
    results = struct([]);
    return
end

if numel(candidate_idx) > max_candidates
    candidate_idx = candidate_idx(1:max_candidates);
    candidate_Nd  = candidate_Nd(1:max_candidates);
end

% ---- Stage 2: real tech-selection solve on each size-matching candidate ----
run_opts = struct('MAX_LIN_ITER', 1, 'verbose_debug', false, 'log_fid', []);
results = struct([]);

for k = 1:numel(candidate_idx)
    n_idx = candidate_idx(k);
    net_id = string(ctx.data_SFOE.LV_grid_id{n_idx});
    fprintf('\n--- [%d/%d] %s (Nd=%d) ---\n', k, numel(candidate_idx), net_id, candidate_Nd(k));

    row = struct('net_id', net_id, 'Nd', candidate_Nd(k), 'status', "", ...
        'solve_time_s', NaN, 'naion_selected', false, 'installed_techs', {{}}, ...
        'n_installed_nodes', 0, 'total_cost_kCHF', NaN);

    t1 = tic;
    try
        [status, result] = solve_network_tech_selection(ctx, n_idx, [], false, run_opts);
        row.status = string(status);
        row.solve_time_s = toc(t1);

        if strcmp(status, 'solved')
            out = result.out;
            I_inst = out.sizing.Installation;
            tech_names = out.sizing.tech_names;
            [~, j_] = find(I_inst);
            installed = unique(tech_names(j_));
            row.installed_techs = installed;
            row.naion_selected = any(strcmp(installed, 'NaIon'));
            row.n_installed_nodes = numel(find(any(I_inst,2)));
            row.total_cost_kCHF = out.costs.total / 1000;
            fprintf('  status=solved  t=%.1fs  installed_techs=%s  NaIon selected? %d\n', ...
                row.solve_time_s, strjoin(installed, ','), row.naion_selected);
        else
            fprintf('  status=%s  t=%.1fs\n', status, row.solve_time_s);
        end
    catch ME
        row.status = "error";
        row.solve_time_s = toc(t1);
        fprintf('  ERROR: %s\n', ME.message);
    end

    if isempty(results); results = row; else; results(end+1) = row; end %#ok<AGROW>
end

fprintf('\n=== Summary: networks with NaIon selected (Nd %d-%d) ===\n', nd_range(1), nd_range(2));
for k = 1:numel(results)
    if results(k).naion_selected
        fprintf('  %s  Nd=%d  t=%.1fs  techs=%s  total=%.2f kCHF\n', ...
            results(k).net_id, results(k).Nd, results(k).solve_time_s, ...
            strjoin(results(k).installed_techs, ','), results(k).total_cost_kCHF);
    end
end

out_dir = fullfile(proj.results, 'experiments');
if ~isfolder(out_dir); mkdir(out_dir); end
save(fullfile(out_dir, 'find_small_multitech_network_results.mat'), 'results');
end
