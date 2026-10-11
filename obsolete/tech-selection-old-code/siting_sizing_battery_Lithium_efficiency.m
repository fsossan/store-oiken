
addpath('./grid');
addpath('./util');
addpath('./Sierre_data');
close all
clear
gridFunc = @grid;
rng(1234); % fix seed for load profile generator
% %% Silence everything
warning('off','all');
set(0, 'DefaultFigureVisible', 'off');
% if ispc
%     diary('NUL');
% else
%     diary('/dev/null');
% end

% load Sierre data
load('Sierre_v2.mat')
% load sane network IDs
load('Sierre_sane_networks.mat');

% PV and EV allocation
Sierre_2 = PV_EV_allocation_SFOE_based(Sierre);
% testing specific network id
network_id_test = 'LV_Grid_92710';
test_idx = find(strcmp(Sierre.LV_grid_id,network_id_test));


% run the algorithm only on sane networks
sane_ids_full = "LV_Grid_" + Sierre_sane_idx;
all_ids = string(Sierre.LV_grid_id);
is_sane = ismember(all_ids, sane_ids_full);
sane_net_indices = find(is_sane);


% preallocate per-network storage
res = cell(numel(sane_net_indices),1);
res_count = 1;
failed = false(numel(sane_net_indices),1);

% store networks outside voltage OPF threshold
net_thresh = {};
thres_count = 1;

t_tot = tic; % timing large scale analysis code


