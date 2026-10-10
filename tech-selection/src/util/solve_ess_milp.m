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
%                         cha_dis_bin_activate, curtailment_activate,
%                         one_tech_per_node (optional, default true: adds
%                         sum(I(n,:)) <= 1 when siting_activate),
%                         lossless_bess (optional, default false: see below)
%
%   opts.lossless_bess: models an idealized 100%-round-trip-efficient BESS
%   (eta_ch=eta_dis=1) to get a LOWER-BOUND estimate of required E_nom/S_conv
%   -- with no round-trip loss, B_plus/B_minus collapse into one signed net
%   power variable B_bat (a single real number can't be "charging and
%   discharging at once", so the whole ct-binary / exclusivity-penalty
%   apparatus becomes unnecessary by construction, not just switched off).
%   sol.B_plus/B_minus are still populated (synthesized from B_bat via
%   max(B_bat,0)/max(-B_bat,0) after solving) so every downstream consumer
%   (run_seq_lin_loop_ess.m, build_network_result.m,
%   analyze_charge_discharge_exclusivity.m, analyze_losses.m, warm-starting)
%   needs no changes -- they always see two complementary, nonneg arrays.
%   cfg.tech.eta_ch/eta_dis are not read in this mode (there is no loss
%   concept to apply them to); cfg.solver.cha_dis_penalty_eps and
%   opts.cha_dis_bin_activate/opts.throughput_penalty are ignored (forced
%   off) regardless of their config values.
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
%
%   SOE recursion (sparsity fix): SOE is now an explicit CVX variable
%   evolved via sequential per-step equality constraints
%   (SOE_t = SOE_{t-1} + Ts*(...)) instead of the previous
%   SOE_0 + Ts*cumsum(...) formulation. The cumsum version expands into a
%   dense lower-triangular constraint block (each of the T SOE bounds
%   referencing all prior steps), which was measured to produce nnz(A)
%   growing as O(T^2) with horizon length — the confirmed cause of the
%   Gurobi out-of-memory failures beyond ~60-day horizons. The sequential
%   form has each constraint reference only the previous timestep, giving
%   nnz(A) growth that is O(T) (linear) instead. Feasible set is
%   unchanged; only the constraint representation is sparser.

T   = dims.T;   Nd = dims.Nd;   N = dims.N;   L = dims.L;   J = dims.J;
Npv = dims.Npv;
Ts  = cfg.solver.Ts_h;

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

% Operational voltage limits (sizing_cfg.json solver.V_MIN/V_MAX); absent
% fields fall back to 0.9/1.1 for experiments/ scripts that hand-build cfg.
V_MIN = 0.9;  if isfield(cfg.solver, 'V_MIN'), V_MIN = cfg.solver.V_MIN; end
V_MAX = 1.1;  if isfield(cfg.solver, 'V_MAX'), V_MAX = cfg.solver.V_MAX; end

R         = grid_params.R_TNd_toNdT;
CABLE_AMP = grid_params.CABLE_AMP;
slack_S   = grid_params.slack_S_mag_pu;

lossless_bess = isfield(opts, 'lossless_bess') && opts.lossless_bess;

if lossless_bess
    B_bat_prev = prev.B_plus_prev - prev.B_minus_prev;  % synthesized fields round-trip cleanly
else
    B_plus_prev  = prev.B_plus_prev;
    B_minus_prev = prev.B_minus_prev;
end
Q_ess_prev   = prev.Q_ess_prev;


%%
% activate/deactivate tech


cvx_solver gurobi
cvx_begin

% Gurobi parameters from cfg.solver.gurobi (config/sizing_cfg.json): every
% field (MIPGap, FeasibilityTol, IntFeasTol, TimeLimit, ...) is passed to the
% solver as a model-local setting through cvx_solver_settings, which must be
% called after cvx_solver gurobi (settings attach to the active solver).
% Absent/empty block -> Gurobi defaults (MIPGap 1e-4).
%
% Switch: cfg.solver.apply_gurobi_settings (default true). Stock CVX 2.2's
% Gurobi shim (<CVX>/shims/cvx_gurobi.m) has an indexing bug that makes any
% custom setting fail with an empty gurobi() error; the one-line fix (pass
% `settings, 2` instead of `3` to cvx_run_solver) is described in
% docs/DEVELOPMENT_NOTES.md. Set the switch to false to run with Gurobi's
% defaults instead -- then the gurobi block in the JSON is NOT in effect, and
% a 1e-4 gap can flip a near-tie technology choice. Until 2026-10-10 this
% call was commented out, so the JSON block was silently ignored.
apply_gp = ~isfield(cfg.solver, 'apply_gurobi_settings') || cfg.solver.apply_gurobi_settings;
if apply_gp && isfield(cfg.solver, 'gurobi') && ~isempty(fieldnames(cfg.solver.gurobi))
    gp      = cfg.solver.gurobi;
    gp_args = [fieldnames(gp)'; struct2cell(gp)'];
    cvx_solver_settings(gp_args{:});
