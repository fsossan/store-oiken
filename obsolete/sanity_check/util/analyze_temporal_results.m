function stats = analyze_temporal_results(output_dir, scenario_name)
fprintf('\n=== Temporal Results Analysis ===\n');

% Get all saved result files — filter out macOS metadata files
files = dir(fullfile(output_dir, '*_temporal.mat'));
% files = files([files.bytes] > 1000);
n_networks = length(files);
fprintf('Loading summaries from %d network files...\n', n_networks);

% Get configuration file
config = jsondecode(fileread('general_config.json'));

% Load SFOE allocation data
sc = load(sprintf('output/scenario_%s_allocation.mat', scenario_name));
all_alloc_ids = string(sc.combined_data.LV_grid_id);

% Demand factor
demand_factor = config.demand_level.demand_factor;

%% Preallocate summary arrays
has_violations    = false(n_networks, 1);
converged_all_net = false(n_networks, 1);
converged_pct_net = zeros(n_networks, 1);
n_undervolt       = zeros(n_networks, 1);
n_overvolt        = zeros(n_networks, 1);
n_overload        = zeros(n_networks, 1);
has_UV            = false(n_networks, 1);
has_OV            = false(n_networks, 1);
has_OL            = false(n_networks, 1);
V_min_all         = zeros(n_networks, 1);
V_max_all         = zeros(n_networks, 1);
has_congestion    = false(n_networks, 1);
n_congested       = zeros(n_networks, 1);
congested_hours   = zeros(n_networks, 1);
n_transformers    = zeros(n_networks, 1);
T_rat_kVA_total   = zeros(n_networks, 1);
network_ids       = cell(n_networks, 1);
PV_per_network    = zeros(n_networks, 1);
EV_per_network    = zeros(n_networks, 1);
demand_per_network = zeros(n_networks, 1);

%% Load per-network summaries
for i = 1:n_networks
    tmp = load(fullfile(output_dir, files(i).name), 'result');
    r = tmp.result;

    has_violations(i)    = r.has_violations;
    converged_all_net(i) = r.converged_all;
    converged_pct_net(i) = r.converged_pct;
    n_undervolt(i)       = r.n_undervolt_events;
    n_overvolt(i)        = r.n_overvolt_events;
    n_overload(i)        = r.n_overload_events;
    has_UV(i)            = r.n_undervolt_events > 0;
    has_OV(i)            = r.n_overvolt_events > 0;
    has_OL(i)            = r.n_overload_events > 0;
    V_min_all(i)         = r.V_min;
    V_max_all(i)         = r.V_max;
    has_congestion(i)  = r.has_congestion;
    n_congested(i)     = r.n_congested_events;
    congested_hours(i) = r.congested_hours;
    n_transformers(i)  = r.n_transformers;
    T_rat_kVA_total(i) = sum(r.T_rat_kVA);
    network_ids{i}       = r.network_id;

    % Match with SFOE allocation to get PV, EV and demand per network
    net_id = string(r.network_id);
    idx = find(strcmp(all_alloc_ids, net_id), 1);
    if ~isempty(idx)
        g = sc.combined_data.LV_grid{idx};
        PV_per_network(i)     = sum(g.PV_kW_);           % kWp 3-phase
        EV_per_network(i)     = sum(g.EV_count);          % count
        demand_per_network(i) = sum(g.PLmax_kW_) * demand_factor; % kW 3-phase
    end

    clear tmp r;
end

%% PV EV and demand split between violation and compliant networks
PV_violation  = sum(PV_per_network(has_violations));
PV_compliant  = sum(PV_per_network(~has_violations));
EV_violation  = sum(EV_per_network(has_violations));
EV_compliant  = sum(EV_per_network(~has_violations));
PV_total      = PV_violation + PV_compliant;
EV_total      = EV_violation + EV_compliant;
demand_total  = sum(demand_per_network);

%% Build stats struct
stats = struct();
stats.scenario_name          = scenario_name;
stats.n_networks             = n_networks;

% Demand in kW 3-phase (per network) and MW 3-phase (total)
stats.total_demand_kW             = demand_total;          % kW 3-phase
stats.total_demand_MW             = demand_total / 1e3;    % MW 3-phase

