function [Vk_load, Ibr, S_slack, converged, num_iter] = loadflow_FPIs_convergance( ...
    Y, V0, Swye, n_phases, voltageToBranchCurrent_pu)
%LOADFLOW_FPI_CONVERGENCE Fixed-point (Z-bus) load flow for constant-power wye loads.
%
% Inputs
%   Y   : full nodal admittance matrix (n_phases*n_nodes) x (n_phases*n_nodes)
%   V0  : slack-bus phase voltage vector (n_phases x 1), in p.u.
%   Swye: constant-power wye load vector at non-slack nodes ((n_nodes-1)*n_phases x 1), in p.u.
%         (positive for consumption; algorithm uses conj(S)./conj(V))
%   n_phases : 1, 2, or 3
%   voltageToBranchCurrent_pu : mapping matrix from nodal V to branch I (size: n_branches x n_phases*n_nodes)
%
% Outputs
%   Vk_load   : voltages at non-slack nodes ((n_nodes-1)*n_phases x 1)
%   Ibr       : branch currents (n_branches x 1)
%   S_slack   : slack complex power injection (n_phases x 1), positive when supplying network
%   converged : true if converged within tolerance
%   num_iter  : number of iterations executed

% -----------------------------
% Settings (tune as you like)
% -----------------------------
MAX_ITER   = 100;     % maximum iterations
TOL_ABS    = 1e-5;    % absolute voltage tolerance (p.u.)
TOL_REL    = 1e-5;    % relative voltage tolerance
V_FLOOR    = 0.05;    % p.u. floor to avoid division by ~0
ALPHA      = 0.70;    % damping factor (0<ALPHA<=1); lower = more stable
GROWTH_FAC = 1.20;    % divergence heuristic: error growth factor
MIN_IT_GROWTH_CHECK = 6;

% -----------------------------
% Basic dimensions
% -----------------------------
n_total = size(Y, 1);
n_nodes = n_total / n_phases;
if abs(n_nodes - round(n_nodes)) > 0
    error('Size(Y,1) must be divisible by n_phases.');
end
n_nodes = round(n_nodes);

% -----------------------------
% Partition Y into slack/non-slack
% -----------------------------
idx0 = 1:n_phases;                      % slack node phases
idxL = (n_phases+1):n_total;            % load nodes phases

Y00 = Y(idx0, idx0);
Y0L = Y(idx0, idxL);
YL0 = Y(idxL, idx0);
YLL = Y(idxL, idxL);

% -----------------------------
% Precompute zero-load voltage (w) via linear solve
% w = -YLL^{-1} * YL0 * V0
% -----------------------------
w = -(YLL \ (YL0 * V0));

% -----------------------------
% Initialize
% -----------------------------
Vk = w;
converged = false;
num_iter = 0;
prev_err = inf;

% -----------------------------
% Fixed-point iterations
% Vk1 = w + YLL^{-1} * ( conj(S) ./ conj(Vk) )
% -----------------------------
for ii = 1:MAX_ITER
    % % Voltage floor for safe division
    Vk_safe = Vk;
    small = abs(Vk_safe) < V_FLOOR;
    if any(small)
        Vk_safe(small) = V_FLOOR .* exp(1j * angle(Vk_safe(small)));
        % if angle is NaN (exact zero), just set to 0 angle
        Vk_safe(~isfinite(Vk_safe)) = V_FLOOR;
    end

    % Constant-power current injections (wye)
    Iinj = conj(Swye) ./ conj(Vk_safe);

    % Solve for update (avoid inv)
    Vk1 = w + (YLL \ Iinj);

    % Damping (relaxation)
    if ALPHA < 1
        Vk1 = ALPHA * Vk1 + (1 - ALPHA) * Vk;
    end

    % Error metrics
    abs_err = max(abs(Vk1 - Vk));
    rel_err = abs_err / max(1, max(abs(Vk1)));

    % Bookkeeping
    num_iter = ii;

    % NaN/Inf check
    if any(~isfinite(Vk1))
        warning('Load flow diverged: NaN/Inf detected at iteration %d', ii);
        converged = false;
        break;
    end

    % Optional physical bounds check (helps catch runaway early)
    if max(abs(Vk1)) > 2.0 || min(abs(Vk1)) < 0.02
        warning('Load flow likely diverging: voltages out of bounds at iteration %d', ii);
        converged = false;
        % break;
    end

    % Convergence check
    if (abs_err < TOL_ABS) || (rel_err < TOL_REL)
        converged = true;
        % disp("Loadflow converged")
        break;
    end

    % Divergence/oscillation heuristic: error growing persistently
    if ii >= MIN_IT_GROWTH_CHECK && abs_err > GROWTH_FAC * prev_err
        warning('Load flow likely diverging/oscillating: error increased at iteration %d (%.2e -> %.2e)', ...
            ii, prev_err, abs_err);
        converged = false;
        break;
    end
    prev_err = abs_err;

    % Update for next iteration
    Vk = Vk1;
end

% Warn if max iterations reached without convergence
if ~converged && num_iter == MAX_ITER
    warning('Load flow did not converge after %d iterations. Final abs error: %.2e', MAX_ITER, abs_err);
end

% -----------------------------
% Slack power (positive injection supplying network)
% I0 = Y00*V0 + Y0L*VL
% S0 = diag(V0) * conj(I0)
% Here we return S_slack as injection into the network => negative of "load convention"
% -----------------------------
I0 = Y00 * V0 + Y0L * Vk1;
S_slack = -diag(V0) * conj(I0);

% -----------------------------
% Combine voltages for branch current mapping
% -----------------------------
V_all = [V0; Vk1];

% -----------------------------
% Branch currents
% -----------------------------
Ibr = voltageToBranchCurrent_pu * V_all;

% Optional: clamp tiny currents for numerical cleanliness
tiny = 1e-14;
Ibr(abs(Ibr) < tiny) = 0;

% Return load-node voltages only (all phases, all non-slack nodes)
Vk_load = Vk1;

end