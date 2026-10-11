function sol = solve_ess_milp(sens, prev, dims, cfg, grid_params, opts)
% SOLVE_ESS_MILP  CVX MILP for ESS technology selection, siting, and dispatch.
%
%   sol = solve_ess_milp(sens, prev, dims, cfg, grid_params, opts)
%
%   Inputs
%   ------
%   sens        - sensitivity struct from build_sensitivity_matrices
%   prev        - warm-start struct:
%                   .B_plus_prev  [T*Nd x J]
%                   .B_minus_prev [T*Nd x J]
%                   .Q_ess_prev   [T*Nd x J]
%   dims        - struct: T, Nd, N, L, J, Npv
%   cfg         - config struct from load_ess_selection_config
%   grid_params - struct: R_TNd_toNdT, CABLE_AMP, slack_S_mag_pu,
%                         R_TNpv_toNpvT, PV_avail_pu_stacked (PV curtailment)
%   opts        - struct: current_mag_cstr, siting_activate,
%                         cha_dis_bin_activate, curtailment_activate
%
%   Output
%   ------
%   sol  - struct with fields:
%            B_plus, B_minus, Q_ess        [T*Nd x J]
%            E_nom, S_conv, Installation   [Nd x J]
%            SOE_0                         [Nd x J], cyclic-boundary SOE (pu)
%            vmag                          [N*T x 1]
%            Imag                          [L*T x 1] (real or complex)
%            delta_P, delta_Q             [T*Nd x 1]
%            P_curt                       [T*Npv x 1] curtailed PV, pu (zero-length if Npv==0)
%            P_sl, Q_sl, P_sloss          [T x 1]
%            costs                        struct .E .S .I .L .Curt .total (CHF, per objective terms)
%            status, optval
%
%   PV curtailment (opts.curtailment_activate, dims.Npv > 0): a continuous
%   P_curt in [0, PV_avail], entering vmag/Imag/P_sl/Q_sl/P_sloss as an
%   additional additive term via its own PV-node sensitivities
%   (sens.dVmagdP_PV etc. from build_sensitivity_matrices) and its own
%   reshape matrix (grid_params.R_TNpv_toNpvT) — mirrors the existing
%   demand-node ESS plumbing but over the (possibly different) PV-node set.
%   No new binaries are introduced.

T   = dims.T;   Nd = dims.Nd;   N = dims.N;   L = dims.L;   J = dims.J;
Npv = dims.Npv;
Ts  = 1/4;

c_rate_j = cfg.tech.c_rate;
eta_ch   = cfg.tech.eta_ch;
eta_dis  = cfg.tech.eta_dis;
Emax_j   = cfg.tech.Emax_pu;
Smax_j   = cfg.tech.Smax_pu;
cE = cfg.tech.cE;
cS = cfg.tech.cS;
cI = cfg.tech.cI;

kP      = cfg.converter.kP;
kQ_conv = cfg.converter.kQ_conv;
kPF     = cfg.converter.kPF;
kP_tr   = cfg.transformer.kP_tr;
kQ_tr   = cfg.transformer.kQ_tr;

R         = grid_params.R_TNd_toNdT;
CABLE_AMP = grid_params.CABLE_AMP;
slack_S   = grid_params.slack_S_mag_pu;

B_plus_prev  = prev.B_plus_prev;
B_minus_prev = prev.B_minus_prev;
Q_ess_prev   = prev.Q_ess_prev;

cvx_solver gurobi_3
%%
cvx_begin

variables delta_P(T*Nd)  delta_Q(T*Nd)
variables vmag(N*T)

if opts.current_mag_cstr
    variable Imag(L*T)
else
    variable Imag(L*T) complex
end
if opts.cha_dis_bin_activate
    variable ct(Nd*T,J) binary
end

variables dB_plus(T*Nd,J)   dB_minus(T*Nd,J)
variables B_plus(T*Nd,J)    B_minus(T*Nd,J)
variables Q_ess(T*Nd,J)     dQ_ess(T*Nd,J)
variables E_nom(Nd,J)       S_conv(Nd,J)
variables SOE_0(Nd,J)
variable  I(Nd,J) binary

curtailment_on = opts.curtailment_activate && Npv > 0;
if curtailment_on
    variables dP_curt(T*Npv,1)  P_curt(T*Npv,1)
end


subject to

% --- non-negativity ---
E_nom    >= 0;
S_conv   >= 0;
SOE_0    >= 0;
B_plus_prev + dB_plus   >= 0;
B_minus_prev + dB_minus >= 0;

% --- warm-start linkage ---
B_plus  == B_plus_prev  + dB_plus;
B_minus == B_minus_prev + dB_minus;