end

variables delta_P(T*Nd)  delta_Q(T*Nd)
variables vmag(N*T)

if opts.current_mag_cstr
    variable Imag(L*T)
else
    variable Imag(L*T) complex
end
if opts.cha_dis_bin_activate && ~lossless_bess
    variable ct(Nd*T,J) binary
end

if lossless_bess
    variables dB_bat(T*Nd,J)   B_bat(T*Nd,J) B_bat_pen(T*Nd,J)
else
    variables dB_plus(T*Nd,J)   dB_minus(T*Nd,J)
    variables B_plus(T*Nd,J)    B_minus(T*Nd,J)
end
variables Q_ess(T*Nd,J)     dQ_ess(T*Nd,J)
variables E_nom(Nd,J)       S_conv(Nd,J)
variables SOE_0(Nd,J)
variables SOE(T*Nd,J)
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
if ~lossless_bess
    B_plus_prev + dB_plus   >= 0;
    B_minus_prev + dB_minus >= 0;
end

% --- warm-start linkage ---
if lossless_bess
    B_bat == B_bat_prev + dB_bat;   % free sign, no non-negativity to enforce
else
    B_plus  == B_plus_prev  + dB_plus;
    B_minus == B_minus_prev + dB_minus;
end

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
    % Absent field = constraint on (many experiments/ scripts hand-build opts
    % without it); false lets a node host more than one technology.
    if ~isfield(opts, 'one_tech_per_node') || opts.one_tech_per_node
        for n = 1:Nd
            sum(I(n,:)) <= 1;   % at most one technology per node
        end
    end
else
    for j = 1:J
        E_nom(:,j) <= Emax_j(j);
        S_conv(:,j) <= Smax_j(j);
    end
end

% testing forced siting
% I(2:end,:) == 0;


% --- SOE evolution (cyclic boundary, sparse sequential recursion) ---
cost_BESS_loss_acc = 0;
for n = 1:Nd
    Idx = (n-1)*T + (1:T);
    for j = 1:J
        if lossless_bess
            % 100%-round-trip-efficient BESS: one signed net-power variable,
            % no eta terms, no loss to price -- see opts.lossless_bess above.
            SOE(Idx(1),j) == SOE_0(n,j) + Ts * B_bat(Idx(1),j);
            SOE(Idx(2:end),j) == SOE(Idx(1:end-1),j) + Ts * B_bat(Idx(2:end),j);
            SOE(Idx(end),j) == SOE_0(n,j);   % cyclic boundary
            0 <= SOE(Idx,j) <= E_nom(n,j);

            % C-rate: one box on net power -- a single real variable can't
            % be both charging and discharging at once, so there is no
            % phantom-throughput exploit to guard against here (no ct
            % binary, no exclusivity penalty needed).
            -c_rate_j(j) * E_nom(n,j) <= B_bat(Idx,j) <= c_rate_j(j) * E_nom(n,j);
        else
            % step 1: linked to SOE_0 (not to SOE(Idx(end)) of any other n,j)
            SOE(Idx(1),j) == SOE_0(n,j) + Ts * ( eta_ch(j)      * B_plus(Idx(1),j) ...
                                                - (1/eta_dis(j)) * B_minus(Idx(1),j) );
            % steps 2..T: each references only the immediately preceding step
            SOE(Idx(2:end),j) == SOE(Idx(1:end-1),j) + Ts * ( eta_ch(j)      * B_plus(Idx(2:end),j) ...
                                                              - (1/eta_dis(j)) * B_minus(Idx(2:end),j) );

            SOE_0(n,j)==SOE(Idx(end),j); %<= SOE_0(n,j);   % cyclic boundary
            0 <= SOE(Idx,j) <= E_nom(n,j);

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
            % Joint C-rate cap: non-binding whenever dispatch is genuinely
            % single-directional (B_plus=0 or B_minus=0, where it reduces to
            % one of the two bounds above exactly) -- full rated C-rate power
            % stays available in either direction. Only restricts simultaneous
            % charge+discharge, halving the max combined headroom available to
            % the phantom-throughput exploit (2*c_rate*E_nom -> c_rate*E_nom),
            % with no binaries and no effect on legitimate dispatch.
            % B_plus(Idx,j) + B_minus(Idx,j) <= c_rate_j(j) * E_nom(n,j);
        end
    end
