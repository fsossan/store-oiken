function result = run_temporal_network(data_SFOE, n_idx, profiles, config, t_horizon, master_seed)
%RUN_TEMPORAL_NETWORK Run temporal loadflow for a single network
%
% Inputs:
%   data_SFOE - Combined data with SFOE allocation
%   n_idx - Network index
%   profiles - Struct with X_train, cluster_idx, PV_prof
%   config - Configuration struct
%   t_horizon - Number of timesteps to simulate
%   master_seed - Master RNG seed from config
%
% Outputs:
%   result - Struct with V(t), I(t), violations, network_id

%% Get grid data
grid = get_grid_SFOE(data_SFOE, n_idx, config);
net_id = string(data_SFOE.LV_grid_id{n_idx});

% Extract numeric part of network ID for seeding
net_num = str2double(regexp(net_id, '\d+', 'match', 'once'));

% Network-specific seed = master_seed + network_number
network_seed = master_seed + net_num;
rng(network_seed); % considering rng generator for future like 'twister'

N = numel(grid.nodal_nominal_power);
L = numel(grid.ampacities);

%% Generate temporal profiles

% --- Demand profiles ---
nodes_with_demand = grid.nodal_nominal_power > 0;
Nd = sum(nodes_with_demand);

if Nd > 0
    nodal_injections_D = -generate_nodal_scenarios(profiles.X_train, ...
        profiles.cluster_idx, grid.nodal_nominal_power(nodes_with_demand)).';
    nodal_injections_D_pu = nodal_injections_D / (grid.basepower/1000);
    to_all_nodes_D = pinv(make_M(nodes_with_demand));
else
    nodal_injections_D = zeros(t_horizon, 1);
    nodal_injections_D_pu = zeros(t_horizon, 1);
    to_all_nodes_D = zeros(N, 1);
end

% --- PV generation profiles ---
nodes_with_PV = grid.nodal_PV_SFOE > 0;
Npv = sum(nodes_with_PV);

