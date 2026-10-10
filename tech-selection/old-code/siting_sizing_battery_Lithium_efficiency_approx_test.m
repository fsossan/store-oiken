
addpath(genpath(pwd))
close all
clear
gridFunc = @grid;
rng(1234); % fix seed for load profile generator
% %% Silence everything
warning('off','all');
set(0, 'DefaultFigureVisible', 'off');
allow_mult_instances = false;
% if ispc
%     diary('NUL');
% else
%     diary('/dev/null');
% end

% load data
load('all_LV_data.mat') % LV data
load('one_shot_lf_network_classification.mat'); % network classification after one-shot lf analysis
config = jsondecode(fileread("general_config.json"));

% PV and EV allocation
scenario = 'sc1_2040';
data_SFOE = allocate_PV_EV_SFOE(data,scenario);
% testing specific network id
network_id_test = 'LV_Grid_92688';
test_idx = find(strcmp(data_SFOE.LV_grid_id,network_id_test));


% run the algorithm only on sane networks
one_shot_sane_ids = network_ids.healthy;
sane_ids_full = "LV_Grid_" + one_shot_sane_ids;
all_ids = string(data_SFOE.LV_grid_id);
is_sane = ismember(all_ids, sane_ids_full);
sane_net_indices = find(is_sane);

% Run this once to generate the index splits
if allow_mult_instances
    n = numel(sane_net_indices);
    splits = round(linspace(0, n, 5));  % 5 edges = 4 chunks
    for k = 1:4
        idx_chunk = sane_net_indices(splits(k)+1 : splits(k+1));
        save(sprintf('output/split_%d.mat', k), 'idx_chunk');
    end
    instance_id = 4; % Change this to 1, 2, 3, or 4 in each MATLAB instance
    load(sprintf('output/split_%d.mat', instance_id), 'idx_chunk');
    sane_net_indices = idx_chunk;
end



% preallocate per-network storage=
failed = false(numel(sane_net_indices),1);

% store networks outside voltage OPF threshold
net_thresh = {};
thres_count = 1;

t_tot = tic; % timing large scale analysis code

% log file
% if allow_mult_instances
%     log_fid = fopen(fullfile(pwd, 'output', sprintf('run_log_%s.txt',string(instance_id))), 'w');
% else
%     log_fid = fopen(fullfile(pwd, 'output', 'run_log_ALL.txt'), 'w');
% end


