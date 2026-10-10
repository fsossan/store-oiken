% PF_testing_script.m
% -------------------------------------------------------------------------
% Power Factor validation script — reads CVX solution variables from workspace.
% Run immediately after cvx_end inside the lin_iter loop, or after the loop
% using best_out variables.
%
% Required workspace variables:
%   B_plus, B_minus   — (T*Nd x J) charging/discharging power (p.u.)
%   Q_ess             — (T*Nd x J) reactive power (p.u.)
%   E_nom             — (Nd x J)   energy capacity (p.u.)
%   S_conv            — (Nd x J)   converter rating (p.u.)
%   I                 — (Nd x J)   installation binary
%   T, Nd, J, Ts      — dimensions and timestep
%   kP, kQ_conv, kPF  — converter PQ box parameters
%
% CONVENTION:
%   delta_P == -(dB_plus - dB_minus)   % active power increment
%   delta_Q == sum(dQ_ess, 2)          % reactive power increment (NOT sum(Q_ess))
% -------------------------------------------------------------------------

fprintf('\n=== PF VALIDATION SCRIPT ===\n');

% -------------------------------------------------------------------------
% Extract and reshape
% -------------------------------------------------------------------------
B_plus_f  = full(B_plus);    % T*Nd x J
B_minus_f = full(B_minus);   % T*Nd x J
Q_ess_f   = full(Q_ess);     % T*Nd x J
E_nom_f   = full(E_nom);     % Nd x J
S_conv_f  = full(S_conv);    % Nd x J
I_f       = full(I);         % Nd x J

% Active nodes (installation binary above threshold)
active_nodes = find(any(I_f > 1e-4, 2));   % Nd_active x 1
n_active     = numel(active_nodes);

if n_active == 0
    fprintf('  No active BESS nodes found (I < 1e-4 everywhere).\n');
    return
end

fprintf('  Active nodes: %d / %d\n', n_active, Nd);

% -------------------------------------------------------------------------
% Per-node per-timestep quantities
% -------------------------------------------------------------------------
% Reshape to (T x Nd x J)
P_bat_3d = zeros(T, Nd, J);
Q_ess_3d = zeros(T, Nd, J);
for n = 1:Nd
    Idx = (n-1)*T + (1:T);
    P_bat_3d(:, n, :) = B_plus_f(Idx, :) - B_minus_f(Idx, :);
    Q_ess_3d(:, n, :) = Q_ess_f(Idx, :);
end

% Apparent power and PF per node/timestep
S_app_3d = sqrt(P_bat_3d.^2 + Q_ess_3d.^2);   % T x Nd x J
PF_3d    = P_bat_3d ./ (S_app_3d + eps);        % T x Nd x J

% PQ box constraint check: |Q_ess| <= kPF * (B_plus + B_minus)
B_sum_3d = zeros(T, Nd, J);
for n = 1:Nd
    Idx = (n-1)*T + (1:T);
    B_sum_3d(:, n, :) = B_plus_f(Idx, :) + B_minus_f(Idx, :);
end
Q_abs_3d    = abs(Q_ess_3d);
PQ_limit_3d = kPF * B_sum_3d;
PQ_vio_3d   = Q_abs_3d - PQ_limit_3d;   % > 0 means violation

% -------------------------------------------------------------------------
% Print summary per active node
% -------------------------------------------------------------------------
fprintf('\n  %-8s  %-8s  %-8s  %-8s  %-8s  %-10s  %-10s\n', ...
    'Node', 'E(kWh)', 'S(kVA)', 'PF_min', 'PF_mean', 'Q_max(pu)', 'PQ_vio_max');
fprintf('  %s\n', repmat('-', 1, 72));

