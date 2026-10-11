function [lp_out, lp_status] = solve_lp_relaxation(gm, dims, coeffs, cfg)
% SOLVE_LP_RELAXATION  Stage-1 LP: no siting binary, all Nd nodes eligible.
%                      Runs MAX_LIN_ITER_lp sequential linearisation steps
%                      (typically 1).
%
%   [lp_out, lp_status] = solve_lp_relaxation(gm, dims, coeffs, cfg)
%
%   Inputs
%   ------
%   gm     : struct   linear grid model (from preprocess_network)
%   dims   : struct   dimension/matrix struct
%   coeffs : struct   pu-scaled cost coefficients
%   cfg    : struct   sizing config
%
%   Outputs
%   -------
%   lp_out : struct
%       .E_nom_node_pu   [Nd x J]    energy capacity per node per tech
%       .S_conv_node_pu  [Nd x J]    converter rating per node per tech
%       .B_plus          [T*Nd x J]  charge dispatch
%       .B_minus         [T*Nd x J]  discharge dispatch
%       .Q_ess           [T*Nd x J]  reactive dispatch
%       .vmag_lin        [N*T x 1]   linearised voltage (best iter)
%       .V_lf            [N*T x 1]   load-flow verified voltage
%       .Imag_lin        [L*T x 1]   linearised current magnitude
%       .I_lf            [L*T x 1]   load-flow verified current magnitude
%       .cvx_optval      scalar
%       .volt_error      scalar      max|vmag_lin - V_lf|
%       .curr_error      scalar
%       .solve_time_s    scalar
%
%   lp_status : string   'Solved' | 'Inaccurate/Solved' | failure string

% ---- unpack frequently used fields ----
N    = dims.N;    Nd   = dims.Nd;   L  = dims.L;
T    = dims.T;    J    = dims.J;
AUX  = dims.AUX_to_all_nodes;
R    = dims.R_TNd_toNdT;
CAMP = dims.CABLE_AMP;
Smax = dims.slack_S_mag_pu;

Ts       = cfg.solver.Ts_h;
tol_num  = cfg.solver.tol_num;
MAX_ITER = cfg.solver.MAX_LIN_ITER_lp;
VTHRESH  = cfg.solver.VOLT_CONV_THRESH;

kP      = cfg.converter.kP;
kQ_conv = cfg.converter.kQ_conv;
kPF     = cfg.converter.kPF;
kP_tr   = cfg.transformer.kP_tr;
kQ_tr   = cfg.transformer.kQ_tr;

cE = coeffs.cE;   cS = coeffs.cS;
J_names  = cfg.tech.names;
c_rate_j = cfg.tech.c_rate;
eta_ch   = cfg.tech.eta_ch;
eta_dis  = cfg.tech.eta_dis;
Emax_j   = cfg.tech.Emax_pu;
Smax_j   = cfg.tech.Smax_pu;

% ---- warm-start ----
B_plus_prev  = zeros(T*Nd, J);
B_minus_prev = zeros(T*Nd, J);
Q_ess_prev   = zeros(T*Nd, J);

gm_curr = gm;

best_volt_err = Inf;
lp_out   = [];
lp_status = 'NotRun';

for lin_iter = 1:MAX_ITER

    % -- sensitivity matrices for this operating point --
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

    % numerical clean-up
    Imag0(abs(Imag0)     < tol_num) = 0;
    dImagdP(abs(dImagdP) < tol_num) = 0;
    dImagdQ(abs(dImagdQ) < tol_num) = 0;
    dIdP(abs(dIdP)       < tol_num) = 0;
    dIdQ(abs(dIdQ)       < tol_num) = 0;

    % ---- CVX LP (no binary I, no Big-M) ----
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

        % no Big-M / no binary: simple box upper bounds
        for j = 1:J
            E_nom(:,j)  <= Emax_j(j);
            S_conv(:,j) <= Smax_j(j);
        end

        % objective (no cI term)
        minimize( sum(E_nom*cE) + sum(S_conv*cS) + ...
                  sum(0.5*(B_plus + B_minus)) )

        % SOE evolution (cyclic)
        for n = 1:Nd
            Idx = (n-1)*T + (1:T);
            for j = 1:J
                SOE = SOE_0(n,j) + Ts * ( eta_ch(j)       * cumsum(B_plus(Idx,j)) ...
                                         -(1/eta_dis(j))   * cumsum(B_minus(Idx,j)) );
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

        % current constraint (magnitude form)
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

    lp_status = cvx_status;

    if ~strcmp(cvx_status,'Solved') && ~strcmp(cvx_status,'Inaccurate/Solved')
        cvx_clear;
        return
    end

    % load-flow verification
    dP_mat = reshape(R * delta_P, Nd, T);
    dQ_mat = reshape(R * delta_Q, Nd, T);
    P0_mat = reshape(P0, Nd, T);
    Q0_mat = reshape(Q0, Nd, T);
    P_inj  = complex(P0_mat + dP_mat, Q0_mat + dQ_mat);
    [I_lf, V_lf, ~] = OPF_verification(P_inj.', gm_curr.grid);

    v_err = max(abs(full(vmag) - V_lf(:)));
    i_err = max(abs(full(Imag) - abs(I_lf(:))));

    % track best iteration
    if v_err < best_volt_err
        best_volt_err = v_err;
        lp_out.E_nom_node_pu  = full(E_nom);
        lp_out.S_conv_node_pu = full(S_conv);
        lp_out.B_plus         = full(B_plus);
        lp_out.B_minus        = full(B_minus);
        lp_out.Q_ess          = full(Q_ess);
        lp_out.vmag_lin       = full(vmag);
        lp_out.V_lf           = V_lf(:);
        lp_out.Imag_lin       = full(Imag);
        lp_out.I_lf           = abs(I_lf(:));
        lp_out.cvx_optval     = cvx_optval;
        lp_out.volt_error     = v_err;
        lp_out.curr_error     = i_err;
        lp_out.solve_time_s   = solve_time;
        lp_out.dP_mat         = dP_mat;
        lp_out.dQ_mat         = dQ_mat;
    end

    if v_err < VTHRESH
        cvx_clear;
        break
    end

    % re-linearise for next iteration
    if lin_iter < MAX_ITER
        P_inj        = complex(P0_mat + dP_mat, Q0_mat + dQ_mat);
        gm_curr      = re_linearization(gm_curr.grid, P_inj, T);
        B_plus_prev  = round(full(B_plus),  4);
        B_minus_prev = round(full(B_minus), 4);
        Q_ess_prev   = round(full(Q_ess),   4);
    end

    cvx_clear;
end

end