iter_count = 0;
for  n_idx =  test_idx% sane_net_indices(:).'
    iter_count = iter_count+1;
    % set seed for each LV network
    net_id = string(data_SFOE.LV_grid_id{n_idx});
    net_num = str2double(regexp(net_id, '\d+', 'match','once'));
    rng(1234+net_num); % fix seed for individual LV network

    try
        prepros_tot = tic;
        grid = get_grid_SFOE(data_SFOE,n_idx,config); % grid data
        gm = linear_grid_model(grid); % linearization of the grid model

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
        eta_ch = [0.9];
        eta_dis = [0.9];

        % Upper bounds for Big-M linking (per node, per tech)
        Emax_li  = 1e4; % p.u
        Emax_j = [Emax_li];
        Smax_li  = 1e3; % p.u
        Smax_j = [Smax_li];

        % exact formulation
        cha_dis_bin_activate = false;

        % current cstr
        current_mag_cstr = true;



        dVmagdP = blkdiag(gm.lm.Vmag_dxdP{:}) * AUX_to_all_nodes;
        dVmagdQ = blkdiag(gm.lm.Vmag_dxdQ{:}) * AUX_to_all_nodes;
        dImagdP = blkdiag(gm.lm.Imag_dxdP{:}) * AUX_to_all_nodes;
        dImagdQ = blkdiag(gm.lm.Imag_dxdQ{:}) * AUX_to_all_nodes;
        dIdP = blkdiag(gm.lm.I_dxdP{:}) * AUX_to_all_nodes;
        dIdQ = blkdiag(gm.lm.I_dxdQ{:}) * AUX_to_all_nodes;
        P0 = pinv(AUX_to_all_nodes) * vertcat(gm.lm.P0{:});
        Q0 = pinv(AUX_to_all_nodes) * vertcat(gm.lm.Q0{:});
        Vmag0 = vertcat(gm.lm.Vmag0{:});
        Imag0 = vertcat(gm.lm.Imag0{:});

        dSsdP = blkdiag(gm.lm.Ss_dxdP{:}) * AUX_to_all_nodes;
        dSsdQ = blkdiag(gm.lm.Ss_dxdQ{:}) * AUX_to_all_nodes;
        Ss0 = vertcat(gm.lm.Ss0{:});
        Ss0 = -1*Ss0;
        CABLE_AMPACITIES = gm.grid.ampacities./(gm.grid.basepower/1e3);
        slack_bus_rating_3ph=(623.54+301.99i)/(gm.grid.basepower/1e3);
        slack_bus_rating_1ph =(slack_bus_rating_3ph/3 );
        R_NdT_toTNd = linear_reshape_test(Nd, T);
        R_TNd_toNdT = linear_reshape_test(T, Nd);

        % tolerance for numerical accuracy
        tol = 1e-8;
        Imag0(abs(Imag0)<tol) = 0;
        dImagdP(dImagdP(:)<tol) = 0;
        dImagdQ(dImagdQ(:)<tol) = 0;
        dIdP(abs(dIdP(:))<tol) = 0;
        dIdQ(abs(dIdQ(:))<tol) = 0;


        prepros_time = toc(prepros_tot);

        % voltage threshold for the OPF
        if min(Vmag0) < 0.5 || max(Vmag0)>1.4
            fprintf('Voltage magnitude out of bounds for network %s\n', string(data_SFOE.LV_grid_id{n_idx}));
            thresh_out.gm = gm;
            thresh_out.network_id = string(net_num);
            thresh_out.Vmag0_min = min(Vmag0);
            thresh_out.Vmag0_max = max(Vmag0);
            filename = fullfile('output/OPF_result/out_dir_thresh',string(net_num)+".mat");
            save(filename,'thresh_out');

            % log file

            fprintf(log_fid, 'THRESH  %s  Vmin=%.3f  Vmax=%.3f\n', ...
                thresh_out.network_id, min(Vmag0), max(Vmag0));
            continue;
        end




        fprintf('Running network %d / %d : %s\n', ...
            iter_count, numel(sane_net_indices), string(data_SFOE.LV_grid_id{n_idx}));
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
        variables vmag(N*T)
        variables Psl_plus(T,1) Psl_minus(T,1)

        if current_mag_cstr
            variable  Imag(L*T)
        else
            variable Imag(L*T) complex
        end

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


        if cha_dis_bin_activate
            minimize(costE + costS + costI)
        else
            minimize(costE + costS + costI+sum(0.5*(B_plus+B_minus)))
        end


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
                if cha_dis_bin_activate
                    M_nj = kP * Smax_j(j);
                    B_plus(Idx,j)  <= M_nj * ct(Idx,j);
                    B_minus(Idx,j) <= M_nj * (1 - ct(Idx,j));
                end

                % C-rate
                B_plus(Idx,j) <= c_rate_j(j)*E_nom(n,j);
                B_minus(Idx,j) <= c_rate_j(j)*E_nom(n,j);


            end
        end




        % reactive power limits of the converter
        kPF = tan(acos(0.98));
        for n = 1:Nd
            Idx = (n-1)*T + (1:T);
            for j = 1:J
                % Active power limited by converter ratings
                B_bat(Idx, j)  <=  kP * S_conv(n, j);
                B_bat(Idx, j)  >= -kP * S_conv(n, j);

                % Reactive power limited by converter ratings (inner box)
                Q_ess(Idx, j) <=  kQ * S_conv(n, j);
                Q_ess(Idx, j) >= -kQ * S_conv(n, j);

                % PF approx Cstr (Since B_bat = B_plus - B_minus, and both are >= 0):
                abs(Q_ess(Idx, j)) <= kPF * (B_plus(Idx, j) + B_minus(Idx, j));



            end
        end



        % power balance
        delta_P == -B_bat;
        delta_Q == Q_ess;
        % delta_Q == 0;  % testing converter power rating vs nominal energy capacity

        % grid constraint
        % -- Grid model

        vmag == Vmag0 + dVmagdP * (R_TNd_toNdT*(delta_P))+dVmagdQ * (R_TNd_toNdT*(delta_Q));
        0.9 <= vmag <= 1.1;

        if current_mag_cstr
            Imag == abs(Imag0) + dImagdP * (R_TNd_toNdT*(delta_P))+dImagdQ * (R_TNd_toNdT*(delta_Q));
            Imag./repmat(CABLE_AMPACITIES, T, 1) <= 1;
            Imag./repmat(CABLE_AMPACITIES, T, 1) >= 0;

        else
            Imag == Imag0 + dIdP * (R_TNd_toNdT*(delta_P))+dIdQ * (R_TNd_toNdT*(delta_Q));
            ((real(Imag))+(imag(Imag)))  ./ repmat(CABLE_AMPACITIES, T, 1) <= 1
            ((real(Imag))-(imag(Imag)))  ./ repmat(CABLE_AMPACITIES, T, 1) <= 1
            (-(real(Imag))+(imag(Imag)))  ./ repmat(CABLE_AMPACITIES, T, 1) <= 1
            (-(real(Imag))-(imag(Imag)))  ./ repmat(CABLE_AMPACITIES, T, 1) <= 1
        end
        %
        % % % Slack bus real power constraint
        % real(Ss0)+real(dSsdP)*(R_TNd_toNdT * (delta_P ))+real(dSsdQ)*(R_TNd_toNdT * (delta_Q ))<=real(slack_bus_rating_1ph);
        % imag(Ss0)+imag(dSsdP)*(R_TNd_toNdT * (delta_P ))+imag(dSsdQ)*(R_TNd_toNdT * (delta_Q ))<=imag(slack_bus_rating_1ph);
        KP_tr = 0.95 ;
        kQ_tr = sqrt(1 - KP_tr^2);
        P_sl =  real(Ss0)+real(dSsdP)*(R_TNd_toNdT * (delta_P ))+real(dSsdQ)*(R_TNd_toNdT * (delta_Q ));
        Q_sl =  imag(Ss0)+imag(dSsdP)*(R_TNd_toNdT * (delta_P ))+imag(dSsdQ)*(R_TNd_toNdT * (delta_Q ));
        P_sl <=  KP_tr*abs(slack_bus_rating_1ph);
        P_sl >= -KP_tr*abs(slack_bus_rating_1ph);
        Q_sl <=  kQ_tr*abs(slack_bus_rating_1ph);
        Q_sl >= -kQ_tr*abs(slack_bus_rating_1ph);

        % % Slack bus PF approxi
        % kPF_sl = tan(acos(0.9));
        % abs(Q_sl) <= 0.1*abs(slack_bus_rating_1ph);
        %
        % PF constraint (convex, linear via epigraph)
        kPF_sl = tan(acos(0.9));

        Psl_plus  >= 0;
        Psl_minus >= 0;
        P_sl == Psl_plus - Psl_minus;
        abs(Q_sl) <= kPF_sl * (Psl_plus + Psl_minus);

        cvx_end
        %% testing slackbus cstr + slackbus PF approx
        % S_slack = sqrt(P_sl.^2+Q_sl.^2);
        % PF_sl = P_sl./S_slack;
        % PF_vio =  sum(abs(PF_sl)<0.9)/length(PF_sl);
        % % fprintf('PF violations: %.2f %%\n', PF_vio*100);
        % t_step = 0:15/60:24-15/60;
        % figure
        % plot(t_step,(P_sl)*3*100)
        % hold on
        % plot(t_step,(Q_sl)*3*100)
        % hold on
        % plot(t_step,S_slack*3*100)
        % gridFunc('on')
        % legend('P','Q','S')
        %
        % figure
        % plot(t_step,PF_sl,'x')


        % % check nodal PF cstr
        % B_idx = find(I);
        % P_inj = reshape(delta_P,T,Nd);
        % Q_inj = reshape(delta_Q,T,Nd);
        % PF_inj = (P_inj(:,B_idx))./(sqrt(P_inj(:,B_idx).^2+Q_inj(:,B_idx).^2));
        %
        % figure
        % subplot(3,1,1)
        % plot(t_step,P_inj(:,B_idx)*3*100)
        % legend('delta_P')
        % subplot(3,1,2)
        % plot(t_step,Q_inj(:,B_idx)*3*100)
        % legend('delta_Q')
        % subplot(3,1,3)
        % plot(t_step,PF_inj,'x')






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

        % charging/discharging exclusivity (relaxed formulation)
        B_exc = min(full(B_plus),full(B_minus));
        tol = 1e-6;
        cha_dis_vio        = any(B_exc(:) > tol);
        cha_dis_vio_max    = max(B_exc(:));
        cha_dis_vio_energy = sum(B_exc(:)) * (15/60);
        cha_dis_vio_frac   = sum(B_exc(:)) / ...
            (sum(B_plus(:)) + sum(B_minus(:)) + eps);
        % ===== store per-network result at the END of try =====
        out.network_id = string(data_SFOE.LV_grid_id{n_idx});
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
        % out.cvx_optval = cvx_optval;
        % out.cvx_optband = cvx_optband;
        out.B_bat = B_bat;
        out.B_plus = B_plus;
        out.B_minus = B_minus;
        out.B_exc = B_exc;
        out.cha_dis_vio = cha_dis_vio;
        out.cha_dis_vio_max = cha_dis_vio_max;
        out.cha_dis_vio_energy = cha_dis_vio_energy;
        out.cha_dis_vio_frac = cha_dis_vio_frac;

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
        out.prepros_time_s = prepros_time;
        out.Sl_P = P_sl;
        out.Sl_Q = Q_sl;
        out.S_lf = S_lf;
        filename = fullfile('output/OPF_result/out_dir_solved',string(net_num)+".mat");
        save(filename,'out');

        % log file
        % fprintf(log_fid, 'SOLVED  %s  status=%s  E=%.4f  S=%.4f  t=%.1fs\n', ...
        %     string(net_num), cvx_status, sum(E_nom(:)), sum(S_conv(:)), toc);

        cvx_clear;
    catch ME
        failed(n_idx) = true;
        fprintf(2, "FAILED %s: %s\n", string(data_SFOE.LV_grid_id{n_idx}), ME.message);
        fail_out.network_id = string(net_num);
        fail_out.error_msg  = ME.message;
        fail_out.error_id   = ME.identifier;
        filename = fullfile('output/OPF_result/out_dir_error',string(net_num)+".mat");
        save(filename,'fail_out');

        % % log file
        fprintf(log_fid, 'FAILED  %s  %s\n', fail_out.network_id, ME.message);

        cvx_clear;

        continue
    end
end

% save log file
% fclose(log_fid);

total_time = toc(t_tot);
