function analyze_voltage_current(out)
% ANALYZE_VOLTAGE_CURRENT  Nodal voltages and line currents (pu of ampacity),
%                           before vs. after optimization.
%
%   analyze_voltage_current(out)
%
%   Restores the "before vs. after" voltage/current diagnostic that used to
%   be pasted inline into the sequential-linearization loop
%   (old-code/build_relin_diagnostic.m + old-code/plot_relin_diagnostic.m,
%   using the pre-refactor main.m locals). This version reads entirely from
%   a saved `out` struct, so it works the same on a fresh run or a `.mat`
%   loaded later, same convention as analyze_tech_selection/analyze_losses.
%
%   Produces two figures:
%     Fig 1 — Nodal voltages: initial operating point / linear model /
%             nonlinear load flow, plus error and shift subplots
%     Fig 2 — Line currents (pu of ampacity rating): same layout
%
%   Note: the original snippet also plotted current-iteration vs.
%   previous-iteration BESS dispatch. That comparison isn't reconstructable
%   post-hoc — only the best (min voltage-error) iteration is saved into
%   `out`, not the warm-start history — so it's not reproduced here.

N = out.grid.N;
L = numel(out.grid.CABLE_AMP);
T = numel(out.grid.vmag_lin) / N;

net_id = string(out.meta.network_id_str);

% Initial (pre-BESS, pre-curtailment) operating point, from the stored gm
Vmag0 = reshape(lm_stack(out.gm.lm.Vmag0), [], 1);   % [N*T x 1]
Imag0 = reshape(lm_stack(out.gm.lm.Imag0), [], 1);   % [L*T x 1], complex phasor (see docs/DEVELOPMENT_NOTES.md gotcha)

v_lin = out.grid.vmag_lin;   % [N*T x 1] linear model, solved
v_lf  = out.grid.V_lf;       % [N*T x 1] nonlinear load flow, solved

i_lin = out.grid.Imag_lin;   % [L*T x 1] linear model, solved
i_lf  = out.grid.I_lf;       % [L*T x 1] nonlinear load flow, solved

% Reshape to [N or L] x T (one row per node/branch); stacking is
% node-fast / timestep-slow (gm.lm.Vmag0 is [N x T], flattened column-major),
% so reshape(., N, T) recovers the [N x T] matrix directly (matches
% build_sensitivity_matrices.m).
vmag0_mat = reshape(abs(Vmag0), N, T);
v_lin_mat = reshape(abs(v_lin), N, T);
v_lf_mat  = reshape(abs(v_lf),  N, T);

amp_rat   = repmat(out.grid.CABLE_AMP, 1, T);
i0_mat    = reshape(abs(Imag0), L, T);
i_lin_mat = reshape(abs(i_lin), L, T);
i_lf_mat  = reshape(abs(i_lf),  L, T);

if isfield(out, 'meta') && isfield(out.meta, 'Ts_h') && ~isempty(out.meta.Ts_h)
    Ts_h = out.meta.Ts_h;
else
    Ts_h = 15/60;
end
t_axis = (1:T) * Ts_h;   % hours

% =========================================================================
%  FIGURE 1 — Nodal voltages
% =========================================================================
figure('Name', sprintf('Voltages | %s', net_id))

