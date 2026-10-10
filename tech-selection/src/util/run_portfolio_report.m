function [tbl, out_dir] = run_portfolio_report(scenario, network_id, opts)
%RUN_PORTFOLIO_REPORT  Stage-1 report: topology, installed capacity, peak
%                      demand / PV / EV and net transformer loading per
%                      network, from the nodal injections alone (no load flow).
%
%   tbl = run_portfolio_report('sc1_2030')                        % every network in the grid file
%   tbl = run_portfolio_report('sc1_2030', "PORTFOLIO")           % the violation-flagged portfolio
%   tbl = run_portfolio_report('sc1_2030', ["LV_Grid_101","LV_Grid_230"])
%   [tbl, out_dir] = run_portfolio_report(scenario, network_id, opts)
%
%   opts : .plots (default true)  portfolio histograms PNG
%          .verbose (true)        one line per network
%          .out_dir ('')          default results/report/<timestamp>_<scenario>/
%          .profile_params        struct with .demand/.pv/.ev overrides merged over
%                                 the config blocks (e.g. demand.enabled = false)
%
%   Writes into out_dir:
%       portfolio_report.csv / .mat   one row per network (see summarize_network_injections)
%       config_snapshot.json          configs + selection, for provenance
%       portfolio_histograms.png      if opts.plots and more than one network
%   A network that fails anywhere (grid construction, profile generation) gets
%   a row with status "error: ..." and NaNs; the loop continues.
%
%   The injections are built by the same code and seeds the MILP uses
%   (build_nodal_injections), so these numbers describe exactly what a solve
%   of the same scenario would see. With the demand GMM cached
%   (data/derived/load_gmm/) a network takes well under a second.

if nargin < 1 || isempty(scenario);   scenario   = 'sc1_2030'; end
if nargin < 2 || isempty(network_id); network_id = "ALL";      end
if nargin < 3 || isempty(opts);       opts       = struct();   end
opts = set_default(opts, 'plots',   true);
opts = set_default(opts, 'verbose', true);
opts = set_default(opts, 'out_dir', '');

network_id = string(network_id);
ctx = load_ess_selection_context(scenario);
ctx.config.visualization.plot_topology = false;   % no per-network topology figure

all_ids = string(ctx.data_SFOE.LV_grid_id);
if isscalar(network_id) && strcmpi(network_id, "ALL")
    idx = 1:numel(all_ids);
elseif isscalar(network_id) && strcmpi(network_id, "PORTFOLIO")
    idx = ctx.sane_net_indices(:).';
else
    idx = find(ismember(all_ids, network_id)).';
    missing = network_id(~ismember(network_id, all_ids));
    if ~isempty(missing)
        warning('run_portfolio_report:unknownIds', 'Unknown network id(s): %s', strjoin(missing, ', '));
    end
end
if isempty(idx)
    error('run_portfolio_report:noNetworks', 'No networks selected.');
end

out_dir = opts.out_dir;
if isempty(out_dir)
    stamp   = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
    out_dir = fullfile(ctx.paths.results, 'report', sprintf('%s_%s', stamp, scenario));
end
if ~isfolder(out_dir); mkdir(out_dir); end

profile_params = struct();
if isfield(ctx.cfg, 'demand_profile'); profile_params.demand = ctx.cfg.demand_profile; end
if isfield(ctx.cfg, 'pv_profile');     profile_params.pv     = ctx.cfg.pv_profile;     end
if isfield(ctx.cfg, 'ev_profile');     profile_params.ev     = ctx.cfg.ev_profile;     end
% opts.profile_params: optional overrides merged field by field over the config
% blocks, e.g. struct('demand', struct('enabled', false)) for a PV/EV-only report.
if isfield(opts, 'profile_params') && ~isempty(opts.profile_params)
    for s = {'demand', 'pv', 'ev'}
        s = s{1};
        if isfield(opts.profile_params, s)
            if ~isfield(profile_params, s); profile_params.(s) = struct(); end
            ov = opts.profile_params.(s);
            fn = fieldnames(ov);
            for q = 1:numel(fn); profile_params.(s).(fn{q}) = ov.(fn{q}); end
        end
    end
