function generate_loadflow_markdown(lf_data, converged_data, stats)
%GENERATE_LOADFLOW_MARKDOWN Create markdown report for loadflow analysis
%
% stats struct should contain:
%   - n_networks, n_converged
%   - total_load_MW, converged_load_MW
%   - n_excluded, excluded_load_MW, excluded_load_pct
%   - total_losses_kW, avg_loss_kW, loss_pct
%   - total_overloads, networks_with_overloads, overload_pct

filename = 'sanity-check-website/docs/One_shot_loadflow_analysis.md';
fid = fopen(filename, 'w');

if fid == -1
    error('Cannot open file: %s', filename);
end

fprintf(fid, '# One-shot Loadflow Analysis Results\n\n');
fprintf(fid, '_Combined analysis of all LV networks_\n\n');

%% Overall Summary
fprintf(fid, '## Overall Summary\n\n');
fprintf(fid, '- **Networks analyzed:** %d\n', stats.n_networks);
fprintf(fid, '- **Total load:** %.0f MW\n\n', stats.total_load_MW);

%% Network Classification (with links to separate files)
fprintf(fid, '## Network Classification\n\n');
fprintf(fid, '### Convergence Status\n\n');
fprintf(fid, '- **Converged:** %d (%.1f%%) → [📋 View list](converged_networks.md)\n', ...
    stats.n_converged, 100*stats.n_converged/stats.n_networks);
fprintf(fid, '- **Non-converged:** %d (%.1f%%) → [📋 View list](non_converged_networks.md)\n', ...
    stats.n_networks - stats.n_converged, 100*(stats.n_networks - stats.n_converged)/stats.n_networks);
fprintf(fid, '- **Converged load:** %.0f MW\n\n', stats.converged_load_MW);

fprintf(fid, '### Converged Network Health\n\n');
n_healthy = stats.n_converged - stats.n_excluded;
fprintf(fid, '- **✅ Healthy networks:** %d (%.1f%%) → [📋 View list](healthy_networks.md)\n', ...
    n_healthy, 100*n_healthy/stats.n_converged);
fprintf(fid, '- **⚠️ Networks with violations:** %d (%.1f%%) → [📋 View list](violation_networks.md)\n', ...
    stats.n_excluded, 100*stats.n_excluded/stats.n_converged);
fprintf(fid, '  - Load affected: %.0f MW (%.1f%% of converged load)\n\n', ...
    stats.excluded_load_MW, stats.excluded_load_pct);

%% Convergence Details
min_voltages = [converged_data.min_voltage];
max_voltages = [converged_data.max_voltage];
iters = [converged_data.iterations];

fprintf(fid, '## Convergence Statistics\n\n');
fprintf(fid, '**Iterations to converge:**\n\n');
fprintf(fid, '- Mean: %.1f\n', mean(iters));
fprintf(fid, '- Median: %.0f\n', median(iters));
fprintf(fid, '- Maximum: %d\n\n', max(iters));

%% Voltage Quality
n_undervolt_critical = sum(min_voltages < 0.9);
n_undervolt_warning = sum(min_voltages < 0.95 & min_voltages >= 0.9);
n_overvolt_warning = sum(max_voltages > 1.05 & max_voltages <= 1.1);
n_overvolt_critical = sum(max_voltages > 1.1);

fprintf(fid, '## Voltage Quality\n\n');
fprintf(fid, '### Network-Level Statistics\n\n');
fprintf(fid, '- **Mean minimum voltage:** %.3f p.u.\n', mean(min_voltages));
fprintf(fid, '- **Lowest voltage:** %.3f p.u.\n', min(min_voltages));
fprintf(fid, '- **Mean maximum voltage:** %.3f p.u.\n', mean(max_voltages));
fprintf(fid, '- **Highest voltage:** %.3f p.u.\n\n', max(max_voltages));

fprintf(fid, '### Voltage Violations\n\n');
fprintf(fid, '| Severity | Threshold | Networks | Percentage |\n');
fprintf(fid, '|----------|-----------|----------|------------|\n');
fprintf(fid, '| 🔴 Critical Low | < 0.9 p.u. | %d | %.1f%% |\n', ...
    n_undervolt_critical, 100*n_undervolt_critical/stats.n_converged);
fprintf(fid, '| 🟡 Warning Low | 0.9-0.95 p.u. | %d | %.1f%% |\n', ...
    n_undervolt_warning, 100*n_undervolt_warning/stats.n_converged);
fprintf(fid, '| 🟡 Warning High | 1.05-1.1 p.u. | %d | %.1f%% |\n', ...
    n_overvolt_warning, 100*n_overvolt_warning/stats.n_converged);
fprintf(fid, '| 🔴 Critical High | > 1.1 p.u. | %d | %.1f%% |\n\n', ...
    n_overvolt_critical, 100*n_overvolt_critical/stats.n_converged);

