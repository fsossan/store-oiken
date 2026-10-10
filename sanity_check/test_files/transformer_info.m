% transformer parameter analysis
addpath(genpath(pwd))
clear
clc
close all

T = load('transformer_data.mat').transformer_data;
R_all = T.R_pu;
X_all = T.X_pu;
R_nan_tot     = sum(isnan(R_all));
X_nan_tot     = sum(isnan(X_all));
R_is0_tot     = sum(R_all == 0);
X_is0_tot     = sum(X_all == 0);
n_unique_tra  = length(unique(T.kVA));
n_total_tra   = length(T.kVA);
fprintf('\n Total nan values for R and X :  %d   %d \n', R_nan_tot, X_nan_tot)
fprintf('\n Total 0 values for R and X   :  %d   %d \n', R_is0_tot, X_is0_tot)
fprintf('\n N total transformers and N total unique transformers : %d    %d \n', n_total_tra, n_unique_tra)

kVA_vals = unique(T.kVA);

fprintf('\n%-10s  %-6s  %-6s  %-6s  %-8s  %-8s  %-8s  %-8s  %-8s  %-8s\n', ...
    'kVA', 'N_tot', 'N_ok', 'N_zer', ...
    'R_mean', 'R_std', 'R_min', 'R_max', ...
    'X_mean', 'X_std');
fprintf('%s\n', repmat('-', 1, 85));

for i = 1:length(kVA_vals)
    idx    = T.kVA == kVA_vals(i);
    n_tot  = sum(idx);

    R_vals = T.R_pu(idx);
    X_vals = T.X_pu(idx);

    n_ok_R  = sum(R_vals > 0 & ~isnan(R_vals));
    n_zer_R = sum(R_vals == 0 | isnan(R_vals));

    R_valid = R_vals(R_vals > 0 & ~isnan(R_vals));
    X_valid = X_vals(~isnan(X_vals));

    if ~isempty(R_valid)
        R_mean = mean(R_valid); R_std = std(R_valid);
        R_min  = min(R_valid);  R_max = max(R_valid);
    else
        R_mean = NaN; R_std = NaN; R_min = NaN; R_max = NaN;
    end

    X_mean = mean(X_valid, 'omitnan');
    X_std  = std(X_valid,  'omitnan');

    fprintf('%-10g  %-6d  %-6d  %-6d  %-8.4f  %-8.4f  %-8.4f  %-8.4f  %-8.4f  %-8.4f\n', ...
        kVA_vals(i), n_tot, n_ok_R, n_zer_R, ...
        R_mean, R_std, R_min, R_max, ...
        X_mean, X_std);
end

%% Step 2 — Recover Uk% and Psc from existing R and X
fprintf('\n%-10s  %-6s  %-6s  %-10s  %-10s  %-10s  %-10s\n', ...
    'kVA', 'N_tot','N_ok', 'Uk%_mean', 'Uk%_std', 'Psc_W_mean', 'Psc_W_std');
fprintf('%s\n', repmat('-', 1, 65));

trans_no_X_R_tot  = 0;
kVA_no_pairs      = [];   % <-- store types with no valid R/X pairs

for i = 1:length(kVA_vals)
    idx    = T.kVA == kVA_vals(i);
    kva    = kVA_vals(i);
    R_vals = T.R_pu(idx);
    X_vals = T.X_pu(idx);

    valid  = R_vals > 0 & ~isnan(R_vals) & ~isnan(X_vals);
    n_ok   = sum(valid);

    if n_ok == 0
        fprintf('%-10g  %-6d  %-6d  [no valid R/X pairs]\n', kva, sum(idx), n_ok);
        trans_no_X_R_tot = trans_no_X_R_tot + sum(idx);
        kVA_no_pairs(end+1) = kva;   % <-- record this type
        continue
    end

    R_v = R_vals(valid);
    X_v = X_vals(valid);

    Zsc    = sqrt(R_v.^2 + X_v.^2);
    Uk_pct = Zsc * 100;
    Psc_W  = R_v * (kva * 1000);

    fprintf('%-10g  %-6d  %-6d  %-10.3f  %-10.3f  %-10.1f  %-10.1f\n', ...
        kva, sum(idx), n_ok, mean(Uk_pct), std(Uk_pct), mean(Psc_W), std(Psc_W));
