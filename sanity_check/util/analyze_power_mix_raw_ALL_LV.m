function analyze_power_mix_raw_ALL_LV(varargin)
%ANALYZE_POWER_MIX_RAW Analyze power demand and PV from raw network data
%
%   analyze_power_mix_raw(Sierre, 'Sierre')
%   analyze_power_mix_raw(Sion, 'Sion')

if nargin == 0
    error('No data input for Power Mix Analysis')
else
    data = varargin{:};
end

fprintf('\n=== ALL LV grid Power Mix Analysis (Raw Data) ===\n');

%% Load configuration
config = jsondecode(fileread('general_config.json'));
demand_factor = config.demand_level.demand_factor;
generation_factor = config.demand_level.generation_factor;


%% Initialize storage
n_networks = numel(data.LV_grid_id);
power_data = struct([]);

fprintf('Analyzing %d networks...\n', n_networks);

%% Process each network
for i = 1:n_networks
    network_id = string(regexp(data.LV_grid_id{i}, '\d+', 'match', 'once'));

    try
        % Get LV grid data
        lv_grid = data.LV_grid{1,i};

        % Extract power columns (assuming columns 8-10: P, Q, PV)
        if width(lv_grid) >= 10
            % Deduplicate by From-To node pair to avoid double counting
            % parallel cables connecting the same nodes
            from_to_keys = strcat(lv_grid.From, '|', lv_grid.To);
            [~, unique_idx] = unique(from_to_keys, 'stable');
            lv_grid_unique = lv_grid(unique_idx, :);

            P_demand = lv_grid_unique{:, 8};
            Q_demand = lv_grid_unique{:, 9};
            PV_gen   = lv_grid_unique{:, 10};
        else
            disp('skipped width(lv_grid)>=10\n')
            fprint('Skipped %s\n',network_id)
            continue;  % Skip if data missing
        end

        % Aggregate totals
        power_data(i).network_id = network_id;
        power_data(i).total_P_kW = sum(P_demand) * demand_factor;
        power_data(i).total_Q_kVAR = sum(Q_demand) * demand_factor;
        power_data(i).total_PV_kW = sum(PV_gen) * generation_factor;
        power_data(i).net_demand_kW = power_data(i).total_P_kW - power_data(i).total_PV_kW;
        power_data(i).PV_penetration_pct = (power_data(i).total_PV_kW / power_data(i).total_P_kW) * 100;
        power_data(i).power_factor = power_data(i).total_P_kW / sqrt(power_data(i).total_P_kW^2 + power_data(i).total_Q_kVAR^2);
        power_data(i).has_PV = power_data(i).total_PV_kW > 0;

    catch ME
        fprintf('Error processing network %s: %s\n', network_id, ME.message);
        continue;
    end
end

%% Remove empty entries
power_data = power_data(~arrayfun(@(x) isempty(x.network_id), power_data));

%% Statistics
fprintf('\n--- Summary Statistics ---\n');
fprintf('Networks analyzed: %d\n', length(power_data));

total_P = sum([power_data.total_P_kW]);
total_Q = sum([power_data.total_Q_kVAR]);
total_PV = sum([power_data.total_PV_kW]);
total_net = sum([power_data.net_demand_kW]);

fprintf('Total load: %.0f kW\n', total_P);
fprintf('Total reactive: %.0f kVAR\n', total_Q);
fprintf('Total PV: %.0f kW\n', total_PV);
fprintf('Total net demand: %.0f kW\n', total_net);
fprintf('Overall PV penetration: %.1f%%\n', (total_PV/total_P)*100);

% Networks with PV
n_with_PV = sum([power_data.has_PV]);
fprintf('Networks with PV: %d/%d (%.1f%%)\n', n_with_PV, length(power_data), 100*n_with_PV/length(power_data));

% PV penetration statistics (only for networks with PV)
pv_networks = power_data([power_data.has_PV]);
if ~isempty(pv_networks)
    pv_pen = [pv_networks.PV_penetration_pct];
    pv_pen_finite = pv_pen(isfinite(pv_pen));  % Remove Inf and NaN

    if ~isempty(pv_pen_finite)
        fprintf('PV penetration (networks with PV and load):\n');
        fprintf('  Mean: %.1f%%\n', mean(pv_pen_finite));
        fprintf('  Median: %.1f%%\n', median(pv_pen_finite));
        fprintf('  Max: %.1f%%\n', max(pv_pen_finite));
    end

    % Report special cases
    n_inf = sum(isinf(pv_pen));
    if n_inf > 0
        fprintf('  Networks with PV but no load: %d\n', n_inf);
    end

end

% Power factor
pf_all = [power_data.power_factor];
pf_valid = pf_all(isfinite(pf_all));
avg_pf = mean(pf_valid);
fprintf('Average power factor: %.3f\n', avg_pf);

