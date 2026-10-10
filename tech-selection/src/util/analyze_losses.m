function analyze_losses(varargin)
out = varargin{1};

bp = kw_per_pu_of(out);   % pu -> real 3-phase kW/kWh (out.meta.kW_per_pu; 300 for old results)

% --- Base quantities ---
P_aggr = sum(out.injections.P0_mat)' * bp;   % [T x 1] total nodal injection
P_s_0  = real(out.injections.Ss0)   * bp;   % [T x 1] initial slack power
dP     = sum(out.injections.delta_P)' * bp;  % [T x 1] total BESS injection
Q_aggr = sum(out.injections.Q0_mat)' * bp;   % [T x 1] total nodal reactive injection
Q_s_0  = imag(out.injections.Ss0)   * bp;   % [T x 1] initial slack reactive power
dQ     = sum(out.injections.delta_Q)' * bp;  % [T x 1] total BESS reactive injection

% Initial losses
P_loss_0   = P_s_0 + P_aggr;
Q_loss_0   = Q_s_0 + Q_aggr;

% Updated quantities after BESS
P_aggr_upd = P_aggr + dP;
P_s_upd    = real(out.injections.Sl_P) * bp;
if isfield(out.injections, 'P_sloss')
    % Solver-computed loss proxy: nets out PV curtailment (pv_loss_adj) too,
    % which P_s_upd + P_aggr_upd alone doesn't see (curtailment lives in
    % Npv-space, invisible to this Nd-space P_aggr sum) — see docs/DEVELOPMENT_NOTES.md.
    P_loss_upd = out.injections.P_sloss * bp;
else
    P_loss_upd = P_s_upd + P_aggr_upd;   % pre-curtailment saved results
end

Q_aggr_upd = Q_aggr + dQ;
Q_s_upd    = imag(out.injections.Sl_Q) * bp;
Q_loss_upd = Q_s_upd + Q_aggr_upd;

% --- BESS loss computation setup ---
if isfield(out.meta, 'eta_ch')
    eta_ch_v  = out.meta.eta_ch;   % [1 x J]
    eta_dis_v = out.meta.eta_dis;
else
    eta_ch_v  = repmat(0.9, 1, size(out.injections.B_plus, 2));
    eta_dis_v = repmat(0.9, 1, size(out.injections.B_plus, 2));
end

Nd_loc     = size(out.sizing.Installation, 1);
J_loc      = size(out.sizing.Installation, 2);
T_loc      = size(out.injections.B_plus, 1) / Nd_loc;
tech_names = out.sizing.tech_names;
T          = numel(P_aggr);
t          = (1:T)';

% --- kQ_conv per tech ---
if isfield(out.meta, 'kQ_conv')
    kQ_conv_v = out.meta.kQ_conv * ones(1, J_loc);
else
    kQ_conv_v = repmat(sqrt(1 - 0.98^2), 1, J_loc);
end

% =========================================================================
%  FIGURE 1 — ACTIVE POWER
% =========================================================================
figure('Name', 'Active Power Loss Analysis')
tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact')

% --- Plot 1: Active nodal injections ---
nexttile
hold on
area(t, P_aggr,     'FaceAlpha', 0.6, 'DisplayName', 'Base load')
area(t, P_aggr_upd, 'FaceAlpha', 0.6, 'DisplayName', 'Base load + BESS')
hold off
xlabel('Time step (15 min)'); ylabel('kW'); grid on
legend('Location', 'best')
title('Active Power Injections')

% --- Plot 2: Slack bus active power ---
nexttile
hold on
area(t, P_s_0,   'FaceAlpha', 0.4, 'FaceColor', [0.85 0.33 0.1], ...
    'DisplayName', 'Slack (initial)')
area(t, P_s_upd, 'FaceAlpha', 0.4, 'FaceColor', [0.0  0.45 0.74], ...
    'DisplayName', 'Slack (with BESS)')
hold off
xlabel('Time step (15 min)'); ylabel('kW'); grid on
legend('Location', 'best')
title('Slack bus power: before vs after BESS')

% --- Plot 3: BESS losses per node per tech (stacked) ---
nexttile
hold on
stack_t = zeros(T, 1);   % running stack baseline
for nd = 1:Nd_loc
    if ~any(out.sizing.Installation(nd,:) > 0.5); continue; end
    Idx = (nd-1)*T_loc + (1:T_loc);
    for j = 1:J_loc
        if out.sizing.Installation(nd,j) < 0.5; continue; end
        node_id  = out.sizing.demand_node_id(nd);
        % Same loss model as solve_ess_milp's throughput term: charging at
        % grid-side power B_plus stores eta_ch*B_plus, so (1-eta_ch)*B_plus is
        % lost; discharging B_minus to the grid draws B_minus/eta_dis from the
        % SOE, so (1/eta_dis-1)*B_minus is lost. (The two factors were swapped
        % here before 2026-10-10.)
        loss_ch  = out.injections.B_plus(Idx,j)  * (1 - eta_ch_v(j))     * bp;
        loss_dis = out.injections.B_minus(Idx,j) * (1/eta_dis_v(j) - 1)  * bp;
        area(t, stack_t + loss_ch, ...
            'FaceAlpha', 0.6, 'FaceColor', [0.85 0.35 0.35], ...
            'DisplayName', sprintf('Node %d | %s | charge loss', ...
            node_id, string(tech_names{j})));
        area(t, stack_t + loss_ch + loss_dis, ...
            'FaceAlpha', 0.4, 'FaceColor', [0.35 0.35 0.85], ...
            'DisplayName', sprintf('Node %d | %s | discharge loss', ...
            node_id, string(tech_names{j})));
        stack_t = stack_t + loss_ch + loss_dis;
    end
