function analyze_loadflow_results(varargin)
%ANALYZE_LOADFLOW_RESULTS Analyze loadflow results from oneshot simulation
 % Takes any number of structs and concatenates them
    % Usage: combined = combine_structs(Sierre_oneshot_lf, Sion_oneshot_lf)
    %        combined = combine_structs(A, B, C, D, ...)

fprintf('\n===  One-shot Loadflow Results Analysis ===\n');

results = [varargin{:}];

fprintf('Analyzing %d networks...\n', length(results));

%% Extract key metrics
n_networks = length(results);
lf_data = struct([]);
total_aggr_load = 0;

for i = 1:n_networks
    net = results(i);
    total_aggr_load = total_aggr_load+sum(results(i).P_loads);
    
    % Basic info
    lf_data(i).network_id = net.network_id;
    lf_data(i).converged = net.convergance;
    lf_data(i).iterations = net.conv_iter_num;
    
    % Skip non-converged networks for detailed analysis
    if ~net.convergance
        lf_data(i).min_voltage = NaN;
        lf_data(i).max_voltage = NaN;
        lf_data(i).voltage_drop = NaN;
        lf_data(i).max_current_pu = NaN;
        lf_data(i).n_overloaded = NaN;
        lf_data(i).slack_power_kVA = NaN;
        lf_data(i).total_losses_kW = NaN;
        lf_data(i).under_volt_nodes = NaN;
        lf_data(i).over_volt_nodes = NaN;
        lf_data(i).total_demand = NaN;
        lf_data(i).total_lines = NaN;
    
        continue;
    end
    
    % Voltage analysis
    V = abs(net.V);
    lf_data(i).min_voltage = min(V);
    lf_data(i).max_voltage = max(V);
    lf_data(i).voltage_drop = V(1) - min(V);  % Slack - minimum
    lf_data(i).under_volt_nodes = sum(V<0.9);
    lf_data(i).over_volt_nodes = sum(V>1.1);
    
    % Current analysis
    I = abs(net.I);
    lf_data(i).max_current_pu = max(I);
    lf_data(i).n_overloaded = sum(I > 1.0);
    lf_data(i).total_lines = sum(I);
    
    % Power analysis
    Sb = net.config.PU_values.Sb;
    lf_data(i).slack_power_kVA = abs(net.S) * Sb /1000*3;
    lf_data(i).total_demand =  sum(net.P_loads);
    
    % Losses (approximate from slack power - load)
    total_load = sum(net.P_loads) + sum(net.Q_loads)*1i;
    total_pv = sum(net.PV);
    net_demand = total_load + total_pv;
    lf_data(i).total_losses_kW = lf_data(i).slack_power_kVA -  abs(net_demand);
end

%% Statistics
fprintf('which host a total load of %.0f MW \n', sum(total_aggr_load)/1e3)
fprintf('\n--- Convergence Statistics ---\n');
n_converged = sum([lf_data.converged]);
fprintf('Converged networks: %d/%d (%.1f%%)\n', n_converged, n_networks, 100*n_converged/n_networks);

% Iteration statistics (converged networks only)
converged_data = lf_data([lf_data.converged]);
converged_data_total_demand = abs(sum(vertcat(converged_data.total_demand)));
fprintf('which host a total load of %.0f MW \n', converged_data_total_demand/1e3)
if ~isempty(converged_data)
    iters = [converged_data.iterations];
    fprintf('Iterations to converge:\n');
    fprintf('  Mean: %.1f\n', mean(iters));
    fprintf('  Median: %.0f\n', median(iters));
    fprintf('  Max: %d\n', max(iters));
end

%% Voltage quality
fprintf('\n--- Voltage Quality ---\n');
min_voltages = [converged_data.min_voltage];
max_voltages = [converged_data.max_voltage];

fprintf('Minimum voltages:\n');
fprintf('  Mean: %.3f p.u.\n', mean(min_voltages));
fprintf('  Lowest: %.3f p.u.\n', min(min_voltages));

n_undervolt = sum(min_voltages < 0.9);
n_overvolt = sum(max_voltages > 1.1);
fprintf('Voltage violations:\n');
fprintf('  Undervoltage (<0.9): %d (%.1f%%)\n', n_undervolt, 100*n_undervolt/n_converged);
fprintf('  Overvoltage (>1.1): %d (%.1f%%)\n', n_overvolt, 100*n_overvolt/n_converged);

%% Line overloads
fprintf('\n--- Line Overloads ---\n');
n_overloaded = [converged_data.n_overloaded];
total_lines = [converged_data.total_lines];
networks_with_overloads = sum(n_overloaded > 0);
total_overloads = sum(n_overloaded);

fprintf('Networks with overloaded lines: %d (%.1f%%)\n', networks_with_overloads, 100*networks_with_overloads/n_converged);
fprintf('Total overloaded lines: %d (%.1f%%)\n', total_overloads, total_overloads/sum(total_lines)*100);

%% Losses
fprintf('\n--- System Losses ---\n');
losses = [converged_data.total_losses_kW];
losses_valid = losses(losses >= 0);  % Filter negative values (calculation errors)

if ~isempty(losses_valid)
    fprintf('Total losses: %.0f kW (%.1f%%)\n', sum(losses_valid),sum(losses_valid)/converged_data_total_demand*100);
    fprintf('Average losses per network: %.1f kW  \n', mean(losses_valid));
end

%% Excluded networks
fprintf('\n--- Networks with either overloaded lines or voltage violations ---\n');

has_any_violation =  n_overloaded > 0 | min_voltages < 0.9 | max_voltages > 1.1;
n_excluded = sum(has_any_violation);
n_excluded_total_load = abs(sum(vertcat(converged_data(has_any_violation).total_demand)));
fprintf('Networks with any violation: %d (%.1f%%)\n', n_excluded, 100*n_excluded/n_converged);
fprintf('which host a total load of %.0f MW  (%.1f%%) \n',n_excluded_total_load/1e3,n_excluded_total_load/converged_data_total_demand*100)


%% Visualizations
create_loadflow_plots(lf_data, converged_data);

%% Save results
save('output/One_shot_loadflow_analysis.mat',  'lf_data');
fprintf('\nAnalysis data saved: output/One_shot_loadflow_analysis.mat\n');
%% Save network classification
save_network_classification(lf_data, converged_data, has_any_violation,results)
%% Generate markdown report
stats = struct();
stats.n_networks = n_networks;
stats.n_converged = n_converged;
stats.total_load_MW = abs(total_aggr_load)/1e3;
stats.converged_load_MW = converged_data_total_demand/1e3;
stats.n_excluded = n_excluded;
stats.excluded_load_MW = n_excluded_total_load/1e3;
stats.excluded_load_pct = n_excluded_total_load/converged_data_total_demand*100;
stats.total_losses_kW = sum(losses_valid);
stats.loss_pct = sum(losses_valid)/converged_data_total_demand*100;
stats.avg_loss_kW = mean(losses_valid);
stats.total_overloads = total_overloads;
stats.networks_with_overloads = networks_with_overloads;
stats.overload_pct = total_overloads/sum(total_lines)*100;

generate_loadflow_markdown(lf_data, converged_data, stats);


end