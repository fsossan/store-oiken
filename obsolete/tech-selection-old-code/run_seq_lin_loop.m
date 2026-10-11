function [milp_iters, best_iter_idx] = run_seq_lin_loop(gm, dims, coeffs, cfg, candidates)
% RUN_SEQ_LIN_LOOP  Stage-2 MILP sequential linearisation loop.
%
%   Binary installation variable I is declared over ALL Nd nodes but
%   zero-fixed for non-candidate nodes.  This keeps sensitivity-matrix
%   dimensions unchanged while restricting siting to LP-screened nodes.
%
%   [milp_iters, best_iter_idx] = run_seq_lin_loop(gm, dims, coeffs, cfg, candidates)
%
%   Inputs
%   ------
%   gm         : struct      linear grid model (gm_orig)
%   dims       : struct      dimension/matrix struct
%   coeffs     : struct      pu-scaled cost coefficients
%   cfg        : struct      sizing config
%   candidates : [Nd x 1]   logical mask from extract_lp_candidates
%
%   Outputs
%   -------
%   milp_iters   : struct array [n_ran x 1]  one entry per completed iter
%   best_iter_idx: int   index into milp_iters with minimum volt_error
%
%   milp_iters(k) fields
%   --------------------
%   cvx_status       string
%   cvx_optval       scalar
%   E_nom_node_pu    [Nd x J]    zero for non-candidates
%   S_conv_node_pu   [Nd x J]
%   Installation     [Nd x J]    post-processed binary (> 0.5), zero for non-cands
%   B_plus           [T*Nd x J]
%   B_minus          [T*Nd x J]
%   Q_ess            [T*Nd x J]
%   vmag_lin         [N*T x 1]
%   V_lf             [N*T x 1]
%   Imag_lin         [L*T x 1]
%   I_lf             [L*T x 1]
%   volt_error       scalar
%   curr_error       scalar
%   solve_time_s     scalar

% ---- unpack ----
N    = dims.N;    Nd   = dims.Nd;   L  = dims.L;
T    = dims.T;    J    = dims.J;
AUX  = dims.AUX_to_all_nodes;
R    = dims.R_TNd_toNdT;
CAMP = dims.CABLE_AMP;
Smax = dims.slack_S_mag_pu;

Ts       = cfg.solver.Ts_h;
tol_num  = cfg.solver.tol_num;
MAX_ITER = cfg.solver.MAX_LIN_ITER_milp;
VTHRESH  = cfg.solver.VOLT_CONV_THRESH;

kP      = cfg.converter.kP;
kQ_conv = cfg.converter.kQ_conv;
kPF     = cfg.converter.kPF;
kP_tr   = cfg.transformer.kP_tr;
kQ_tr   = cfg.transformer.kQ_tr;

cE = coeffs.cE;   cS = coeffs.cS;   cI = coeffs.cI;
c_rate_j = cfg.tech.c_rate;
eta_ch   = cfg.tech.eta_ch;
eta_dis  = cfg.tech.eta_dis;
Emax_j   = cfg.tech.Emax_pu;
Smax_j   = cfg.tech.Smax_pu;

% non-candidate mask (for zero-fix constraints)
non_cands = ~candidates;   % [Nd x 1] logical

% ---- warm-start ----
B_plus_prev  = zeros(T*Nd, J);
B_minus_prev = zeros(T*Nd, J);
Q_ess_prev   = zeros(T*Nd, J);

gm_curr = gm;

milp_iters   = struct([]);
best_iter_idx = 0;
best_volt_err = Inf;