% --- PV curtailment box (no new binaries: plain continuous variable) ---
if curtailment_on
    P_curt == prev.P_curt_prev + dP_curt;
    P_curt >= 0;
    P_curt <= grid_params.PV_avail_pu_stacked;
end

% --- Big-M installation linking ---
if opts.siting_activate
    for j = 1:J
        E_nom(:,j) <= Emax_j(j) * I(:,j);
        S_conv(:,j) <= Smax_j(j) * I(:,j);
    end
    for n = 1:Nd
        sum(I(n,:)) <= 1;   % at most one technology per node
    end
else
    for j = 1:J
        E_nom(:,j) <= Emax_j(j);
        S_conv(:,j) <= Smax_j(j);
    end
end



% --- SOE evolution (cyclic boundary) ---
cost_BESS_loss_acc = 0;
for n = 1:Nd
    Idx = (n-1)*T + (1:T);
    for j = 1:J
        SOE = SOE_0(n,j) + Ts * ( eta_ch(j)      * cumsum(B_plus(Idx,j)) ...
            - (1/eta_dis(j)) * cumsum(B_minus(Idx,j)) );
        SOE(end) == SOE_0(n,j);
        0 <= SOE <= E_nom(n,j);

        % BESS round-trip throughput loss: charging power B_plus only
        % delivers eta_ch*B_plus to the SOE ((1-eta_ch)*B_plus is lost);
        % discharging power B_minus draws B_minus/eta_dis from the SOE to
        % deliver B_minus to the grid ((1/eta_dis - 1)*B_minus is lost).
        if opts.throughput_penalty
            loss_inst = Ts * ( (1 - eta_ch(j)) * B_plus(Idx,j) + (1/eta_dis(j) - 1) * B_minus(Idx,j) );
            cost_BESS_loss_acc = cost_BESS_loss_acc + sum(loss_inst);
        end

        if opts.cha_dis_bin_activate
            M_nj = kP * Smax_j(j);
            B_plus(Idx,j)  <= M_nj * ct(Idx,j);
            B_minus(Idx,j) <= M_nj * (1 - ct(Idx,j));
        end

        % C-rate constraint
        B_plus(Idx,j)  <= c_rate_j(j) * E_nom(n,j);
        B_minus(Idx,j) <= c_rate_j(j) * E_nom(n,j);
        % Joint C-rate cap: see util/solve_ess_milp_v2.m for the full
        % rationale -- non-binding for single-directional dispatch, halves
        % the max combined headroom available to the phantom-throughput
        % exploit, no binaries.
        B_plus(Idx,j) + B_minus(Idx,j) <= c_rate_j(j) * E_nom(n,j);
    end
end

% --- converter PQ box ---
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

% --- power balance ---
delta_P == -sum(dB_plus  - dB_minus, 2);
delta_Q ==  sum(dQ_ess, 2);
delta_Q == 0;

% --- PV curtailment perturbation (additive, active-power only) ---
% Curtailing PV can only REDUCE injection at a PV node (P_curt >= 0, so
% -P_curt <= 0), so this term only ever pushes vmag/Imag/P_sl down — it can
% relieve an over-voltage/over-current from PV export, never an
% under-voltage/overload caused by demand (see CLAUDE.md).
if curtailment_on
    Rpv         = grid_params.R_TNpv_toNpvT;
    pv_dV       = sens.dVmagdP_PV * (Rpv * (-P_curt));
    pv_dI       = sens.dImagdP_PV * (Rpv * (-P_curt));
    pv_dPs      = real(sens.dSsdP_PV) * (Rpv * (-P_curt));
    pv_dQs      = imag(sens.dSsdP_PV) * (Rpv * (-P_curt));
    pv_loss_adj = sum(reshape(Rpv * (-P_curt), Npv, T), 1)';
else
    pv_dV       = 0;
    pv_dI       = 0;
    pv_dPs      = 0;
    pv_dQs      = 0;
    pv_loss_adj = 0;
end

% --- voltage constraint ---
vmag == sens.Vmag0 + sens.dVmagdP * (R * delta_P) ...
    + sens.dVmagdQ * (R * delta_Q) + pv_dV;
0.9 <= vmag <= 1.1;

% --- current constraint ---
if opts.current_mag_cstr
    Imag == abs(sens.Imag0) + sens.dImagdP * (R * delta_P) ...
        + sens.dImagdQ * (R * delta_Q) + pv_dI;
    Imag ./ repmat(CABLE_AMP, T, 1) <= 1;
    Imag ./ repmat(CABLE_AMP, T, 1) >= 0;
