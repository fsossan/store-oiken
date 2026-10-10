function generate_power_mix_markdown_ALL_LV(power_data)
%GENERATE_POWER_MIX_MARKDOWN Create markdown summary for power mix analysis

output_file = sprintf('sanity-check-website/docs/all_LV_grid_power_mix_analysis.md'); % Path to save the markdown file



% Open file for writing
fid = fopen(output_file, 'w');
if fid == -1
    error('Cannot open file: %s', output_file);
end

fprintf(fid, '# All LV grid Power Mix Analysis\n\n');

%% Summary statistics
total_P = sum([power_data.total_P_kW]);
total_Q = sum([power_data.total_Q_kVAR]);
total_PV = sum([power_data.total_PV_kW]);
total_net = sum([power_data.net_demand_kW]);
n_with_PV = sum([power_data.has_PV]);

fprintf(fid, '## Summary Statistics\n\n');
fprintf(fid, '- **Networks analyzed:** %d\n', length(power_data));
fprintf(fid, '- **Total load:** %.0f kW\n', total_P);
fprintf(fid, '- **Total reactive power:** %.0f kVAR\n', total_Q);
fprintf(fid, '- **Total PV generation:** %.0f kW\n', total_PV);
fprintf(fid, '- **Total net demand:** %.0f kW\n', total_net);
fprintf(fid, '- **Overall PV penetration:** %.1f%%\n', (total_PV/total_P)*100);
fprintf(fid, '- **Networks with PV:** %d (%.1f%%)\n\n', n_with_PV, 100*n_with_PV/length(power_data));

%% PV penetration statistics (networks with PV and valid data)
pv_networks = power_data([power_data.has_PV]);
if ~isempty(pv_networks)
    pv_pen = [pv_networks.PV_penetration_pct];
    pv_pen_finite = pv_pen(isfinite(pv_pen));
    
    if ~isempty(pv_pen_finite)
        fprintf(fid, '### PV Penetration (Networks with PV and Load)\n\n');
        fprintf(fid, '- **Mean:** %.1f%%\n', mean(pv_pen_finite));
        fprintf(fid, '- **Median:** %.1f%%\n', median(pv_pen_finite));
        fprintf(fid, '- **Maximum:** %.1f%%\n\n', max(pv_pen_finite));
    end
    
    % Special cases
    n_inf = sum(isinf(pv_pen));
    if n_inf > 0
        fprintf(fid, '- **Networks with PV but no load:** %d\n\n', n_inf);
    end
end

%% Power factor
pf_all = [power_data.power_factor];
pf_valid = pf_all(isfinite(pf_all));
if ~isempty(pf_valid)
    fprintf(fid, '### Power Factor\n\n');
    fprintf(fid, '- **Average:** %.3f\n\n', mean(pf_valid));
end

%% Visualization
fprintf(fid, '## Visualizations\n\n');
fprintf(fid, '![Power Mix Analysis](All_LV_grid_power_mix_raw.png)\n\n');

%% PV penetration categories
pen_0 = sum([power_data.PV_penetration_pct] == 0);
pen_25 = sum([power_data.PV_penetration_pct] > 0 & [power_data.PV_penetration_pct] <= 25);
pen_50 = sum([power_data.PV_penetration_pct] > 25 & [power_data.PV_penetration_pct] <= 50);
pen_75 = sum([power_data.PV_penetration_pct] > 50 & [power_data.PV_penetration_pct] <= 75);
pen_100 = sum([power_data.PV_penetration_pct] > 75 & [power_data.PV_penetration_pct] <= 100);
pen_100_plus = sum([power_data.PV_penetration_pct] > 100);

fprintf(fid, '## PV Penetration Distribution\n\n');
fprintf(fid, '| Category | Networks | Percentage |\n');
fprintf(fid, '|----------|----------|------------|\n');
fprintf(fid, '| 0%% | %d | %.1f%% |\n', pen_0, 100*pen_0/length(power_data));
fprintf(fid, '| 1-25%% | %d | %.1f%% |\n', pen_25, 100*pen_25/length(power_data));
fprintf(fid, '| 26-50%% | %d | %.1f%% |\n', pen_50, 100*pen_50/length(power_data));
fprintf(fid, '| 51-75%% | %d | %.1f%% |\n', pen_75, 100*pen_75/length(power_data));
fprintf(fid, '| 76-100%% | %d | %.1f%% |\n', pen_100, 100*pen_100/length(power_data));
fprintf(fid, '| >100%% | %d | %.1f%% |\n\n', pen_100_plus, 100*pen_100_plus/length(power_data));

%% Top networks by load
fprintf(fid, '## Top 10 Networks by Load\n\n');
fprintf(fid, '| Network ID | Load (kW) | PV (kW) | Net Demand (kW) | PV Penetration |\n');
fprintf(fid, '|------------|-----------|---------|-----------------|----------------|\n');

[~, idx] = sort([power_data.total_P_kW], 'descend');
for k = 1:min(10, length(idx))
    net = power_data(idx(k));
    
    % Handle infinite/NaN penetration values
    if isfinite(net.PV_penetration_pct)
        pen_str = sprintf('%.1f%%', net.PV_penetration_pct);
    else
        pen_str = 'N/A';
    end
    
    fprintf(fid, '| %s | %.0f | %.0f | %.0f | %s |\n', ...
            net.network_id, net.total_P_kW, net.total_PV_kW, net.net_demand_kW, pen_str);
end
fprintf(fid, '\n');

%% Top networks by PV penetration
pv_sorted = power_data([power_data.has_PV]);
if ~isempty(pv_sorted)
    % Get finite penetration values
    pv_pen_all = [pv_sorted.PV_penetration_pct];
    finite_mask = isfinite(pv_pen_all);
    pv_sorted_finite = pv_sorted(finite_mask);
    
    if ~isempty(pv_sorted_finite)
        [~, idx] = sort([pv_sorted_finite.PV_penetration_pct], 'descend');
        
        fprintf(fid, '## Top 10 Networks by PV Penetration\n\n');
        fprintf(fid, '| Network ID | Load (kW) | PV (kW) | PV Penetration |\n');
        fprintf(fid, '|------------|-----------|---------|----------------|\n');
        
        for k = 1:min(10, length(idx))
            net = pv_sorted_finite(idx(k));
            fprintf(fid, '| %s | %.0f | %.0f | %.1f%% |\n', ...
                    net.network_id, net.total_P_kW, net.total_PV_kW, net.PV_penetration_pct);
        end
        fprintf(fid, '\n');
    end
end

fclose(fid);
fprintf('Power mix analysis of ALL LV grid saved: \n');

end