end
fprintf('Sum of transformers with no pairs of X and R: %-6d\n', trans_no_X_R_tot);

%% Step 3 — Verify X-only entries for types recorded in Step 2
fprintf('\n--- Step 3: X-only entries — types with no valid R/X pairs ---\n');
fprintf('%-10s  %-6s  %-10s  %-10s\n', 'kVA', 'N', 'Uk%_mean', 'Uk%_std');
fprintf('%s\n', repmat('-', 1, 40));

for i = 1:length(kVA_no_pairs)
    kva    = kVA_no_pairs(i);
    idx    = T.kVA == kva;
    X_vals = T.X_pu(idx);
    R_vals = T.R_pu(idx);

    xonly   = (R_vals == 0 | isnan(R_vals)) & X_vals > 0 & ~isnan(X_vals);
    n_xonly = sum(xonly);

    if n_xonly == 0
        fprintf('%-10g  %-6d  [no X values either]\n', kva, 0);
        continue
    end

    Uk_pct = X_vals(xonly) * 100;
    fprintf('%-10g  %-6d  %-10.3f  %-10.3f\n', ...
        kva, n_xonly, mean(Uk_pct), std(Uk_pct));
end
%% Step 4 — Plot Psc vs kVA for interpolation assessment
% Collect known Psc means from Step 2
kVA_known  = [];
Psc_known  = [];
Uk_known   = [];

for i = 1:length(kVA_vals)
    idx    = T.kVA == kVA_vals(i);
    kva    = kVA_vals(i);
    R_vals = T.R_pu(idx);
    X_vals = T.X_pu(idx);

    valid  = R_vals > 0 & ~isnan(R_vals) & ~isnan(X_vals);
    if sum(valid) == 0; continue; end

    R_v   = R_vals(valid);
    X_v   = X_vals(valid);
    Zsc   = sqrt(R_v.^2 + X_v.^2);

    kVA_known(end+1) = kva;
    Psc_known(end+1) = mean(R_v * (kva * 1000));
    Uk_known(end+1)  = mean(Zsc * 100);
end

figure;
subplot(1,2,1);
plot(kVA_known, Psc_known, 'o-', 'LineWidth', 1.5);
xlabel('kVA'); ylabel('Psc (W)');
title('Psc vs kVA — known types');
grid on;
text(kVA_known, Psc_known, arrayfun(@(x) sprintf('  %g',x), kVA_known, ...
    'UniformOutput', false), 'FontSize', 8);

subplot(1,2,2);
plot(kVA_known, Uk_known, 'o-', 'LineWidth', 1.5);
xlabel('kVA'); ylabel('Uk% (%)');
title('Uk% vs kVA — known types');
grid on;
yline(4, 'r--', '4%');
yline(6, 'b--', '6%');


%% Step 5 — Interpolate R_pu for missing types, compute corrected X
fprintf('\n--- Step 5: Interpolated R and X for missing types ---\n');
fprintf('%-10s  %-6s  %-10s  %-10s  %-10s  %-10s  %-10s\n', ...
    'kVA', 'N', 'Uk%', 'Psc_W', 'R_pu', 'X_pu', 'R/X');
fprintf('%s\n', repmat('-', 1, 70));

kVA_imputed  = [];
R_imputed    = [];
X_imputed    = [];
Psc_imputed  = [];
Uk_imputed   = [];

R_pu_known = Psc_known ./ (kVA_known * 1000);   % compute once outside loop

