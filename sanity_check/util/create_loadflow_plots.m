function create_loadflow_plots(lf_data, converged_data)
%CREATE_LOADFLOW_PLOTS Generate plots for loadflow analysis with enhancements

figure('Position', [100 100 1600 900]);  % Wider for 2x4 layout

%% Subplot 1: Convergence iterations
subplot(2,4,1)
iters = [converged_data.iterations];
h1 = histogram(iters, 'BinMethod', 'integers', 'FaceColor', [0.3 0.6 0.8]);
xlabel('Iterations to Converge'); ylabel('Count');
title('Convergence Iterations');
grid on;

% Add counts on bars
xtips1 = h1.BinEdges(1:end-1) + 0.5;
ytips1 = h1.Values;
non_zero1 = ytips1 > 0;
text(xtips1(non_zero1), ytips1(non_zero1), string(ytips1(non_zero1)), ...
     'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 8);

% Add summary stats
text(max(xlim)*0.7, max(ylim)*0.85, sprintf('Mean: %.1f\nMedian: %.0f\nMax: %d', ...
     mean(iters), median(iters), max(iters)), ...
     'FontSize', 9, 'BackgroundColor', 'w', 'EdgeColor', 'k');

%% Subplot 2: Minimum voltage distribution
subplot(2,4,2)
min_v = [converged_data.min_voltage];
h2 = histogram(min_v, 'BinWidth', 0.01, 'FaceColor', [0.8 0.4 0.4]);
xlabel('Minimum Voltage (p.u.)'); ylabel('Count');
title('Minimum Voltage Distribution');
grid on;

% Reference lines with legend
hold on;
l1 = xline(0.9, 'r-', '0.9 p.u','LineWidth', 2);

hold off;

% Add counts on bars (only show some to avoid clutter)
xtips2 = h2.BinEdges(1:end-1) + h2.BinWidth/2;
ytips2 = h2.Values;
% % Only show top 5 bars
% [~, top_idx] = maxk(ytips2, 5);
% text(xtips2(top_idx), ytips2(top_idx), string(ytips2(top_idx)), ...
%      'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 8);

% Add summary stats (top-right to avoid legend)
n_critical = sum(min_v < 0.9);
n_warning = sum(min_v < 0.95 & min_v >= 0.9);
text(max(xlim)*0.7, max(ylim)*0.95, sprintf('Mean: %.3f\n Lowest: %.3f\n <0.9: %d\n', ...
     mean(min_v), min(min_v), n_critical), ...
     'FontSize', 9, 'BackgroundColor', 'w', 'EdgeColor', 'k', ...
     'VerticalAlignment', 'top','HorizontalAlignment','right');

%% Subplot 3: Voltage drop
subplot(2,4,3)
v_drop = [converged_data.voltage_drop];
h3 = histogram(v_drop, 'BinWidth', 0.005, 'FaceColor', [0.6 0.5 0.7]);
xlabel('Voltage Drop (p.u.)'); ylabel('Count');
title('Voltage Drop Distribution');
grid on;

% Reference lines with legend
hold on;
l3 = xline(0.05, 'r--', 'LineWidth', 1.5);
l4 = xline(0.10, 'r-', 'LineWidth', 2);
legend([l3 l4], {'5% drop', '10% drop'}, 'Location', 'northeast');
hold off;



%% Subplot 4: Maximum current (FIXED WITH LEGEND)
subplot(2,4,4)
max_i = [converged_data.max_current_pu];
h4 = histogram(max_i, 'BinWidth', 0.05, 'FaceColor', [0.9 0.6 0.3]);
xlabel('Maximum Current (p.u.)'); ylabel('Count');
title('Maximum Current Distribution');
grid on;

% Reference lines with legend (NO inline labels)
hold on;
l5 = xline(1.0, 'r-', 'LineWidth', 2);

legend(l5 , '1.0 p.u (line rating )', 'Location', 'northeast');
hold off;

% Add summary stats (moved to avoid overlap)
n_overload = sum(max_i > 1.0);
n_severe = sum(max_i > 1.1);
% text(max(xlim)*0.5, max(ylim)*0.95, sprintf('Mean: %.2f\nMax: %.2f\n>100%%: %d\n>110%%: %d', ...
%      mean(max_i), max(max_i), n_overload, n_severe), ...
%      'FontSize', 9, 'BackgroundColor', 'w', 'EdgeColor', 'k', ...
%      'VerticalAlignment', 'top');

%% Subplot 5: Overloaded lines per network
subplot(2,4,5)
n_overload = [converged_data.n_overloaded];
h5 = histogram(n_overload, 'BinMethod', 'integers', 'FaceColor', [0.8 0.3 0.3]);
xlabel('Number of Overloaded Lines'); ylabel('Count');
title('Overloaded Lines per Network');
grid on;

% Set y-limit with padding BEFORE adding text
ylim([0 max(h5.Values)*1.1]);  

% Add counts on bars
xtips5 = h5.BinEdges(1:end-1) + 0.5;
ytips5 = h5.Values;
non_zero5 = ytips5 > 0;
text(xtips5(non_zero5), ytips5(non_zero5), string(ytips5(non_zero5)), ...
     ...
     'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 8);

% Add summary stats
text(max(xlim)*0.6, max(ylim)*0.85, sprintf('Networks: %d\nTotal lines: %d', ...
     sum(n_overload > 0), sum(n_overload)), ...
     'FontSize', 9, 'BackgroundColor', 'w', 'EdgeColor', 'k');

%% Subplot 6: Losses
subplot(2,4,6)
losses = [converged_data.total_losses_kW];
losses_valid = losses(losses >= 0 & losses < 1000);  % Filter outliers
h6 = histogram(losses_valid, 'BinWidth', 10, 'FaceColor', [0.5 0.7 0.5]);
xlabel('Losses (kW)'); ylabel('Count');
title('System Losses Distribution');
grid on;

% Add summary stats
total_loss = sum(losses_valid);
avg_loss = mean(losses_valid);
text(max(xlim)*0.6, max(ylim)*0.85, sprintf('Total: %.0f kW\nMean: %.1f kW\nMedian: %.1f kW', ...
     total_loss, avg_loss, median(losses_valid)), ...
     'FontSize', 9, 'BackgroundColor', 'w', 'EdgeColor', 'k');

%% Subplot 7: Network health summary
subplot(2,4,7)
has_overloads = [converged_data.n_overloaded] > 0;
has_undervolt = [converged_data.min_voltage] < 0.9;
has_overvolt = [converged_data.max_voltage] > 1.1;
has_any = has_overloads | has_undervolt | has_overvolt;

categories = {'Healthy', 'Overloads', 'Undervolt', 'Overvolt', 'Any'};
counts = [sum(~has_any), sum(has_overloads), sum(has_undervolt), sum(has_overvolt), sum(has_any)];
pcts = 100 * counts / length(converged_data);

b = bar(counts);
b.FaceColor = 'flat';
b.CData(1,:) = [0.3 0.7 0.3];  % Green for healthy
b.CData(2:end,:) = repmat([0.9 0.4 0.4], 4, 1);  % Red for violations

set(gca, 'XTickLabel', categories, 'XTickLabelRotation', 45);
ylabel('Number of Networks');
title('Network Health Summary');
grid on;

% Set y-axis limit with 20% padding for labels
ylim([0 max(counts)*1.12]);  % Add 25% space at top


% Add counts and percentages on bars
for k = 1:length(counts)
    text(k, counts(k), sprintf('%d\n(%.1f%%)', counts(k), pcts(k)), ...
         'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
         'FontSize', 8, 'FontWeight', 'bold');
end

%% Subplot 8: Voltage compliance breakdown (FIXED LABELS)
subplot(2,4,8)
min_v = [converged_data.min_voltage];
max_v = [converged_data.max_voltage];

% Categorize networks
compliant = (min_v >= 0.9) & (max_v <= 1.1);
critical_low = min_v < 0.9;
critical_high = max_v > 1.1;

% Shorter, clearer labels
categories_v = {'Compliant', 'Crit Low', 'Crit High'};
counts_v = [sum(compliant),  sum(critical_low), sum(critical_high)];
pcts_v = 100 * counts_v / length(converged_data);

bv = bar(counts_v);
bv.FaceColor = 'flat';
bv.CData(1,:) = [0.3 0.7 0.3];   % Green
bv.CData(2,:) = [0.9 0.3 0.3];   % Red
bv.CData(3,:) = [0.9 0.3 0.3];   % Red


set(gca, 'XTickLabel', categories_v, 'FontSize', 9);
ylabel('Number of Networks');
title('Voltage Compliance Breakdown');
grid on;

% Set y-limit with padding BEFORE adding text
ylim([0 max(counts_v)*1.1]);  


% Add percentages
for k = 1:length(counts_v)
    if counts_v(k) > 0
        text(k, counts_v(k), sprintf('%d\n(%.1f%%)', counts_v(k), pcts_v(k)), ...
             'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
             'FontSize', 8, 'FontWeight', 'bold');
    end
end

% % Add legend explaining categories
% text(0.5, max(ylim)*0.95, sprintf('0.95-1.05 | 0.9-0.95 | <0.9 | 1.05-1.1 | >1.1'), ...
%      'FontSize', 8, 'HorizontalAlignment', 'left', 'VerticalAlignment', 'top', ...
%      'BackgroundColor', 'w', 'EdgeColor', 'k');

%% Overall title
sgtitle('One-shot Loadflow Analysis Results', 'FontSize', 14, 'FontWeight', 'bold');

%% Save figure
saveas(gcf, 'sanity-check-website/docs/One_shot_loadflow_analysis.png');
fprintf('Figure saved: sanity-check-website/docs/One_shot_loadflow_analysis.png\n');

end