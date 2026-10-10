function results = screen_crate_need(network_id, ev_offsets, scenario)
% SCREEN_CRATE_NEED  Cheap, pre-OPF screen for which EV seed_offset is most
%   likely to genuinely need a high-C-rate technology (NaIon) once actually
%   solved -- no MILP, and calls generate_ev_profile directly (NOT
%   build_temporal_profiles) so it never touches the ~47s demand GMM fit.
%   Screens EV seed_offset only, at demand's default profile.
%
%   Rationale: C-rate need is driven by how PEAKY the power requirement is
%   relative to its own energy content -- a short simultaneous-arrival spike
%   needs high power for little energy (high peak/average ratio); a smooth,
%   spread-out profile needs the opposite. This screens on the EV stream's
%   own peak-to-average ratio at each multi-EV node, with realistic staggered
%   arrivals (synchronized_arrivals is NOT used here -- this is meant to find
%   a natural seed combination, not force one).
%
%   results = screen_crate_need('LV_Grid_230', 1000:2000)
%
%   Output: struct array, one row per ev_offset, sorted by descending max
%   per-node peak/average ratio (score). Score is a SCREENING HEURISTIC, not
%   a guarantee -- verify top candidates with a real solve before trusting
%   the technology-selection outcome.

this_dir  = fileparts(mfilename('fullpath'));
repo_root = fileparts(this_dir);
addpath(repo_root);
proj = setup_paths();   % src/ on the path + project folder layout (proj.results, ...)

if nargin < 3 || isempty(scenario); scenario = 'sc1_2040'; end

ctx = load_ess_selection_context(scenario);
n_idx = find(ismember(string(ctx.data_SFOE.LV_grid_id), network_id), 1);
grid = get_grid_SFOE(ctx.data_SFOE, n_idx, ctx.config);

% Single-EV nodes are a degenerate case: peak/average of one lone vehicle's
% own flat-4h profile is ALWAYS the same fixed ratio (steps_per_day /
% charging-duration-in-steps, e.g. 96/16=6) regardless of seed -- not
% seed-informative. Only multi-EV nodes vary with how much their several
% vehicles' independent arrivals happen to overlap. Restrict the score to
% those (and to the counts themselves, for calling generate_ev_profile
% directly below).
nodes_with_EV  = grid.nodal_N_EV > 0;
node_ev_counts = grid.nodal_N_EV(nodes_with_EV);
multi_ev_cols  = find(node_ev_counts > 1);
if isempty(multi_ev_cols)
    error('screen_crate_need:noMultiEVNode', ...
        '%s has no multi-EV node -- nothing for this screen to search over.', network_id);
end
fprintf('%s: %d EV-hosting nodes, %d with >1 EV (columns %s, counts %s) -- scoring only those\n', ...
    network_id, numel(node_ev_counts), numel(multi_ev_cols), mat2str(multi_ev_cols'), ...
    mat2str(node_ev_counts(multi_ev_cols)'));

ev_params = struct('enabled', true, 'charger_kw', 11, 'synchronized_arrivals', false);
results = struct([]);
for e_off = ev_offsets
    [X_kw, ~] = generate_ev_profile(node_ev_counts, 1, ev_params, e_off);   % [Nev x S x 1]
    EV_pu = squeeze(X_kw(multi_ev_cols, :, 1));   % [n_multi x S]
    if size(EV_pu,1) ~= numel(multi_ev_cols); EV_pu = EV_pu.'; end
    peak = max(abs(EV_pu), [], 2);
    avg  = mean(abs(EV_pu), 2);
    ratio = peak ./ max(avg, eps);
    [best_ratio, best_idx] = max(ratio);
    best_node = multi_ev_cols(best_idx);

    row = struct('ev_offset', e_off, 'max_ratio', best_ratio, ...
        'worst_node_col', best_node, 'n_multi_ev_nodes', numel(multi_ev_cols));
    if isempty(results); results = row; else; results(end+1) = row; end %#ok<AGROW>
end

[~, ord] = sort([results.max_ratio], 'descend');
results = results(ord);

fprintf('\n=== Top 10 ev_offset by peak/average EV ratio (node col, count) ===\n');
for k = 1:min(10, numel(results))
    fprintf('  ev_offset=%-6d  max_ratio=%.3f  (node col %d)\n', ...
        results(k).ev_offset, results(k).max_ratio, results(k).worst_node_col);
end
fprintf('(theoretical max for full overlap: steps_per_day/charging_duration_steps -- e.g. 96/16=6 at 15-min steps)\n');

out_dir = fullfile(proj.results, 'experiments');
if ~isfolder(out_dir); mkdir(out_dir); end
save(fullfile(out_dir, 'screen_crate_need_results.mat'), 'results');
end
