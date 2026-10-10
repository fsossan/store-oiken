function report = analyze_curtailment(out, cfg)
% ANALYZE_CURTAILMENT  Explain PV-curtailment behaviour: costs, dispatch,
%                       and slack-bus impact for one solved network.
%
%   report = analyze_curtailment(out)
%   report = analyze_curtailment(out, cfg)   % cfg optional, adds CHF/kWh
%                                             % price context to the printout
%
%   Call after loading a solved .mat (or right after run_seq_lin_loop_ess),
%   same convention as analyze_tech_selection(out, cfg) / analyze_losses(out).
%
%   Produces one figure (2x3 tiledlayout):
%     1. Objective cost breakdown (E / S / I / L / Curt)
%     2. Aggregate PV: available vs. delivered vs. curtailed, over time
%     3. Curtailed energy per PV node (kWh over the horizon)
%     4. Curtailment fraction per node per timestep (curtailed / available)
%     5. Slack active power: baseline (no BESS/no curtailment) vs. final
%     6. Slack loss proxy (P_sloss): baseline vs. final
%
%   Panels 5-6 compare the ORIGINAL (pre-solve) operating point against the
%   FINAL solved one, which includes both BESS dispatch and curtailment
%   together — the two can't be cleanly separated post-hoc without another
%   solve, so this mirrors analyze_losses.m's existing before/after framing
%   rather than claiming a curtailment-only counterfactual.
%
%   Returns a struct with the same numbers printed to console, for scripted
%   use (e.g. batch-comparing curtailment across networks).

if nargin < 2; cfg = []; end

bp = kw_per_pu_of(out);   % pu -> real 3-phase kW/kWh (out.meta.kW_per_pu; 300 for old results)
if isfield(out, 'meta') && isfield(out.meta, 'Ts_h') && ~isempty(out.meta.Ts_h)
    Ts = out.meta.Ts_h;
elseif ~isempty(cfg) && isfield(cfg, 'solver') && isfield(cfg.solver, 'Ts_h')
    Ts = cfg.solver.Ts_h;
else
    Ts = 15/60;
end

T   = numel(out.injections.P_sloss);
t   = (1:T)';
Npv = numel(out.sizing.pv_node_id);

% -------------------------------------------------------------------------
%  Curtailment quantities
% -------------------------------------------------------------------------
if Npv > 0
    PV_avail_kW     = out.gm.injectinos_PV_pu * bp;               % [T x Npv]
    P_curt_kW       = reshape(out.injections.P_curt, T, Npv) * bp; % [T x Npv]
    PV_delivered_kW = PV_avail_kW - P_curt_kW;

    curt_energy_node_kWh = sum(P_curt_kW, 1) * Ts;      % [1 x Npv]
    avail_energy_node_kWh = sum(PV_avail_kW, 1) * Ts;   % [1 x Npv]

    total_curt_kWh  = sum(curt_energy_node_kWh);
    total_avail_kWh = sum(avail_energy_node_kWh);
    pct_curtailed   = 100 * total_curt_kWh / max(total_avail_kWh, eps);

    curt_frac = P_curt_kW ./ max(PV_avail_kW, eps);     % [T x Npv]
    tol = 1e-6 * bp;
    n_active = nnz(P_curt_kW > tol);
    [max_curt_kW, max_idx] = max(P_curt_kW(:));
    [max_t, max_n] = ind2sub(size(P_curt_kW), max_idx);
    max_node_id = out.sizing.pv_node_id(max_n);

    curt_total_per_t = sum(P_curt_kW, 2);               % [T x 1] combined across all PV nodes
    [max_combined_kW, max_combined_t] = max(curt_total_per_t);
else
    PV_avail_kW = zeros(T, 0); P_curt_kW = zeros(T, 0); PV_delivered_kW = zeros(T, 0);
    curt_energy_node_kWh = []; total_curt_kWh = 0; total_avail_kWh = 0; pct_curtailed = 0;
    curt_frac = zeros(T, 0); n_active = 0; max_curt_kW = 0; max_t = 0; max_node_id = NaN;
    max_combined_kW = 0; max_combined_t = 0;
