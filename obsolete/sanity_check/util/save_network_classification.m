function save_network_classification(lf_data, converged_data, has_any_violation,results)
%SAVE_NETWORK_CLASSIFICATION Save classified network lists to separate MD files
%
% Creates four files:
%   - violation_networks.md
%   - converged_networks.md
%   - non_converged_networks.md
%   - healthy_networks.md
%   - network_classification.mat (NEW - contains network IDs only)

%% Extract network IDs for each category
network_ids = struct();

% All networks
network_ids.all = {lf_data.network_id}';

% Converged vs non-converged
idx_converged = [lf_data.converged];
network_ids.converged = {lf_data(idx_converged).network_id}';
network_ids.non_converged = {lf_data(~idx_converged).network_id}';

% Among converged: healthy vs violation
network_ids.healthy = {converged_data(~has_any_violation).network_id}';
network_ids.violation = {converged_data(has_any_violation).network_id}';

% Save to MAT file
save('output/one_shot_lf_network_classification.mat', 'network_ids');
fprintf('\nNetwork IDs saved: output/one_shot_lf_network_classification\n');
%% 1. Networks with violations
filename = 'sanity-check-website/docs/violation_networks.md';
fid = fopen(filename, 'w');

violation_networks = converged_data(has_any_violation);

fprintf(fid, '# Networks with Violations\n\n');
fprintf(fid, 'Total networks with violations: **%d**\n\n', length(violation_networks));

fprintf(fid, '| Network ID | Min Voltage (p.u.) | Max Current (p.u.) | Overloaded Lines | Violation Type |\n');
fprintf(fid, '|------------|-------------------|-------------------|------------------|----------------|\n');

for i = 1:length(violation_networks)
    net = violation_networks(i);
    
    % Determine violation type
    violations = {};
    if net.min_voltage < 0.9
        violations{end+1} = 'Undervolt';
    end
    if net.max_voltage > 1.1
        violations{end+1} = 'Overvolt';
    end
    if net.n_overloaded > 0
        violations{end+1} = 'Overload';
    end
    violation_str = strjoin(violations, ', ');
    
    fprintf(fid, '| %s | %.3f | %.2f | %d | %s |\n', ...
            net.network_id, net.min_voltage, net.max_current_pu, net.n_overloaded, violation_str);
end

fclose(fid);

fprintf('Saved: %s (%d networks)\n', filename, length(violation_networks));

%% 2. Healthy networks (converged, no violations)
filename = 'sanity-check-website/docs/healthy_networks.md';
fid = fopen(filename, 'w');

healthy_networks = converged_data(~has_any_violation);

fprintf(fid, '# Healthy Networks\n\n');
fprintf(fid, 'Networks that converged with no violations: **%d**\n\n', length(healthy_networks));

fprintf(fid, '| Network ID | Min Voltage (p.u.) | Max Voltage (p.u.) | Max Current (p.u.) | Losses (kW) |\n');
fprintf(fid, '|------------|-------------------|-------------------|-------------------|-------------|\n');

for i = 1:length(healthy_networks)
    net = healthy_networks(i);
    fprintf(fid, '| %s | %.3f | %.3f | %.2f | %.1f |\n', ...
            net.network_id, net.min_voltage, net.max_voltage, net.max_current_pu, net.total_losses_kW);
end

fclose(fid);
fprintf('Saved: %s (%d networks)\n', filename, length(healthy_networks));

%% 3. All converged networks
filename = 'sanity-check-website/docs/converged_networks.md';
fid = fopen(filename, 'w');

fprintf(fid, '# Converged Networks\n\n');
fprintf(fid, 'All networks that successfully converged: **%d**\n\n', length(converged_data));

fprintf(fid, '| Network ID | Min Voltage (p.u.) | Max Current (p.u.) | Overloaded Lines | Status |\n');
fprintf(fid, '|------------|-------------------|-------------------|------------------|--------|\n');

for i = 1:length(converged_data)
    net = converged_data(i);
    
    % Determine status
    if net.min_voltage < 0.9 || net.max_voltage > 1.1 || net.n_overloaded > 0
        status = '⚠️ Has Violations';
    else
        status = '✅ Healthy';
    end
    
    fprintf(fid, '| %s | %.3f | %.2f | %d | %s |\n', ...
            net.network_id, net.min_voltage, net.max_current_pu, net.n_overloaded, status);
end

fclose(fid);
fprintf('Saved: %s (%d networks)\n', filename, length(converged_data));

%% 4. Non-converged networks
filename = 'sanity-check-website/docs/non_converged_networks.md';
fid = fopen(filename, 'w');

non_converged = results(~[lf_data.converged]);

fprintf(fid, '# Non-Converged Networks\n\n');
fprintf(fid, 'Networks that failed to converge: **%d**\n\n', length(non_converged));

if length(non_converged) > 0
    fprintf(fid, '| Network ID | Iterations Attempted |\n');
    fprintf(fid, '|------------|----------------------|\n');
    
    for i = 1:length(non_converged)
        net = non_converged(i);
        fprintf(fid, '| %s | %d |\n', net.network_id, net.conv_iter_num);
    end
else
    fprintf(fid, '*All networks converged successfully!*\n');
end

fclose(fid);
fprintf('Saved: %s (%d networks)\n', filename, length(non_converged));

%% Summary
fprintf('\n--- Network Classification Summary ---\n');
fprintf('Total networks: %d\n', length(lf_data));
fprintf('  ✅ Healthy (converged, no violations): %d (%.1f%%)\n', length(healthy_networks), 100*length(healthy_networks)/length(lf_data));
fprintf('  ⚠️  Converged with violations: %d (%.1f%%)\n', length(violation_networks), 100*length(violation_networks)/length(lf_data));
fprintf('  ❌ Non-converged: %d (%.1f%%)\n', length(non_converged), 100*length(non_converged)/length(lf_data));

end