subplot(3,2,1)
plot(t_axis, vmag0_mat', 'Color', [0.5 0.5 0.5])
ylabel('Voltage (pu)'); xlabel('Time (h)')
title('Initial operating point (Vmag0)')
yline(0.9,'--','Color','r'); yline(1.1,'--','Color','r')
grid on

subplot(3,2,2)
plot(t_axis, v_lin_mat', 'b')
ylabel('Voltage (pu)'); xlabel('Time (h)')
title('Linear model prediction (solved)')
yline(0.9,'--','Color','r'); yline(1.1,'--','Color','r')
grid on

subplot(3,2,3)
plot(t_axis, v_lf_mat', 'r')
ylabel('Voltage (pu)'); xlabel('Time (h)')
title('Nonlinear load flow (ground truth)')
yline(0.9,'--','Color','r'); yline(1.1,'--','Color','r')
grid on

subplot(3,2,4)
plot(t_axis, (v_lin_mat - v_lf_mat)'*100, 'k')
yline(0, '--', 'HandleVisibility', 'off')
ylabel('\Delta Voltage (%)'); xlabel('Time (h)')
title(sprintf('Error: linear - load flow  (max=%.2f %%)', out.summary.volt_error*100))
grid on

subplot(3,2,5)
plot(t_axis, (vmag0_mat - v_lf_mat)', 'Color', [0.8 0.4 0])
yline(0, '--', 'HandleVisibility', 'off')
ylabel('\Delta Voltage (pu)'); xlabel('Time (h)')
title('Shift from initial point to load flow (before vs. after)')
grid on

subplot(3,2,6)
plot(t_axis, v_lin_mat', 'b', 'HandleVisibility', 'off');
hold on
plot(t_axis, v_lf_mat',  'r--', 'HandleVisibility', 'off');
plot(t_axis(1), v_lin_mat(1,1), 'b',   'DisplayName', 'Linear');
plot(t_axis(1), v_lf_mat(1,1),  'r--', 'DisplayName', 'Load flow');
hold off
ylabel('Voltage (pu)'); xlabel('Time (h)')
title('Linear vs load flow overlay')
grid on
legend('Location', 'best')

sgtitle(sprintf('Nodal Voltages | Network %s | status: %s', ...
    net_id, out.summary.cvx_status), 'FontSize', 12, 'Interpreter', 'none')

% =========================================================================
%  FIGURE 2 — Line currents (pu of ampacity)
% =========================================================================
figure('Name', sprintf('Currents | %s', net_id))

subplot(3,2,1)
plot(t_axis, (i0_mat./amp_rat)', 'Color', [0.5 0.5 0.5])
ylabel('Current (pu of ampacity)'); xlabel('Time (h)')
title('Initial operating point (Imag0)')
grid on

subplot(3,2,2)
plot(t_axis, (i_lin_mat./amp_rat)', 'b')
ylabel('Current (pu of ampacity)'); xlabel('Time (h)')
title('Linear model prediction (solved)')
grid on

subplot(3,2,3)
plot(t_axis, (i_lf_mat./amp_rat)', 'r')
ylabel('Current (pu of ampacity)'); xlabel('Time (h)')
title('Nonlinear load flow (ground truth)')
grid on

subplot(3,2,4)
plot(t_axis, ((i_lin_mat - i_lf_mat)./amp_rat)', 'k')
yline(0, '--', 'HandleVisibility', 'off')
ylabel('\Delta Current (pu)'); xlabel('Time (h)')
title(sprintf('Error: linear - load flow  (max=%.2e pu)', out.summary.curr_error))
grid on

subplot(3,2,5)
plot(t_axis, ((i0_mat - i_lf_mat)./amp_rat)', 'Color', [0.8 0.4 0])
yline(0, '--', 'HandleVisibility', 'off')
ylabel('\Delta Current (pu)'); xlabel('Time (h)')
title('Shift from initial point to load flow (before vs. after)')
grid on

subplot(3,2,6)
i_lin_pu = i_lin_mat./amp_rat;
i_lf_pu  = i_lf_mat./amp_rat;
plot(t_axis, i_lin_pu', 'b', 'HandleVisibility', 'off');
hold on
plot(t_axis, i_lf_pu',  'r--', 'HandleVisibility', 'off');
plot(t_axis(1), i_lin_pu(1,1), 'b',   'DisplayName', 'Linear');
plot(t_axis(1), i_lf_pu(1,1),  'r--', 'DisplayName', 'Load flow');
hold off
ylabel('Current (pu of ampacity)'); xlabel('Time (h)')
title('Linear vs load flow overlay')
grid on
legend('Location', 'best')

sgtitle(sprintf('Line Currents (pu of ampacity) | Network %s', net_id), ...
    'FontSize', 12, 'Interpreter', 'none')

end
