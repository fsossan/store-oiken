

addpath(genpath(pwd))
close all
clear

% -------------------------------------------------------------------------
%  CONFIG
% -------------------------------------------------------------------------
gridFunc             = @grid;
rng(1234);
warning('on','all');
set(0, 'DefaultFigureVisible', 'on');

% Multi-instance splitting (set true when running 4 parallel MATLAB sessions)
allow_mult_instances = false;

% Sequential linearization settings
MAX_LIN_ITER      = 20;
VOLT_CONV_THRESH  = 1e-3;   % pu — early-exit convergence criterion
alpha             = 0.6;    % Re-linearization weight
enable_plots_iter = false;  % flag to enable plots in each iteration for diagnosis

% Technology (single-tech; extend vectors for multi-tech)
tech_names = {'LiIon'};
J          = numel(tech_names);

% BESS parameters
c_rate_j = [1.1];
eta_ch   = [0.9];
eta_dis  = [0.9];
Emax_j   = [1e4];   % pu upper bound for Big-M
Smax_j   = [1e3];   % pu upper bound for Big-M

% Converter PQ box
kP      = 0.98;
kQ_conv = sqrt(1 - kP^2);
kPF     = tan(acos(0.98));

% Transformer / slack bus box + PF approximation
kP_tr   = 0.95;
kQ_tr   = sqrt(1 - kP_tr^2);
kPF_sl  = tan(acos(0.9));

% Slack bus rating (physical kVA, converted to pu inside loop)
slack_bus_rating_3ph_phys = 623.54 + 301.99i;

% Voltage guard thresholds (skip degenerate linearisation points)
VMAG_LB = 0.001;
VMAG_UB = 200;

% Charge/discharge binary exclusivity (false = relaxed + penalty term)
cha_dis_bin_activate = false;

% Current magnitude constraint (true = |I|, false = complex box)
current_mag_cstr = true;

% -------------------------------------------------------------------------
%  LOAD DATA
% -------------------------------------------------------------------------
load('all_LV_data.mat');
load('temporal_stats.mat');
config   = jsondecode(fileread("general_config.json"));
scenario = 'sc1_2040';

data_SFOE = allocate_PV_EV_SFOE(data, scenario);

% Select networks that need reinforcement (violations from temporal LF)
temporal_violation_ids = stats.network_ids.violations;
all_ids          = string(data_SFOE.LV_grid_id);
is_sane          = ismember(all_ids, temporal_violation_ids);
sane_net_indices = find(is_sane);

% -------------------------------------------------------------------------
%  MULTI-INSTANCE INDEX SPLITTING
% -------------------------------------------------------------------------
if allow_mult_instances
    n      = numel(sane_net_indices);
    splits = round(linspace(0, n, 5));   % 4 chunks
    for k  = 1:4
        idx_chunk = sane_net_indices(splits(k)+1 : splits(k+1));
        save(sprintf('output/split_%d.mat', k), 'idx_chunk');
    end
    instance_id      = 4;                % <- change per MATLAB instance (1-4)
    load(sprintf('output/split_%d.mat', instance_id), 'idx_chunk');
    sane_net_indices = idx_chunk;
end

% -------------------------------------------------------------------------
%  LOG FILE
% -------------------------------------------------------------------------
if allow_mult_instances
    log_fname = fullfile(pwd, 'output', sprintf('run_log_%d.txt', instance_id));
else
    log_fname = fullfile(pwd, 'output', 'run_log_ALL.txt');
end
log_fid = fopen(log_fname, 'w');

% -------------------------------------------------------------------------
%  MAIN LOOP
% -------------------------------------------------------------------------
t_tot      = tic;
iter_count = 0;


% testing specific network id
network_id_test = ["LV_Grid_536"]; %;["LV_Grid_182";"LV_Grid_536"];
test_idx = find(ismember(data_SFOE.LV_grid_id,network_id_test));

