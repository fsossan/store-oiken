function plot_relin_diagnostic(diag)
%PLOT_RELIN_DIAGNOSTIC  Visualise sequential linearization quality.
%
%   plot_relin_diagnostic(diag)
%
%   Expects the diagnostic struct built by build_relin_diagnostic.m.
%   Produces three figures:
%     Fig 1 — Nodal voltages: initial / linear / load flow
%     Fig 2 — Line currents: initial / linear / load flow
%     Fig 3 — BESS injections: current vs previous iteration

N  = diag.meta.N;
L  = diag.meta.L;
T  = diag.meta.T;
Nd = diag.meta.Nd;
net_id   = diag.meta.network_id;
lin_iter = diag.meta.lin_iter;

% Reshape to (N or L or Nd) x T for plotting (one line per node/branch)
vmag0_mat = reshape(abs(diag.volt.vmag0), N, T);
v_lin_mat = reshape(abs(diag.volt.v_lin),  N, T);
v_lf_mat  = reshape(abs(diag.volt.v_lf),   N, T);

amp_rat   = repmat(diag.curr.amp_rat,1,T);
i0_mat    = reshape(abs(diag.curr.imag0),  L, T);
i_lin_mat = reshape(abs(diag.curr.i_lin),  L, T);
i_lf_mat  = reshape(abs(diag.curr.i_lf),  L, T);

t_axis = (1:T) * 15/60;   % hours