for lin_iter = 1:MAX_ITER

    % -- sensitivity matrices --
    dVmagdP = blkdiag(gm_curr.lm.Vmag_dxdP{:}) * AUX;
    dVmagdQ = blkdiag(gm_curr.lm.Vmag_dxdQ{:}) * AUX;
    dImagdP = blkdiag(gm_curr.lm.Imag_dxdP{:}) * AUX;
    dImagdQ = blkdiag(gm_curr.lm.Imag_dxdQ{:}) * AUX;
    dIdP    = blkdiag(gm_curr.lm.I_dxdP{:})    * AUX;
    dIdQ    = blkdiag(gm_curr.lm.I_dxdQ{:})    * AUX;
    dSsdP   = blkdiag(gm_curr.lm.Ss_dxdP{:})   * AUX;
    dSsdQ   = blkdiag(gm_curr.lm.Ss_dxdQ{:})   * AUX;

    P0    = pinv(AUX) * vertcat(gm_curr.lm.P0{:});
    Q0    = pinv(AUX) * vertcat(gm_curr.lm.Q0{:});
    Vmag0 = vertcat(gm_curr.lm.Vmag0{:});
    Imag0 = vertcat(gm_curr.lm.Imag0{:});
    Ss0   = -1 * vertcat(gm_curr.lm.Ss0{:});

    Imag0(abs(Imag0)     < tol_num) = 0;
    dImagdP(abs(dImagdP) < tol_num) = 0;
    dImagdQ(abs(dImagdQ) < tol_num) = 0;
    dIdP(abs(dIdP)       < tol_num) = 0;
    dIdQ(abs(dIdQ)       < tol_num) = 0;

    % ---- CVX MILP ----
    t_solve = tic;
    cvx_solver gurobi_5
    cvx_begin quiet

        variables delta_P(T*Nd)   delta_Q(T*Nd)
        variables vmag(N*T)
        variables Psl_plus(T,1)   Psl_minus(T,1)
        variable  Imag(L*T)

        variables dB_plus(T*Nd,J)   dB_minus(T*Nd,J)
        variables B_plus(T*Nd,J)    B_minus(T*Nd,J)
        variables Q_ess(T*Nd,J)     dQ_ess(T*Nd,J)
        variables E_nom(Nd,J)       S_conv(Nd,J)
        variables SOE_0(Nd,J)
        variable  I_bin(Nd,J) binary

        subject to

        % non-negativity
        E_nom    >= 0;
        S_conv   >= 0;
        SOE_0    >= 0;
        Psl_plus  >= 0;
        Psl_minus >= 0;
        B_plus_prev + dB_plus   >= 0;
        B_minus_prev + dB_minus >= 0;

        % incremental linkage
        B_plus  == B_plus_prev  + dB_plus;
        B_minus == B_minus_prev + dB_minus;

        % ---- zero-fix non-candidates ----
        for j = 1:J
            I_bin(non_cands, j)  == 0;
            E_nom(non_cands, j)  == 0;
            S_conv(non_cands, j) == 0;
        end
        % zero-fix dispatch at non-candidate nodes
        for n = 1:Nd
            if non_cands(n)
                Idx = (n-1)*T + (1:T);
                for j = 1:J
                    B_plus(Idx,j)  == 0;
                    B_minus(Idx,j) == 0;
                    Q_ess(Idx,j)   == 0;
                end
            end
        end

        % Big-M linking (candidates only — non-cands already fixed to 0)
        for j = 1:J
            E_nom(:,j)  <= Emax_j(j) * I_bin(:,j);
            S_conv(:,j) <= Smax_j(j) * I_bin(:,j);
        end

        % objective
        minimize( sum(E_nom*cE) + sum(S_conv*cS) + sum(I_bin*cI) + ...
                  sum(0.5*(B_plus + B_minus)) )

        % SOE evolution (cyclic) — only meaningful at candidate nodes,
        % but constraints at non-cands are automatically satisfied since
        % B_plus, B_minus are fixed to 0 and E_nom is 0 there.
        for n = 1:Nd
            Idx = (n-1)*T + (1:T);
            for j = 1:J
                SOE = SOE_0(n,j) + Ts * ( eta_ch(j)      * cumsum(B_plus(Idx,j)) ...
                                         -(1/eta_dis(j))  * cumsum(B_minus(Idx,j)) );
                SOE(end) == SOE_0(n,j);
                0 <= SOE <= E_nom(n,j);

                B_plus(Idx,j)  <= c_rate_j(j) * E_nom(n,j);
                B_minus(Idx,j) <= c_rate_j(j) * E_nom(n,j);
            end
        end

        % converter PQ box
        B_bat_var = B_plus - B_minus;
        Q_ess == Q_ess_prev + dQ_ess;
        for n = 1:Nd
            Idx = (n-1)*T + (1:T);
            for j = 1:J
                B_bat_var(Idx,j) <=  kP      * S_conv(n,j);
                B_bat_var(Idx,j) >= -kP      * S_conv(n,j);
                Q_ess(Idx,j)     <=  kQ_conv * S_conv(n,j);
                Q_ess(Idx,j)     >= -kQ_conv * S_conv(n,j);
                Q_ess(Idx,j)     <=  kPF * (B_plus(Idx,j) + B_minus(Idx,j));
                Q_ess(Idx,j)     >= -kPF * (B_plus(Idx,j) + B_minus(Idx,j));
            end
        end

        % power balance
        delta_P == -(sum(dB_plus - dB_minus, 2));
        delta_Q ==  sum(dQ_ess, 2);

        % voltage constraint
        vmag == Vmag0 + dVmagdP*(R*delta_P) + dVmagdQ*(R*delta_Q);
        0.9 <= vmag <= 1.1;

        % current constraint
        Imag == abs(Imag0) + dImagdP*(R*delta_P) + dImagdQ*(R*delta_Q);
        Imag ./ repmat(CAMP, T, 1) <= 1;
        Imag ./ repmat(CAMP, T, 1) >= 0;

        % slack bus box
        P_sl = real(Ss0) + real(dSsdP)*(R*delta_P) + real(dSsdQ)*(R*delta_Q);
        Q_sl = imag(Ss0) + imag(dSsdP)*(R*delta_P) + imag(dSsdQ)*(R*delta_Q);
        P_sl <=  kP_tr * Smax;    P_sl >= -kP_tr * Smax;
        Q_sl <=  kQ_tr * Smax;    Q_sl >= -kQ_tr * Smax;

    cvx_end
    solve_time = toc(t_solve);

    % ---- store this iteration ----
    k = lin_iter;
    milp_iters(k).cvx_status    = cvx_status;
    milp_iters(k).cvx_optval    = cvx_optval;
    milp_iters(k).solve_time_s  = solve_time;

    if strcmp(cvx_status,'Solved') || strcmp(cvx_status,'Inaccurate/Solved')

        % post-process binary (relaxation artefacts)
        I_clean = double(full(I_bin) > 0.5);

        % load-flow verification
        dP_mat = reshape(R * delta_P, Nd, T);
        dQ_mat = reshape(R * delta_Q, Nd, T);
        P0_mat = reshape(P0, Nd, T);
        Q0_mat = reshape(Q0, Nd, T);
        P_inj  = complex(P0_mat + dP_mat, Q0_mat + dQ_mat);
        [I_lf, V_lf, ~] = OPF_verification(P_inj.', gm_curr.grid);

        v_err = max(abs(full(vmag) - V_lf(:)));
        i_err = max(abs(full(Imag) - abs(I_lf(:))));

        milp_iters(k).E_nom_node_pu  = full(E_nom);
        milp_iters(k).S_conv_node_pu = full(S_conv);
        milp_iters(k).Installation   = I_bin;
        milp_iters(k).B_plus         = full(B_plus);
        milp_iters(k).B_minus        = full(B_minus);
        milp_iters(k).Q_ess          = full(Q_ess);
        milp_iters(k).vmag_lin       = full(vmag);
        milp_iters(k).V_lf           = V_lf(:);
        milp_iters(k).Imag_lin       = full(Imag);
        milp_iters(k).I_lf           = abs(I_lf(:));
        milp_iters(k).volt_error     = v_err;
        milp_iters(k).curr_error     = i_err;
        milp_iters(k).dP_mat         = dP_mat;
        milp_iters(k).dQ_mat         = dQ_mat;

        if v_err < best_volt_err
            best_volt_err = v_err;
            best_iter_idx = k;
        end

        if v_err < VTHRESH
            cvx_clear;
            break
        end

        % re-linearise
        if lin_iter < MAX_ITER
            gm_curr      = re_linearization(gm_curr.grid, P_inj, T);
            B_plus_prev  = round(full(B_plus),  4);
            B_minus_prev = round(full(B_minus), 4);
            Q_ess_prev   = round(full(Q_ess),   4);
        end

    else
        % solver failed this iteration — record and stop
        milp_iters(k).E_nom_node_pu  = zeros(Nd, J);
        milp_iters(k).S_conv_node_pu = zeros(Nd, J);
        milp_iters(k).Installation   = zeros(Nd, J);
        milp_iters(k).B_plus         = zeros(T*Nd, J);
        milp_iters(k).B_minus        = zeros(T*Nd, J);
        milp_iters(k).Q_ess          = zeros(T*Nd, J);
        milp_iters(k).vmag_lin       = zeros(N*T, 1);
        milp_iters(k).V_lf           = zeros(N*T, 1);
        milp_iters(k).Imag_lin       = zeros(L*T, 1);
        milp_iters(k).I_lf           = zeros(L*T, 1);
        milp_iters(k).volt_error     = Inf;
        milp_iters(k).curr_error     = Inf;
        milp_iters(k).dP_mat         = zeros(Nd, T);
        milp_iters(k).dQ_mat         = zeros(Nd, T);
        cvx_clear;
        break
    end

    cvx_clear;
end

end
