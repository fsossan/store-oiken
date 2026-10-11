
function OPF_verification(P,Grid)

 grid  = Grid;


t0_hour =  0;
tf_hour = 24;

% Number of samples, nodes and lines
T = tf_hour - t0_hour;
N = numel(grid.nodal_nominal_power);
L = numel(grid.ampacities);


% ----
% Initialize some variables that will later store some results
% ----
% Voltage and line current magnitudes w. some nominal power injections
Vm = nan(T, N);
Im = nan(T, L);

nodes_with_demand = grid.nodal_nominal_power >0;
to_all_nodes_D = pinv(make_M(nodes_with_demand));
nodal_injections_D_pu=P;

% ------
% Running Load flow Verification
% ------




for t=1:T
    injections_D = to_all_nodes_D* nodal_injections_D_pu(mod(t + t0_hour, 24)+1, :)';
    injections = injections_D;


    
    
    [ V, I, S ] = loadflow_FPIs(grid.Y, 1, injections, 1, ...
        grid.voltageToBranchCurrent_pu);
    
     Vm(t, :) = reshape(abs(V), 1, N);
     Im(t, :) = reshape(abs(I), 1, L);
     

    
end


Im=Im*grid.basecurrent;
ampacities_extended=repmat(grid.ampacities,1,T)';
Im=Im./ampacities_extended;
figure%('Position', [100, 100, 1000, 600]);
% subplot(1,2,1)
plot(Vm)
xlabel('Time (Hour)')
ylabel('Voltage magnitude (pu)')
title('Voltage verification of P_{opt}')
legend( 'V_{verification}')


% subplot(1,2,2)
% plot(Im)
% xlabel('Time (Hour)')
% ylabel('Current magnitude (pu)')
% title('Current verification of P_{opt}')
% legend( 'I_{verification}')
% sgtitle('Optimal Injections Verification')%('Voltage and current verification of P_{opt}')
end