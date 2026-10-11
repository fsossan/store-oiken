% plot_temporal_from_gm.m



figure;

subplot(3,2,1)
plot(real(gm.injections_D_pu) * bp)
title('Nodal Demand Profiles')
xlabel('Time (15-min intervals)')
ylabel('Power (kW)')
grid on

subplot(3,2,2)
plot(gm.injectinos_PV_pu * bp)
title('PV Generation Profiles')
xlabel('Time (15-min intervals)')
ylabel('Power (kW)')
grid on

subplot(3,2,3)
plot(gm.injections_EV_pu * bp)
title('EV Charging Profiles')
xlabel('Time (15-min intervals)')
ylabel('Power (kW)')
grid on

subplot(3,2,4)
plot(real(gm.nodal_injections_D_pu) * bp)
title('Aggregate Nodal Power')
xlabel('Time (15-min intervals)')
ylabel('Power (kW)')
grid on

subplot(3,2,5)
v_test = vertcat(gm.lm.Vmag0{:});
plot(reshape(abs(v_test),N,T)');
hold on
yline(0.9, 'r--', 'LineWidth', 1.5)
yline(1.1, 'r--', 'LineWidth', 1.5)
hold off
title('Nodal Voltages')
xlabel('Time (15-min intervals)')
ylabel('Voltage (p.u.)')
grid on

subplot(3,2,6)
i_test = vertcat(gm_curr.lm.Imag0{:});
i_test = reshape(abs(i_test),L,T);
amp_limit =  repmat(CABLE_AMP, T, 1);
amp_limit = reshape(amp_limit,L,T);
i_test = i_test./amp_limit;
plot(reshape(i_test,L,T)' )
hold on
yline(1.0, 'r--', 'LineWidth', 1.5)
hold off
title('Line Currents')
xlabel('Time (15-min intervals)')
ylabel('Current (p.u. of ampacity)')
grid on

net_disp  = strrep(net_id,  '_', '\_');
scen_disp = strrep(scenario,'_', '\_');
sgtitle(sprintf('Temporal Analysis(%s): %s', scen_disp, net_disp), ...
    'FontWeight', 'bold', 'FontSize', 14)