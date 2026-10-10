function ctx = load_ess_selection_context(scenario)
% LOAD_ESS_SELECTION_CONTEXT  Load portfolio data, general/tech config, and
%                              the sane-network index list for a scenario.
%
%   ctx = load_ess_selection_context(scenario)
%
%   Input
%   -----
%   scenario : string   SFOE scenario name, e.g. 'sc1_2040' (a key of
%                       config/general_config.json "scenarios")
%
%   Output
%   ------
%   ctx : struct
%       .data_SFOE         struct   output of allocate_PV_EV_SFOE
%       .config            struct   general_config.json
%       .cfg               struct   output of load_ess_selection_config
%       .tech_names        cell     cfg.tech.names
%       .J                 scalar   number of technologies
%       .sane_net_indices  [n x 1]  indices into data_SFOE for networks with
%                                   converged temporal violations
%       .scenario          string
%       .paths             struct   project_paths() used for this context
%
%   All file locations come from project_paths (see data/README.md); nothing
%   here depends on the current directory. This function has no side effects
%   on disk: the PV/EV allocation is saved into the run folder by
%   run_ess_selection_portfolio instead.

paths = project_paths();

S    = load(paths.lv_grids_file, 'data');
data = S.data;

config = jsondecode(fileread(fullfile(paths.config, 'general_config.json')));

cfg = load_ess_selection_config( ...
    fullfile(paths.config, 'sizing_cfg.json'), ...
    fullfile(paths.config, 'technology_cfg.json'), ...
    config.PU_values.Sb);

data_SFOE = allocate_PV_EV_SFOE(data, scenario, config);

% Portfolio definition: networks whose base-case temporal load flow converged
% AND showed a violation. These lists are pre-computed per scenario in
% data/derived/ (see data/README.md). If no list exists for the requested
% scenario, fall back to the sc1_2040 list with a warning rather than using
% it silently -- that fallback is what the pre-restructure code always did.
viol_file = fullfile(paths.data_derived, sprintf('violation_ids_%s.mat', scenario));
if ~isfile(viol_file)
    fallback = fullfile(paths.data_derived, 'violation_ids_sc1_2040.mat');
    warning('load_ess_selection_context:violationListFallback', ...
        ['No violation list for scenario %s (looked for %s).\n' ...
         'Using the sc1_2040 list instead, so the "ALL" portfolio is the 2040 one.'], ...
        scenario, viol_file);
    viol_file = fallback;
end
V = load(viol_file);
temporal_violation_ids = V.viol_converged_single_tr_ids;

all_ids          = string(data_SFOE.LV_grid_id);
sane_net_indices = find(ismember(all_ids, temporal_violation_ids));

ctx.data_SFOE        = data_SFOE;
ctx.config           = config;
ctx.cfg              = cfg;
ctx.tech_names       = cfg.tech.names;
ctx.J                = cfg.J;
ctx.sane_net_indices = sane_net_indices;
ctx.scenario         = scenario;
ctx.paths            = paths;

end
