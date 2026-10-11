function plot_dispatch_convergence_multi(all_dispatch_logs, all_dispatch_ids)
% PLOT_DISPATCH_CONVERGENCE_MULTI  Overlay convergence diagnostics for N networks.
%
%   plot_dispatch_convergence_multi(all_dispatch_logs, all_dispatch_ids)
%
%   all_dispatch_logs   cell array {1 x N} of dispatch_log structs
%   all_dispatch_ids    cell array {1 x N} of network ID strings
%
% CONVENTION: delta_* variables are INCREMENTS from warm-start point.
%   delta_P == -(dB_plus - dB_minus)   % active power increment
%   delta_Q == sum(dQ_ess, 2)          % reactive power increment (NOT sum(Q_ess))

N      = numel(all_dispatch_logs);
colors = lines(N);

figure;

% -------------------------------------------------------------------------
% 1 — Sizing: E_nom
% -------------------------------------------------------------------------
subplot(3,2,1); hold on;
for k = 1:N
    dl    = all_dispatch_logs{k};
    iters = 1:numel(dl.volt_err);
    plot(iters, dl.E_nom_total, 'o-', ...
        'Color', colors(k,:), 'LineWidth', 1.5, ...
        'DisplayName', strrep(all_dispatch_ids{k}, '_', '\_'));
end
ylabel('E_{nom} total (kWh)');
xlabel('Iteration');
title('Sizing — E_{nom}');
legend('Location', 'best', 'Interpreter', 'tex');
grid on;

% -------------------------------------------------------------------------
% 2 — Active dispatch: B+ and B- on same axis, Q on right
% -------------------------------------------------------------------------
subplot(3,2,2); hold on;
for k = 1:N
    dl    = all_dispatch_logs{k};
    iters = 1:numel(dl.volt_err);
    yyaxis left
    plot(iters, dl.B_plus_max  * 100 * 3, 'o-', ...
        'Color', colors(k,:), 'LineWidth', 1.5, ...
        'DisplayName', strrep(all_dispatch_ids{k}, '_', '\_'));
    plot(iters, dl.B_minus_max * 100 * 3, 's--', ...
        'Color', colors(k,:), 'LineWidth', 1.0, ...
        'HandleVisibility', 'off');
    yyaxis right
    plot(iters, dl.Q_ess_max * 100 * 3, '^:', ...
        'Color', colors(k,:), 'LineWidth', 1.0, ...
        'HandleVisibility', 'off');
end
yyaxis left;  ylabel('max B+/B- (kW)  solid/dashed');
yyaxis right; ylabel('max |Q_{ess}| (kVAR)');
xlabel('Iteration');
title('Max Active (solid=B+, dashed=B-) and Reactive (dotted)');
legend('Location', 'best', 'Interpreter', 'tex');
grid on;

% -------------------------------------------------------------------------
% 3 — Linearization errors (linear)
% -------------------------------------------------------------------------
subplot(3,2,3); hold on;
for k = 1:N
    dl    = all_dispatch_logs{k};
    iters = 1:numel(dl.volt_err);
    plot(iters, dl.volt_err * 100, 'o-', ...
        'Color', colors(k,:), 'LineWidth', 1.5, ...
        'DisplayName', strrep(all_dispatch_ids{k}, '_', '\_'));
    plot(iters, dl.curr_err * 100, 's--', ...
        'Color', colors(k,:), 'LineWidth', 1.0, ...
        'HandleVisibility', 'off');
end
yline(1, 'k:', 'LineWidth', 1.5,'DisplayName','1% thresh', 'LabelHorizontalAlignment', 'left');
ylabel('Max error (%)');
xlabel('Iteration');
title('Linearization Errors (solid=volt, dashed=curr)');
legend('Location', 'best', 'Interpreter', 'tex');
grid on;

% -------------------------------------------------------------------------
% 4 — Linearization errors (log)
% -------------------------------------------------------------------------
subplot(3,2,4); hold on;
for k = 1:N
    dl    = all_dispatch_logs{k};
    iters = 1:numel(dl.volt_err);
    semilogy(iters, dl.volt_err * 100, 'o-', ...
        'Color', colors(k,:), 'LineWidth', 1.5, ...
        'DisplayName', strrep(all_dispatch_ids{k}, '_', '\_'));
    semilogy(iters, dl.curr_err * 100, 's--', ...
        'Color', colors(k,:), 'LineWidth', 1.0, ...
        'HandleVisibility', 'off');
end
yline(1, 'k:', 'LineWidth', 1.5,'DisplayName','1% thresh', 'LabelHorizontalAlignment', 'left');
ylabel('Max error (%)');
xlabel('Iteration');
title('Linearization Errors log (solid=volt, dashed=curr)');
legend('Location', 'best', 'Interpreter', 'tex');
grid on;

% -------------------------------------------------------------------------
% 5 — Cost (left) + BESS count (right)
% -------------------------------------------------------------------------
subplot(3,2,5); hold on;
for k = 1:N
    dl    = all_dispatch_logs{k};
    iters = 1:numel(dl.volt_err);
    yyaxis left
    plot(iters, dl.cost, 'o-', ...
        'Color', colors(k,:), 'LineWidth', 1.5, ...
        'DisplayName', strrep(all_dispatch_ids{k}, '_', '\_'));
    yyaxis right
    plot(iters, dl.num_batt, 's--', ...
        'Color', colors(k,:), 'LineWidth', 1.0, ...
        'HandleVisibility', 'off');
end
yyaxis left;  ylabel('CVX cost');
yyaxis right; ylabel('BESS count'); ylim([0 max(2, max(cellfun(@(d) max(d.num_batt), all_dispatch_logs))) + 1]);
xlabel('Iteration');
title('Objective Value (solid) and BESS Count (dashed)');
legend('Location', 'best', 'Interpreter', 'tex');
grid on;

% -------------------------------------------------------------------------
% 6 — C-rate (left) + PF (right)
% -------------------------------------------------------------------------
subplot(3,2,6); hold on;
for k = 1:N
    dl    = all_dispatch_logs{k};
    iters = 1:numel(dl.volt_err);
    yyaxis left
    plot(iters, dl.C_rate_max, 'o-', ...
        'Color', colors(k,:), 'LineWidth', 1.5, ...
        'DisplayName', strrep(all_dispatch_ids{k}, '_', '\_'));
    yyaxis right
    plot(iters, dl.PF_min, 's--', ...
        'Color', colors(k,:), 'LineWidth', 1.0, ...
        'HandleVisibility', 'off');
end
yyaxis left;  ylabel('Max C-rate (h^{-1})');
yyaxis right; ylabel('Min PF (-)'); ylim([0 1]);
xlabel('Iteration');
title('C-rate (solid) and Power Factor (dashed)');
legend('Location', 'best', 'Interpreter', 'tex');
grid on;

sgtitle('Sequential Linearization Diagnostics — Multi-Network', ...
        'FontWeight', 'bold', 'Interpreter', 'none');

end