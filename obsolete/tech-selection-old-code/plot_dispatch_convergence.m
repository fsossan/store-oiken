function plot_dispatch_convergence(dispatch_log, net_id)
% PLOT_DISPATCH_CONVERGENCE  Plot sequential linearization convergence diagnostics.
%
%   plot_dispatch_convergence(dispatch_log, net_id)
%
%   dispatch_log  struct built inside the lin_iter loop (fields below)
%   net_id        string network identifier for figure title
%
%   Required dispatch_log fields (scalar per iteration):
%     E_nom_total      — total BESS energy capacity (kWh, 3-phase)
%     S_conv_total     — total converter rating (kVA, 3-phase)
%     B_plus_max       — max charging power (p.u.)
%     B_minus_max      — max discharging power (p.u.)
%     Q_ess_max        — max reactive power magnitude (p.u.)
%     Q_nonzero_frac   — fraction of Q_ess entries above 1e-6
%     volt_err         — max nodal voltage linearization error (p.u.)
%     curr_err         — max line current linearization error (p.u.)
%     cost             — CVX objective value
%     num_batt         — number of installed BESS (I > 1e-4)
%     C_rate_max       — max C-rate across nodes/techs (h^-1)
%     PF_min           — min power factor at converter output
%
% CONVENTION: delta_* variables are INCREMENTS from warm-start point.
%   delta_P == -(dB_plus - dB_minus)   % active power increment
%   delta_Q == sum(dQ_ess, 2)          % reactive power increment (NOT sum(Q_ess))

n_iter = numel(dispatch_log.volt_err);
iters  = 1:n_iter;

figure;

% -------------------------------------------------------------------------
% 1 — Sizing: E and S
% -------------------------------------------------------------------------
subplot(3,2,1);
yyaxis left
plot(iters, dispatch_log.E_nom_total, 'o-', 'LineWidth', 1.5);
ylabel('E_{nom} total (kWh)');
yyaxis right
plot(iters, dispatch_log.S_conv_total, 's--', 'LineWidth', 1.5);
ylabel('S_{conv} total (kVA)');
xlabel('Iteration');
title('Sizing');
legend('E_{nom}','S_{conv}','Location','best');
grid on;

% -------------------------------------------------------------------------
% 2 — Active + Q dispatch
% -------------------------------------------------------------------------
subplot(3,2,2);
yyaxis left
plot(iters, dispatch_log.B_plus_max  * 100 * 3, 'o-',  'LineWidth', 1.5); hold on;
plot(iters, dispatch_log.B_minus_max * 100 * 3, 's--', 'LineWidth', 1.5);
ylabel('max B (kW)');
yyaxis right
plot(iters, dispatch_log.Q_ess_max * 100 * 3, '^:', 'LineWidth', 1.5);
ylabel('max |Q_{ess}| (kVAR)');
xlabel('Iteration');
title('Max Active and Reactive Dispatch');
legend('B_{plus}','B_{minus}','Q_{ess}','Location','best');
grid on;

% -------------------------------------------------------------------------
% 3 — Linearization errors (linear scale)
% -------------------------------------------------------------------------
subplot(3,2,3);
plot(iters, dispatch_log.volt_err * 100, 'o-',  'LineWidth', 1.5); hold on;
plot(iters, dispatch_log.curr_err * 100, 's--', 'LineWidth', 1.5);
yline(1, 'k:', '1% thresh', 'LabelHorizontalAlignment', 'left');
ylabel('Max error (%)');
xlabel('Iteration');
title('Linearization Errors');
legend('Volt err','Curr err','Location','best');
grid on;

% -------------------------------------------------------------------------
% 4 — Linearization errors (log scale)
% -------------------------------------------------------------------------
subplot(3,2,4);
semilogy(iters, dispatch_log.volt_err * 100, 'o-',  'LineWidth', 1.5); hold on;
semilogy(iters, dispatch_log.curr_err * 100, 's--', 'LineWidth', 1.5);
yline(1, 'k:', '1% thresh', 'LabelHorizontalAlignment', 'left');
ylabel('Max error (%)');
xlabel('Iteration');
title('Linearization Errors (log)');
legend('Volt err','Curr err','Location','best');
grid on;

% -------------------------------------------------------------------------
% 5 — Cost + BESS count
% -------------------------------------------------------------------------
subplot(3,2,5);
yyaxis left
plot(iters, dispatch_log.cost, 'o-', 'LineWidth', 1.5);
ylabel('CVX cost');
yyaxis right
bar(iters, dispatch_log.num_batt, 0.4, 'FaceAlpha', 0.4);
ylabel('BESS count');
xlabel('Iteration');
title('Objective Value and BESS Count');
legend('Cost','N_{batt}','Location','best');
grid on;

% -------------------------------------------------------------------------
% 6 — C-rate + Power Factor
% -------------------------------------------------------------------------
subplot(3,2,6);
yyaxis left
plot(iters, dispatch_log.C_rate_max, 'o-', 'LineWidth', 1.5);
ylabel('Max C-rate (h^{-1})');
yyaxis right
plot(iters, dispatch_log.PF_min, 's--', 'LineWidth', 1.5);
ylabel('Min Power Factor (-)');
ylim([0 1]);
xlabel('Iteration');
title('C-rate and Power Factor');
legend('C-rate','PF','Location','best');
grid on;

sgtitle(sprintf('Sequential Linearization Diagnostics — %s', net_id), ...
        'FontWeight', 'bold','Interpreter','none');

end
