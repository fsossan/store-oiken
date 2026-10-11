function generate_temporal_markdown(stats, scenario_name)
% Generates three markdown files:
%   1. temporal_analysis_<scenario>.md       — summary page
%   2. temporal_reinforcement_<scenario>.md  — networks requiring reinforcement
%   3. temporal_compliant_<scenario>.md      — networks meeting operational goals

% Load SFOE allocation data
sc = load(sprintf('output/scenario_%s_allocation.mat', scenario_name));

%% ================================================================
%  FILE 1 — SUMMARY PAGE
%% ================================================================
filename = sprintf('sanity-check-website/docs/temporal_analysis_%s.md', scenario_name);
fid = fopen(filename, 'w');

fprintf(fid, '# Temporal Analysis: %s\n\n', scenario_name);
fprintf(fid, '**Analysis Date:** %s\n\n', char(datetime('now')));

%% SFOE Scenario Context
fprintf(fid, '## SFOE Scenario Context\n\n');
fprintf(fid, '**Scenario:** %s\n\n', sc.scenario.SFOE_scenario);
fprintf(fid, '**Planning Year:** %d\n\n', sc.scenario.year);

fprintf(fid, '### National Projections\n\n');
fprintf(fid, '| Indicator | Value |\n');
fprintf(fid, '|-----------|-------|\n');
fprintf(fid, '| National Population | %d |\n', sc.scenario.population_national);
fprintf(fid, '| PV Installed Capacity | %d MW |\n', sc.scenario.PV_national_MW);
fprintf(fid, '| Total Installed Capacity | %d MW |\n', sc.scenario.total_installed_capacity_MW);
fprintf(fid, '| EV Fleet | %d thousand vehicles |\n', sc.scenario.EV_national_thousands);

fprintf(fid, '\n### From Global to Local: Sion & Sierre\n\n');
fprintf(fid, '| Indicator | Value |\n');
fprintf(fid, '|-----------|-------|\n');
fprintf(fid, '| Population Sion & Sierre | %d |\n', sc.scenario.population_sion_sierre);
fprintf(fid, '| Population Share (national) | %.2f%% |\n', ...
    100*sc.scenario.population_sion_sierre/sc.scenario.population_national);
fprintf(fid, '| LV Networks in Portfolio | %d |\n', length(sc.combined_data.LV_grid));
fprintf(fid, '| Peak Demand Factor | %.0f%% |\n', stats.config.demand_level.demand_factor*100);
fprintf(fid, '| Total Installed Demand (based on the demand factor) | %.1f MW |\n', (sc.Pnet_total*stats.config.demand_level.demand_factor)/1e3);
fprintf(fid, '| Total PV Allocated to LV Networks | %.1f MWp |\n', stats.PV_total_MWp);
fprintf(fid, '| Total EVs Allocated to LV Networks | %d vehicles |\n', round(stats.EV_total));

%% Summary Statistics
fprintf(fid, '\n## Summary Statistics\n\n');
fprintf(fid, '| Metric | Value |\n');
fprintf(fid, '|--------|-------|\n');
fprintf(fid, '| Networks Analyzed | %d |\n', stats.n_networks);
fprintf(fid, '| Total Demand of Analyzed Networks | %.1f MW |\n', stats.total_demand_MW);
fprintf(fid, '| Total PV of Analyzed Networks | %.1f MWp |\n', stats.PV_total_MWp);
fprintf(fid, '| Total EVs of Analyzed Networks | %d |\n', round(stats.EV_total));
fprintf(fid, '| Fully Converged (all timesteps) | %d (%.1f%%) |\n', ...
    stats.n_converged_all, 100*stats.n_converged_all/stats.n_networks);
fprintf(fid, '| Partial/Non-Converged | %d |\n', stats.n_non_converged);
fprintf(fid, '| [Networks Requiring Reinforcement](temporal_reinforcement_%s.md) | [%d (%.1f%%)](temporal_reinforcement_%s.md) |\n', ...
    scenario_name, stats.n_violations, stats.violation_pct, scenario_name);
fprintf(fid, '| [Networks Meeting Operational Goals](temporal_compliant_%s.md) | [%d (%.1f%%)](temporal_compliant_%s.md) |\n', ...
    scenario_name, stats.n_networks - stats.n_violations, ...
    100*(1-stats.violation_pct/100), scenario_name);