end

% -------------------------------------------------------------------------
%  Slack bus power / loss proxy: baseline (pre-solve) vs. final (solved)
% -------------------------------------------------------------------------
P_aggr_0   = sum(out.injections.P0_mat)' * bp;     % [T x 1] baseline net nodal injection
P_s_0      = real(out.injections.Ss0)    * bp;     % [T x 1] baseline slack power
P_sloss_0  = P_s_0 + P_aggr_0;                      % baseline loss proxy (no BESS, no curtailment)

P_s_final     = real(out.injections.Sl_P) * bp;     % [T x 1] final slack power (BESS + curtailment)
P_sloss_final = out.injections.P_sloss    * bp;     % [T x 1] final loss proxy

% -------------------------------------------------------------------------
%  Cost breakdown
% -------------------------------------------------------------------------
c = out.costs;
cost_names = {'E (energy capex)', 'S (power capex)', 'I (install)', 'L (losses)', 'Curt (curtailment)'};
cost_vals  = [c.E, c.S, c.I, c.L, c.Curt];
cost_pct   = 100 * cost_vals / max(c.total, eps);

% -------------------------------------------------------------------------
%  Console report
% -------------------------------------------------------------------------
fprintf('\n=== Curtailment diagnostics: network %s ===\n', string(out.meta.network_id_str));
fprintf('--- Objective cost breakdown ---\n');
for k = 1:numel(cost_names)
    fprintf('  %-20s %10.2f  (%5.1f%%)\n', cost_names{k}, cost_vals(k), cost_pct(k));
end
fprintf('  %-20s %10.2f\n', 'TOTAL', c.total);

if Npv > 0
    fprintf('--- PV curtailment ---\n');
    fprintf('  PV-bearing nodes:        %d\n', Npv);
    fprintf('  Available PV energy:     %.2f kWh (over %d steps)\n', total_avail_kWh, T);
    fprintf('  Curtailed PV energy:     %.2f kWh (%.1f%% of available)\n', total_curt_kWh, pct_curtailed);
    fprintf('  Active curtailment instances (node,timestep pairs): %d / %d\n', n_active, T*Npv);
    fprintf('  Largest single curtailment: %.2f kW at node %d, timestep %d\n', ...
        max_curt_kW, max_node_id, max_t);
    fprintf('  Largest COMBINED curtailment (all PV nodes, same timestep): %.2f kW at timestep %d\n', ...
        max_combined_kW, max_combined_t);
    if ~isempty(cfg) && isfield(cfg, 'economics')
        fprintf('  Curtailment price used:  %.3f CHF/kWh\n', cfg.economics.curtailment_price_CHF_per_kWh);
    end
else
    fprintf('--- PV curtailment ---\n  No PV-bearing nodes in this network.\n');
end
fprintf('\n');

% -------------------------------------------------------------------------
%  Figure
% -------------------------------------------------------------------------
figure('Name', 'Curtailment Diagnostics')
tiledlayout(2, 3, 'TileSpacing', 'compact', 'Padding', 'compact')

% --- Panel 1: cost breakdown ---
nexttile
bar(categorical(cost_names, cost_names), cost_vals)
ylabel('Cost (objective units)'); grid on
title(sprintf('Cost breakdown (total = %.1f)', c.total))

% --- Panel 2: aggregate PV available / delivered / curtailed ---
nexttile
if Npv > 0
    hold on
    area(t, sum(PV_avail_kW, 2),     'FaceAlpha', 0.3, 'DisplayName', 'Available')
    area(t, sum(PV_delivered_kW, 2), 'FaceAlpha', 0.6, 'DisplayName', 'Delivered')
    plot(t, sum(P_curt_kW, 2), 'r-', 'LineWidth', 1.5, 'DisplayName', 'Curtailed')
    hold off
    legend('Location', 'best')
