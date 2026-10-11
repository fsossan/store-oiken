function gm = linear_grid_model(grid)


% load consumption profile data
historic_load_data =  load('load_consumption_train_new.mat');
X_train = historic_load_data.X_train;
cluser_idx = historic_load_data.cluster_idx;
% load PV profile
load('PV_prof_15mins.mat');
% Number of samples, nodes and lines
[T,~,~] = size(X_train);% 15-minute timestep
% get network features
N = numel(grid.nodal_nominal_power);
L = numel(grid.ampacities);
nodes_with_demand = grid.nodal_nominal_power > 0;
Nd = sum(nodes_with_demand);

% nodal demand
nodal_injections_D = -generate_nodal_scenarios(X_train,cluser_idx,grid.nodal_nominal_power(nodes_with_demand)).';
nodal_injections_D_pu = nodal_injections_D/(grid.basepower/1000);
to_all_nodes_D = pinv(make_M(nodes_with_demand));

% PV generation
nodes_with_PV = grid.nodal_PV_SFOE > 0;
PV = sum(nodes_with_PV);
nodal_injections_PV = repmat(PV_prof', 1, PV) .* repmat(grid.nodal_PV_SFOE(nodes_with_PV)', numel(PV_prof), 1) ;
nodal_injections_PV_pu = nodal_injections_PV/(grid.basepower/1000);
to_all_nodes_PV = pinv(make_M(nodes_with_PV));

% EV charging
nodes_with_EV = grid.nodal_N_EV>0;
EV = sum(nodes_with_EV);
[time_step,nodal_injections_EV,arrival_times] = EV_uncontrolled_profile(EV,15); 
nodal_injections_EV = -1 * nodal_injections_EV;
nodal_injections_EV_pu = nodal_injections_EV/(grid.basepower/1000);
to_all_nodes_EV = pinv(make_M(nodes_with_EV));
%------
% Liner grid models
% ------

% Linearization points (active, reactive, slack voltage)
P0 = {};
Q0 = {};
Vsmag0 = {};
% Sensitivity coefficients for voltage magnitudes, ...
Vmag_dxdP = {};
Vmag_dxdQ = {};
Vmag_dxdVsmag = {};
Vmag0 = {};

% line current magnitudes, and
Imag_dxdP = {};
Imag_dxdQ = {};
Imag_dxdVsmag = {};
Imag0  = {};

%line current complex
I_dxdP = {};
I_dxdQ = {};

% complex power at the slack bus.
Ss_dxdP = {};
Ss_dxdQ = {};
Ss_dxdVsmag = {};
Ss0 = {};