%% PV and EV split
fprintf(fid, '\n## DER Hosting: Compliant vs Reinforcement Needed\n\n');
fprintf(fid, '| Indicator | Needs Reinforcement | Meets Operational Goals |\n');
fprintf(fid, '|-----------|--------------------|--------------------------|\n');
fprintf(fid, '| PV Capacity | %.1f MWp (%.1f%%) | %.1f MWp (%.1f%%) |\n', ...
    stats.PV_violation_kWp/1e3, 100*stats.PV_violation_kWp/max(stats.PV_total_kWp,1), ...
    stats.PV_compliant_kWp/1e3, 100*stats.PV_compliant_kWp/max(stats.PV_total_kWp,1));
fprintf(fid, '| EV Count | %d (%.1f%%) | %d (%.1f%%) |\n', ...
    round(stats.EV_violation), 100*stats.EV_violation/max(stats.EV_total,1), ...
    round(stats.EV_compliant), 100*stats.EV_compliant/max(stats.EV_total,1));

fprintf(fid, '\n> **Key insight:** Networks requiring reinforcement represent %.1f%% of the portfolio but host %.1f%% of allocated PV capacity and %.1f%% of EVs — highlighting the correlation between DER penetration and grid stress.\n\n', ...
    stats.violation_pct, ...
    100*stats.PV_violation_kWp/max(stats.PV_total_kWp,1), ...
    100*stats.EV_violation/max(stats.EV_total,1));

%% Violation Breakdown
fprintf(fid, '\n## Violation Breakdown\n\n');
fprintf(fid, '| Violation Type | Networks Affected |\n');
fprintf(fid, '|----------------|-------------------|\n');
fprintf(fid, '| At least one violation | %d (%.1f%%) |\n', ...
    stats.n_violations, stats.violation_pct);
fprintf(fid, '| Undervoltage (<0.9 p.u.) | %d |\n', stats.undervolt_networks);
fprintf(fid, '| Overvoltage (>1.1 p.u.) | %d |\n', stats.overvolt_networks);
fprintf(fid, '| Line Overload (OL) | %d |\n', stats.overload_networks);
fprintf(fid, '| Transformer Congestion (TC) | %d |\n', stats.congestion_networks);

%% Numerical Quality Note
fprintf(fid, '\n## Numerical Quality\n\n');
fprintf(fid, '- **Average LF convergence rate:** %.1f%%\n', stats.avg_convergence_pct);
fprintf(fid, '- **Minimum LF convergence rate:** %.1f%%\n', stats.min_convergence_pct);
fprintf(fid, '- **Networks with partial non-convergence:** %d\n', stats.n_non_converged);
fprintf(fid, '\n> Networks with non-converging timesteps are flagged in the network tables.\n');

fclose(fid);
fprintf('Summary report saved: %s\n', filename);

%% ================================================================
%  FILE 2 — NETWORKS REQUIRING REINFORCEMENT
%% ================================================================
filename2 = sprintf('sanity-check-website/docs/temporal_reinforcement_%s.md', scenario_name);
fid2 = fopen(filename2, 'w');

fprintf(fid2, '# Networks Requiring Reinforcement: %s\n\n', scenario_name);
fprintf(fid2, '**Total:** %d networks (%.1f%% of portfolio)\n\n', ...
    stats.n_violations, stats.violation_pct);
n_viol_converged = sum(stats.per_network.has_violations & stats.per_network.converged_all);
fprintf(fid2, '**Fully converged LF:** %d of %d violation networks (%.1f%%)\n\n', ...
    n_viol_converged, stats.n_violations, 100*n_viol_converged/stats.n_violations);

fprintf(fid2, '## Violation Type Summary\n\n');
fprintf(fid2, '| Violation Type | Networks | Percentage |\n');
fprintf(fid2, '|----------------|----------|------------|\n');