stats.n_converged_all             = sum(converged_all_net);
stats.n_non_converged             = sum(~converged_all_net);
stats.n_violations                = sum(has_violations);
stats.violation_pct               = 100 * stats.n_violations / n_networks;
stats.undervolt_networks          = sum(has_UV);
stats.overvolt_networks           = sum(has_OV);
stats.overload_networks           = sum(has_OL);
stats.total_undervolt_events      = sum(n_undervolt);
stats.total_overvolt_events       = sum(n_overvolt);
stats.total_overload_events       = sum(n_overload);
stats.congestion_networks         = sum(has_congestion);
stats.per_network.has_congestion  = has_congestion;
stats.per_network.n_congested     = n_congested;
stats.per_network.congested_hours = congested_hours;
stats.per_network.n_transformers  = n_transformers;
stats.per_network.T_rat_kVA_total = T_rat_kVA_total;
stats.avg_convergence_pct    = mean(converged_pct_net);
stats.min_convergence_pct    = min(converged_pct_net);

% PV in kWp 3-phase (per network) and MWp 3-phase (total)
stats.PV_total_kWp      = PV_total;
stats.PV_total_MWp      = PV_total / 1e3;
stats.PV_violation_kWp  = PV_violation;
stats.PV_compliant_kWp  = PV_compliant;

% EV counts
stats.EV_total          = EV_total;
stats.EV_violation      = EV_violation;
stats.EV_compliant      = EV_compliant;

% Network ID lists
stats.network_ids.all           = network_ids;
stats.network_ids.violations    = network_ids(has_violations);
stats.network_ids.healthy       = network_ids(~has_violations);
stats.network_ids.non_converged = network_ids(~converged_all_net);

% Per-network summary for markdown
stats.per_network.network_ids    = network_ids;
stats.per_network.has_violations = has_violations;
stats.per_network.converged_all  = converged_all_net;
stats.per_network.converged_pct  = converged_pct_net;
stats.per_network.has_UV         = has_UV;
stats.per_network.has_OV         = has_OV;
stats.per_network.has_OL         = has_OL;
stats.per_network.n_undervolt    = n_undervolt;
stats.per_network.n_overvolt     = n_overvolt;
stats.per_network.n_overload     = n_overload;
stats.per_network.V_min          = V_min_all;
stats.per_network.V_max          = V_max_all;
stats.per_network.PV_kWp         = PV_per_network;    % kWp 3-phase
stats.per_network.EV_count       = EV_per_network;    % count
stats.per_network.demand_kW      = demand_per_network; % kW 3-phase

% Store config
stats.config = config;

%% Print summary
fprintf('Networks analyzed:             %d\n', n_networks);
fprintf('Total demand (3-phase):        %.1f MW\n', stats.total_demand_MW);
fprintf('Total PV allocated:            %.1f MWp\n', stats.PV_total_MWp);
fprintf('Total EVs allocated:           %d\n', round(EV_total));
fprintf('Fully converged:               %d (%.1f%%)\n', stats.n_converged_all, ...
    100*stats.n_converged_all/n_networks);
fprintf('Non-converged:                 %d\n', stats.n_non_converged);
fprintf('Requiring reinforcement:       %d (%.1f%%)\n', ...
    stats.n_violations, stats.violation_pct);
fprintf('Meeting operational goals:     %d (%.1f%%)\n', ...
    n_networks - stats.n_violations, 100*(1-stats.violation_pct/100));
fprintf('\n--- Violation Breakdown ---\n');
fprintf('Undervoltage:  %d networks\n', stats.undervolt_networks);
fprintf('Overvoltage:   %d networks\n', stats.overvolt_networks);
fprintf('Line overload: %d networks\n', stats.overload_networks);
fprintf('Transformer congestion: %d networks\n', stats.congestion_networks);
fprintf('\n--- PV/EV Split ---\n');
fprintf('PV in violation networks:      %.1f MWp (%.1f%%)\n', ...
    PV_violation/1e3, 100*PV_violation/max(PV_total,1));
fprintf('PV in compliant networks:      %.1f MWp (%.1f%%)\n', ...
    PV_compliant/1e3, 100*PV_compliant/max(PV_total,1));
fprintf('EVs in violation networks:     %d (%.1f%%)\n', ...
    round(EV_violation), 100*EV_violation/max(EV_total,1));
fprintf('EVs in compliant networks:     %d (%.1f%%)\n', ...
    round(EV_compliant), 100*EV_compliant/max(EV_total,1));

%% Save
output_file = sprintf('output/scenario_%s/temporal_stats.mat', scenario_name);
save(output_file, 'stats');
fprintf('Statistics saved: %s\n', output_file);
end