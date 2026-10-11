function loadflow_temporal(grid)


% Load demand (and pv generation) data and sample data at a 1 hour resolution
load('cigre_daily_demand.mat');
demand = halfhour_demand_pu(1:2:end, 2);
clear halfhour_demand_pu;
load('pv_scenarios.mat');

t0_hour =  0;
tf_hour = 24;
% Number of samples, nodes and lines
T = tf_hour - t0_hour;
N = numel(grid.nodal_nominal_power);
L = numel(grid.ampacities);
% Nodes with Demand
nodes_with_demand = grid.nodal_nominal_power > 0;
Nd = sum(nodes_with_demand);

nodal_injections_D = -repmat(demand, 1, Nd) .* ...
    repmat(grid.nodal_nominal_power(nodes_with_demand)', numel(demand), 1);
nodal_injections_D_pu = nodal_injections_D/(grid.basepower/1000);
to_all_nodes_D = pinv(make_M(nodes_with_demand));

nodes_with_PV = grid.nodal_PV_power > 0;
PV = sum(nodes_with_PV);
% % pvgeneration.forecast = repmat(OUT.f, 1, PV);
nodal_injections_PV = repmat(OUT.f, 1, PV) .* repmat(grid.nodal_PV_power(nodes_with_PV)', numel(demand), 1) ;
nodal_injections_PV_pu = nodal_injections_PV/(grid.basepower/1000);
to_all_nodes_PV = pinv(make_M(nodes_with_PV));


for t=1:T
    %t = t_ - t0_hour + 1;
    injections_D = to_all_nodes_D * nodal_injections_D_pu(mod(t + t0_hour, 24)+1, :)';
    injections_PV = to_all_nodes_PV * nodal_injections_PV_pu(mod(t + t0_hour, 24)+1, :)';
    injections_combined = injections_PV +  injections_D; 
    injections = injections_combined; % injections are already negative demand
    [ V, I, S ] = loadflow_FPIs(grid.Y, 1, injections, 1, ...
        grid.voltageToBranchCurrent_pu);

    Vm(t, :) = reshape(abs(V), 1, N);
    Im(t, :) = reshape(abs(I), 1, L);
 
end
Im=Im*grid.basecurrent;
Im = Im ./ repmat(grid.ampacities', T, 1);
% Create a figure with a larger size
figure('Position', [100, 100, 1000, 600]);

subplot(1,2,1)
plot(Vm)
xlabel('Time (Hour)')
ylabel('Voltage magnitude (pu)')
legend('Voltage magnitudes in the network')

subplot(1,2,2)
plot(Im)
xlabel('Time (Hour)')
ylabel('Observed Current*')
legend('Line currents in the network')

end