% Count networks with each violation type (within violation set only)
viol_mask = stats.per_network.has_violations;
n_UV_only   = sum(viol_mask & stats.per_network.has_UV & ~stats.per_network.has_OV & ~stats.per_network.has_OL & ~stats.per_network.has_congestion);
n_OV_only   = sum(viol_mask & stats.per_network.has_OV & ~stats.per_network.has_UV & ~stats.per_network.has_OL & ~stats.per_network.has_congestion);
n_OL_only   = sum(viol_mask & stats.per_network.has_OL & ~stats.per_network.has_UV & ~stats.per_network.has_OV & ~stats.per_network.has_congestion);
n_TC_only   = sum(viol_mask & stats.per_network.has_congestion & ~stats.per_network.has_UV & ~stats.per_network.has_OV & ~stats.per_network.has_OL);
n_UV_OV     = sum(viol_mask & stats.per_network.has_UV & stats.per_network.has_OV & ~stats.per_network.has_OL & ~stats.per_network.has_congestion);
n_UV_OL     = sum(viol_mask & stats.per_network.has_UV & stats.per_network.has_OL & ~stats.per_network.has_OV & ~stats.per_network.has_congestion);
n_OV_OL     = sum(viol_mask & stats.per_network.has_OV & stats.per_network.has_OL & ~stats.per_network.has_UV & ~stats.per_network.has_congestion);
n_UV_TC     = sum(viol_mask & stats.per_network.has_UV & stats.per_network.has_congestion & ~stats.per_network.has_OV & ~stats.per_network.has_OL);
n_OV_TC     = sum(viol_mask & stats.per_network.has_OV & stats.per_network.has_congestion & ~stats.per_network.has_UV & ~stats.per_network.has_OL);
n_OL_TC     = sum(viol_mask & stats.per_network.has_OL & stats.per_network.has_congestion & ~stats.per_network.has_UV & ~stats.per_network.has_OV);
n_all_four  = sum(viol_mask & stats.per_network.has_UV & stats.per_network.has_OV & stats.per_network.has_OL & stats.per_network.has_congestion);


fprintf(fid2, '| Undervoltage (UV) only | %d | %.1f%% |\n',       n_UV_only,  100*n_UV_only/stats.n_violations);
fprintf(fid2, '| Overvoltage (OV) only | %d | %.1f%% |\n',        n_OV_only,  100*n_OV_only/stats.n_violations);
fprintf(fid2, '| Line Overload (OL) only | %d | %.1f%% |\n',      n_OL_only,  100*n_OL_only/stats.n_violations);
fprintf(fid2, '| Transformer Congestion (TC) only | %d | %.1f%% |\n', n_TC_only, 100*n_TC_only/stats.n_violations);
fprintf(fid2, '| UV + OV | %d | %.1f%% |\n',                      n_UV_OV,    100*n_UV_OV/stats.n_violations);
fprintf(fid2, '| UV + OL | %d | %.1f%% |\n',                      n_UV_OL,    100*n_UV_OL/stats.n_violations);
fprintf(fid2, '| OV + OL | %d | %.1f%% |\n',                      n_OV_OL,    100*n_OV_OL/stats.n_violations);
fprintf(fid2, '| UV + TC | %d | %.1f%% |\n',                      n_UV_TC,    100*n_UV_TC/stats.n_violations);
fprintf(fid2, '| OV + TC | %d | %.1f%% |\n',                      n_OV_TC,    100*n_OV_TC/stats.n_violations);
fprintf(fid2, '| OL + TC | %d | %.1f%% |\n',                      n_OL_TC,    100*n_OL_TC/stats.n_violations);
fprintf(fid2, '| All (UV + OV + OL + TC) | %d | %.1f%% |\n\n',    n_all_four, 100*n_all_four/stats.n_violations);

fprintf(fid2, '_[← Back to Summary](temporal_analysis_%s.md)_\n\n', scenario_name);

fprintf(fid2, '| # | Network | Full LF Convergence | Violations | T_rat (kVA) | # Tr | PV (kWp) | EVs | Demand (kW) | Figures |\n');
fprintf(fid2, '|---|---------|--------------------:|------------|------------:|-----:|---------:|----:|------------:|---------|\n');

