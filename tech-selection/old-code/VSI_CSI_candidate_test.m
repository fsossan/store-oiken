% VSI_CSI_candidate_test.m
% -------------------------------------------------------------------------
% Reads from workspace populated by main_script.m after CVX solve
% Computes both VSI (voltage) and CSI (current) sensitivity indices
% -------------------------------------------------------------------------

fprintf('\n========== VSI + CSI CANDIDATE TEST: %s ==========\n', net_id);

% -------------------------------------------------------------------------
%  STEP 1 — compute VSI from dVmagdP, dVmagdQ
%  and CSI from dImagdP, dImagdQ
%  both are (T*N x T*Nd) — node n occupies columns (n-1)*T+1 : n*T
% -------------------------------------------------------------------------
VSI_P = zeros(1, Nd);
VSI_Q = zeros(1, Nd);
CSI_P = zeros(1, Nd);
CSI_Q = zeros(1, Nd);

for n = 1:Nd
    col_idx  = (n-1)*T + (1:T);
    VSI_P(n) = sum(sum(abs(dVmagdP(:, col_idx))));
    VSI_Q(n) = sum(sum(abs(dVmagdQ(:, col_idx))));
    CSI_P(n) = sum(sum(abs(dImagdP(:, col_idx))));
    CSI_Q(n) = sum(sum(abs(dImagdQ(:, col_idx))));
end

VSI = VSI_P + VSI_Q;   % voltage sensitivity index
CSI = CSI_P + CSI_Q;   % current sensitivity index

% normalize both to [0,1] for combined index
VSI_norm = VSI / max(VSI);
CSI_norm = CSI / max(CSI);

% combined index — equal weight, can be tuned
alpha = 0.5;
VCSI  = alpha * VSI_norm + (1 - alpha) * CSI_norm;

% rank each independently
[~, VSI_rank]  = sort(VSI,  'descend');
[~, CSI_rank]  = sort(CSI,  'descend');
[~, VCSI_rank] = sort(VCSI, 'descend');

% -------------------------------------------------------------------------
%  STEP 2 — where did BESS get installed
% -------------------------------------------------------------------------
I_full    = full(I);
installed = find(I_full > 0.5);
E_full    = full(E_nom);
S_full    = full(S_conv);

% -------------------------------------------------------------------------
%  STEP 3 — print scores per node
% -------------------------------------------------------------------------
fprintf('\n%-6s  %-10s  %-6s  %-10s  %-6s  %-10s  %-6s  %-8s\n', ...
    'Node', 'VSI', 'Vrank', 'CSI', 'Crank', 'VCSI', 'VCrank', 'BESS');
fprintf('%s\n', repmat('-', 1, 70));
for i = 1:Nd
    is_inst = any(installed == i);
    marker  = '';
    if is_inst; marker = ' <==='; end
    fprintf('%-6d  %-10.2f  %-6d  %-10.2f  %-6d  %-10.4f  %-6d  %-8s%s\n', ...
        i, VSI(i), find(VSI_rank==i), ...
        CSI(i), find(CSI_rank==i), ...
        VCSI(i), find(VCSI_rank==i), ...
        mat2str(is_inst), marker);
end

% -------------------------------------------------------------------------
%  STEP 4 — rank of installed node under each metric
% -------------------------------------------------------------------------
if ~isempty(installed)
    fprintf('\nInstalled node(s) rank under each metric:\n');
    for idx = installed'
        fprintf('  Node %d — VSI rank=%d  CSI rank=%d  VCSI rank=%d\n', ...
            idx, find(VSI_rank==idx), find(CSI_rank==idx), find(VCSI_rank==idx));
    end
end

% -------------------------------------------------------------------------
%  STEP 5 — top-k coverage under each metric
% -------------------------------------------------------------------------
fprintf('\nTop-k coverage (does top-k contain the optimal node?):\n');
fprintf('  %-4s  %-8s  %-8s  %-8s\n', 'k', 'VSI', 'CSI', 'VCSI');
fprintf('  %s\n', repmat('-', 1, 32));
for k = 1:Nd
    cov_VSI  = all(ismember(installed, VSI_rank(1:k)));
    cov_CSI  = all(ismember(installed, CSI_rank(1:k)));
    cov_VCSI = all(ismember(installed, VCSI_rank(1:k)));
    fprintf('  %-4d  %-8d  %-8d  %-8d\n', k, cov_VSI, cov_CSI, cov_VCSI);
end

% -------------------------------------------------------------------------
%  STEP 6 — save
% -------------------------------------------------------------------------
VSI_CSI_result.net_id        = net_id;
VSI_CSI_result.VSI           = VSI;
VSI_CSI_result.CSI           = CSI;
VSI_CSI_result.VCSI          = VCSI;
VSI_CSI_result.VSI_rank      = VSI_rank;
VSI_CSI_result.CSI_rank      = CSI_rank;
VSI_CSI_result.VCSI_rank     = VCSI_rank;
VSI_CSI_result.installed     = installed;
VSI_CSI_result.cost          = cvx_optval;
VSI_CSI_result.E_nom_kWh     = sum(E_full(:)) * 100 * 3;
VSI_CSI_result.S_conv_kVA    = sum(S_full(:)) * 100 * 3;
VSI_CSI_result.Vmin          = min(full(vmag));

for k = 1:Nd
    VSI_CSI_result.cov_VSI(k)  = all(ismember(installed, VSI_rank(1:k)));
    VSI_CSI_result.cov_CSI(k)  = all(ismember(installed, CSI_rank(1:k)));
    VSI_CSI_result.cov_VCSI(k) = all(ismember(installed, VCSI_rank(1:k)));
end

save(fullfile('output', sprintf('VSI_CSI_result_%s.mat', net_id)), 'VSI_CSI_result');
fprintf('\nSaved VSI_CSI_result_%s.mat\n', net_id);