else
    Imag == sens.Imag0 + sens.dIdP * (R * delta_P) ...
        + sens.dIdQ * (R * delta_Q);
    ( real(Imag) + imag(Imag)) ./ repmat(CABLE_AMP, T, 1) <= 1;
    ( real(Imag) - imag(Imag)) ./ repmat(CABLE_AMP, T, 1) <= 1;
    (-real(Imag) + imag(Imag)) ./ repmat(CABLE_AMP, T, 1) <= 1;
    (-real(Imag) - imag(Imag)) ./ repmat(CABLE_AMP, T, 1) <= 1;
end

% --- slack bus / transformer box ---
P_sl = real(sens.Ss0) + real(sens.dSsdP) * (R * delta_P) ...
    + real(sens.dSsdQ) * (R * delta_Q) + pv_dPs;
Q_sl = imag(sens.Ss0) + imag(sens.dSsdP) * (R * delta_P) ...
    + imag(sens.dSsdQ) * (R * delta_Q) + pv_dQs;
P_sl <=  kP_tr * slack_S;
P_sl >= -kP_tr * slack_S;
Q_sl <=  kQ_tr * slack_S;
Q_sl >= -kQ_tr * slack_S;

% Transformer losses

P_sloss  = P_sl + sum(reshape(sens.P0 + R * delta_P, Nd, T), 1)' + pv_loss_adj;
P_sloss  >= 0; 

% --- objective ---
% See util/solve_ess_milp_v2.m for why days_simulated is needed: costL/
% costCurt/costBESSLoss's *365*15 annualization is only correct if the
% summed quantity represents exactly one simulated day, so the raw
% horizon-length sum is converted to an average-day rate first.
days_simulated = T * Ts / 24;

costE = sum(sum(E_nom  .* repmat(cE, Nd, 1)));
costS = sum(sum(S_conv .* repmat(cS, Nd, 1)));
if opts.min_loss
    costL = cfg.economics.cL * Ts * sum(P_sloss) / days_simulated * 365 * 15;
else
    costL = 0;
end
if opts.siting_activate
    costI = sum(sum(I .* repmat(cI, Nd, 1)));
else
    costI = 0;
end
if curtailment_on
    costCurt = cfg.economics.cCurt * Ts * sum(P_curt) / days_simulated * 365 * 15;
else
    costCurt = 0;
end
if opts.throughput_penalty
    costBESSLoss = cfg.economics.cThroughputLoss * cost_BESS_loss_acc / days_simulated * 365 * 15;
else
    costBESSLoss = 0;
end

% --- charge/discharge exclusivity penalty (relaxed formulation only) ---
% See util/solve_ess_milp_v2.m for the full rationale.
if ~opts.cha_dis_bin_activate
    penalty_unit_cost = cfg.solver.cha_dis_penalty_eps * min([cE(:); cS(:)]);
    costPenalty = penalty_unit_cost * sum(sum(B_plus + B_minus)) / T;
else
    costPenalty = 0;
end

if opts.cha_dis_bin_activate
    minimize((costE + costS + costI + costL + costCurt + costBESSLoss)/1000); % in Thousand Francs
else
    minimize((costE + costS + costI + costL + costCurt + costPenalty + costBESSLoss)/1000); % in Thousand Francs, incl. exclusivity penalty
end

cvx_end

% --- pack outputs ---
sol.B_plus        = full(B_plus);
sol.B_minus       = full(B_minus);
sol.Q_ess         = full(Q_ess);
sol.E_nom         = full(E_nom);
sol.S_conv        = full(S_conv);
sol.Installation  = full(I);
sol.SOE_0         = full(SOE_0);
sol.vmag          = full(vmag);
sol.Imag          = full(Imag);
sol.delta_P       = full(delta_P);
sol.delta_Q       = full(delta_Q);
if curtailment_on
    sol.P_curt = full(P_curt);
else
    sol.P_curt = zeros(T*Npv, 1);
end
sol.P_sl          = full(P_sl);
sol.Q_sl          = full(Q_sl);
sol.P_sloss       = full(P_sloss);
sol.status        = cvx_status;
sol.optval        = cvx_optval;

sol.costs.E       = full(costE);
sol.costs.S       = full(costS);
sol.costs.I       = full(costI);
sol.costs.L       = full(costL);
sol.costs.Curt    = full(costCurt);
sol.costs.BESSLoss = full(costBESSLoss);
sol.costs.Penalty = full(costPenalty);   % diagnostic only, NOT a real economic cost -- excluded from .total
sol.costs.total   = full(costE + costS + costI + costL + costCurt + costBESSLoss);

end