end
D   = ctx.cfg.horizon.days;
spd = ctx.cfg.horizon.steps_per_day;

template = summarize_network_injections([], [], ctx.cfg);
rows     = repmat(template, numel(idx), 1);
n_err    = 0;
t0       = tic;
for k = 1:numel(idx)
    n_idx  = idx(k);
    net_id = all_ids(n_idx);
    if opts.verbose; fprintf('[%4d/%4d] %s\n', k, numel(idx), net_id); end
    try
        grid = get_grid_SFOE(ctx.data_SFOE, n_idx, ctx.config);
        inj  = build_nodal_injections(grid, [], D, spd, profile_params);
        row  = summarize_network_injections(grid, inj, ctx.cfg);
    catch ME
        n_err = n_err + 1;
        row = template;
        row.net_id  = net_id;
        row.net_num = str2double(regexp(net_id, '\d+', 'match', 'once'));
        row.status  = "error: " + string(ME.message);
        fprintf(2, '  FAILED %s: %s\n', net_id, ME.message);
    end
    row.scenario = string(scenario);
    rows(k) = row;
end
elapsed = toc(t0);

tbl = struct2table(rows);
writetable(tbl, fullfile(out_dir, 'portfolio_report.csv'));
save(fullfile(out_dir, 'portfolio_report.mat'), 'tbl', 'scenario');

snap = struct('created', char(datetime('now')), 'scenario', scenario, ...
    'n_networks', numel(idx), 'selection', {cellstr(network_id)}, ...
    'cfg', ctx.cfg, 'general_config', ctx.config, 'matlab_version', version);
fid = fopen(fullfile(out_dir, 'config_snapshot.json'), 'w');
if fid > 0
    fprintf(fid, '%s\n', jsonencode(snap, 'PrettyPrint', true));
    fclose(fid);
end

ok = tbl.status == "ok";
fprintf('\nPortfolio report: %d networks, %d failed, %.0f s -> %s\n', numel(idx), n_err, elapsed, out_dir);
if any(ok)
    fprintf('  median demand peak / trafo rating : %.3f\n', median(tbl.demand_peak_over_trafo(ok)));
    fprintf('  median PV kWp / demand peak       : %.3f\n', median(tbl.pv_kWp_over_demand_peak(ok)));
    fprintf('  networks with any EV              : %d\n', nnz(tbl.ev_count(ok) > 0));
    fprintf('  networks with reverse flow        : %d\n', nnz(tbl.net_peak_export_kW(ok) > 0));
    fprintf('  slack not internal node 1         : %d\n', nnz(~tbl.slack_is_node1(ok)));
end

if opts.plots && nnz(ok) > 1
    plot_portfolio_histograms(tbl(ok, :), scenario, out_dir);
end
end

% =========================================================================
function plot_portfolio_histograms(t, scenario, out_dir)
fig = figure('Name', 'Portfolio report', 'Color', 'w', 'Visible', 'off');
tiledlayout(2, 3, 'Padding', 'compact', 'TileSpacing', 'compact');
hist_panel(t.demand_peak_over_trafo,  'Demand peak / transformer rating [-]');
hist_panel(t.pv_kWp_over_demand_peak, 'PV kWp / demand peak [-]');
hist_panel(t.ev_count,                'EVs per network [-]');
hist_panel(t.net_peak_over_trafo,     'Net peak (import or export) / rating [-]');
hist_panel(t.demand_peak_kW,          'Demand peak [kW]');
hist_panel(t.n_nodes,                 'Nodes per network [-]');
sgtitle(sprintf('Portfolio report, scenario %s, %d networks', strrep(scenario, '_', '\_'), height(t)), ...
    'FontWeight', 'bold');
saveas(fig, fullfile(out_dir, 'portfolio_histograms.png'));
close(fig);
end

function hist_panel(x, label)
nexttile;
x = x(isfinite(x));
histogram(x);
xlabel(label); ylabel('networks'); grid on;
end
