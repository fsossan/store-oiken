function plot_tech_selection_summary(out)
% PLOT_TECH_SELECTION_SUMMARY  Show which technology was selected and why.

if nargin < 1 || ~isfield(out, 'selection') || isempty(out.selection)
    error('plot_tech_selection_summary:MissingSelection', ...
        'The output struct does not contain selection data yet.');
end

sel = out.selection;
if ~isfield(sel, 'selected_nodes') || isempty(sel.selected_nodes)
    warning('plot_tech_selection_summary:NoSelection', ...
        'No installed ESS technologies are available to plot.');
    return
end

figure('Name', 'ESS Technology Selection', 'Color', 'w');
tiledlayout(2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
bar(sel.selected_nodes, sel.tech_index(sel.selected_nodes));
yticks(1:numel(sel.tech_names));
yticklabels(sel.tech_names);
ylabel('Selected technology');
xlabel('Node index');
title('Installed technology by node');
grid on;

nexttile;
bar(sel.selected_nodes, sel.required_c_rate(sel.selected_nodes, sel.tech_index(sel.selected_nodes)));
ylabel('Required C-rate');
xlabel('Node index');
title('Required C-rate at selected sites');
grid on;

nexttile([1 2]);
axis off;
text(0.01, 0.92, sprintf('Selected nodes: %d', numel(sel.selected_nodes)), 'FontWeight', 'bold');

y = 0.80;
for k = 1:min(numel(sel.selected_nodes), 10)
    n = sel.selected_nodes(k);
    text(0.01, y, sprintf('Node %d: %s', n, sel.reason(n)));
    y = y - 0.08;
end
if numel(sel.selected_nodes) > 10
    text(0.01, y, sprintf('... and %d more nodes', numel(sel.selected_nodes) - 10));
end
title('Selection explanation');

sgtitle(sprintf('ESS technology selection | network %s', string(out.summary.network_id)), ...
    'FontWeight', 'bold');

end