for i = 1:length(kVA_no_pairs)
    kva    = kVA_no_pairs(i);
    idx    = T.kVA == kva;
    X_vals = T.X_pu(idx);
    R_vals = T.R_pu(idx);

    % Get Uk% from X (since R=0, X = Zsc)
    xonly = (R_vals == 0 | isnan(R_vals)) & X_vals > 0 & ~isnan(X_vals);
    if sum(xonly) == 0
        fprintf('%-10g  %-6d  [no X — skipping]\n', kva, sum(idx));
        continue
    end

    Uk_pct_val = mean(X_vals(xonly)) * 100;   % Uk% from X
    Zsc_pu     = Uk_pct_val / 100;

    % Interpolate R_pu with range guards
    if kva < min(kVA_known)
        % nearest neighbor — below range
        R_pu_interp = interp1(kVA_known, R_pu_known, kva, 'nearest', 'extrap');
        Psc_interp  = R_pu_interp * (kva * 1000);
    elseif kva > max(kVA_known)
        % clamp to last known value — above range
        R_pu_interp = R_pu_known(end);
        Psc_interp  = R_pu_interp * (kva * 1000);
    else
        % linear interpolation within range
        R_pu_interp = interp1(kVA_known, R_pu_known, kva, 'linear');
        Psc_interp  = R_pu_interp * (kva * 1000);
    end

    % Compute corrected X from Uk% and interpolated R
    X_pu = sqrt(max(Zsc_pu^2 - R_pu_interp^2, 0));   % max guards against numerical negative
    R_pu = R_pu_interp;
    RX   = R_pu / X_pu;

    fprintf('%-10g  %-6d  %-10.3f  %-10.1f  %-10.6f  %-10.6f  %-10.4f\n', ...
        kva, sum(idx), Uk_pct_val, Psc_interp, R_pu, X_pu, RX);

    kVA_imputed(end+1)  = kva;
    R_imputed(end+1)    = R_pu;
    X_imputed(end+1)    = X_pu;
    Psc_imputed(end+1)  = Psc_interp;
    Uk_imputed(end+1)   = Uk_pct_val;
end

% --- Diagnostic plot ---
figure;
subplot(1,3,1);
plot(kVA_known,   Psc_known,   'bo-', 'LineWidth', 1.5, 'DisplayName', 'Known'); hold on;
plot(kVA_imputed, Psc_imputed, 'r^--','LineWidth', 1.5, 'DisplayName', 'Imputed');
xlabel('kVA'); ylabel('Psc (W)');
title('Psc — known vs imputed');
legend('Location', 'best'); grid on;

subplot(1,3,2);
R_pu_known_mean = arrayfun(@(i) mean(T.R_pu(T.kVA == kVA_known(i) & T.R_pu > 0)), ...
    1:length(kVA_known));
plot(kVA_known,   R_pu_known_mean, 'bo-', 'LineWidth', 1.5, 'DisplayName', 'Known'); hold on;
plot(kVA_imputed, R_imputed,       'r^--','LineWidth', 1.5, 'DisplayName', 'Imputed');
xlabel('kVA'); ylabel('R (p.u.)');
title('R p.u. — known vs imputed');
legend('Location', 'best'); grid on;

subplot(1,3,3);
RX_known = arrayfun(@(i) mean(T.R_pu(T.kVA == kVA_known(i) & T.R_pu > 0)) / ...
    mean(T.X_pu(T.kVA == kVA_known(i) & ~isnan(T.X_pu))), 1:length(kVA_known));
plot(kVA_known,   RX_known,             'bo-', 'LineWidth', 1.5, 'DisplayName', 'Known'); hold on;
plot(kVA_imputed, R_imputed./X_imputed, 'r^--','LineWidth', 1.5, 'DisplayName', 'Imputed');
xlabel('kVA'); ylabel('R/X (-)');
title('R/X ratio — known vs imputed');
legend('Location', 'best'); grid on;