else
    text(0.5, 0.5, 'No PV nodes', 'HorizontalAlignment', 'center')
end
xlabel('Time step (15 min)'); ylabel('kW'); grid on
title('Aggregate PV: available vs. delivered')

% --- Panel 3: curtailed energy per node ---
nexttile
if Npv > 0 && total_curt_kWh > 0
    [sorted_kWh, ord] = sort(curt_energy_node_kWh, 'descend');
    keep = sorted_kWh > 1e-6;
    bar(categorical(string(out.sizing.pv_node_id(ord(keep))), ...
        string(out.sizing.pv_node_id(ord(keep)))), sorted_kWh(keep))
    xlabel('PV node id'); ylabel('Curtailed energy (kWh)')
else
    text(0.5, 0.5, 'No curtailment', 'HorizontalAlignment', 'center')
end
grid on
title('Curtailed energy per node')

% --- Panel 4: curtailment fraction heatmap ---
nexttile
if Npv > 0
    imagesc(t, 1:Npv, curt_frac')
    set(gca, 'YDir', 'normal')
    yticks(1:Npv); yticklabels(string(out.sizing.pv_node_id))
    colorbar; clim([0 1])
    xlabel('Time step (15 min)'); ylabel('PV node id')
else
    text(0.5, 0.5, 'No PV nodes', 'HorizontalAlignment', 'center')
end
title('Curtailed / available fraction')

% --- Panel 5: slack active power, baseline vs. final ---
nexttile
hold on
area(t, P_s_0,     'FaceAlpha', 0.4, 'FaceColor', [0.85 0.33 0.1], 'DisplayName', 'Baseline (no BESS/curt.)')
area(t, P_s_final, 'FaceAlpha', 0.4, 'FaceColor', [0.0  0.45 0.74], 'DisplayName', 'Final (BESS + curt.)')
hold off
legend('Location', 'best')
xlabel('Time step (15 min)'); ylabel('kW'); grid on
title('Slack active power')

% --- Panel 6: slack loss proxy, baseline vs. final ---
nexttile
hold on
area(t, P_sloss_0,     'FaceAlpha', 0.4, 'FaceColor', [0.85 0.33 0.1], 'DisplayName', 'Baseline (no BESS/curt.)')
area(t, P_sloss_final, 'FaceAlpha', 0.4, 'FaceColor', [0.0  0.45 0.74], 'DisplayName', 'Final (BESS + curt.)')
hold off
legend('Location', 'best')
xlabel('Time step (15 min)'); ylabel('kW'); grid on
title('Slack loss proxy (P_{sloss})')

sgtitle(sprintf('Network %s — Curtailment Diagnostics', string(out.meta.network_id_str)), ...
    'FontSize', 13, 'FontWeight', 'bold')

% -------------------------------------------------------------------------
%  Return struct
% -------------------------------------------------------------------------
report.costs             = c;
report.costs.pct         = struct('E', cost_pct(1), 'S', cost_pct(2), 'I', cost_pct(3), ...
                                    'L', cost_pct(4), 'Curt', cost_pct(5));
report.curtailment.Npv                    = Npv;
report.curtailment.pv_node_id             = out.sizing.pv_node_id;
report.curtailment.total_curtailed_kWh    = total_curt_kWh;
report.curtailment.total_available_kWh   = total_avail_kWh;
report.curtailment.pct_curtailed          = pct_curtailed;
report.curtailment.per_node_curtailed_kWh = curt_energy_node_kWh;
report.curtailment.n_active_instances     = n_active;
report.curtailment.max_curt_kW            = max_curt_kW;
report.curtailment.max_curt_node_id       = max_node_id;
report.curtailment.max_curt_timestep      = max_t;
report.curtailment.max_combined_kW        = max_combined_kW;
report.curtailment.max_combined_timestep  = max_combined_t;

end
