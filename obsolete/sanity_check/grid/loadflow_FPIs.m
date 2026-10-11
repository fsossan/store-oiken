function [ Vk1, I, S ] = loadflow_FPIs(Y, V0, Swye, n_phases, voltageToBranchCurrent_pu)
%POWER_FLOW Computes voltage magnitude at the nodes as a function of the
%power injections with fixed point iterations Z-bus impedance.
%   Y : Admittance matrix
%   V0 : Voltage at the slack
%   Swye : apparent power of wye-connected loads
%   SDelta : apparent power of delta-connected loads
% All quantities are in per unit of the respective base.

N_OF_ITER = 20;

n_of_nodes = size(Y, 1)/n_phases;

G = [1 -1 0; 0 1 -1; -1 0 1];
G = G(1:n_phases,1:n_phases); %so that single phase G = [1]
H = [];
for ii = 1:n_of_nodes-1
    H = blkdiag(H,G);
end


YLL = Y(n_phases+1:end, n_phases+1:end);
Y00 = Y(1:n_phases, 1:n_phases);
Y0L = Y(1:n_phases, n_phases+1:end);
YL0 = Y(n_phases+1:end,1:n_phases);
YLLi = inv(YLL);


% zero-load grid voltage
w = -YLLi*YL0*V0;

% Fixed-point iterations
Viter = [w];
error = [];
Vk = w;
% Solve iteratively
Vlin = w + YLLi*(inv(diag(conj(Vk)))*conj(Swye));% + H.'*inv(diag(H*conj(Vk)))*conj(Sdelta));
for ii = 1:N_OF_ITER
    % Eq. (4), solved iteratively
    Vk1 = w + YLLi*(inv(diag(conj(Vk)))*conj(Swye)); % + H.'*inv(diag(H*conj(Vk)))*conj(Sdelta));
    Viter = [Viter Vk1];
    error = [error sum(abs(Vk1-Vk))];
    Vk = Vk1;
end

% Apparent power at node 0
%S = diag(V0)*( conj(Y00) + conj(Y0L)*conj(Vk) );
S = diag(V0) * conj(Y00 * V0 + Y0L*Vk); 
S = - S;

Vk = [V0; Vk]; %Commented out this line
Vk1=Vk(2:end);
% Branch current
% Define a custom threshold for small values
threshold = 1e-14;
I = voltageToBranchCurrent_pu * Vk;
% Replace values in I that are smaller than the custom threshold with eps
I_modified = I;
I_modified(abs(I) < threshold) = eps;
I=I_modified;
%B=0.001+0.0001i;
%I(8,:)=B;
end
