% VSI_candidate_test.m
fprintf('\n========== VSI CANDIDATE TEST: %s ==========\n', net_id);

% -------------------------------------------------------------------------
%  STEP 1 — compute VSI correctly from time-expanded sensitivity matrices
%  dVmagdP is (T*N x T*Nd) — each node n occupies columns (n-1)*T+1 : n*T
% -------------------------------------------------------------------------
VSI_P = zeros(1, Nd);
VSI_Q = zeros(1, Nd);
for n = 1:Nd
    col_idx    = (n-1)*T + (1:T);
    VSI_P(n)   = sum(sum(abs(dVmagdP(:, col_idx))));
    VSI_Q(n)   = sum(sum(abs(dVmagdQ(:, col_idx))));
end
VSI = VSI_P + VSI_Q;   % 1 x Nd — one score per demand node

[VSI_sorted, VSI_rank] = sort(VSI, 'descend');

fprintf('\nVSI scores per demand node:\n');
for i = 1:Nd
    fprintf('  Demand node %d — VSI_P = %.6f  VSI_Q = %.6f  VSI = %.6f  rank = %d\n', ...
        i, VSI_P(i), VSI_Q(i), VSI(i), find(VSI_rank == i));
end

% -------------------------------------------------------------------------
%  STEP 2 — where did BESS get installed
% -------------------------------------------------------------------------
I_full    = full(I);
installed = find(I_full > 1e-4);
E_full    = full(E_nom);
S_full    = full(S_conv);

fprintf('\nFull OPF result (unconstrained):\n');
fprintf('  BESS installed at demand node(s): %s\n', num2str(installed'));
fprintf('  E_nom  = %.2f kWh\n', sum(E_full(:)) * 100 * 3);
fprintf('  S_conv = %.2f kVA\n', sum(S_full(:)) * 100 * 3);
fprintf('  Cost   = %.4f\n',     cvx_optval);
fprintf('  Vmin   = %.4f pu\n',  min(full(vmag)));

% -------------------------------------------------------------------------
%  STEP 3 — VSI rank of the optimal node
% -------------------------------------------------------------------------
if ~isempty(installed)
    fprintf('\nVSI rank of installed node(s):\n');
    for idx = installed'
        rank_of_optimal = find(VSI_rank == idx);
        fprintf('  Demand node %d — VSI = %.6f  rank = %d / %d\n', ...
            idx, VSI(idx), rank_of_optimal, Nd);
    end
end

% -------------------------------------------------------------------------
%  STEP 4 — top-k coverage for all k
% -------------------------------------------------------------------------
fprintf('\nTop-k coverage check:\n');
fprintf('  %-6s  %-30s  %-15s  %-10s\n', 'k', 'candidates', 'covers optimal', 'VSI scores');
for k = 1:Nd
    top_k      = VSI_rank(1:k);
    covers_opt = all(ismember(installed, top_k));
    fprintf('  k=%-4d  nodes=%-25s  covers=%d  scores=%s\n', ...
        k, num2str(top_k), covers_opt, num2str(VSI(top_k), '%.4f '));
end

% -------------------------------------------------------------------------
%  STEP 5 — comparison summary table
% -------------------------------------------------------------------------
fprintf('\n--- SUMMARY TABLE ---\n');
fprintf('  %-15s  %-10s  %-10s  %-8s\n', 'Demand node', 'VSI score', 'VSI rank', 'BESS here');
for i = 1:Nd
    is_installed = any(installed == i);
    fprintf('  %-15d  %-10.6f  %-10d  %-8s\n', ...
        i, VSI(i), find(VSI_rank == i), mat2str(is_installed));
end

% -------------------------------------------------------------------------
%  STEP 6 — save
% -------------------------------------------------------------------------
VSI_result.net_id                  = net_id;
VSI_result.VSI_P                   = VSI_P;
VSI_result.VSI_Q                   = VSI_Q;
VSI_result.VSI                     = VSI;
VSI_result.VSI_rank                = VSI_rank;
VSI_result.installed_nodes         = installed;
VSI_result.cost_full               = cvx_optval;
VSI_result.E_nom_kWh               = sum(E_full(:)) * 100 * 3;
VSI_result.S_conv_kVA              = sum(S_full(:)) * 100 * 3;
VSI_result.Vmin_full               = min(full(vmag));
VSI_result.top_k_covers_optimal    = false(1, Nd);
for k = 1:Nd
    VSI_result.top_k_covers_optimal(k) = all(ismember(installed, VSI_rank(1:k)));
end

% save(fullfile('output', sprintf('VSI_result_%s.mat', net_id)), 'VSI_result');
% fprintf('\nSaved VSI_result_%s.mat\n', net_id);