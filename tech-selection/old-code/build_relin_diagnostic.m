% -------------------------------------------------------------------------
%  Build linearization diagnostic struct
%  Paste this block immediately after:
%  [I_lf, V_lf, S_lf] = OPF_verification(P_inj.', gm_curr.grid);
% -------------------------------------------------------------------------

diag.meta.network_id  = net_id;
diag.meta.lin_iter    = lin_iter;
diag.meta.N           = N;
diag.meta.L           = L;
diag.meta.T           = T;
diag.meta.Nd          = Nd;

% Initial operating point (before any BESS, from gm_orig / first linearization)
diag.volt.vmag0       = Vmag0;           % N*T x 1, initial linearization point voltages

% Linear model prediction (CVX output)
diag.volt.v_lin       = vmag;            % N*T x 1

% Nonlinear load flow (ground truth at CVX solution)
diag.volt.v_lf        = V_lf;           % N*T x 1

% Current: initial linearization point
diag.curr.imag0       = Imag0;          % L*T x 1, complex

% Current: linear model prediction
diag.curr.i_lin       = Imag;           % L*T x 1

% Current: nonlinear load flow
diag.curr.i_lf        = I_lf;           % L*T x 1

% Current: line ampacity rating
diag.curr.amp_rat     = CABLE_AMP;

% BESS injections: current iteration
diag.bess.B_plus      = full(B_plus);   % T*Nd x J
diag.bess.B_minus     = full(B_minus);  % T*Nd x J
diag.bess.B_bat       = full(B_plus - B_minus);
diag.bess.delta_P     = dP_mat;         % Nd x T
diag.bess.delta_Q     = dQ_mat;         % Nd x T
diag.bess.Q_ess_prev = Q_ess_prev;
diag.bess.Q_ess      = full(Q_ess);

% BESS injections: previous iteration (warm-start point)
diag.bess.B_plus_prev  = B_plus_prev;   % T*Nd x J
diag.bess.B_minus_prev = B_minus_prev;  % T*Nd x J

% Errors
diag.errors.volt_error = v_err;         % max nodal voltage error (pu)
diag.errors.curr_error = i_err;         % max line current error (pu)
diag.errors.cvx_optval = cvx_optval;
diag.errors.cvx_status = cvx_status;

% Call diagnostic function
plot_relin_diagnostic(diag);
