function analysis = analyze_tech_selection(out, cfg)
% ANALYZE_TECH_SELECTION  Explain ESS technology selection with diagnostic figures.
%
%   analysis = analyze_tech_selection(out)
%   analysis = analyze_tech_selection(out, cfg)   % cfg optional
%
%   Produces three figures:
%     Fig 1 — Selection overview: which tech, E/S sizing, C-rate utilisation
%     Fig 2 — Cost counterfactual: chosen vs. alternative technologies
%     Fig 3 — Dispatch profiles and voltage impact per top-E node
%
%   The key driver of technology choice in the MILP is cost minimisation
%   subject to C-rate, capacity, and grid constraints.  These figures show:
%     - What each technology would cost at each installed node (Fig 2)
%     - Whether the C-rate constraint ruled out cheaper alternatives (Fig 2)
%     - What dispatch pattern the node required (Fig 3)
%     - Whether ESS resolved the voltage/current violation (Fig 3)

if nargin < 2; cfg = []; end

% -------------------------------------------------------------------------
%  Extract core sizing data
% -------------------------------------------------------------------------
Install    = out.sizing.Installation;      % [Nd x J]
E_nom_pu   = out.sizing.E_nom_node_pu;     % [Nd x J]
S_conv_pu  = out.sizing.S_conv_node_pu;    % [Nd x J]
C_rate_act = out.sizing.C_rate;            % [Nd x J]
tech_names = out.sizing.tech_names;        % {J x 1}
J          = numel(tech_names);
Nd         = size(Install, 1);