for k = 1:n_active
    n      = active_nodes(k);
    for j  = 1:J
        PF_node  = PF_3d(:, n, j);
        Q_node   = Q_ess_3d(:, n, j);
        vio_node = PQ_vio_3d(:, n, j);

        % Only report timesteps where there is meaningful dispatch
        active_ts = abs(P_bat_3d(:, n, j)) > 1e-6 | abs(Q_node) > 1e-6;

        if any(active_ts)
            fprintf('  %-8d  %-8.2f  %-8.2f  %-8.4f  %-8.4f  %-10.6f  %-10.6f\n', ...
                n, ...
                E_nom_f(n,j) * 100 * 3, ...
                S_conv_f(n,j) * 100 * 3, ...
                min(PF_node(active_ts)), ...
                mean(PF_node(active_ts)), ...
                max(abs(Q_node)), ...
                max(vio_node));
        else
            fprintf('  %-8d  %-8.2f  %-8.2f  [no dispatch]\n', ...
                n, E_nom_f(n,j)*100*3, S_conv_f(n,j)*100*3);
        end
    end
end

% Global PQ box violation check
max_vio = max(PQ_vio_3d(:));
if max_vio > 1e-4
    fprintf('\n  [WARNING] PQ box constraint violated: max violation = %.6f p.u.\n', max_vio);
else
    fprintf('\n  [OK] PQ box constraint satisfied (max violation = %.2e p.u.)\n', max_vio);
end

% -------------------------------------------------------------------------
% Plot 1 — Per active node: P_bat and Q_ess time series
% -------------------------------------------------------------------------
t_ax = (0:T-1) * Ts;   % hours

figure('Name', 'PF Validation — P and Q dispatch per node', ...
       'NumberTitle', 'off'...
       );

for k = 1:n_active
    n = active_nodes(k);
    for j = 1:J
        subplot(n_active, 1, k);
        hold on;
        plot(t_ax, P_bat_3d(:, n, j) * 100 * 3, 'b-',  'LineWidth', 1.5, 'DisplayName', 'P_{bat} (kW)');
        plot(t_ax, Q_ess_3d(:, n, j) * 100 * 3, 'r--', 'LineWidth', 1.5, 'DisplayName', 'Q_{ess} (kVAR)');
        yline(0, 'k:', 'HandleVisibility', 'off');
        ylabel('Power (kW / kVAR)');
        xlabel('Time (h)');
        title(sprintf('Node %d  |  E=%.2f kWh  S=%.2f kVA  I=%.4f', ...
            n, E_nom_f(n,j)*100*3, S_conv_f(n,j)*100*3, I_f(n,j)));
        legend('Location', 'best');
        grid on;
    end
end
sgtitle('P_{bat} and Q_{ess} Time Series — Active Nodes', 'FontWeight', 'bold');

% -------------------------------------------------------------------------
% Plot 2 — Per active node: PF time series with kP limit
% -------------------------------------------------------------------------
figure('Name', 'PF Validation — Power Factor per node', ...
       'NumberTitle', 'off' ...
       );

for k = 1:n_active
    n = active_nodes(k);
    for j = 1:J
        subplot(n_active, 1, k);
        hold on;

        active_ts  = abs(P_bat_3d(:, n, j)) > 1e-6 | abs(Q_ess_3d(:, n, j)) > 1e-6;
        PF_plot    = nan(T, 1);
        PF_plot(active_ts) = PF_3d(active_ts, n, j);

        plot(t_ax, PF_plot, 'b-', 'LineWidth', 1.5, 'DisplayName', 'PF');
        yline(kP,  'r--', sprintf('kP=%.2f', kP),  'LabelHorizontalAlignment', 'left');
        yline(-kP, 'r--', sprintf('-kP=%.2f', -kP), 'LabelHorizontalAlignment', 'left', ...
            'HandleVisibility', 'off');
        ylim([-1.1 1.1]);
        ylabel('Power Factor (-)');
        xlabel('Time (h)');
        title(sprintf('Node %d  |  PF min=%.4f  mean=%.4f', ...
            n, min(PF_plot(active_ts)), mean(PF_plot(active_ts))));
        legend('Location', 'best');
        grid on;
    end
end
sgtitle('Power Factor Time Series — Active Nodes', 'FontWeight', 'bold');

fprintf('\n=== END PF VALIDATION ===\n\n');