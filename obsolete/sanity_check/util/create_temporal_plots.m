function create_temporal_plots(result, scenario_name, fig_dir)
%CREATE_TEMPORAL_PLOTS Generate temporal analysis figure for one network
%
% Creates a 6-subplot figure:
%   1. Demand profiles
%   2. PV generation profiles
%   3. EV charging profiles
%   4. Aggregate power profiles
%   5. Nodal voltages
%   6. Line currents (p.u. of ampacity)

fig = figure('Position', [100, 100, 1600, 1000], 'Visible', 'off');

%% 1. Demand profiles
subplot(3, 2, 1);
if ~isempty(result.profiles.demand)
    plot(result.profiles.demand');
    title('Nodal Demand Profiles');
    ylabel('Power (kW)');
    xlabel('Time (15-min intervals)');
    grid on;
end

%% 2. PV generation
subplot(3, 2, 2);
if ~isempty(result.profiles.PV) && any(result.profiles.PV(:) ~= 0)
    plot(result.profiles.PV');
    title('PV Generation Profiles');
    ylabel('Power (kW)');
    xlabel('Time (15-min intervals)');
    grid on;
else
    text(0.5, 0.5, 'No PV in this network', 'HorizontalAlignment', 'center');
    title('PV Generation Profiles');
    axis off;
end

%% 3. EV charging
subplot(3, 2, 3);
if ~isempty(result.profiles.EV) && any(result.profiles.EV(:) ~= 0)
    plot(result.profiles.EV');
    title('EV Charging Profiles');
    ylabel('Power (kW)');
    xlabel('Time (15-min intervals)');
    grid on;
else
    text(0.5, 0.5, 'No EVs in this network', 'HorizontalAlignment', 'center');
    title('EV Charging Profiles');
    axis off;
end

%% 4. Aggregate power
subplot(3, 2, 4);
plot(result.profiles.aggr');
title('Aggregate Nodal Power');
ylabel('Power (kW)');
xlabel('Time (15-min intervals)');
grid on;

%% 5. Voltage timeseries
subplot(3, 2, 5);
if ~isempty(result.V_timeseries)
    plot(result.V_timeseries);
    hold on;
    yline(0.9, 'r--', 'LineWidth', 1.5);
    yline(1.1, 'r--', 'LineWidth', 1.5);
    hold off;
    title(sprintf('Nodal Voltages (violations: %d)', result.has_violations));
    ylabel('Voltage (p.u.)');
    xlabel('Time (15-min intervals)');
    grid on;
else
    text(0.5, 0.5, 'Healthy - timeseries not stored', 'HorizontalAlignment', 'center');
    title('Nodal Voltages');
    axis off;
end

%% 6. Line currents
subplot(3, 2, 6);
if ~isempty(result.I_pu_timeseries)
    plot(result.I_pu_timeseries);
    hold on;
    yline(1.0, 'r--', 'LineWidth', 1.5);
    hold off;
    title(sprintf('Line Currents (overloads: %d)', result.n_overload_events));
    ylabel('Current (p.u. of ampacity)');
    xlabel('Time (15-min intervals)');
    grid on;
elseif ~isempty(result.I_timeseries)
    % Compute I_pu on the fly
    I_pu = result.I_timeseries ./ repmat(result.ampacities', size(result.I_timeseries, 1), 1);
    plot(I_pu);
    hold on;
    yline(1.0, 'r--', 'LineWidth', 1.5);
    hold off;
    title('Line Currents');
    ylabel('Current (p.u. of ampacity)');
    xlabel('Time (15-min intervals)');
    grid on;
else
    text(0.5, 0.5, 'Healthy - timeseries not stored', 'HorizontalAlignment', 'center');
    title('Line Currents');
    axis off;
end

%% Overall title
% Escape underscores for display
network_id_display = strrep(result.network_id, '_', '\_');
scenario_name_display = strrep(scenario_name, '_', '\_');
sgtitle(sprintf('Temporal Analysis(%s): %s (seed: %d)' ,scenario_name_display,network_id_display, result.network_seed), ...
    'FontWeight', 'bold', 'FontSize', 14);
%% Save
fig_path = sprintf('%s/%s_temporal.png', fig_dir, result.network_id);
saveas(fig, fig_path);
close(fig);

end