%% Categorize by PV penetration
pen_0 = sum([power_data.PV_penetration_pct] == 0);
pen_25 = sum([power_data.PV_penetration_pct] > 0 & [power_data.PV_penetration_pct] <= 25);
pen_50 = sum([power_data.PV_penetration_pct] > 25 & [power_data.PV_penetration_pct] <= 50);
pen_75 = sum([power_data.PV_penetration_pct] > 50 & [power_data.PV_penetration_pct] <= 75);
pen_100 = sum([power_data.PV_penetration_pct] > 75 & [power_data.PV_penetration_pct] <= 100);
pen_100_plus = sum([power_data.PV_penetration_pct] > 100);

fprintf('\nPV Penetration Distribution:\n');
fprintf('  0%%:        %d networks\n', pen_0);
fprintf('  1-25%%:     %d networks\n', pen_25);
fprintf('  26-50%%:    %d networks\n', pen_50);
fprintf('  51-75%%:    %d networks\n', pen_75);
fprintf('  76-100%%:  %d networks\n',  pen_100);
fprintf('  100+%%:  %d networks\n',    pen_100_plus);

%% Visualizations
figure;

% Subplot 1: Load vs PV scatter
subplot(2,3,1)
scatter([power_data.total_P_kW], [power_data.total_PV_kW], 30, 'filled', 'MarkerFaceAlpha', 0.6);
xlabel('Total Load (kW)'); ylabel('Total PV (kW)');
title('All LV grid:  Load vs PV');
grid on;
hold on;
max_val = max([power_data.total_P_kW]);
plot([0 max_val], [0 max_val], 'r--', 'LineWidth', 1.5); % 100% line
legend('Networks', '100% penetration', 'Location', 'northwest');

% Subplot 2: PV penetration histogram
subplot(2,3,2)
pv_pen_all = [power_data.PV_penetration_pct];
pv_pen_all(~isfinite(pv_pen_all)) = 0;

h = histogram(pv_pen_all, 'BinMethod', 'fd', 'FaceColor', [0.3 0.7 0.4]);
xlabel('PV Penetration (%)'); ylabel('Count');
title('All LV grid - PV Penetration Distribution');
grid on;

% Add counts on bars
xtips = (h.BinEdges(1:end-1) + h.BinEdges(2:end)) / 2;
ytips = h.Values;
non_zero = ytips > 0;
text(xtips(non_zero), ytips(non_zero), string(ytips(non_zero)), ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 8);

% Subplot 3: Total demand distribution
subplot(2,3,3)
h = histogram([power_data.total_P_kW], 'BinMethod', 'fd', 'FaceColor', [0.2 0.6 0.8]);
xlabel('Total Load (kW)'); ylabel('Count');
title('All LV grid - Load Distribution');
grid on;
% Add counts on bars
xtips = (h.BinEdges(1:end-1) + h.BinEdges(2:end)) / 2;
ytips = h.Values;
non_zero = ytips > 0;
text(xtips(non_zero), ytips(non_zero), string(ytips(non_zero)), ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 8);

% Subplot 4: Power factor distribution
subplot(2,3,4)
histogram([power_data.power_factor], 'BinWidth', 0.02, 'FaceColor', [0.7 0.5 0.3]);
xlabel('Power Factor'); ylabel('Count');
title('All LV grid - Power Factor Distribution');
xline(0.9, 'r--', 'LineWidth', 2, 'Label', 'Target');
grid on;

% Subplot 5: PV penetration categories (bar chart)
% Subplot 5: PV penetration categories (bar chart)
subplot(2,3,5)
categories = {'0%', '1-25%', '26-50%', '51-75%', '76-100%', '>100%'};  % ← Added >100%
counts = [pen_0, pen_25, pen_50, pen_75, pen_100, pen_100_plus];  % ← Added pen_100_plus
bar(counts, 'FaceColor', [0.4 0.7 0.5]);
set(gca, 'XTickLabel', categories);
ylabel('Number of Networks');
title('All LV grid - Networks by PV Category');
grid on;

% Add counts on bars
for k = 1:length(counts)
    text(k, counts(k), string(counts(k)), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
end

% Subplot 6: Net demand (Load - PV)
subplot(2,3,6)
net_demands = [power_data.net_demand_kW];
histogram(net_demands, 'BinWidth', 50, 'FaceColor', [0.8 0.4 0.4]);
xlabel('Net Demand (kW)'); ylabel('Count');
title('All LV grid - Net Demand Distribution');
xline(0, 'r--', 'LineWidth', 2, 'Label', 'Zero net demand');
grid on;

% Save figure
saveas(gcf, 'sanity-check-website/docs/All_LV_grid_power_mix_raw.png');
fprintf('Figure saved: sanity-check-website/docs/All_LV_grid_power_mix_raw.png\n');

%% Save data
save('output/All_LV_grid_power_mix_data.mat', 'power_data');
fprintf('Data saved: output/All_LV_grid_power_mix_data.mat\n');

%% Generate markdown report
generate_power_mix_markdown_ALL_LV(power_data);

end