%% Line Overloads
n_overloaded = [converged_data.n_overloaded];
max_currents = [converged_data.max_current_pu];
n_severe = sum(max_currents > 1.1);
n_critical = sum(max_currents > 1.2);

fprintf(fid, '## Line Overloads\n\n');
fprintf(fid, '### Network-Level\n\n');
fprintf(fid, '- **Networks with overloaded lines:** %d (%.1f%%)\n', ...
    stats.networks_with_overloads, 100*stats.networks_with_overloads/stats.n_converged);
fprintf(fid, '- **Networks with severe overloads (>110%%):** %d (%.1f%%)\n', ...
    n_severe, 100*n_severe/stats.n_converged);
fprintf(fid, '- **Networks with critical overloads (>120%%):** %d (%.1f%%)\n\n', ...
    n_critical, 100*n_critical/stats.n_converged);

fprintf(fid, '### Line-Level\n\n');
fprintf(fid, '- **Total overloaded lines:** %d (%.1f%% of all lines)\n', ...
    stats.total_overloads, stats.overload_pct);
fprintf(fid, '- **Average overloads per affected network:** %.1f\n\n', ...
    stats.total_overloads/stats.networks_with_overloads);

%% System Losses
losses = [converged_data.total_losses_kW];
losses_valid = losses(losses >= 0);

fprintf(fid, '## System Losses\n\n');
fprintf(fid, '- **Total losses:** %.0f kW (%.1f%% of load)\n', ...
    stats.total_losses_kW, stats.loss_pct);
fprintf(fid, '- **Average per network:** %.1f kW\n', stats.avg_loss_kW);
fprintf(fid, '- **Median per network:** %.1f kW\n', median(losses_valid));
fprintf(fid, '- **Maximum per network:** %.1f kW\n\n', max(losses_valid));

%% Visualization
fprintf(fid, '## Visualizations\n\n');
fprintf(fid, '![Loadflow Analysis](One_shot_loadflow_analysis.png)\n\n');

%% Top Problem Networks
fprintf(fid, '## Top Problem Networks\n\n');

fprintf(fid, '### Top 10 Networks by Voltage Drop\n\n');
fprintf(fid, '| Rank | Network ID | Min Voltage (p.u.) | Voltage Drop (p.u.) | Overloaded Lines |\n');
fprintf(fid, '|------|------------|-------------------|---------------------|------------------|\n');

[~, idx] = sort([converged_data.voltage_drop], 'descend');
for k = 1:min(10, length(idx))
    net = converged_data(idx(k));
    fprintf(fid, '| %d | %s | %.3f | %.3f | %d |\n', ...
            k, net.network_id, net.min_voltage, net.voltage_drop, net.n_overloaded);
end
fprintf(fid, '\n');

fprintf(fid, '### Top 10 Networks by Line Overloads\n\n');
fprintf(fid, '| Rank | Network ID | Overloaded Lines | Max Current (p.u.) | Min Voltage (p.u.) |\n');
fprintf(fid, '|------|------------|------------------|-------------------|--------------------|\n');

[~, idx] = sort([converged_data.n_overloaded], 'descend');
count = 0;
for k = 1:length(idx)
    net = converged_data(idx(k));
    if net.n_overloaded > 0
        count = count + 1;
        fprintf(fid, '| %d | %s | %d | %.2f | %.3f |\n', ...
                count, net.network_id, net.n_overloaded, net.max_current_pu, net.min_voltage);
        if count >= 10
            break;
        end
    end
end
fprintf(fid, '\n');

fprintf(fid, '### Top 10 Networks by Lowest Voltage\n\n');
fprintf(fid, '| Rank | Network ID | Min Voltage (p.u.) | Voltage Drop (p.u.) | Overloaded Lines |\n');
fprintf(fid, '|------|------------|-------------------|---------------------|------------------|\n');

[~, idx] = sort([converged_data.min_voltage], 'ascend');
for k = 1:min(10, length(idx))
    net = converged_data(idx(k));
    fprintf(fid, '| %d | %s | %.3f | %.3f | %d |\n', ...
            k, net.network_id, net.min_voltage, net.voltage_drop, net.n_overloaded);
end
fprintf(fid, '\n');

fprintf(fid, '### Top 10 Networks by Highest Current\n\n');
fprintf(fid, '| Rank | Network ID | Max Current (p.u.) | Overloaded Lines | Min Voltage (p.u.) |\n');
fprintf(fid, '|------|------------|-------------------|------------------|--------------------|\n');

[~, idx] = sort([converged_data.max_current_pu], 'descend');
for k = 1:min(10, length(idx))
    net = converged_data(idx(k));
    fprintf(fid, '| %d | %s | %.2f | %d | %.3f |\n', ...
            k, net.network_id, net.max_current_pu, net.n_overloaded, net.min_voltage);
end
fprintf(fid, '\n');

%% Footer
fprintf(fid, '---\n\n');
fprintf(fid, '*Report generated: %s*\n', datetime('now'));

fclose(fid);
fprintf('Markdown report saved: %s\n', filename);

end