for t=1:T
    %t = t_ - t0_hour + 1;
    injections_D = to_all_nodes_D * nodal_injections_D_pu(t, :).';
    injections_PV = to_all_nodes_PV * nodal_injections_PV_pu(t, :).';
    injections_EV = to_all_nodes_EV * nodal_injections_EV_pu(t, :).';
   
    injections = injections_D+injections_EV+injections_PV; % injections are already negative demand
    % injections are already negative demand
    P0{t} = real(injections);
    Q0{t} = imag(injections);
    Vsmag0{t} = 1;
    [ V, I, S ] = loadflow_FPIs(grid.Y, 1, injections, 1, ...
        grid.voltageToBranchCurrent_pu);

    Vm(t, :) = reshape(abs(V), 1, N);
    Im(t, :) = reshape(abs(I), 1, L);
    Vmag0{t} = Vm(t, :);
    Imag0{t} = Im(t, :);
    Ss0{t} = S;
    % Compute and assign SCs
    [Vmag_dxdP{t}, Vmag_dxdQ{t}, Vmag_dxdVsmag{t}, Ss_dxdP{t}, Ss_dxdQ{t}, Ss_dxdVsmag{t}, Imag_dxdP{t}, Imag_dxdQ{t},I_dxdP{t},I_dxdQ{t}, Imag_dxdVsmag{t}] = ...
        getSCs(grid.Y, [1; injections], [1;V], I, grid.N1N2Y, grid.n_of_phases);

    % Assign working point
    Vmag0{t} = abs(V);
    Imag0{t} = I;
    %Sslack0 = {};
    P0{t} = real(injections);
    Q0{t} = imag(injections);
    Vslackmag0{t} = 1;
    % Create perturbed injections * 1.5
    injections_p = injections +real(injections)*0.5 ; % !! problem with increasing both P and Q ??
    [ Vp, Ip, S_ ] = loadflow_FPIs(grid.Y, 1, injections_p, 1, ...
        grid.voltageToBranchCurrent_pu);

    Vmp(t, :) = reshape(abs(Vp), 1, N);
    Imp(t, :) = reshape(abs(Ip), 1, L);
    Sp(t) = S_;

    Vmag_dxdP{t}(1,:)=[];
    Vmag_dxdQ{t}(1,:)=[];
    Vmag_dxdVsmag{t}(1,:)=[];
    Vabslin = abs(V) + Vmag_dxdP{t} * (real(injections_p) - P0{t}) + Vmag_dxdQ{t} * (imag(injections_p) - Q0{t}+ Vmag_dxdVsmag{t} * (abs(1) - Vsmag0{t})) ;%+ Vmag_dxdVsmag{t} * (abs(1) - Vsmag0{t})
    Sl(t) = S - Ss_dxdP{t} * (real(injections_p) - P0{t}) + Ss_dxdQ{t} * (imag(injections_p) - Q0{t}) + Ss_dxdVsmag{t} * (abs(1) - Vsmag0{t});
    Iabslin = abs(I) + abs(Imag_dxdP{t} * (real(injections_p) - P0{t}))+ real(Imag_dxdQ{t} * abs(imag(injections_p) - Q0{t}));


    Vml(t, :) = reshape(Vabslin, 1, N);
    Iml(t, :) = reshape(Iabslin, 1, L);
end

% Create a figure with a larger size
% figure;
% subplot(1, 2, 1)
% plot(median(Vm,2))
% hold on
% plot(median(Vmp,2))
% plot(median(Vml,2), '--')
% hold off
% xlabel('Time (Hour)')
% ylabel('Voltage magnitude (pu)')
% %title('Injection perturbed by 50 %')
% % Injection perturbed by 0.5%
% legend('Original', 'Ground-truth perturbed by 50%', 'Linear model')
% 
% subplot(1, 2, 2)
% plot(median(Im,2))
% hold on
% plot(median(Imp,2))
% plot(median(Iml,2), '--')
% hold off
% xlabel('Time (Hour)')
% ylabel('current magnitude (pu)')
% legend('Original', 'Ground-truth perturbed by 50%', 'Linear model')
% title="Network "+i+": Linear model";
% sgtitle(title, 'FontSize', 14);

% store data
gm.grid = grid;
gm.to_all_nodes = to_all_nodes_D;

gm.lm.P0 = P0;
gm.lm.Q0 = Q0;
gm.lm.Vsmag0 = Vsmag0;

gm.lm.Vmag_dxdP = Vmag_dxdP;
gm.lm.Vmag_dxdQ = Vmag_dxdQ;
gm.lm.Imag_dxdP = Imag_dxdP;
gm.lm.Imag_dxdQ = Imag_dxdQ;
gm.lm.I_dxdP = I_dxdP;
gm.lm.I_dxdQ = I_dxdQ;
gm.lm.Vmag_dxdVsmag = Vmag_dxdVsmag;
gm.lm.Vmag0 = Vmag0;
gm.lm.Imag0 = Imag0;

gm.lm.Ss_dxdP = Ss_dxdP;
gm.lm.Ss_dxdQ = Ss_dxdQ;
gm.lm.Ss_dxdVsmag = Ss_dxdVsmag;
gm.lm.Ss0 = Ss0;

gm.nodal_injections_D_pu = nodal_injections_D_pu;
%gm.nodal_injections_PV_pu = nodal_injections_PV_pu;
gm.Vs = 1;
gm.to_all_nodes_D = to_all_nodes_D;
gm.to_all_nodes_PV = to_all_nodes_PV;
gm.to_all_nodes_EV = to_all_nodes_EV;
gm.injections_D_pu = nodal_injections_D_pu;
gm.injections_EV_pu = nodal_injections_EV_pu;
gm.injectinos_PV_pu = nodal_injections_PV_pu;



end


