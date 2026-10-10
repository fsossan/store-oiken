function temporal_loadflow_main(varargin)
%TEMPORAL_LOADFLOW_MAIN Run temporal loadflow analysis for SFOE scenario
%
%   temporal_loadflow_main(data, 'sc1_2040')           % healthy (default)
%   temporal_loadflow_main(data, 'sc1_2040', 'healthy')
%   temporal_loadflow_main(data, 'sc1_2040', 'violation')
%
% Inputs:
%   data - Combined struct from combine_struct_data(Sierre, Sion)
%   scenario_name - Scenario name (e.g., 'sc1_2040')
%   network_filter - 'healthy', 'violation', or 'all' (default: 'healthy')

% Parse inputs
if nargin < 2
    error('At least 2 arguments required: temporal_loadflow_main(data, scenario_name)');
end

data = varargin{1};
scenario_name = varargin{2};

if nargin >= 3
    network_filter = varargin{3};
else
    network_filter = 'healthy';  % Default
end


fprintf('\n=== Temporal Loadflow Analysis ===\n');
fprintf('Scenario: %s\n', scenario_name);
fprintf('Network filter: %s\n', network_filter);


% Load config
config = jsondecode(fileread('general_config.json'));

% Allocate PV/EV based on scenario
data_SFOE = allocate_PV_EV_SFOE(data, scenario_name);

% Load oneshot classification
load('one_shot_lf_network_classification.mat');

% Get master seed
master_seed = config.rng_seed.seed;
fprintf('Master seed: %d\n', master_seed);

%% 2. Load temporal profiles
fprintf('Loading temporal profiles...\n');

% Load consumption profiles
historic_load_data = load('load_consumption_train_new.mat');
profiles = struct();
profiles.X_train = historic_load_data.X_train;
profiles.cluster_idx = historic_load_data.cluster_idx;

% Load PV profile
pv_data = load('PV_prof_15mins.mat');
profiles.PV_prof = pv_data.PV_prof;

% Temporal settings
t_step = config.Temporal_loads.time_step_min;
t_horizon = config.Temporal_loads.time_horizon;

fprintf('Time step: %d minutes\n', t_step);
fprintf('Time horizon: %d timesteps (%.1f days)\n', t_horizon, t_horizon*t_step/60/24);

%% 3. Select networks to analyze
all_ids = string(data_SFOE.LV_grid_id);

switch network_filter
    case 'healthy'
        target_ids = "LV_Grid_" + network_ids.healthy;
    case 'violation'
        target_ids = "LV_Grid_" + network_ids.violation;
    case 'all'
        target_ids = "LV_Grid_" + network_ids.converged;
    otherwise
        error('Invalid network_filter: %s. Use ''healthy'', ''violation'', or ''all''', network_filter);
end

is_target = ismember(all_ids, target_ids);
network_indices = find(is_target);

fprintf('Selected %d networks for temporal analysis\n', length(network_indices));

%% 4. Create output directories
output_dir = sprintf('output/scenario_%s/temporal_results', scenario_name);
if ~isfolder(output_dir)
    mkdir(output_dir);
end

fig_dir = sprintf('sanity-check-website/docs/scenario_%s/temporal_figures', scenario_name);
temporal_figures_folder_warning(fig_dir,output_dir);


%% 5. Run temporal loadflow
fprintf('\nRunning temporal loadflow...\n');


for i = 1:length(network_indices)

    n_idx = network_indices(i);
    net_id = data_SFOE.LV_grid_id{n_idx};
    
    fprintf('Running network %d out of %d (%s)\n', i, length(network_indices), net_id);
    
    result = run_temporal_network(data_SFOE, n_idx, ...
        profiles, config, t_horizon, master_seed);
    
    % Save full result immediately
    save(sprintf('%s/%s_temporal.mat', output_dir, result.network_id), 'result');
    
    % Create figure
    create_temporal_plots(result, scenario_name, fig_dir);
    
    % Free RAM — do not accumulate
    clear result;
end

    

% fprintf('Completed: %d networks\n', length(network_indices));
% 
% %% 6. Analyze results
% fprintf('\nAnalyzing temporal results...\n');
% stats = analyze_temporal_results(output_dir, scenario_name);
% 
% %% 7. Generate reports
% fprintf('\nGenerating markdown reports...\n');
% generate_temporal_markdown(stats, scenario_name);
% 
% %% 8. Save metadata
% metadata = struct();
% metadata.scenario_name = scenario_name;
% metadata.master_seed = master_seed;
% metadata.network_filter = network_filter;
% metadata.n_networks = length(network_indices);
% metadata.t_horizon = t_horizon;
% metadata.t_step_min = t_step;
% metadata.timestamp = datetime('now');
% metadata.matlab_version = version;
% 
% save(sprintf('output/scenario_%s/temporal_metadata.mat', scenario_name), 'metadata');
% 
% fprintf('\n✅ Temporal analysis complete!\n');
% fprintf('Results: %s\n', output_dir);
% fprintf('Figures: %s\n', fig_dir);

end