for  n_idx = test_idx %sane_net_indices(:).'
    % try

    grid = get_OIKEN_grid_Sierre(Sierre_2.MV_LV_sub{n_idx},Sierre_2.LV_grid{n_idx}); % grid data
    gm = linear_grid_model_Sierre(grid); % linearization of the grid model

    % Number of nodes, of nodes with demand, of lines, of time samples
    [N, Nd] = size(gm.to_all_nodes);
    [L] = size(gm.grid.ampacities, 1);
    T = size(gm.nodal_injections_D_pu, 1);
    % Nodes with Demand
    nodes_with_demand = gm.grid.nodal_nominal_power > 0;
    Nd = sum(nodes_with_demand);
    to_all_nodes_D = pinv(make_M(nodes_with_demand));
    AUX_to_all_nodes = repeat_block_diag(to_all_nodes_D, T);
    activate_relinearization = true;


    %% === TECHNOLOGY SET ===
    % J techs: 1 = Li-ion, 2 = Na-ion, 3 = Power-to-X-to-Power
    tech_names = {'LiIon'};
    J = numel(tech_names);

    % Costs (€/kWh, €/kVA, € fixed)  -> put YOUR numbers here
    Enom_cost_li  = 300/(gm.grid.basepower/1000);
    Snom_cost_li  = 100/(gm.grid.basepower/1000);
    inst_cost_li  = 2000/(gm.grid.basepower/1000);

    % Per-tech vectors (costs)
    cE  = [Enom_cost_li];       % energy cost
    cS  = [Snom_cost_li];
    cI  = [inst_cost_li];       % installation cost



    % Optional reactive headroom fraction per tech (legacy; will be replaced by k_Q)
    q_frac_j = [0.1];
    c_rate_j = [1.1];

    % charging/discharging efficiency
    eta_ch = [1];
    eta_dis = [1];



    % Upper bounds for Big-M linking (per node, per tech)
    % Upper bounds for Big-M linking (per node, per tech)
    Emax_li  = 1e4; % p.u
    Emax_j = [Emax_li];
    Smax_li  = 1e3; % p.u
    Smax_j = [Smax_li];



    dVmagdP = blkdiag(gm.lm.Vmag_dxdP{:}) * AUX_to_all_nodes;
    dVmagdQ = blkdiag(gm.lm.Vmag_dxdQ{:}) * AUX_to_all_nodes;
    dImagdP = blkdiag(gm.lm.Imag_dxdP{:}) * AUX_to_all_nodes;
    dImagdQ = blkdiag(gm.lm.Imag_dxdQ{:}) * AUX_to_all_nodes;
    P0 = pinv(AUX_to_all_nodes) * vertcat(gm.lm.P0{:});
    Q0=pinv(AUX_to_all_nodes) * vertcat(gm.lm.Q0{:});
    Vmag0 = vertcat(gm.lm.Vmag0{:});
    Imag0 = vertcat(gm.lm.Imag0{:});

    dSsdP = blkdiag(gm.lm.Ss_dxdP{:}) * AUX_to_all_nodes;
    dSsdQ = blkdiag(gm.lm.Ss_dxdQ{:}) * AUX_to_all_nodes;
    Ss0 = vertcat(gm.lm.Ss0{:});
    Ss0 = -1*Ss0;
    CABLE_AMPACITIES = gm.grid.ampacities;
    slack_bus_rating_3ph=(623.54+301.99i)/(gm.grid.basepower/1e3);
    slack_bus_rating_1ph =(slack_bus_rating_3ph/3 );
    R_NdT_toTNd = linear_reshape_test(Nd, T);
    R_TNd_toNdT = linear_reshape_test(T, Nd);

    % voltage threshold for the OPF
    if min(Vmag0) < 0.8 || max(Vmag0)>1.2
        fprintf('Voltage magnitude out of bounds for network %s\n', string(Sierre.LV_grid_id{n_idx}));
        thresh_out.gm = gm;
        thresh_out.network_id = string(Sierre.LV_grid_id{n_idx});
        thresh_out.Vmag0_min = min(Vmag0);
        thresh_out.Vmag0_max = max(Vmag0);
        net_thresh{thres_count} = thresh_out;
        thres_count = thres_count+1;
        continue;
    end




    fprintf('Running network %d / %d : %s\n', ...
        n_idx, numel(sane_net_indices), string(Sierre.LV_grid_id{n_idx}));
    %% cvx model
    tic
    cvx_solver gurobi
    % cvx_solver_settings('TimeLimit',1800,'gurobi.OutputFlag', 1)
    cvx_begin 

    % -- variables
    variables  B_bat(T*Nd,J) B_plus(T*Nd,J) B_minus(T*Nd,J);
    variable   ct(Nd*T,J) binary
    variable  Q_ess(T*Nd,J);   % new: per-tech reactive power
    variables  E_nom(Nd,J) S_conv(Nd,J) SOE_0(Nd,J);
    variable   I(Nd,J)  binary;
    variables delta_P(T*Nd) delta_Q(T*Nd)
    variables vmag(N*T) Imag(L*T)
    subject to:


    E_nom   >= 0;
    S_conv  >= 0;
    B_plus  >= 0;
    B_minus >= 0;
    SOE_0   >= 0;

    % -- cost function
    % costE = sum(sum(E_nom .* repmat(cE, Nd, 1)));
    % costS = sum(sum(S_conv .* repmat(cS, Nd, 1)));
    % costI = sum(sum(I     .* repmat(cI, Nd, 1)));
    costE = (sum(E_nom * cE));
    costI = (sum(I * cI));
    costS = (sum(S_conv *cS));

    minimize(costE + costS + costI)

    for j = 1:J
        E_nom(:, j)        <= Emax_j(j) * I(:, j);
        S_conv(:, j)       <= Smax_j(j) * I(:, j);

    end

    % Converter capability (box approximation)
    kP = 0.98;
    kQ = sqrt(1 - kP^2);   % ensure kP^2 + kQ^2 <= 1
    % SOE evolution
    B_bat == B_plus - B_minus;
    for n = 1:Nd
        Idx = (n-1)*T+(1:T);
        for j = 1:J
            Ts = 15/60;
            SOE = SOE_0(n,j) + Ts*(eta_ch(j)*cumsum(B_plus(Idx,j)) ...
                - 1/eta_dis(j)*cumsum(B_minus(Idx,j)));
            SOE(end) == SOE(1)
            0 <= SOE <= E_nom(n,j);


            % exclusivity (tight M)
            M_nj = kP * Smax_j(j);
            B_plus(Idx,j)  <= M_nj * ct(Idx,j);
            B_minus(Idx,j) <= M_nj * (1 - ct(Idx,j));

            % C-rate
            B_plus(Idx,j) <= c_rate_j(j)*E_nom(n,j);
            B_minus(Idx,j) <= c_rate_j(j)*E_nom(n,j);


        end
    end




    % reactive power limits of the converter
    for n = 1:Nd
        Idx = (n-1)*T + (1:T);
        for j = 1:J
            % Active power limited by converter ratings
            B_plus(Idx, j)  <= kP * S_conv(n, j);
            B_minus(Idx, j) <= kP * S_conv(n, j);

            % Reactive power limited by converter ratings (inner box)
            Q_ess(Idx, j) <=  kQ * S_conv(n, j);
            Q_ess(Idx, j) >= -kQ * S_conv(n, j);
        end
    end
    % power balance
    delta_P == -B_bat;
    delta_Q == Q_ess;
    delta_Q == 0;  % testing converter power rating vs nominal energy capacity
    % grid constraint
    % -- Grid model
    vmag == Vmag0 + dVmagdP * (R_TNd_toNdT*(delta_P))+dVmagdQ * (R_TNd_toNdT*(delta_Q));
    0.90 <= vmag <= 1.05;
    Imag == Imag0 + dImagdP * (R_TNd_toNdT*(delta_P))+dImagdQ * (R_TNd_toNdT*(delta_Q));
    %
    % Imag*gm.grid.basecurrent./repmat(CABLE_AMPACITIES, T, 1) <= 1;
    % Imag*gm.grid.basecurrent./repmat(CABLE_AMPACITIES, T, 1) >= -1;
    %
    % % % Slack bus real power constraint
    % real(Ss0)+real(dSsdP)*(R_TNd_toNdT * (delta_P ))+real(dSsdQ)*(R_TNd_toNdT * (delta_Q ))<=real(slack_bus_rating_1ph);
    % imag(Ss0)+imag(dSsdP)*(R_TNd_toNdT * (delta_P ))+imag(dSsdQ)*(R_TNd_toNdT * (delta_Q ))<=imag(slack_bus_rating_1ph);

    cvx_end
    toc
    %% sanity-check of the algorith
    %% SOE and Energy throughput

    C_rate_store = zeros(Nd, J);

    B = full(B_bat);      % T*Nd × J
    E = full(E_nom);      % Nd × J

    for n = 1:Nd
        Idx = (n-1)*T + (1:T);
        for j = 1:J
            En = E(n,j);
            if En > 1e-9          % installed / nonzero energy
                C_rate_store(n,j) = max(abs(B(Idx,j))) / En;
            else
                C_rate_store(n,j) = 0;   % or NaN, your choice
            end
        end
    end
    %% Post processing (power injections: delta_P & delta_Q)
    delta_P = R_TNd_toNdT*delta_P;
    delta_Q = R_TNd_toNdT*delta_Q;
    delta_P = reshape(delta_P, Nd, T);
    delta_Q = reshape(delta_Q, Nd, T);
    Q0 = reshape(Q0, Nd, T);
    P0 = reshape(P0, Nd, T);

    % % load flow verification
    % P_opf_injections=complex(P0+delta_P,Q0+delta_Q);
    % [I_lf,V_lf,S_lf] = OPF_verification(P_opf_injections',gm.grid);

    %%
    %PF check
    PF_check = abs(delta_P)./(sqrt(delta_P.^2+delta_Q.^2));
    % load flow verification
    P_opf_injections=complex(P0+delta_P,Q0+delta_Q);
    [I_lf,V_lf,S_lf] = OPF_verification(P_opf_injections.',gm.grid);

    %% === TEMPORARILY ENABLE OUTPUT ===
    % diary off;                      % restore printing
    % warning('on','all');
    % set(0, 'DefaultFigureVisible', 'off');   % show figures if any
    %
    % fprintf('Iteration %d:\n ',counter);
    % % analyze_CDF(vmag, V_lf, Imag, I_lf);
    % %% === MUTE AGAIN ===
    % warning('off','all');
    % set(0, 'DefaultFigureVisible', 'off');
    % if ispc
    %     diary('NUL');
    % else
    %     diary('/dev/null');
    % end
    %

    if max(abs(vmag-V_lf))<1e-3% 0.1%
        fprintf('linearized model voltage error normal: < 10^-3 p.u. max error %.3e pu\n ',max(abs(vmag-V_lf)));
        activate_relinearization = false;
    else
        fprintf('linearized model voltage error too large: < 10^-3 p.u. max error %.3e pu\n ',max(abs(vmag-V_lf)));

        activate_relinearization = false; % correct later for sequential linearization
    end
    % ===== store per-network result at the END of try =====
    out.network_id = string(Sierre.LV_grid_id{n_idx});
    out.E_nom_total_pu = sum(E_nom(:));
    out.S_conv_total_pu = sum(S_conv(:));
    out.E_nom_node_pu = E_nom;     % optional: keep per-node
    out.S_conv_node_pu = S_conv;   % optional: keep per-node
    out.nodal_volt_error = max(abs(vmag-V_lf));
    out.Imag_lin = Imag;
    out.line_current_error = max(abs(Imag - I_lf));
    out.Vmag0_min = min(Vmag0);
    out.Vmag0_max = max(Vmag0);
    out.cvx_optval = cvx_optval;
    out.cvx_status = cvx_status;
    out.B_bat = B_bat;

    out.Installation = I;
    out.delta_P = delta_P;
    out.delta_Q = delta_Q;
    out.Q_ess   = Q_ess;
    out.vmag_lin = vmag;     % N*T vector
    out.V_lf     = V_lf;     % N*T or N×T depending on OPF_verification output
    out.I_lf     = I_lf;
    out.gm = gm;
    out.N = N;
    out.Nd = Nd;
    out.C_rate = C_rate_store;
    out.C_rate_max = max(C_rate_store, [], 'all');          % optional summary
    out.C_rate_node_max = max(C_rate_store, [], 2);         % max over tech per node
    out.solve_time_s = toc;
    res{res_count} = out;
    res_count = res_count + 1;


    % catch ME
    %     failed(n_idx) = true;
    %     fprintf(2, "FAILED %s: %s\n", string(Sierre.LV_grid_id{n_idx}), ME.message);
    % 
    %     continue
    % end
end
total_time = toc(t_tot);

% filename = 'Sierre_Lithium_result.mat';
% save(filename,'res');
filename = fullfile(pwd,'Sierre_Lithium_result_SAFE_v4.mat');
mf = matfile(filename,'Writable',true);
mf.res = res;
mf2 = matfile('Sierre_net_thresh_SAFE_v4.mat','Writable',true);
mf2.net_thresh = net_thresh;