for n_idx = test_idx%sane_net_indices(:).'
    iter_count = iter_count + 1;

    net_id  = string(data_SFOE.LV_grid_id{n_idx});
    net_num = str2double(regexp(net_id, '\d+', 'match', 'once'));
    rng(1234 + net_num);

    fprintf('Running network %d / %d : %s\n', ...
        iter_count, numel(sane_net_indices), net_id);

    % try
    t_prepros = tic;

    % -----------------------------------------------------------------
    %  PREPROCESSING — grid model and dimension extraction
    % -----------------------------------------------------------------
    grid_data = get_grid_SFOE(data_SFOE, n_idx, config);
    gm        = linear_grid_model(grid_data);

    [N, ~] = size(gm.to_all_nodes);
    L      = size(gm.grid.ampacities, 1);
    T      = size(gm.nodal_injections_D_pu, 1);

    nodes_with_demand = gm.grid.nodal_nominal_power > 0;
    Nd                = sum(nodes_with_demand);
    to_all_nodes_D    = pinv(make_M(nodes_with_demand));
    AUX_to_all_nodes  = repeat_block_diag(to_all_nodes_D, T);
    R_TNd_toNdT       = linear_reshape_test(T, Nd);

    % pu-scaled cost coefficients
    bp = gm.grid.basepower / 1000;   % kW base
    cE = 300  / bp;
    cS = 100  / bp;
    cI = 2000 / bp;

    slack_pu  = (slack_bus_rating_3ph_phys / 3) / (gm.grid.basepower / 1e3);
    CABLE_AMP = gm.grid.ampacities ./ (gm.grid.basepower / 1e3);

    prepros_time = toc(t_prepros);

    % -----------------------------------------------------------------
    %  VOLTAGE GUARD — skip degenerate networks
    % -----------------------------------------------------------------
    Vmag0_init = vertcat(gm.lm.Vmag0{:});
    if min(Vmag0_init) < VMAG_LB || max(Vmag0_init) > VMAG_UB
        fprintf('  [THRESH] Voltage out of bounds (%.3f - %.3f pu), skipping.\n', ...
            min(Vmag0_init), max(Vmag0_init));

        thresh_out.network_id = string(net_num);
        thresh_out.Vmag0_min  = min(Vmag0_init);
        thresh_out.Vmag0_max  = max(Vmag0_init);

        fname = fullfile('output/OPF_result/out_dir_thresh', string(net_num) + ".mat");
        save(fname, 'thresh_out');

        fprintf(log_fid, 'THRESH  %s  Vmin=%.4f  Vmax=%.4f\n', ...
            string(net_num), min(Vmag0_init), max(Vmag0_init));
        continue
    end

    % -----------------------------------------------------------------
    %  SEQUENTIAL LINEARIZATION LOOP
    % -----------------------------------------------------------------
    Ts = 15/60;   % time step (hours)

    % Warm-start: zero BESS injections on first iteration
    B_plus_prev  = zeros(T * Nd, J);
    B_minus_prev = zeros(T * Nd, J);
    Q_ess_prev   = zeros(T * Nd, J);
    dP_mat_prev = zeros(Nd,T);
    dQ_mat_prev = zeros(Nd,T);

    % Per-iteration bookkeeping
    iter_volt_error = nan(MAX_LIN_ITER, 1);
    iter_curr_error = nan(MAX_LIN_ITER, 1);
    iter_cost       = nan(MAX_LIN_ITER, 1);
    iter_status     = cell(MAX_LIN_ITER, 1);
    iter_solve_time = nan(MAX_LIN_ITER, 1);

    % Save criterion: iteration with minimum voltage (linearization) error
    best_iter     = 0;
    best_volt_err = Inf;
    % Also track minimum-cost iteration for cross-reference in summary
    best_cost_iter = 0;
    best_cost      = Inf;
    best_out       = [];   % will hold the best full result struct

    gm_orig = gm;          % original gm (saved in output unchanged)
    gm_curr = gm;          % gm updated by re_linearization each iteration

    dispatch_log = struct();
    for lin_iter = 1:MAX_LIN_ITER

        % -- Build sensitivity matrices from current operating point --
        dVmagdP = blkdiag(gm_curr.lm.Vmag_dxdP{:}) * AUX_to_all_nodes;
        dVmagdQ = blkdiag(gm_curr.lm.Vmag_dxdQ{:}) * AUX_to_all_nodes;
        dImagdP = blkdiag(gm_curr.lm.Imag_dxdP{:}) * AUX_to_all_nodes;
        dImagdQ = blkdiag(gm_curr.lm.Imag_dxdQ{:}) * AUX_to_all_nodes;
        dIdP    = blkdiag(gm_curr.lm.I_dxdP{:})    * AUX_to_all_nodes;
        dIdQ    = blkdiag(gm_curr.lm.I_dxdQ{:})    * AUX_to_all_nodes;
        dSsdP   = blkdiag(gm_curr.lm.Ss_dxdP{:})   * AUX_to_all_nodes;
        dSsdQ   = blkdiag(gm_curr.lm.Ss_dxdQ{:})   * AUX_to_all_nodes;

        P0    = pinv(AUX_to_all_nodes) * vertcat(gm_curr.lm.P0{:});
        Q0    = pinv(AUX_to_all_nodes) * vertcat(gm_curr.lm.Q0{:});
        Vmag0 = vertcat(gm_curr.lm.Vmag0{:});
        Imag0 = vertcat(gm_curr.lm.Imag0{:});
        Ss0   = -1 * vertcat(gm_curr.lm.Ss0{:});

        % Numerical clean-up of small entries
        tol_num = 1e-8;
        Imag0(abs(Imag0) < tol_num)     = 0;
        dImagdP(abs(dImagdP) < tol_num) = 0;
        dImagdQ(abs(dImagdQ) < tol_num) = 0;
        dIdP(abs(dIdP) < tol_num)       = 0;
        dIdQ(abs(dIdQ) < tol_num)       = 0;

        % -----------------------------------------------------------------
        %  CVX SOLVE
        % -----------------------------------------------------------------
        t_solve = tic;
        cvx_solver gurobi_4
        cvx_begin quiet

        % Grid variables
        variables delta_P(T*Nd)   delta_Q(T*Nd)
        variables vmag(N*T)
        variables Psl_plus(T,1)   Psl_minus(T,1)

        if current_mag_cstr
            variable Imag(L*T)
        else
            variable Imag(L*T) complex
        end

        % BESS variables (incremental around warm-start point)
        variables dB_plus(T*Nd, J)   dB_minus(T*Nd, J)
        variables B_plus(T*Nd,  J)   B_minus(T*Nd, J)
        variables Q_ess(T*Nd, J) dQ_ess(T*Nd, J)
        variables E_nom(Nd, J)        S_conv(Nd, J)
        variables SOE_0(Nd, J)
        variable  I(Nd, J) binary

        subject to

        % --- Nonnegativity ---
        E_nom    >= 0;
        S_conv   >= 0;
        SOE_0    >= 0;
        Psl_plus  >= 0;
        Psl_minus >= 0;
        B_plus_prev + dB_plus   >= 0;
        B_minus_prev + dB_minus >= 0;

        % --- Incremental linkage to warm-start ---
        B_plus  == B_plus_prev  + dB_plus;
        B_minus == B_minus_prev + dB_minus;

        % --- Big-M installation linking ---
        for j = 1:J
            E_nom(:, j)  <= Emax_j(j);% * I(:, j);
            S_conv(:, j) <= Smax_j(j);% * I(:, j);
        end

        % --- Objective ---
        costE = sum(E_nom * cE);
        costS = sum(S_conv * cS);
        costI = sum(I * cI);

        if cha_dis_bin_activate
            variable ct(Nd*T, J) binary
            minimize(costE + costS + costI)
        else
            minimize(costE + costS  + sum(0.5*(B_plus + B_minus))) %+ costI
        end

        % --- SOE evolution (cyclic) ---
        for n = 1:Nd
            Idx = (n-1)*T + (1:T);
            for j = 1:J
                SOE = SOE_0(n,j) + Ts * ( eta_ch(j)      * cumsum(B_plus(Idx,j)) ...
                    - (1/eta_dis(j)) * cumsum(B_minus(Idx,j)) );
                SOE(end) == SOE_0(n,j);     % cyclic SoE
                0 <= SOE <= E_nom(n,j);

                if cha_dis_bin_activate
                    M_nj = kP * Smax_j(j);
                    B_plus(Idx,j)  <= M_nj * ct(Idx,j);
                    B_minus(Idx,j) <= M_nj * (1 - ct(Idx,j));
                end

                % C-rate constraint
                B_plus(Idx,j)  <= c_rate_j(j) * E_nom(n,j);
                B_minus(Idx,j) <= c_rate_j(j) * E_nom(n,j);
            end
        end

        % --- Converter PQ box approximation ---
        B_bat_var = B_plus - B_minus;
        Q_ess == Q_ess_prev + dQ_ess;
        % Q_ess == 0 ;
        for n = 1:Nd
            Idx = (n-1)*T + (1:T);
            for j = 1:J
                B_bat_var(Idx,j) <=  kP      * S_conv(n,j);
                B_bat_var(Idx,j) >= -kP      * S_conv(n,j);
                Q_ess(Idx,j)     <=  kQ_conv * S_conv(n,j);
                Q_ess(Idx,j)     >= -kQ_conv * S_conv(n,j);
                abs(Q_ess(Idx,j)) <= kPF * (B_plus(Idx,j) + B_minus(Idx,j));
            end
        end

        % --- Power balance ---
        B_bat_net =   sum(B_plus - B_minus, 2); % Net BESS dispatch
        delta_P   == -(dB_plus-dB_minus);       % Incremental in P: change in BESS active dispatch
        delta_Q   ==  sum(dQ_ess, 2);           % Incremental in Q: change in BESS reactive dispatch
        % delta_Q == 0;

        % --- Voltage constraint ---
        vmag == Vmag0 + dVmagdP * (R_TNd_toNdT * delta_P) ...
            + dVmagdQ * (R_TNd_toNdT * delta_Q);
        0.9 <= vmag <= 1.1;

        % --- Current constraint ---
        if current_mag_cstr
            Imag == abs(Imag0) ...
                + dImagdP * (R_TNd_toNdT * delta_P) ...
                + dImagdQ * (R_TNd_toNdT * delta_Q);
            Imag ./ repmat(CABLE_AMP, T, 1) <= 1;
            Imag ./ repmat(CABLE_AMP, T, 1) >= 0;
        else
            Imag == Imag0 ...
                + dIdP * (R_TNd_toNdT * delta_P) ...
                + dIdQ * (R_TNd_toNdT * delta_Q);
            ( real(Imag) + imag(Imag)) ./ repmat(CABLE_AMP, T, 1) <= 1;
            ( real(Imag) - imag(Imag)) ./ repmat(CABLE_AMP, T, 1) <= 1;
            (-real(Imag) + imag(Imag)) ./ repmat(CABLE_AMP, T, 1) <= 1;
            (-real(Imag) - imag(Imag)) ./ repmat(CABLE_AMP, T, 1) <= 1;
        end

        % --- Slack bus: box constraint + PF approximation ---
        P_sl = real(Ss0) + real(dSsdP) * (R_TNd_toNdT * delta_P) ...
            + real(dSsdQ) * (R_TNd_toNdT * delta_Q);
        Q_sl = imag(Ss0) + imag(dSsdP) * (R_TNd_toNdT * delta_P) ...
            + imag(dSsdQ) * (R_TNd_toNdT * delta_Q);

        % P_sl <=  kP_tr * abs(slack_pu);
        % P_sl >= -kP_tr * abs(slack_pu);
        % Q_sl <=  kQ_tr * abs(slack_pu);
        % Q_sl >= -kQ_tr * abs(slack_pu);
        %
        % P_sl == Psl_plus - Psl_minus;
        % abs(Q_sl) <= kPF_sl * (Psl_plus + Psl_minus);

        cvx_end
        iter_solve_time(lin_iter) = toc(t_solve);

        % -------------------- CVX END --------------------------------- %
        % ---------------------------------------------------------------%

        % testing Q_bess
        fprintf('  Q_ess stats: max=%.4f  mean=%.4f  nonzero_frac=%.2f\n', ...
            max(abs(full(Q_ess(:)))), ...
            mean(abs(full(Q_ess(:)))), ...
            mean(abs(full(Q_ess(:))) > 1e-6));
        % After the loop, compare B_plus/B_minus profiles between the two cases
        % Are they scheduling differently in time, or just sized differently?
        fprintf('B_plus  max=%.4f  mean=%.4f\n', max(full(B_plus(:))), mean(full(B_plus(:))));
        fprintf('B_minus max=%.4f  mean=%.4f\n', max(full(B_minus(:))), mean(full(B_minus(:))));
        % -- Check CVX status — abort linearization if infeasible -----
        if ~strcmp(cvx_status, 'Solved') && ~strcmp(cvx_status, 'Inaccurate/Solved')
            fprintf('  [iter %d] CVX status: %s — stopping linearization.\n', ...
                lin_iter, cvx_status);
            iter_status{lin_iter} = cvx_status;
            cvx_clear;
            break % exit inner loop
        end
        iter_status{lin_iter} = cvx_status;

        % -- Load-flow verification -----------------------------------
        dP_mat = reshape(R_TNd_toNdT * delta_P, Nd, T);
        dQ_mat = reshape(R_TNd_toNdT * delta_Q, Nd, T);
        P0_mat = reshape(P0, Nd, T);
        Q0_mat = reshape(Q0, Nd, T);
        P_inj  = complex(P0_mat + dP_mat, Q0_mat + dQ_mat);

        [I_lf, V_lf, S_lf] = OPF_verification(P_inj.', gm_curr.grid);

        v_err = max(abs(vmag - V_lf));
        i_err = max(abs(Imag - I_lf));
        iter_volt_error(lin_iter) = v_err;
        iter_curr_error(lin_iter) = i_err;
        iter_cost(lin_iter)       = cvx_optval;

        %% sizing diagonstics
        if enable_plots_iter
            run build_relin_diagnostic.m
        end
        % testing sequential inearization
        % C-rate
        B_full_iter = full(B_plus - B_minus);
        E_full_iter = full(E_nom);
        C_rate_iter = zeros(Nd, J);
        I_full_iter = full(I);
        for n = 1:Nd
            Idx = (n-1)*T + (1:T);
            for j = 1:J
                if I_full_iter(n,j) > 1e-4
                    En = E_full_iter(n,j);
                    if En > 1e-9
                        C_rate_iter(n,j) = max(abs(B_full_iter(Idx,j))) / En;
                    end
                end
            end
        end

        % Power factor
        P_mag = max(abs(full(B_plus(:) - B_minus(:))));
        Q_mag = max(abs(full(Q_ess(:))));
        if (P_mag^2 + Q_mag^2) > 1e-12
            PF_iter = P_mag / sqrt(P_mag^2 + Q_mag^2);
        else
            PF_iter = 1;
        end

        dispatch_log.C_rate_max(lin_iter) = max(C_rate_iter(:));
        dispatch_log.PF_min(lin_iter)     = PF_iter;
        dispatch_log.B_plus_max(lin_iter)      = max(full(B_plus(:)));
        dispatch_log.B_minus_max(lin_iter)     = max(full(B_minus(:)));
        dispatch_log.Q_ess_max(lin_iter)       = max(abs(full(Q_ess(:))));
        dispatch_log.Q_nonzero_frac(lin_iter)  = mean(abs(full(Q_ess(:))) > 1e-6);

        dispatch_log.E_nom_total(lin_iter)     = sum(E_nom(:)) * 100 * 3;
        dispatch_log.S_conv_total(lin_iter)    = sum(S_conv(:)) * 100 * 3;
        dispatch_log.volt_err(lin_iter)        = v_err;
        dispatch_log.curr_err(lin_iter)        = i_err;
        dispatch_log.cost(lin_iter)            = cvx_optval;
        dispatch_log.num_batt(lin_iter)        = sum(I>1e-4);
        dispatch_log.solve_time(lin_iter)      = iter_solve_time(lin_iter);

        %%
        fprintf('  [iter %d/%d] E=%.2fkWh  S=%.2fkVA N_batt=%d volt_err=%.4e  curr_err=%.4e  cost=%.4f  t=%.1fs  status=%s\n', ...
            lin_iter, MAX_LIN_ITER, ...
            sum(E_nom(:)) * 100 * 3, ...
            sum(S_conv(:)) * 100 * 3, ...
            sum(I>1e-6), ...
            v_err, i_err, cvx_optval, ...
            iter_solve_time(lin_iter), cvx_status);
        % -- Track minimum-cost iteration (summary reference only) ----
        if cvx_optval < best_cost
            best_cost      = cvx_optval;
            best_cost_iter = lin_iter;
        end

        % -- Track best solution: minimum linearization error ---------
        if v_err < best_volt_err
            best_volt_err = v_err;
            best_iter     = lin_iter;

            % C-rate per node/tech
            B_full = full(B_plus - B_minus);
            E_full = full(E_nom);
            C_rate_store = zeros(Nd, J);
            for n = 1:Nd
                Idx = (n-1)*T + (1:T);
                for j = 1:J
                    En = E_full(n,j);
                    if En > 1e-9
                        C_rate_store(n,j) = max(abs(B_full(Idx,j))) / En;
                    end
                end
            end

            % Charge/discharge exclusivity violation metrics
            B_exc              = min(full(B_plus), full(B_minus));
            tol_exc            = 1e-6;
            cha_dis_vio        = any(B_exc(:) > tol_exc);
            cha_dis_vio_max    = max(B_exc(:));
            cha_dis_vio_energy = sum(B_exc(:)) * Ts;
            cha_dis_vio_frac   = sum(B_exc(:)) / ...
                (sum(full(B_plus(:))) + sum(full(B_minus(:))) + eps);

            % -- Build nested output struct ----------------------------
            best_out = struct();

            % summary: flat scalars — ready for struct2table
            % (best_cost_iter filled after loop once we know the final value)
            best_out.summary.network_id        = string(net_num);
            best_out.summary.cvx_status        = cvx_status;
            best_out.summary.cvx_optval        = cvx_optval;
            best_out.summary.E_nom_total_pu    = sum(E_full(:));
            best_out.summary.S_conv_total_pu   = sum(full(S_conv(:)));
            best_out.summary.best_iter         = lin_iter;       % min volt-err iter
            best_out.summary.best_cost_iter    = [];             % filled after loop
            best_out.summary.n_iters_run       = [];             % filled after loop
            best_out.summary.volt_error        = v_err;
            best_out.summary.curr_error        = i_err;
            best_out.summary.C_rate_max        = max(C_rate_store(:));
            best_out.summary.cha_dis_vio       = cha_dis_vio;
            best_out.summary.prepros_time_s    = prepros_time;
            best_out.summary.solve_time_s      = iter_solve_time(lin_iter);
            best_out.summary.Vmag0_min         = min(Vmag0);
            best_out.summary.Vmag0_max         = max(Vmag0);

            % sizing
            best_out.sizing.E_nom_node_pu    = E_full;
            best_out.sizing.S_conv_node_pu   = full(S_conv);
            best_out.sizing.Installation     = full(I);
            best_out.sizing.C_rate           = C_rate_store;
            best_out.sizing.C_rate_node_max  = max(C_rate_store, [], 2);
            best_out.sizing.tech_names       = tech_names;

            % injections
            best_out.injections.delta_P = dP_mat;
            best_out.injections.delta_Q = dQ_mat;
            best_out.injections.Q_ess   = full(Q_ess);
            best_out.injections.B_bat   = B_full;
            best_out.injections.B_plus  = full(B_plus);
            best_out.injections.B_minus = full(B_minus);
            best_out.injections.B_exc   = B_exc;
            best_out.injections.Sl_P    = full(P_sl);
            best_out.injections.Sl_Q    = full(Q_sl);

            % grid states
            best_out.grid.vmag_lin  = full(vmag);
            best_out.grid.V_lf      = V_lf;
            best_out.grid.Imag_lin  = full(Imag);
            best_out.grid.I_lf      = I_lf;
            best_out.grid.S_lf      = S_lf;
            best_out.grid.Vmag0_min = min(Vmag0);
            best_out.grid.Vmag0_max = max(Vmag0);
            best_out.grid.N         = N;
            best_out.grid.Nd        = Nd;

            % diagnostics (convergence history filled after loop)
            best_out.diagnostics.cha_dis_vio        = cha_dis_vio;
            best_out.diagnostics.cha_dis_vio_max    = cha_dis_vio_max;
            best_out.diagnostics.cha_dis_vio_energy = cha_dis_vio_energy;
            best_out.diagnostics.cha_dis_vio_frac   = cha_dis_vio_frac;
            best_out.diagnostics.iter_volt_error    = [];
            best_out.diagnostics.iter_curr_error    = [];
            best_out.diagnostics.iter_cost          = [];
            best_out.diagnostics.iter_status        = [];

            % meta — makes the file self-documenting
            best_out.meta.scenario          = scenario;
            best_out.meta.network_id_str    = net_id;
            best_out.meta.net_num           = net_num;
            best_out.meta.tech_names        = tech_names;
            best_out.meta.MAX_LIN_ITER      = MAX_LIN_ITER;
            best_out.meta.VOLT_CONV_THRESH  = VOLT_CONV_THRESH;
            best_out.meta.kP                = kP;
            best_out.meta.kQ_conv           = kQ_conv;
            best_out.meta.c_rate_j          = c_rate_j;
            best_out.meta.eta_ch            = eta_ch;
            best_out.meta.eta_dis           = eta_dis;

            % gm: original grid model, pre-linearization
            best_out.gm = gm_orig;

        end  % update best solution

        % -- Early exit if converged ----------------------------------
        if v_err < VOLT_CONV_THRESH
            fprintf('  Converged at iter %d (volt_err=%.2e < %.0e).\n', ...
                lin_iter, v_err, VOLT_CONV_THRESH);
            cvx_clear;
            break
        end

        % -- Re-linearize around updated operating point --------------
        if lin_iter < MAX_LIN_ITER
            P_inj  = complex(P0_mat + (alpha*dP_mat_prev+(1-alpha)*dP_mat), Q0_mat + (alpha*dQ_mat_prev+(1-alpha)*dQ_mat));
            gm_curr      = re_linearization(gm_curr.grid, P_inj,T);
            B_plus_prev  = round(full(B_plus),  4);
            B_minus_prev = round(full(B_minus), 4);
            Q_ess_prev   = round(full(Q_ess),   4);
            dP_mat_prev = dP_mat;
            dQ_mat_prev = dQ_mat;
        end

        cvx_clear;


    end  % sequential linearization loop

    % -----------------------------------------------------------------
    %  FINALISE AND SAVE BEST SOLUTION
    % -----------------------------------------------------------------
    if isempty(best_out)
        error('No valid CVX solution obtained across all linearization iterations.');
    end

    % Stamp convergence history and cross-reference indices
    n_ran = find(~isnan(iter_volt_error), 1, 'last');
    if isempty(n_ran); n_ran = 0; end

    best_out.summary.n_iters_run          = n_ran;
    best_out.summary.best_cost_iter       = best_cost_iter;
    best_out.diagnostics.iter_volt_error  = iter_volt_error(1:n_ran);
    best_out.diagnostics.iter_curr_error  = iter_curr_error(1:n_ran);
    best_out.diagnostics.iter_cost        = iter_cost(1:n_ran);
    best_out.diagnostics.iter_status      = iter_status(1:n_ran);

    out = best_out;
    fname = fullfile('output/OPF_result/out_dir_solved', string(net_num) + ".mat");
    save(fname, '-struct','out');

    fprintf(log_fid, ...
        'SOLVED  %s  status=%s  E=%.4f  S=%.4f  best_iter=%d  best_cost_iter=%d  n_iter=%d  volt_err=%.2e  t=%.1fs\n', ...
        string(net_num), out.summary.cvx_status, ...
        out.summary.E_nom_total_pu, out.summary.S_conv_total_pu, ...
        out.summary.best_iter, out.summary.best_cost_iter, ...
        out.summary.n_iters_run, out.summary.volt_error, ...
        out.summary.solve_time_s);

    cvx_clear;

    % catch ME
    %     fprintf(2, 'FAILED %s: %s\n', net_id, ME.message);
    %
    %     fail_out.network_id = string(net_num);
    %     fail_out.error_msg  = ME.message;
    %     fail_out.error_id   = ME.identifier;
    %     fail_out.stack      = ME.stack;
    %
    %     fname = fullfile('output/OPF_result/out_dir_error', string(net_num) + ".mat");
    %     save(fname, 'fail_out');
    %
    %     fprintf(log_fid, 'FAILED  %s  %s\n', string(net_num), ME.message);
    %
    %     cvx_clear;
    %     continue
    % end
    all_dispatch_logs{iter_count} = dispatch_log;
    all_dispatch_ids{iter_count}  = net_id;
end  % main

plot_dispatch_convergence(dispatch_log, net_id)
plot_dispatch_convergence_multi(all_dispatch_logs,all_dispatch_ids);


fclose(log_fid);
fprintf('\nTotal elapsed time: %.1f s\n', toc(t_tot));