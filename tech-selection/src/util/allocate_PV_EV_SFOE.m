function combined_data = allocate_PV_EV_SFOE(combined_data, scenario_name, config)
%ALLOCATE_PV_EV_SFOE Allocate PV and EV based on SFOE scenarios
%
%   combined_data = allocate_PV_EV_SFOE(combined_data, 'sc1_2040')
%   combined_data = allocate_PV_EV_SFOE(combined_data, 'sc1_2040', config)
%
%   config : struct, optional -- decoded general_config.json. Loaded from
%            config/general_config.json (via project_paths) when omitted.
%
%   No file output: the caller (run_ess_selection_portfolio) saves the
%   allocation it used into the run folder as allocation_<scenario>.mat.
%
% Allocates PV and EV to all LV networks based on:
%   - National -> Sion+Sierre: population ratio
%   - Sion+Sierre -> LV networks: proportional to installed power (PLmax)
%   - Within network: proportional to nodal PLmax
%
% Uses largest remainder method for discrete EV allocation

fprintf('\n=== SFOE-Based PV/EV Allocation ===\n');
fprintf('Scenario: %s\n', scenario_name);

%% Load configuration
if nargin < 3 || isempty(config)
    paths  = project_paths();
    config = jsondecode(fileread(fullfile(paths.config, 'general_config.json')));
end

if ~isfield(config.scenarios, scenario_name)
    error('Scenario %s not found in general_config.json', scenario_name);
end

scenario = config.scenarios.(scenario_name);

fprintf('Year: %d\n', scenario.year);
fprintf('SFOE Scenario: %s\n', scenario.SFOE_scenario);

%% Step 1: National -> Sion+Sierre scaling (population ratio)
pop_ratio = scenario.population_sion_sierre / scenario.population_national;

PV_region_MW = scenario.PV_national_MW * pop_ratio;
EV_region_count = round(scenario.EV_national_thousands * 1000 * pop_ratio);

fprintf('\n--- Sion + Sierre Allocation ---\n');
fprintf('Population ratio: %.6f\n', pop_ratio);
fprintf('PV capacity: %.2f MW\n', PV_region_MW);
fprintf('EV count: %d vehicles\n', EV_region_count);

%% Step 2: Compute total installed power across all LV networks
n_networks = numel(combined_data.LV_grid);
Pnet_vec = zeros(n_networks, 1);

for i = 1:n_networks
    T = combined_data.LV_grid{i};
    [~, ia ,~] = unique(T.To,'stable');
    T_dedup    = T(ia,:);
    Pnet_vec(i) = sum(T_dedup.PLmax_kW_);
end

Pnet_total = sum(Pnet_vec);
fprintf('Total installed power (all LV): %.2f MW\n', Pnet_total/1000);

%% Step 3: Sion+Sierre -> LV network allocation

% PV per network (continuous, in kW)
PV_net_kW = (PV_region_MW * 1000) * (Pnet_vec / Pnet_total);

% EV per network (discrete, largest remainder method)
EV_net = allocate_discrete(EV_region_count, Pnet_vec);

%% Step 4: Within-network allocation (nodal level)

   %% Step 4
for i = 1:n_networks
    T = combined_data.LV_grid{i};
    [~, ia, IC] = unique(T.To, 'stable');
    T_dedup = T(ia, :);
    N = height(T_dedup);

    active = (T_dedup.PLmax_kW_ > 0);
    PL_active = T_dedup.PLmax_kW_(active);

    PV_node = zeros(N, 1);
    EV_node = zeros(N, 1);

    if any(active)
        PV_node(active) = PV_net_kW(i) * (PL_active / sum(PL_active));
    end
    if any(active) && EV_net(i) > 0
        EV_active = allocate_discrete(EV_net(i), PL_active);
        EV_node(active) = EV_active;
    end

    % Spread across parallel branches so downstream sum = correct nodal total
    T.PV_kW_  = PV_node(IC) ;
    T.EV_count = EV_node(IC) ;

    combined_data.LV_grid{i} = T;
end

%% Verification
EV_total_check = 0;
PV_total_check = 0;

for i = 1:n_networks
    T = combined_data.LV_grid{i};
    [~, ia, ~] = unique(T.To, 'stable');
    T_dedup = T(ia, :);
    EV_total_check = EV_total_check + sum(T_dedup.EV_count);
    PV_total_check = PV_total_check + sum(T_dedup.PV_kW_);
end

fprintf('\n--- Verification ---\n');
fprintf('EV allocated: %d (target: %d, diff: %d)\n', ...
    EV_total_check, EV_region_count, abs(EV_total_check - EV_region_count));
fprintf('PV allocated: %.2f MW (target: %.2f MW, diff: %.4f MW)\n', ...
    PV_total_check/1000, PV_region_MW, abs(PV_total_check/1000 - PV_region_MW));

% No file output here: see docstring.

end

%% Helper function: Largest remainder method for discrete allocation
function allocated = allocate_discrete(total_count, weights)
%ALLOCATE_DISCRETE Allocate discrete items proportionally using largest remainder
%
%   allocated = allocate_discrete(100, [10; 20; 30])
%   Returns integer allocation that sums exactly to total_count

if total_count == 0 || sum(weights) == 0
    allocated = zeros(size(weights));
    return;
end

% Proportional allocation
frac = total_count * (weights / sum(weights));
floor_alloc = floor(frac);
remainder = frac - floor_alloc;

% Distribute remaining items to highest remainders
missing = total_count - sum(floor_alloc);
[~, idx_sort] = sort(remainder, 'descend');

allocated = floor_alloc;
if missing > 0
    allocated(idx_sort(1:missing)) = allocated(idx_sort(1:missing)) + 1;
end

end