% -------------------------------------------------------------------------
%  Figure 1 — Nodal voltages
% -------------------------------------------------------------------------
% figure('Name', sprintf('Voltages | %s | iter %d', net_id, lin_iter), ...
%     'Position', [100 100 1000 700]);
figure
subplot(3,2,1)
plot(t_axis, vmag0_mat', 'Color', [0.5 0.5 0.5])
ylabel('Voltage (pu)'); xlabel('Time (h)')
title('Initial operating point (Vmag0)')
yline(0.9,'--','Color','r')
yline(1.1,'--','Color','r')

grid on

subplot(3,2,2)
plot(t_axis, v_lin_mat', 'b')
ylabel('Voltage (pu)'); xlabel('Time (h)')
title('Linear model prediction')
yline(0.9,'--','Color','r')
yline(1.1,'--','Color','r')
grid on

subplot(3,2,3)
plot(t_axis, v_lf_mat', 'r')
ylabel('Voltage (pu)'); xlabel('Time (h)')
title('Nonlinear load flow (ground truth)')
yline(0.9,'--','Color','r')
yline(1.1,'--','Color','r')
grid on

subplot(3,2,4)
plot(t_axis, (v_lin_mat - v_lf_mat)'*100, 'k')
yline(0, '--', 'HandleVisibility', 'off')
ylabel('\Delta Voltage (%)'); xlabel('Time (h)')
title(sprintf('Error: linear - load flow  (max=%.2f %%)', diag.errors.volt_error*100))
grid on

subplot(3,2,5)
plot(t_axis, (vmag0_mat - v_lf_mat)', 'Color', [0.8 0.4 0])
yline(0, '--', 'HandleVisibility', 'off')
ylabel('\Delta Voltage (pu)'); xlabel('Time (h)')
title('Shift from initial point to load flow')
grid on

 subplot(3,2,6)
h1 = plot(t_axis, v_lin_mat', 'b', 'HandleVisibility', 'off');
hold on
h2 = plot(t_axis, v_lf_mat',  'r--', 'HandleVisibility', 'off');
% plot invisible dummy lines just for the legend
plot(t_axis(1), v_lin_mat(1,1), 'b',   'DisplayName', 'Linear');
plot(t_axis(1), v_lf_mat(1,1),  'r--', 'DisplayName', 'Load flow');
hold off
ylabel('Voltage (pu)'); xlabel('Time (h)')
title('Linear vs load flow overlay')
 grid on
legend('Location', 'best')
sgtitle(sprintf('Nodal Voltages | Network %s | Iter %d | status: %s', ...
    net_id, lin_iter, diag.errors.cvx_status), 'FontSize', 12,'Interpreter','none')

% -------------------------------------------------------------------------
%  Figure 2 — Line currents
% -------------------------------------------------------------------------
% figure('Name', sprintf('Currents | %s | iter %d', net_id, lin_iter), ...
%     'Position', [150 100 1000 700]);
figure
subplot(3,2,1)
plot(t_axis, (i0_mat./amp_rat)', 'Color', [0.5 0.5 0.5])
ylabel('Current (pu)'); xlabel('Time (h)')
title('Initial operating point (Imag0)')
grid on

subplot(3,2,2)
plot(t_axis, (i_lin_mat./amp_rat)', 'b')
ylabel('Current (pu)'); xlabel('Time (h)')
title('Linear model prediction')
grid on

subplot(3,2,3)
plot(t_axis, (i_lf_mat./amp_rat)', 'r')
ylabel('Current (pu)'); xlabel('Time (h)')
title('Nonlinear load flow (ground truth)')
grid on

subplot(3,2,4)
plot(t_axis, ((i_lin_mat - i_lf_mat)./amp_rat)', 'k')
yline(0, '--', 'HandleVisibility', 'off')
ylabel('\Delta Current (pu)'); xlabel('Time (h)')
title(sprintf('Error: linear - load flow  (max=%.2e pu)', diag.errors.curr_error))
grid on

subplot(3,2,5)
plot(t_axis, ((i0_mat - i_lf_mat)./amp_rat)', 'Color', [0.8 0.4 0])
yline(0, '--', 'HandleVisibility', 'off')
ylabel('\Delta Current (pu)'); xlabel('Time (h)')
title('Shift from initial point to load flow')
grid on

subplot(3,2,6)
plot(t_axis, (i_lin_mat./amp_rat)', 'b', 'DisplayName', 'Linear')
hold on
plot(t_axis, (i_lf_mat./amp_rat)',  'r--', 'DisplayName', 'Load flow')
hold off
ylabel('Current (pu)'); xlabel('Time (h)')
title('Linear vs load flow overlay')
grid on
legend('Linear', 'Load flow', 'Location', 'best')

sgtitle(sprintf('Line Currents | Network %s | Iter %d', net_id, lin_iter), 'FontSize', 12,'Interpreter','none')

% -------------------------------------------------------------------------
%  Figure 3 — BESS injections: current vs previous iteration
% -------------------------------------------------------------------------
% figure('Name', sprintf('BESS | %s | iter %d', net_id, lin_iter), ...
%     'Position', [200 100 1000 500]);
figure
% Sum across techs and reshape to Nd x T
B_bat_curr = reshape(sum(diag.bess.B_bat,    2), T, Nd)';   % Nd x T
B_plus_curr = reshape(sum(diag.bess.B_plus,  2), T, Nd)';
B_minus_curr= reshape(sum(diag.bess.B_minus, 2), T, Nd)';
B_plus_prev = reshape(sum(diag.bess.B_plus_prev,  2), T, Nd)';
B_minus_prev= reshape(sum(diag.bess.B_minus_prev, 2), T, Nd)';

subplot(2,3,1)
plot(t_axis, B_plus_curr', 'b')
ylabel('Power (pu)'); xlabel('Time (h)')
title('B_{plus} current iter (charging)')
grid on

subplot(2,3,2)
plot(t_axis, B_minus_curr', 'r')
ylabel('Power (pu)'); xlabel('Time (h)')
title('B_{minus} current iter (discharging)')
grid on

subplot(2,3,3)
plot(t_axis, B_bat_curr', 'k')
yline(0, '--', 'HandleVisibility', 'off')
ylabel('Power (pu)'); xlabel('Time (h)')
title('Net BESS power (B_{plus} - B_{minus})')
grid on

subplot(2,3,4)
plot(t_axis, B_plus_prev', 'b--')
ylabel('Power (pu)'); xlabel('Time (h)')
title('B_{plus} previous iter (warm-start)')
grid on

subplot(2,3,5)
plot(t_axis, B_minus_prev', 'r--')
ylabel('Power (pu)'); xlabel('Time (h)')
title('B_{minus} previous iter (warm-start)')
grid on

subplot(2,3,6)
% delta between iterations
dB = B_bat_curr - reshape(sum(diag.bess.B_plus_prev - diag.bess.B_minus_prev, 2), T, Nd)';
plot(t_axis, dB', 'Color', [0.5 0 0.5])
yline(0, '--', 'HandleVisibility', 'off')
ylabel('Power (pu)'); xlabel('Time (h)')
title('Change in net BESS power (iter - prev)')
grid on

sgtitle(sprintf('BESS Injections | Network %s | Iter %d | cost=%.4f', ...
    net_id, lin_iter, diag.errors.cvx_optval), 'FontSize', 12,'Interpreter','none')

end