viol_idx = find(stats.per_network.has_violations);
for i = 1:length(viol_idx)
    k = viol_idx(i);
    net_id  = stats.per_network.network_ids{k};
    net_num = strrep(net_id, 'LV_Grid_', '');

    % Convergence flag
    if stats.per_network.converged_all(k)
        conv_flag = '✅';
    else
        conv_flag = sprintf('⚠️ %.0f%%', stats.per_network.converged_pct(k));
    end

    % Violation types
    viol_str = '';
    if stats.per_network.has_UV(k),         viol_str = [viol_str 'UV ']; end
    if stats.per_network.has_OV(k),         viol_str = [viol_str 'OV ']; end
    if stats.per_network.has_OL(k),         viol_str = [viol_str 'OL ']; end
    if stats.per_network.has_congestion(k), viol_str = [viol_str 'TC ']; end
    viol_str = strtrim(viol_str);

    % URLs
    temp_url     = sprintf('scenario_%s/temporal_figures/%s_temporal.png', scenario_name, net_id);
    topology_url = sprintf('figures/%s_topology.png', net_num);
    oneshot_url  = sprintf('figures/%s_figures.png', net_num);

    fprintf(fid2, '| %d | %s | %s | %s | %.0f | %d | %.1f | %d | %.1f | [temporal](%s) · [topology](%s) · [one-shot](%s) |\n', ...
        i, net_id, conv_flag, viol_str, ...
        stats.per_network.T_rat_kVA_total(k), ...
        stats.per_network.n_transformers(k), ...
        stats.per_network.PV_kWp(k), ...
        round(stats.per_network.EV_count(k)), ...
        stats.per_network.demand_kW(k), ...
        temp_url, topology_url, oneshot_url);
end

% Collect IDs of violation networks with full LF convergence
viol_converged_mask = stats.per_network.has_violations & stats.per_network.converged_all;
viol_converged_ids  = string(stats.per_network.network_ids(viol_converged_mask));

% Collect IDs of violation networks with full LF convergence AND single transformer
viol_converged_single_tr_mask = viol_converged_mask & (stats.per_network.n_transformers == 1);
viol_converged_single_tr_ids  = string(stats.per_network.network_ids(viol_converged_single_tr_mask));

save(sprintf('output/violation_converged_ids_%s.mat', scenario_name), ...
    'viol_converged_ids', 'viol_converged_single_tr_ids');
fprintf('Saved violation+converged IDs: %d networks\n', numel(viol_converged_ids));
fprintf('Saved violation+converged+single transformer IDs: %d networks\n', numel(viol_converged_single_tr_ids));
fclose(fid2);
fprintf('Reinforcement report saved: %s\n', filename2);

%% ================================================================
%  FILE 3 — NETWORKS MEETING OPERATIONAL GOALS
%% ================================================================
filename3 = sprintf('sanity-check-website/docs/temporal_compliant_%s.md', scenario_name);
fid3 = fopen(filename3, 'w');

fprintf(fid3, '# Networks Meeting Operational Goals: %s\n\n', scenario_name);
fprintf(fid3, '**Total:** %d networks (%.1f%% of portfolio)\n\n', ...
    stats.n_networks - stats.n_violations, 100*(1-stats.violation_pct/100));
fprintf(fid3, '_[← Back to Summary](temporal_analysis_%s.md)_\n\n', scenario_name);

fprintf(fid3, '| # | Network | Full LF Convergence | T_rat (kVA) | # Tr | PV (kWp) | EVs | Demand (kW) | Figures |\n');
fprintf(fid3, '|---|---------|--------------------:|------------:|-----:|---------:|----:|------------:|---------|\n');

compliant_idx = find(~stats.per_network.has_violations);
for i = 1:length(compliant_idx)
    k = compliant_idx(i);
    net_id  = stats.per_network.network_ids{k};

    % Convergence flag
    if stats.per_network.converged_all(k)
        conv_flag = '✅';
    else
        conv_flag = sprintf('⚠️ %.0f%%', stats.per_network.converged_pct(k));
    end

    % URL
    temp_url = sprintf('scenario_%s/temporal_figures/%s_temporal.png', scenario_name, net_id);

    fprintf(fid3, '| %d | %s | %s | %.0f | %d | %.1f | %d | %.1f | [temporal](%s) |\n', ...
        i, net_id, conv_flag, ...
        stats.per_network.T_rat_kVA_total(k), ...
        stats.per_network.n_transformers(k), ...
        stats.per_network.PV_kWp(k), ...
        round(stats.per_network.EV_count(k)), ...
        stats.per_network.demand_kW(k), ...
        temp_url);
end

fclose(fid3);
fprintf('Compliant report saved: %s\n', filename3);

end