end

% --- converter PQ box ---
if lossless_bess
    B_bat_var = B_bat;
else
    B_bat_var = B_plus - B_minus;
end
Q_ess == Q_ess_prev + dQ_ess;

for n = 1:Nd
    Idx = (n-1)*T + (1:T);
    for j = 1:J
        B_bat_var(Idx,j) <=  kP      * S_conv(n,j);
        B_bat_var(Idx,j) >= -kP      * S_conv(n,j);
        Q_ess(Idx,j)     <=  kQ_conv * S_conv(n,j);
        Q_ess(Idx,j)     >= -kQ_conv * S_conv(n,j);
        if ~lossless_bess
            % Vestigial given delta_Q==0 below pins Q_ess at 0 regardless
            % (see docs/DEVELOPMENT_NOTES.md) -- skipped in lossless mode since B_plus/
            % B_minus don't exist as CVX variables to sum here.
            Q_ess(Idx,j) <=  kPF * (B_plus(Idx,j) + B_minus(Idx,j));
            Q_ess(Idx,j) >= -kPF * (B_plus(Idx,j) + B_minus(Idx,j));
        end
    end
end

% --- power balance ---
if lossless_bess
    delta_P == -sum(dB_bat, 2);
else
    delta_P == -sum(dB_plus  - dB_minus, 2);
end
delta_Q ==  sum(dQ_ess, 2);
delta_Q == 0;

% --- PV curtailment perturbation (additive, active-power only) ---
% Curtailing PV can only REDUCE injection at a PV node (P_curt >= 0, so
% -P_curt <= 0), so this term only ever pushes vmag/Imag/P_sl down — it can
% relieve an over-voltage/over-current from PV export, never an
% under-voltage/overload caused by demand (see docs/DEVELOPMENT_NOTES.md).
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
V_MIN <= vmag <= V_MAX;

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
% costL/costCurt/costBESSLoss all annualize a horizon-length sum via
% *365*15 (days/year * technology life_span years), which is only correct
% if the summed quantity represents exactly one simulated day. Dividing by
% days_simulated first turns the raw horizon-length sum into an
% average-day rate before annualizing, so the annualized cost no longer
% scales with how many days T happens to cover (D=1 is unaffected by this
% change; D>1 no longer overstates these three terms by a factor of D).
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
    costBESSLoss = ((cfg.economics.cThroughputLoss * cost_BESS_loss_acc)/days_simulated)  * 365 * 15;
else
    costBESSLoss = 0;
end


if lossless_bess
    B_bat_pen >=  B_bat;
    B_bat_pen >= -B_bat;
    penalty_unit_cost = cfg.solver.cha_dis_penalty_eps * min([cE(:); cS(:)]);
    costPenalty =  0;%penalty_unit_cost * sum(sum(B_bat_pen)) / T; %testing   % structurally no exclusivity to penalize -- see opts.lossless_bess above
elseif ~opts.cha_dis_bin_activate
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
fprintf("Investment cost (kCHF)%f\n",(costE+costS+costI)/1e3);
fprintf("Penalty cost (kCHF)%f\n",costPenalty/1e3);
fprintf("Sloss cost (kCHF)%f\n",costL/1e3);
fprintf("Eloss cost (kCHF)%f\n",costBESSLoss/1e3);


% --- pack outputs ---
if lossless_bess
    B_bat_val   = full(B_bat);
    sol.B_plus  = max(B_bat_val, 0);
    sol.B_minus = max(-B_bat_val, 0);
else
    sol.B_plus        = full(B_plus);
    sol.B_minus       = full(B_minus);
end
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