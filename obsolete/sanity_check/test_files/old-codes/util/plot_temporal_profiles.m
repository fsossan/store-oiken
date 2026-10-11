function plot_temporal_profiles(profiles, grid_data, net_id)
%PLOT_TEMPORAL_PROFILES  One figure: demand / PV / EV profiles (each its own
%                         panel) plus their aggregate.
%
%   plot_temporal_profiles(profiles, grid_data)
%   plot_temporal_profiles(profiles, grid_data, net_id)
%
%   profiles  : struct   output of build_temporal_profiles
%   grid_data : struct   output of get_grid_SFOE (for basepower). Named
%               grid_data, not grid, because this function calls the
%               `grid on` plotting command -- MATLAB does not allow a
%               variable and a command to share a name in the same scope.
%   net_id    : string   optional, for the figure title
%
%   Works straight off build_temporal_profiles' output -- no load flow
%   required, so it stays useful for inspecting profile generation in
%   isolation. For the post-load-flow diagnostic (also covers voltage/
%   current), see plot_gm_temporal_profiles.

if nargin < 3; net_id = ''; end

% 3-phase kW scaling: Sb = 100 kVA single-phase base -> x3 for 3-phase,
% /1000 for kW (bp*ph convention, see CLAUDE.md; matches plot_gm_temporal_profiles).
scale = (grid_data.basepower / 1000) * 3;

D_kw   = real(profiles.nodal_injections_D_pu)  * scale;
PV_kw  = real(profiles.nodal_injections_PV_pu) * scale;
EV_kw  = real(profiles.nodal_injections_EV_pu) * scale;
agg_kw = sum(D_kw, 2) + sum(PV_kw, 2) + sum(EV_kw, 2);

t = (1:profiles.T)';

figure('Name', 'Temporal profiles: demand / PV / EV / aggregate', 'Color', 'w');
tiledlayout(2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
plot_panel_or_placeholder(t, D_kw, 'No demand nodes');
if isfield(profiles, 'demand_cluster') && ~isempty(profiles.demand_cluster)
    node_ids = find(profiles.nodes_with_demand) + 1;
    legend(arrayfun(@(c,n) sprintf('C%d_{N%d}', c, n), ...
        profiles.demand_cluster(:), node_ids, 'UniformOutput', false), ...
        'Location', 'best', 'FontSize', 7);
end
xlabel('Timestep (day-contiguous)'); ylabel('Power [kW]');
title(sprintf('Demand (%d node%s)', size(D_kw,2), plural_s(size(D_kw,2)))); grid on;

nexttile;
plot_panel_or_placeholder(t, PV_kw, 'No PV nodes');
xlabel('Timestep (day-contiguous)'); ylabel('Power [kW]');
title(sprintf('PV (%d node%s)', size(PV_kw,2), plural_s(size(PV_kw,2)))); grid on;

nexttile;
plot_panel_or_placeholder(t, EV_kw, 'No EV nodes');
xlabel('Timestep (day-contiguous)'); ylabel('Power [kW]');
title(sprintf('EV (%d node%s)', size(EV_kw,2), plural_s(size(EV_kw,2)))); grid on;

nexttile;
plot(t, agg_kw, 'k-', 'LineWidth', 1.2);
xlabel('Timestep (day-contiguous)'); ylabel('Power [kW]');
title('Aggregate (demand + PV + EV)'); grid on;

sgtitle(sprintf('Network %s — temporal profiles', strrep(string(net_id), '_', '\_')), ...
    'FontWeight', 'bold');

end

% =========================================================================
function plot_panel_or_placeholder(t, X, empty_msg)
if ~isempty(X) && any(X(:) ~= 0)
    plot(t, X);
elseif ~isempty(X)
    plot(t, X);   % all-zero but present (e.g. demand test-toggled off) -- still show the flat line
else
    text(0.5, 0.5, empty_msg, 'HorizontalAlignment', 'center'); axis off;
end
end

function s = plural_s(n)
if n == 1; s = ''; else; s = 's'; end
end