end
hold off
xlabel('Time step (15 min)'); ylabel('kW'); grid on
legend('Location', 'best')
title('BESS losses per node per tech')

% --- Plot 4: Slack losses ---
nexttile
hold on
area(t, P_loss_0,   'FaceAlpha', 0.4, 'FaceColor', [0.85 0.33 0.1], ...
    'DisplayName', 'Slack initial losses')
area(t, P_loss_upd, 'FaceAlpha', 0.4, 'FaceColor', [0.0  0.45 0.74], ...
    'DisplayName', 'Slack (with BESS) losses')
hold off
legend('Location', 'best')
xlabel('Time step (15 min)'); ylabel('kW'); grid on
title('Slack losses before and after BESS')

sgtitle(sprintf('Network %s - Active Power Analysis', out.meta.network_id_str), ...
    'FontSize', 13, 'FontWeight', 'bold')

% =========================================================================
%  FIGURE 2 — REACTIVE POWER
% =========================================================================
figure('Name', 'Reactive Power Analysis')
tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact')

% --- Plot 1: Reactive nodal injections ---
nexttile
hold on
area(t, Q_aggr,     'FaceAlpha', 0.6, 'DisplayName', 'Base reactive load')
area(t, Q_aggr_upd, 'FaceAlpha', 0.6, 'DisplayName', 'Base load + BESS Q')
hold off
xlabel('Time step (15 min)'); ylabel('kVAR'); grid on
legend('Location', 'best')
title('Reactive Power Injections')

% --- Plot 2: Slack bus reactive power ---
nexttile
hold on
area(t, Q_s_0,   'FaceAlpha', 0.4, 'FaceColor', [0.85 0.33 0.1], ...
    'DisplayName', 'Slack Q (initial)')
area(t, Q_s_upd, 'FaceAlpha', 0.4, 'FaceColor', [0.0  0.45 0.74], ...
    'DisplayName', 'Slack Q (with BESS)')
hold off
xlabel('Time step (15 min)'); ylabel('kVAR'); grid on
legend('Location', 'best')
title('Slack bus reactive power: before vs after BESS')

% --- Plot 3: Converter reactive utilisation per node per tech ---
nexttile
colors = lines(Nd_loc * J_loc);
hold on
c_idx = 0;
for nd = 1:Nd_loc
    if ~any(out.sizing.Installation(nd,:) > 0.5); continue; end
    Idx = (nd-1)*T_loc + (1:T_loc);
    for j = 1:J_loc
        if out.sizing.Installation(nd,j) < 0.5; continue; end
        c_idx   = c_idx + 1;
        node_id = out.sizing.demand_node_id(nd);
        Q_cap   = out.sizing.S_conv_node_pu(nd,j) * kQ_conv_v(j) * bp;
        Q_used  = abs(out.injections.Q_ess(Idx,j)) * bp;
        util    = Q_used / (Q_cap + eps);
        plot(t, util, 'Color', colors(c_idx,:), 'LineWidth', 1.5, ...
            'DisplayName', sprintf('Node %d | %s', node_id, string(tech_names{j})));
    end
end
yline(1.0, 'k--', 'Capacity limit', 'FontSize', 8, ...
    'LabelHorizontalAlignment', 'right', 'HandleVisibility', 'off');
hold off
xlabel('Time step (15 min)'); ylabel('Q utilisation [-]')
ylim([0 1.1]); grid on
legend('Location', 'best')
title('Converter reactive utilisation per node per tech')

% --- Plot 4: Slack reactive losses ---
nexttile
hold on
area(t, Q_loss_0,   'FaceAlpha', 0.4, 'FaceColor', [0.85 0.33 0.1], ...
    'DisplayName', 'Slack Q initial losses')
area(t, Q_loss_upd, 'FaceAlpha', 0.4, 'FaceColor', [0.0  0.45 0.74], ...
    'DisplayName', 'Slack Q (with BESS) losses')
hold off
legend('Location', 'best')
xlabel('Time step (15 min)'); ylabel('kVAR'); grid on
title('Slack reactive losses before and after BESS')

sgtitle(sprintf('Network %s - Reactive Power Analysis', out.meta.network_id_str), ...
    'FontSize', 13, 'FontWeight', 'bold')
end