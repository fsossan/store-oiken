%PLOT_TECH_SELECTION_SUMMARY  Three summary figures distilling the
% Tech-selection.md case study (LV_Grid_230, demand+PV(clearsky,factor=1)+EV)
% down to the actual claims, instead of the notebook's per-scenario tables.
%
%   Fig 1 - Slope chart: does the F^inv-only technology ranking survive once
%           losses (F^Sloss+F^Eloss) are priced? One panel per profile
%           scenario (EV-only, PV+EV), one line per technology. This is the
%           central finding of the whole document.
%   Fig 2 - Stacked bar: cost composition (E/S/I/L/Eloss) at the final
%           (loss-priced) objective, for Li-Ion-only / Na-Ion-only / Both,
%           PV+EV scenario -- shows WHY the reversal in Fig 1 happens
%           (Na-Ion's Eloss slice).
%   Fig 3 - Grouped bars: per-node sizing (energy capacity, converter
%           rating) for the winning "Both" scenario, PV+EV, loss-priced --
%           grounds the cost story in physical siting/sizing, colored by
%           which technology actually got picked at each node.
%
% Data sources
% ------------
%   PV+EV (9 runs: 3 cost-fn x 3 tech)      -> output/pvev_costterm_tech_study/results.mat
%   C-rate-equalized check (4 runs)          -> output/pvev_crate_equalized_check/results.mat
%   EV-only (no PV)                          -> HARDCODED below, straight from
%                                                experiments/Tech-selection.md's own
%                                                "EV charging profiles" tables
%                                                (Part 1 / Part 3). Not re-run this
%                                                session -- if you re-run the EV-only
%                                                case, swap this block for a loaded
%                                                .mat the same way as PV+EV below.
%
% Edit freely -- this is meant as a starting point, not a final artifact.
% Re-run individual sections (Ctrl+Enter per cell, if using MATLAB's Live
% Editor / cell mode) to iterate on one figure at a time.

close all

this_dir  = fileparts(mfilename('fullpath'));
repo_root = fileparts(this_dir);

%% ------------------------------------------------------------------
%  Load data
%  ------------------------------------------------------------------
s_main       = load(fullfile(repo_root, 'results', 'experiments', 'pvev_costterm_tech_study',   'results.mat'));
s_crate_pvev = load(fullfile(repo_root, 'results', 'experiments', 'pvev_crate_equalized_check', 'results.mat'));
s_crate_pv   = load(fullfile(repo_root, 'results', 'experiments', 'pv_crate_equalized_check',   'results.mat'));
r_main      = s_main.results;         % 9 entries: cost_fn x {LiIon,NaIon,Both}
r_crate_pvev = s_crate_pvev.results;  % 4 entries: cost_fn x {LiIon,NaIon_Crate1p1}
r_crate_pv   = s_crate_pv.results;    % 6 entries: cost_fn x {LiIon,NaIon,NaIon_Crate1p1}

% EV-only (base loads + EV, no PV) -- hardcoded, see header note above.
ev_only.Finv.LiIon             = 28.447;
ev_only.Finv.NaIon             = 26.2697;
ev_only.Finv.Both              = 25.3511;
ev_only.Finv_Sloss_Eloss.LiIon = 39.846;
ev_only.Finv_Sloss_Eloss.NaIon = 43.702;
ev_only.Finv_Sloss_Eloss.Both  = 37.13;

% PV-only (base loads + PV, no EV) -- hardcoded, same source as EV-only
% above (Tech-selection.md's own "Base loads + PV generation" section).
% That section never ran a "Both" scenario (only separate Li-Ion-only /
% Na-Ion-only tables), so there is no Both value here -- plot_slope_panel
% below skips the Both line/label when it's left empty.
pv_only.Finv.LiIon             = 3.607;
pv_only.Finv.NaIon             = 3.529;
pv_only.Finv.Both              = [];
pv_only.Finv_Sloss_Eloss.LiIon = 11.151;
pv_only.Finv_Sloss_Eloss.NaIon = 11.444;
pv_only.Finv_Sloss_Eloss.Both  = [];

% EV-only C-rate-equalized check, F^inv only -- also hardcoded straight
% from Tech-selection.md's own original hypothesis test (the EV section
% never tested the loss-priced objective at matched C-rate).
ev_only_crate.Finv.LiIon = 28.447;
ev_only_crate.Finv.NaIon_Crate1p1 = 29.3663;

%% ------------------------------------------------------------------
%  Shared style: one color per technology, used consistently across all
%  three figures. Okabe-Ito colorblind-safe categorical set.
%  ------------------------------------------------------------------
col.LiIon = [0.00, 0.45, 0.70];   % blue
col.NaIon = [0.90, 0.62, 0.00];   % orange
col.Both  = [0.40, 0.40, 0.40];   % neutral gray (portfolio choice, not a chemistry)

fontName = 'Helvetica';
fontSize = 11;

%% ====================================================================
%  FIGURE 1 -- Slope chart: cost ranking, F^inv-only vs loss-priced
%  ====================================================================
fig1 = figure('Name', 'Fig 1: Technology ranking reversal', 'Color', 'w', ...
    'Position', [100 100 1300 620]);
tl1 = tiledlayout(fig1, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
tl1.Position = [0.05 0.27 0.92 0.63];   % reserve bottom ~27% for the three per-panel robustness captions

x_pos = [1 2];
x_labels = {'F^{inv} only', 'F^{inv}+F^{Sloss}+F^{Eloss}'};

% --- Panel A: PV-only ---
nexttile(tl1);
plot_slope_panel(x_pos, x_labels, ...
    [pv_only.Finv.LiIon, pv_only.Finv_Sloss_Eloss.LiIon], ...
    [pv_only.Finv.NaIon, pv_only.Finv_Sloss_Eloss.NaIon], ...
    [pv_only.Finv.Both,  pv_only.Finv_Sloss_Eloss.Both], ...   % empty -> no Both line for this scenario
    col, fontName, fontSize, 'Base loads + PV');

% --- Panel B: EV-only ---
nexttile(tl1);
plot_slope_panel(x_pos, x_labels, ...
    [ev_only.Finv.LiIon, ev_only.Finv_Sloss_Eloss.LiIon], ...
    [ev_only.Finv.NaIon, ev_only.Finv_Sloss_Eloss.NaIon], ...
    [ev_only.Finv.Both,  ev_only.Finv_Sloss_Eloss.Both], ...
    col, fontName, fontSize, 'Base loads + EV');

% --- Panel C: PV + EV ---
nexttile(tl1);
LiIon_pair = [get_cost(r_main,'Finv','LiIon'),             get_cost(r_main,'Finv_Sloss_Eloss','LiIon')];
NaIon_pair = [get_cost(r_main,'Finv','NaIon'),              get_cost(r_main,'Finv_Sloss_Eloss','NaIon')];
Both_pair  = [get_cost(r_main,'Finv','Both'),                get_cost(r_main,'Finv_Sloss_Eloss','Both')];
plot_slope_panel(x_pos, x_labels, LiIon_pair, NaIon_pair, Both_pair, ...
    col, fontName, fontSize, 'Base loads + PV + EV');

title(tl1, 'Does the F^{inv}-only technology ranking survive once losses are priced?', ...
    'FontName', fontName, 'FontSize', fontSize+1, 'FontWeight', 'normal');

% --- C-rate-equalized robustness check: ONE caption per panel, not one
%     blanket claim -- the three profile scenarios turn out to behave
%     genuinely differently (see caption text), not just "confirmed in
%     every case". Column x-ranges below match tl1's 1x3 layout
%     (tl1.Position = [0.05 0.20 0.92 0.68], compact spacing).
col_w = 0.92/3;
col_x0 = 0.05 + (0:2)*col_w;

% Panel A (PV-only): natural (C-rate=5) vs forced (C-rate=1.1) Na-Ion --
% IDENTICAL at both cost functions (see run_pv_crate_equalized_check.m
% output: 3.529 vs 3.529 kCHF at F^inv, 11.444 vs 11.444 kCHF loss-priced).
% C-rate is never the binding constraint for this (charge-dominated,
% small-power) violation -- so there is nothing for the check to isolate.
annotation(fig1, 'textbox', [col_x0(1) 0.01 col_w 0.16], 'String', ...
    'C-rate-equalized check: NO effect (natural C-rate=5 and forced C-rate=1.1 give identical costs, both cost functions). C-rate never binds here -- Na-Ion''s F^{Eloss} disadvantage is 100% efficiency, not a C-rate artifact.', ...
    'EdgeColor', 'none', 'HorizontalAlignment', 'center', 'FontName', fontName, 'FontSize', fontSize-3, 'FontAngle', 'italic');

% Panel B (EV-only): doc's own original hypothesis test, F^inv only.
gap_ev = ev_only_crate.Finv.NaIon_Crate1p1 - ev_only_crate.Finv.LiIon;
annotation(fig1, 'textbox', [col_x0(2) 0.01 col_w 0.16], 'String', ...
    sprintf(['C-rate-equalized check (F^{inv} only): Na-Ion still costs more (+%.2f kCHF) -- confirms a genuine ' ...
             'C-rate advantage. (Loss-priced case not tested for this scenario.)'], gap_ev), ...
    'EdgeColor', 'none', 'HorizontalAlignment', 'center', 'FontName', fontName, 'FontSize', fontSize-3, 'FontAngle', 'italic');

% Panel C (PV+EV): both cost functions tested, gap widens sharply.
crate_gap_Finv  = get_cost(r_crate_pvev,'Finv','NaIon_Crate1p1')             - get_cost(r_crate_pvev,'Finv','LiIon');
crate_gap_Eloss = get_cost(r_crate_pvev,'Finv_Sloss_Eloss','NaIon_Crate1p1') - get_cost(r_crate_pvev,'Finv_Sloss_Eloss','LiIon');
annotation(fig1, 'textbox', [col_x0(3) 0.01 col_w 0.16], 'String', ...
    sprintf(['C-rate-equalized check: Na-Ion still costs more at F^{inv} (+%.2f kCHF); gap widens %.1f\\times ' ...
             'once losses are priced (+%.2f kCHF) -- a real, load-bearing C-rate advantage.'], ...
             crate_gap_Finv, crate_gap_Eloss/crate_gap_Finv, crate_gap_Eloss), ...
    'EdgeColor', 'none', 'HorizontalAlignment', 'center', 'FontName', fontName, 'FontSize', fontSize-3, 'FontAngle', 'italic');

%% ====================================================================
%  FIGURE 2 -- Stacked bar: cost composition at the loss-priced objective
%  ====================================================================
fig2 = figure('Name', 'Fig 2: Cost composition (why the reversal happens)', 'Color', 'w', ...
    'Position', [150 150 700 450]);

scenarios = {'LiIon', 'NaIon', 'Both'};
scenario_labels = {'Li-Ion only', 'Na-Ion only', 'Both'};
components = {'E', 'S', 'I', 'L', 'BESSLoss'};
component_labels = {'Energy capacity (F^E)', 'Converter rating (F^{conv})', 'Installation (F^{inst})', ...
    'Slack losses (F^{Sloss})', 'ESS throughput losses (F^{Eloss})'};

comp_costs = zeros(numel(scenarios), numel(components));
for si = 1:numel(scenarios)
    row = get_row(r_main, 'Finv_Sloss_Eloss', scenarios{si});
    for ci = 1:numel(components)
        comp_costs(si, ci) = row.costs.(components{ci}) / 1000;   % CHF -> kCHF
    end
end

comp_colors = [ ...
    0.20 0.50 0.75;   % E
    0.55 0.75 0.90;   % S
    0.75 0.75 0.75;   % I
    0.95 0.65 0.30;   % L
    0.75 0.15 0.15];  % BESSLoss (Eloss) -- deliberately the "hot" color: this is the segment that drives the story

bh = bar(comp_costs, 'stacked', 'BarWidth', 0.55);
for ci = 1:numel(components)
    bh(ci).FaceColor = comp_colors(ci, :);
end
set(gca, 'XTick', 1:numel(scenarios), 'XTickLabel', scenario_labels, ...
    'FontName', fontName, 'FontSize', fontSize, 'Box', 'off', 'TickDir', 'out');
ylabel('Total cost (kCHF)', 'FontName', fontName, 'FontSize', fontSize);
title('Cost composition, min(F^{inv}+F^{Sloss}+F^{Eloss}), base loads + PV + EV', ...
    'FontName', fontName, 'FontSize', fontSize+1, 'FontWeight', 'normal');
legend(component_labels, 'Location', 'eastoutside', 'FontName', fontName, 'FontSize', fontSize-2, 'Box', 'off');
grid on; ax = gca; ax.YGrid = 'on'; ax.XGrid = 'off'; ax.GridAlpha = 0.15;

% direct total labels on top of each bar
totals = sum(comp_costs, 2);
for si = 1:numel(scenarios)
    text(si, totals(si) + max(totals)*0.02, sprintf('%.1f', totals(si)), ...
        'HorizontalAlignment', 'center', 'FontName', fontName, 'FontSize', fontSize-1, 'FontWeight', 'bold');
end

%% ====================================================================
%  FIGURE 3 -- Grouped bars: per-node sizing, "Both" scenario, loss-priced
%  ====================================================================
fig3 = figure('Name', 'Fig 3: Per-node sizing (Both, loss-priced)', 'Color', 'w', ...
    'Position', [200 200 850 400]);
tl3 = tiledlayout(fig3, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

row_both = get_row(r_main, 'Finv_Sloss_Eloss', 'Both');
pn = row_both.per_node;   % table: node_id, tech, E_kWh, S_kW, throughput_kWh

node_labels = arrayfun(@(n) sprintf('n%d', n), pn.node_id, 'UniformOutput', false);
bar_colors = zeros(height(pn), 3);
for k = 1:height(pn)
    bar_colors(k, :) = col.(char(pn.tech(k)));
end

% --- Panel A: energy capacity ---
nexttile(tl3);
plot_sized_bars(pn.E_kWh, node_labels, bar_colors, 'Energy capacity (kWh)', fontName, fontSize);

% --- Panel B: converter rating ---
nexttile(tl3);
plot_sized_bars(pn.S_kW, node_labels, bar_colors, 'Converter rating (kW)', fontName, fontSize);

title(tl3, 'Optimal siting/sizing, Both technologies available, min(F^{inv}+F^{Sloss}+F^{Eloss})', ...
    'FontName', fontName, 'FontSize', fontSize+1, 'FontWeight', 'normal');

% shared legend (technology -> color) via dummy patches
lg_ax = axes(fig3, 'Position', [0 0 1 1], 'Visible', 'off');
hold(lg_ax, 'on');
p1 = patch(lg_ax, NaN, NaN, col.LiIon);
p2 = patch(lg_ax, NaN, NaN, col.NaIon);
legend(lg_ax, [p1 p2], {'Li-Ion', 'Na-Ion'}, 'Orientation', 'horizontal', ...
    'Position', [0.4 0.01 0.2 0.05], 'FontName', fontName, 'FontSize', fontSize-1, 'Box', 'off');

%% ====================================================================
%  Local functions
%  ====================================================================
function row = get_row(results, cost_fn, tech)
idx = find(strcmp({results.cost_fn}, cost_fn) & strcmp({results.tech}, tech), 1);
if isempty(idx)
    error('get_row:notFound', 'No result for cost_fn=%s, tech=%s', cost_fn, tech);
end
row = results(idx);
end

function total_kCHF = get_cost(results, cost_fn, tech)
row = get_row(results, cost_fn, tech);
total_kCHF = row.costs.total / 1000;
end

function plot_slope_panel(x_pos, x_labels, li_pair, na_pair, both_pair, col, fontName, fontSize, panelTitle)
hold on;
has_both = ~isempty(both_pair) && all(~isnan(both_pair));
if has_both
    plot(x_pos, both_pair, ':o', 'Color', col.Both, 'LineWidth', 1.5, 'MarkerFaceColor', col.Both, 'MarkerSize', 5);
end
plot(x_pos, li_pair,   '-o', 'Color', col.LiIon, 'LineWidth', 2.5, 'MarkerFaceColor', col.LiIon, 'MarkerSize', 7);
plot(x_pos, na_pair,   '-o', 'Color', col.NaIon, 'LineWidth', 2.5, 'MarkerFaceColor', col.NaIon, 'MarkerSize', 7);

text(x_pos(1)-0.08, li_pair(1), 'Li-Ion', 'Color', col.LiIon, 'HorizontalAlignment', 'right', ...
    'VerticalAlignment', 'bottom', 'FontName', fontName, 'FontSize', fontSize-1, 'FontWeight', 'bold');
text(x_pos(1)-0.08, na_pair(1), 'Na-Ion', 'Color', col.NaIon, 'HorizontalAlignment', 'right', ...
    'VerticalAlignment', 'top', 'FontName', fontName, 'FontSize', fontSize-1, 'FontWeight', 'bold');
if has_both
    text(x_pos(1)-0.08, both_pair(1), 'Both', 'Color', col.Both, 'HorizontalAlignment', 'right', ...
        'VerticalAlignment', 'top', 'FontName', fontName, 'FontSize', fontSize-2);
end

xlim([x_pos(1)-0.5, x_pos(2)+0.15]);
yl = ylim;
ylim([yl(1) - 0.08*diff(yl), yl(2)]);   % headroom below the lowest point for its label
set(gca, 'XTick', x_pos, 'XTickLabel', x_labels, 'FontName', fontName, 'FontSize', fontSize, ...
    'Box', 'off', 'TickDir', 'out');
ylabel('Total cost (kCHF)', 'FontName', fontName, 'FontSize', fontSize);
title(panelTitle, 'FontName', fontName, 'FontSize', fontSize, 'FontWeight', 'normal');
grid on; ax = gca; ax.YGrid = 'on'; ax.XGrid = 'off'; ax.GridAlpha = 0.15;
end

function plot_sized_bars(values, labels, colors, yLabelStr, fontName, fontSize)
b = bar(values, 'FaceColor', 'flat', 'BarWidth', 0.5);
b.CData = colors;
set(gca, 'XTick', 1:numel(values), 'XTickLabel', labels, 'FontName', fontName, 'FontSize', fontSize, ...
    'Box', 'off', 'TickDir', 'out');
ylabel(yLabelStr, 'FontName', fontName, 'FontSize', fontSize);
grid on; ax = gca; ax.YGrid = 'on'; ax.XGrid = 'off'; ax.GridAlpha = 0.15;
for k = 1:numel(values)
    text(k, values(k) + max(values)*0.03, sprintf('%.1f', values(k)), ...
        'HorizontalAlignment', 'center', 'FontName', fontName, 'FontSize', fontSize-1);
end
end