% Per-node max active/reactive dispatch magnitude (not a flat column max —
% B_bat/Q_ess are stacked [T*Nd x J], so reduce per node's own T-block)
T_loc      = size(out.injections.B_bat, 1) / Nd;
B_max_pu   = zeros(Nd, J);
Q_max_pu   = zeros(Nd, J);
for n = 1:Nd
    Idx = (n-1)*T_loc + (1:T_loc);
    B_max_pu(n,:) = max(abs(out.injections.B_bat(Idx,:)), [], 1);
    Q_max_pu(n,:) = max(abs(out.injections.Q_ess(Idx,:)), [], 1);
end

% pu -> real 3-phase kWh / kW (Sb/1000 x 3 phases; out.meta.kW_per_pu, 300 for old results)
scale      = kw_per_pu_of(out);
E_kWh      = E_nom_pu  * scale;   % [Nd x J]
S_kVA      = S_conv_pu * scale;   % [Nd x J]
B_kW       = B_max_pu  * scale;   % [Nd x J]
Q_kVAR     = Q_max_pu  * scale;   % [Nd x J]

% Cost coefficients [1 x J] — prefer stored meta, fall back to cfg
if isfield(out, 'meta') && isfield(out.meta, 'cE_per_kWh')
    cE_per_kWh = out.meta.cE_per_kWh;
    cS_per_kW  = out.meta.cS_per_kW;
    cI_fixed   = out.meta.cI_fixed;
elseif ~isempty(cfg)
    cE_per_kWh = cfg.tech.cE_per_kWh;
    cS_per_kW  = cfg.tech.cS_per_kW;
    cI_fixed   = cfg.tech.cI_fixed;
else
    cE_per_kWh = ones(1,J);  cS_per_kW = ones(1,J);  cI_fixed = zeros(1,J);
    warning('analyze_tech_selection: cost data missing — using unit costs.');
end

% C-rate limits [1 x J]
if isfield(out, 'meta') && isfield(out.meta, 'c_rate_j')
    c_rate_lim = out.meta.c_rate_j;
elseif ~isempty(cfg)
    c_rate_lim = cfg.tech.c_rate;
else
    c_rate_lim = nan(1, J);
end

% Installed nodes
I_full   = double(Install);
sel_mask = any(I_full > 0.5, 2);
sel_nd   = find(sel_mask);
N_sel    = numel(sel_nd);

if N_sel == 0
    warning('analyze_tech_selection: no installed ESS nodes — nothing to show.');
    analysis = struct('sel_nd', [], 'N_sel', 0);
    return
end

% Which technology is installed at each selected node
tech_idx_sel = zeros(N_sel, 1);
for k = 1:N_sel
    tech_idx_sel(k) = find(I_full(sel_nd(k),:) > 0.5, 1);
end

% -------------------------------------------------------------------------
%  Cost computation (counterfactual: same E & S sizing, different tech)
%  This is a lower bound — using the chosen tech's E,S for the alternative.
% -------------------------------------------------------------------------
cost_E = zeros(N_sel, J);
cost_S = zeros(N_sel, J);
cost_I = zeros(N_sel, J);
for k = 1:N_sel
    n      = sel_nd(k);
    j_ch   = tech_idx_sel(k);
    En     = E_kWh(n, j_ch);
    Sn     = S_kVA(n,  j_ch);
    for j = 1:J
        cost_E(k,j) = cE_per_kWh(j) * En;
        cost_S(k,j) = cS_per_kW(j)  * Sn;
        cost_I(k,j) = cI_fixed(j);
    end
end
cost_total = cost_E + cost_S + cost_I;

% Required C-rate at each installed node
req_c_rate = zeros(N_sel, 1);
for k = 1:N_sel
    n = sel_nd(k);
    j = tech_idx_sel(k);
    req_c_rate(k) = C_rate_act(n,j);
end

% C-rate feasibility for each technology
c_rate_feasible = req_c_rate <= (c_rate_lim + 1e-9);   % [N_sel x J]

% -------------------------------------------------------------------------
%  Pack analysis struct
% -------------------------------------------------------------------------
analysis.sel_nd          = sel_nd;
analysis.node_id         = out.sizing.demand_node_id(sel_nd);  % real N-space node index, for labels
analysis.N_sel           = N_sel;
analysis.tech_idx_sel    = tech_idx_sel;
analysis.E_kWh           = E_kWh(sel_nd, :);
analysis.S_kVA           = S_kVA(sel_nd, :);
analysis.B_kW            = B_kW(sel_nd, :);
analysis.Q_kVAR          = Q_kVAR(sel_nd, :);
analysis.req_c_rate      = req_c_rate;
analysis.c_rate_lim      = c_rate_lim;
analysis.c_rate_feasible = c_rate_feasible;
analysis.cost_E          = cost_E;
analysis.cost_S          = cost_S;
analysis.cost_I          = cost_I;
analysis.cost_total      = cost_total;
analysis.tech_names      = tech_names;

net_id = '';
if isfield(out, 'summary'); net_id = string(out.summary.network_id); end

% -------------------------------------------------------------------------
%  Figure 1 — Selection overview
% -------------------------------------------------------------------------
p_fig1_overview(analysis, net_id, E_kWh, S_kVA, C_rate_act);

% -------------------------------------------------------------------------
%  Figure 2 — Cost counterfactual (only meaningful when J > 1)
% -------------------------------------------------------------------------
if J > 1
    p_fig2_cost(analysis, net_id);
end

% -------------------------------------------------------------------------
%  Figure 3 — Dispatch profiles and voltage impact
% -------------------------------------------------------------------------
if isfield(out, 'gm') && ~isempty(out.gm) && isfield(out, 'grid')
    p_fig3_dispatch(out, analysis, net_id, cfg);
end

end


% =========================================================================
%  Figure 1 — Selection overview
% =========================================================================
function p_fig1_overview(an, net_id, E_kWh, S_kVA, C_rate_act)

J          = numel(an.tech_names);
N_sel      = an.N_sel;
sel_nd     = an.sel_nd;
node_id    = an.node_id;
tech_idx   = an.tech_idx_sel;
c_rate_lim = an.c_rate_lim;

colors = lines(J);
x_tk   = 1:N_sel;
x_lbl  = arrayfun(@(n) sprintf('n%d', n), node_id, 'UniformOutput', false);

figure('Name', 'Fig1: ESS Selection Overview', 'Color', 'w' ...
    );
tl = tiledlayout(2, 3, 'Padding', 'compact', 'TileSpacing', 'compact');

% [1,1] Technology installed per node
nexttile;
hold on;
for j = 1:J
    mask = tech_idx == j;
    if any(mask)
        bar(x_tk(mask), ones(sum(mask),1), 0.6, 'FaceColor', colors(j,:), ...
            'DisplayName', string(an.tech_names{j}));
    end
end
hold off;
yticks([]); xticks(x_tk); xticklabels(x_lbl); xtickangle(45);
xlabel('Node (network ID)'); title('Installed technology per node');
legend('Location','best','FontSize',8); grid on;

% [1,2] Energy capacity per installed node
nexttile;
hold on;
for j = 1:J
    mask = tech_idx == j;
    if any(mask)
        bar(x_tk(mask), E_kWh(sel_nd(mask), j), 0.6, ...
            'FaceColor', colors(j,:), 'DisplayName', string(an.tech_names{j}));
    end
end
hold off;
xticks(x_tk); xticklabels(x_lbl); xtickangle(45);
xlabel('Node'); ylabel('E_{nom} [kWh]');
title('Energy capacity per installed node');
legend('Location','best','FontSize',8); grid on;

% [1,3] Power capacity per installed node (kVA bars, kW overlay on right axis)
nexttile;

hold on;
% apparent power rating
for j = 1:J
    mask = tech_idx == j;
    if any(mask)
        bar(x_tk(mask), S_kVA(sel_nd(mask), j), 0.6, ...
            'FaceColor', colors(j,:), 'DisplayName', string(an.tech_names{j}));
    end
end

% active power rating
for j = 1:J
    mask = tech_idx == j;
    if any(mask)
        plot(x_tk(mask), an.B_kW(mask, j), '^', 'Color', [0.15 0.15 0.15], ...
            'MarkerFaceColor', [0.15 0.15 0.15], 'MarkerSize', 6, ...
            'LineStyle', 'none', 'HandleVisibility', 'off');
    end
end
hold off;
ylabel('S_{conv} [kVA]');

xticks(x_tk); xticklabels(x_lbl); xtickangle(45);
xlabel('Node');
title('Power capacity per installed node');
legend('Location','best','FontSize',8); grid on;

% [2,1] Required C-rate per node vs technology limits
nexttile;
bar(x_tk, an.req_c_rate, 0.5, 'FaceColor', [0.4 0.6 0.85]);
hold on;
cmap = lines(J);
for j = 1:J
    if ~isnan(c_rate_lim(j))
        yline(c_rate_lim(j), '--', 'Color', cmap(j,:), 'LineWidth', 2, ...
            'Label', sprintf('%s (%.1f h^{-1})', string(an.tech_names{j}), c_rate_lim(j)), ...
            'LabelHorizontalAlignment', 'right', 'FontSize', 8);
    end
end
hold off;
xticks(x_tk); xticklabels(x_lbl); xtickangle(45);
xlabel('Node'); ylabel('C-rate [h^{-1}]');
title('Required C-rate vs technology limits');
grid on;

% [2,2] E vs S scatter per node, coloured by technology
nexttile;
hold on;
for j = 1:J
    mask = tech_idx == j;
    if any(mask)
        scatter(E_kWh(sel_nd(mask),j), S_kVA(sel_nd(mask),j), 70, ...
            colors(j,:), 'filled', 'DisplayName', string(an.tech_names{j}));
    end
end
% Iso-C-rate reference lines
E_ref = linspace(0, max(E_kWh(:))*1.1, 100);
cmap  = lines(J);
for j = 1:J
    if ~isnan(c_rate_lim(j)) && c_rate_lim(j) > 0
        plot(E_ref, E_ref *  c_rate_lim(j), '--', 'Color', cmap(j,:), ...
            'LineWidth', 1, 'HandleVisibility', 'off');
    end
end
hold off;
xlabel('E_{nom} [kWh]'); ylabel('S_{conv} [kVA]');
title('Sizing: E vs S (dashed = C-rate limit)');
legend('Location','best','FontSize',8); grid on;

% [2,3] Total capacity split by technology
nexttile;
E_by_tech = arrayfun(@(j) sum(E_kWh(sel_nd(tech_idx==j), j)), (1:J)');
S_by_tech = arrayfun(@(j) sum(S_kVA(sel_nd(tech_idx==j), j)), (1:J)');
b = bar(1:J, [E_by_tech, S_by_tech], 'grouped');
b(1).FaceColor = [0.2 0.6 0.9];
b(2).FaceColor = [0.9 0.55 0.2];
set(gca, 'XTick', 1:J, ...
    'XTickLabel', cellfun(@string, an.tech_names, 'UniformOutput', false));
ylabel('[kWh] / [kW]');
title('Total capacity by technology');
legend({'Total E [kWh]', 'Total S [kVA]'}, 'Location','best','FontSize',8);
grid on;

sgtitle(sprintf('Network %s — ESS Technology Selection Overview', net_id), ...
    'FontWeight','bold');
end


% =========================================================================
%  Figure 2 — Cost counterfactual
% =========================================================================
function p_fig2_cost(an, net_id)

N_sel  = an.N_sel;
J      = numel(an.tech_names);

N_show = min(N_sel, 9);
ncols  = min(N_show, 3);
nrows  = ceil(N_show / ncols);

% Sort by E_nom descending so the most impactful nodes come first
E_chosen = arrayfun(@(k) an.E_kWh(k, an.tech_idx_sel(k)), (1:N_sel)');
[~, order] = sort(E_chosen, 'descend');
show_k = order(1:N_show);

bar_colors = [0.25 0.58 0.90;   % E cost — blue
    0.92 0.52 0.18;   % S cost — orange
    0.48 0.78 0.47];  % I cost — green

figure('Name', 'Fig2: Cost Counterfactual', 'Color', 'w' ...
    );
tiledlayout(nrows, ncols, 'Padding', 'compact', 'TileSpacing', 'compact');

for i = 1:N_show
    k    = show_k(i);
    nd   = an.node_id(k);
    j_ch = an.tech_idx_sel(k);

    nexttile;

    bar_data = [an.cost_E(k,:)', an.cost_S(k,:)', an.cost_I(k,:)'];  % [J x 3]
    b = bar(1:J, bar_data, 'stacked');
    for m = 1:3
        b(m).FaceColor = bar_colors(m,:);
    end

    hold on;
    % Bold outline on the chosen technology bar
    rectangle('Position', [j_ch-0.4, 0, 0.8, an.cost_total(k,j_ch)], ...
        'EdgeColor', 'k', 'LineWidth', 2.5, 'FaceColor', 'none');

    % Mark C-rate infeasible alternatives in red
    for j = 1:J
        if ~an.c_rate_feasible(k,j)
            text(j, an.cost_total(k,j)*1.05, 'C-rate', ...
                'Color','r','FontSize',7, ...
                'HorizontalAlignment','center','FontWeight','bold');
        end
    end
    hold off;

    tn_strs = cellfun(@string, an.tech_names, 'UniformOutput', false);
    set(gca, 'XTick', 1:J, 'XTickLabel', tn_strs, 'FontSize', 9);
    title(sprintf('Node %d  →  %s', nd, string(an.tech_names{j_ch})), ...
        'FontSize', 9, 'FontWeight', 'bold');
    ylabel('Cost [CHF]', 'FontSize', 8);
    grid on;

    if i == 1
        legend({'E cost','S cost','Install'}, 'Location','best','FontSize',7);
    end
end

sgtitle(sprintf('Network %s — Cost Breakdown: Chosen vs. Alternatives\n(same E & S sizing; bold outline = chosen; "C-rate" = infeasible)', ...
    net_id), 'FontWeight','bold','FontSize',10);
end


% =========================================================================
%  Figure 3 — Dispatch and voltage impact
% =========================================================================
function p_fig3_dispatch(out, an, net_id, cfg)

T   = size(out.gm.nodal_injections_D_pu, 1);
kW_per_pu = kw_per_pu_of(out);   % pu -> real 3-phase kW/kWh
N   = out.grid.N;
J   = numel(an.tech_names);

% Top-3 nodes by installed energy (chosen tech)
E_chosen = arrayfun(@(k) an.E_kWh(k, an.tech_idx_sel(k)), (1:an.N_sel)');
[~, order] = sort(E_chosen, 'descend');
N_show  = min(3, an.N_sel);
show_k  = order(1:N_show);

% Baseline voltage (pre-ESS) stacked [N*T x 1]
Vmag0_all = reshape(lm_stack(out.gm.lm.Vmag0), [], 1);

% Efficiency parameters for SOE reconstruction
eta_ch  = 0.9;   eta_dis = 0.9;
if isfield(out, 'meta') && isfield(out.meta, 'eta_ch')
    eta_ch_v  = out.meta.eta_ch;
    eta_dis_v = out.meta.eta_dis;
else
    eta_ch_v  = repmat(eta_ch,  1, J);
    eta_dis_v = repmat(eta_dis, 1, J);
end

% Step length: the solve's own Ts_h (stamped into out.meta from sizing_cfg.json
% at solve time, so a reloaded .mat keeps its own value even if the config has
% changed since), else the passed cfg, else the native 15-min default.
if isfield(out, 'meta') && isfield(out.meta, 'Ts_h') && ~isempty(out.meta.Ts_h)
    Ts = out.meta.Ts_h;
elseif ~isempty(cfg) && isfield(cfg, 'solver') && isfield(cfg.solver, 'Ts_h')
    Ts = cfg.solver.Ts_h;
else
    Ts = 0.25;
end
t_h = (1:T) * Ts;     % time axis in hours

figure('Name', 'Fig3: Dispatch and Voltage Impact', 'Color', 'w' ...
    );
tiledlayout(4, N_show, 'Padding', 'compact', 'TileSpacing', 'compact');

for col = 1:N_show
    k    = show_k(col);
    nd     = an.sel_nd(k);      % Nd-space index: indexes sizing/injections arrays
    j      = an.tech_idx_sel(k);
    n_full = an.node_id(k);     % full topology node ID (slack-shifted, +1): for display only
    n_all  = n_full - 1;        % N-space index (slack excluded): indexes voltage arrays

    Idx = (nd-1)*T + (1:T);

    B_plus_n  = out.injections.B_plus(Idx, j)  * kW_per_pu;   % kW
    B_minus_n = out.injections.B_minus(Idx, j) * kW_per_pu;

    D_n = real(out.gm.nodal_injections_D_pu(:, nd)) * kW_per_pu;     % demand [kW]

    % Node voltages: indices n_all, n_all+N, n_all+2N, ... across T steps
    vmag_n = out.grid.vmag_lin(n_all : N : N*T);
    V0_n   = Vmag0_all(n_all : N : N*T);
    Vlf_n  = out.grid.V_lf(n_all : N : N*T);

    % SOE reconstruction [pu] — mirrors the SOE evolution constraint in
    % solve_ess_milp.m (cyclic boundary SOE_0, not assumed zero at t=0)
    SOE0_n  = out.sizing.SOE_0_pu(nd, j);
    SOE_pu  = SOE0_n + Ts * ( eta_ch_v(j)      * cumsum(out.injections.B_plus(Idx, j)) ...
        - (1/eta_dis_v(j)) * cumsum(out.injections.B_minus(Idx, j)) );
    SOE_kWh = SOE_pu * kW_per_pu;

    tech_str = string(an.tech_names{j});

    % ---- Row 1: Active power dispatch ----
    nexttile(col);
    hold on;
    % Discharge: B_minus is delivered to the grid (grid-side); the BESS
    % internally draws B_minus/eta_dis to produce it (larger, due to loss).
    % Draw the larger BESS-side quantity first (light halo), the smaller
    % grid-side quantity second (dark core) so both remain visible.
    area(t_h,  B_minus_n / eta_dis_v(j),       'FaceColor', [0.3 0.7 0.35], 'FaceAlpha', 0.25, ...
        'EdgeColor','none', 'DisplayName','Discharge (BESS-side, after \eta)');
    area(t_h,  B_minus_n,                      'FaceColor', [0.3 0.7 0.35], 'FaceAlpha', 0.7,  ...
        'EdgeColor','none', 'DisplayName','Discharge (grid-side)');

    % Charge: B_plus is drawn from the grid (grid-side, larger); only
    % eta_ch*B_plus is actually stored in the BESS (smaller, due to loss).
    % Larger grid-side drawn first (light halo), smaller BESS-side second
    % (dark core).
    area(t_h, -B_plus_n,                        'FaceColor', [0.85 0.35 0.35], 'FaceAlpha', 0.25, ...
        'EdgeColor','none', 'DisplayName','Charge (grid-side)');
    area(t_h, -eta_ch_v(j) * B_plus_n,          'FaceColor', [0.85 0.35 0.35], 'FaceAlpha', 0.7,  ...
        'EdgeColor','none', 'DisplayName','Charge (BESS-side, stored)');
    % area(t_h,  B_minus_n, 'FaceColor', [0.3 0.7 0.35], 'FaceAlpha', 0.5, ...
    %     'EdgeColor','none', 'DisplayName','Discharge (→grid)');
    % area(t_h, -B_plus_n,  'FaceColor', [0.85 0.35 0.35], 'FaceAlpha', 0.5, ...
    %     'EdgeColor','none', 'DisplayName','Charge (←grid)');
    plot(t_h, D_n, 'k-', 'LineWidth', 1.2, 'DisplayName','Net demand');
    hold off; yline(0,'k:','HandleVisibility','off');
    xlabel('Time [h]'); ylabel('[kW]');
    title(sprintf('Node %d | %s | E=%.1fkWh', n_full, tech_str, an.E_kWh(k,j)), ...
        'FontSize', 9);
    legend('Location','best','FontSize',7); grid on;

    % ---- Row 2: State of energy ----
    nexttile(N_show + col);
    plot(t_h, SOE_kWh, 'b-', 'LineWidth', 1.5);
    yline(an.E_kWh(k,j), 'r--', 'E_{nom}', 'FontSize', 8,'HandleVisibility','off');
    yline(0, 'r--');
    xlabel('Time [h]'); ylabel('SOE [kWh]');
    title('State of Energy', 'FontSize', 9);
    ylim([-0.05, 1.05] * max(an.E_kWh(k,j), eps)); grid on;

    % ---- Row 3: Node voltage ----
    nexttile(2*N_show + col);
    hold on;
    plot(t_h, V0_n,   'r--',  'LineWidth', 1.2, 'DisplayName', 'Baseline (no ESS)');
    plot(t_h, vmag_n, 'b-',   'LineWidth', 1.5, 'DisplayName', 'Linearised (with ESS)');
    plot(t_h, Vlf_n,  'g-.', 'LineWidth', 1.0, 'DisplayName', 'LF verified');
    hold off;
    yline(0.9, 'k:', '0.9 pu', 'FontSize', 8, 'LabelHorizontalAlignment','left','HandleVisibility','off');
    yline(1.1, 'k:', '1.1 pu', 'FontSize', 8, 'LabelHorizontalAlignment','left','HandleVisibility','off');
    xlabel('Time [h]'); ylabel('Voltage [pu]');
    title('Node voltage', 'FontSize', 9);
    legend('Location','best','FontSize',7); grid on;
end

% ---- Row 4: Line current impact, all branches (network-wide, spans row) ----
nexttile(3*N_show + 1, [1 N_show]);
L         = numel(out.grid.CABLE_AMP);
Imag0_mat = abs(lm_stack(out.gm.lm.Imag0).');            % [T x L], baseline (no ESS)
I0_pu     = Imag0_mat ./ repmat(out.grid.CABLE_AMP.', T, 1);
Ilin_pu   = reshape(out.grid.Imag_lin_pu, L, T).';       % [T x L], linearised (with ESS)
Ilf_pu    = reshape(out.grid.I_lf_pu,     L, T).';       % [T x L], LF verified (with ESS)
hold on;
plot(t_h, I0_pu,   'Color', [0.85 0.35 0.35], 'LineWidth', 0.75, 'HandleVisibility', 'off');
plot(t_h, Ilin_pu, 'Color', [0.20 0.40 0.85], 'LineWidth', 0.75, 'HandleVisibility', 'off');
plot(t_h, Ilf_pu,  'Color', [0.30 0.70 0.35], 'LineWidth', 0.75, 'HandleVisibility', 'off');
plot(nan, nan, 'Color', [0.85 0.35 0.35], 'DisplayName', 'Baseline (no ESS)');
plot(nan, nan, 'Color', [0.20 0.40 0.85], 'DisplayName', 'Linearised (with ESS)');
plot(nan, nan, 'Color', [0.30 0.70 0.35], 'DisplayName', 'LF verified (with ESS)');
yline(1.0, 'k--', 'LineWidth', 1.5, 'HandleVisibility', 'off');
hold off;
xlabel('Time [h]'); ylabel('Current [p.u. ampacity]');
title('Line currents — all branches (network-wide impact)', 'FontSize', 9);
legend('Location','best','FontSize',7); grid on;

sgtitle(sprintf('Network %s — Dispatch Profiles and Voltage Impact (top-%d nodes by E_{nom})', ...
    net_id, N_show), 'FontWeight','bold');
end
