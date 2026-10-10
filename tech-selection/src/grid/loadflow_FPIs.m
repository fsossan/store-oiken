function [ Vk1, I, S, converged, num_iter ] = loadflow_FPIs(Y, V0, Swye, n_phases, voltageToBranchCurrent_pu, YLLi)
%POWER_FLOW Computes voltage magnitude at the nodes as a function of the
%power injections with fixed point iterations Z-bus impedance.
%   Y : Admittance matrix
%   V0 : Voltage at the slack
%   Swye : apparent power of wye-connected loads
%   SDelta : apparent power of delta-connected loads
%   YLLi : (optional) precomputed inv(Y(n_phases+1:end, n_phases+1:end)).
%          YLL depends only on Y, so callers that run this in a per-timestep
%          loop should compute it once and pass it in. Omitted/[] -> inv(YLL).
%   converged : (output) true if max|Vk1-Vk| dropped below TOL_ABS within
%          N_OF_ITER iterations. Tracked only -- the loop still always runs
%          the full N_OF_ITER passes exactly as before this output was
%          added, so Vk1/I/S are byte-identical to the pre-tracking
%          behavior. See loadflow_FPIs_convergance.m for an adaptive/damped
%          variant that stops early and handles divergence -- not merged in
%          here, since doing so would also need to preserve the YLLi-reuse
%          optimization that variant currently lacks.
%   num_iter  : (output) iteration index at which convergence was first
%          reached, or N_OF_ITER+1 as a "did not converge within budget"
%          sentinel (kept numeric, not NaN, so callers can e.g. take max()
%          across timesteps without special-casing).
% All quantities are in per unit of the respective base.

N_OF_ITER = 20;
TOL_ABS   = 1e-5;   % p.u., matches loadflow_FPIs_convergance's default

YLL = Y(n_phases+1:end, n_phases+1:end);
Y00 = Y(1:n_phases, 1:n_phases);
Y0L = Y(1:n_phases, n_phases+1:end);
YL0 = Y(n_phases+1:end,1:n_phases);
if nargin < 6 || isempty(YLLi)
    YLLi = inv(YLL);
end


% zero-load grid voltage
w = -YLLi*YL0*V0;

% Fixed-point iterations
Viter = [w];
err_hist = [];   % renamed from "error", which shadowed the built-in
Vk = w;
converged = false;
num_iter  = N_OF_ITER + 1;   % sentinel: "did not converge within budget"
% Solve iteratively
Vlin = w + YLLi*(inv(diag(conj(Vk)))*conj(Swye));% + H.'*inv(diag(H*conj(Vk)))*conj(Sdelta));
for ii = 1:N_OF_ITER
    % Eq. (4), solved iteratively
    Vk1 = w + YLLi*(inv(diag(conj(Vk)))*conj(Swye)); % + H.'*inv(diag(H*conj(Vk)))*conj(Sdelta));
    Viter = [Viter Vk1];
    err_hist = [err_hist sum(abs(Vk1-Vk))]; %#ok<AGROW>
    if ~converged && max(abs(Vk1 - Vk)) < TOL_ABS
        converged = true;
        num_iter  = ii;
    end
    Vk = Vk1;
end

% Apparent power at node 0
%S = diag(V0)*( conj(Y00) + conj(Y0L)*conj(Vk) );
S = diag(V0) * conj(Y00 * V0 + Y0L*Vk); 
% S = - S;

Vk = [V0; Vk]; %Commented out this line
Vk1=Vk(2:end);
% Branch current
% Define a custom threshold for small values
threshold = 1e-12;
I = voltageToBranchCurrent_pu * Vk;
 % Replace values in I that are smaller than the custom threshold with eps
I_modified = I;
I_modified(abs(I) < threshold) = eps;
I=I_modified;
% B=0.001+0.0001i;
% I(8,:)=B;
end