if Npv > 0
    nodal_injections_PV = repmat(profiles.PV_prof', 1, Npv) .* ...
        repmat(grid.nodal_PV_SFOE(nodes_with_PV)', numel(profiles.PV_prof), 1);
    nodal_injections_PV_pu = nodal_injections_PV / (grid.basepower/1000);
    to_all_nodes_PV = pinv(make_M(nodes_with_PV));
else
    nodal_injections_PV = zeros(t_horizon, 1);
    nodal_injections_PV_pu = zeros(t_horizon, 1);
    to_all_nodes_PV = zeros(N, 1);
end

% --- EV charging profiles ---
nodes_with_EV = grid.nodal_N_EV > 0;
Nev = sum(nodes_with_EV);

if Nev > 0
    t_step = config.Temporal_loads.time_step_min;
    [~, nodal_injections_EV, ~] = EV_uncontrolled_profile(Nev, t_step);
    nodal_injections_EV = -1 * nodal_injections_EV;
    nodal_injections_EV_pu = nodal_injections_EV / (grid.basepower/1000);
    to_all_nodes_EV = pinv(make_M(nodes_with_EV));
else
    nodal_injections_EV = zeros(t_horizon, 1);
    nodal_injections_EV_pu = zeros(t_horizon, 1);
    to_all_nodes_EV = zeros(N, 1);
end

%% Run temporal loadflow
V_timeseries = zeros(t_horizon, N);
I_timeseries = zeros(t_horizon, L);
S_timeseries = cell(t_horizon, 1);
converged_flags = false(t_horizon, 1);
   

for t = 1:t_horizon
    % Aggregate injections at time t
    injections_D = to_all_nodes_D * nodal_injections_D_pu(t, :).';
    injections_PV = to_all_nodes_PV * nodal_injections_PV_pu(t, :).';
    injections_EV = to_all_nodes_EV * nodal_injections_EV_pu(t, :).';
    injections_aggr = injections_D + injections_EV + injections_PV;

    % Run loadflow
    [V, I, S, convergance, ~] = loadflow_FPIs_convergance(grid.Y, 1, ...
        injections_aggr, 1, grid.voltageToBranchCurrent_pu);

    % Store results
    if convergance
        V_timeseries(t, :) = abs(V).';
        I_timeseries(t, :) = abs(I).';
        S_timeseries{t}    = S;
        converged_flags(t) = true;
    else
        % Non-convergence: store NaN
        V_timeseries(t, :) = NaN;
        I_timeseries(t, :) = NaN;
        S_timeseries{t}    = NaN;
        converged_flags(t) = false;
    end
end

%% Compute violations

% Add slack bus voltage (always 1.0)
V_with_slack = [ones(t_horizon, 1), V_timeseries];

% Voltage violations (only for converged timesteps)
valid_idx = converged_flags;
undervolt = false(size(V_with_slack));
overvolt = false(size(V_with_slack));

undervolt(valid_idx, :) = V_with_slack(valid_idx, :) < 0.9;
overvolt(valid_idx, :) = V_with_slack(valid_idx, :) > 1.1;

% Line overloads (I in p.u. vs ampacity)
I_pu = I_timeseries ./ repmat((grid.ampacities./grid.basecurrent)', t_horizon, 1);
overload = false(size(I_pu));
overload(valid_idx, :) = I_pu(valid_idx, :) > 1.0;

% transformer congestions 
n_tr = grid.n_transformers;
congested = false(t_horizon, n_tr);
for k = 1:n_tr
    I_tr_pu = I_timeseries(:, grid.tr_branch_idx(k)) ./ ...
              (grid.T_ampacity(k) / grid.basecurrent);
    congested(valid_idx, k) = I_tr_pu(valid_idx) > 1.0;
end

%% Package results
result = struct();
result.network_id = char(net_id);
result.network_seed = network_seed;
result.n_nodes = N;
result.n_lines = L;
result.t_horizon = t_horizon;

% Convergence
result.converged_all = all(converged_flags);
result.converged_pct = 100 * sum(converged_flags) / t_horizon;
result.n_non_converged = sum(~converged_flags);

% Violations
has_violations = any(undervolt(:)) || any(overvolt(:)) || any(overload(:)) || any(congested(:));
result.has_violations = has_violations;
result.has_congestion     = any(congested(:));
result.n_undervolt_events = sum(undervolt(:));
result.n_overvolt_events  = sum(overvolt(:));
result.n_overload_events  = sum(overload(:));
result.n_congested_events = sum(congested(:));



result.undervolt_hours = sum(any(undervolt, 2));
result.overvolt_hours = sum(any(overvolt, 2));
result.overload_hours = sum(any(overload, 2));
result.congested_hours    = sum(any(congested, 2));

% Statistics (computed only on converged timesteps)
if any(converged_flags)
    result.V_min = min(V_with_slack(converged_flags, :), [], 'all');
    result.V_max = max(V_with_slack(converged_flags, :), [], 'all');
    result.I_max_pu = max(I_pu(converged_flags, :), [], 'all');
else
    result.V_min = NaN;
    result.V_max = NaN;
    result.I_max_pu = NaN;
end

% store time-series lf result
result.V_timeseries     = V_with_slack;
result.I_timeseries     = I_timeseries;
result.I_pu_timeseries  = I_pu;
result.S_pu_timeseries  = S_timeseries;


% Profiles (for plotting) - convert to kW
result.profiles = struct();
result.profiles.demand = real(to_all_nodes_D * nodal_injections_D.');
result.profiles.PV = to_all_nodes_PV * nodal_injections_PV.';
result.profiles.EV = to_all_nodes_EV * nodal_injections_EV.';
result.profiles.aggr = result.profiles.demand + result.profiles.PV + result.profiles.EV;

% Store ampacity for plotting
result.ampacities = grid.ampacities;

% Store transformer(s) data
result.n_transformers = grid.n_transformers;
result.T_rat_kVA      = grid.T_rat_kVA;
result.T_ampacity     = grid.T_ampacity;
end