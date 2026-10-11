function transformer_parameter_analysis(T)
% TRANSFORMER_PARAMETER_ANALYSIS
%   Validates transformer R/X parameters, recovers Uk% and Psc from
%   existing data, imputes missing R and X for types with no valid pairs,
%   saves a fill table, and generates markdown and diagnostic figure.
%
%   Input:
%     T   — transformer_data table with columns:
%             substation_ID, transformer_ID, R_pu, X_pu, kVA, HV_kV, LV_kV
%
%   Outputs :
%     output/transformer_fill_table.mat
%     sanity-check-website/docs/Transformer_summary.md
%     sanity-check-website/docs/Transformer_details.md
%     sanity-check-website/docs/transformer_analysis.png
%
% CONVENTION:
%   R=0 or NaN treated as missing.
%   For types with valid R/X pairs: fill = mean of valid entries.
%   For types with no valid R/X pairs: R imputed from R_pu interpolation,
%   X corrected from Uk% (recovered from X-only entries where R=0).

kVA_vals = unique(T.kVA);
kVA_vals = kVA_vals(~isnan(kVA_vals));

% -------------------------------------------------------------------------
%  Step 1 — Per-type statistics
% -------------------------------------------------------------------------
n_types       = length(kVA_vals);

R_mean_all    = nan(n_types, 1);
R_std_all     = nan(n_types, 1);
R_min_all     = nan(n_types, 1);
R_max_all     = nan(n_types, 1);
X_mean_all    = nan(n_types, 1);
X_std_all     = nan(n_types, 1);
N_tot_all     = zeros(n_types, 1);
N_ok_all      = zeros(n_types, 1);
N_zer_all     = zeros(n_types, 1);

for i = 1:n_types
    idx    = T.kVA == kVA_vals(i);
    R_vals = T.R_pu(idx);
    X_vals = T.X_pu(idx);

    N_tot_all(i)  = sum(idx);
    N_ok_all(i)   = sum(R_vals > 0 & ~isnan(R_vals));
    N_zer_all(i)  = sum(R_vals == 0 | isnan(R_vals));

    R_valid = R_vals(R_vals > 0 & ~isnan(R_vals));
    X_valid = X_vals(~isnan(X_vals));

    if ~isempty(R_valid)
        R_mean_all(i) = mean(R_valid);
        R_std_all(i)  = std(R_valid);
        R_min_all(i)  = min(R_valid);
        R_max_all(i)  = max(R_valid);
    end
    if ~isempty(X_valid)
        X_mean_all(i) = mean(X_valid, 'omitnan');
        X_std_all(i)  = std(X_valid,  'omitnan');
    end
end

% -------------------------------------------------------------------------
%  Step 2 — Recover Uk% and Psc from valid R/X pairs
% -------------------------------------------------------------------------
kVA_known   = [];
Psc_known   = [];
Uk_known    = [];
kVA_no_pairs = [];

for i = 1:n_types
    idx    = T.kVA == kVA_vals(i);
    kva    = kVA_vals(i);
    R_vals = T.R_pu(idx);
    X_vals = T.X_pu(idx);

    valid = R_vals > 0 & ~isnan(R_vals) & ~isnan(X_vals);
    if sum(valid) == 0
        kVA_no_pairs(end+1) = kva;
        continue
    end

    R_v = R_vals(valid);
    X_v = X_vals(valid);
    Zsc = sqrt(R_v.^2 + X_v.^2);

    kVA_known(end+1)  = kva;
    Psc_known(end+1)  = mean(R_v * (kva * 1000));
    Uk_known(end+1)   = mean(Zsc * 100);
end

% -------------------------------------------------------------------------
%  Step 3 — Verify Uk% for X-only types
% -------------------------------------------------------------------------
Uk_xonly = nan(length(kVA_no_pairs), 1);
for i = 1:length(kVA_no_pairs)
    kva    = kVA_no_pairs(i);
    idx    = T.kVA == kva;
    X_vals = T.X_pu(idx);
    R_vals = T.R_pu(idx);
    xonly  = (R_vals == 0 | isnan(R_vals)) & X_vals > 0 & ~isnan(X_vals);
    if sum(xonly) > 0
        Uk_xonly(i) = mean(X_vals(xonly)) * 100;
    end
end

% -------------------------------------------------------------------------
%  Step 4 — Interpolate R_pu for missing types
% -------------------------------------------------------------------------
R_pu_known   = Psc_known ./ (kVA_known * 1000);

kVA_imputed  = [];
R_imputed    = [];
X_imputed    = [];
Psc_imputed  = [];
Uk_imputed   = [];

for i = 1:length(kVA_no_pairs)
    kva    = kVA_no_pairs(i);
    idx    = T.kVA == kva;
    X_vals = T.X_pu(idx);
    R_vals = T.R_pu(idx);

    xonly = (R_vals == 0 | isnan(R_vals)) & X_vals > 0 & ~isnan(X_vals);
    if sum(xonly) == 0
        continue
    end

    Uk_pct_val = mean(X_vals(xonly)) * 100;
    Zsc_pu     = Uk_pct_val / 100;

    % Interpolate R_pu with range guards
    if kva < min(kVA_known)
        R_pu_interp = interp1(kVA_known, R_pu_known, kva, 'nearest', 'extrap');
    elseif kva > max(kVA_known)
        R_pu_interp = R_pu_known(end);
    else
        R_pu_interp = interp1(kVA_known, R_pu_known, kva, 'linear');
    end

    X_pu_corrected = sqrt(max(Zsc_pu^2 - R_pu_interp^2, 0));
    Psc_val        = R_pu_interp * (kva * 1000);

    kVA_imputed(end+1)  = kva;
    R_imputed(end+1)    = R_pu_interp;
    X_imputed(end+1)    = X_pu_corrected;
    Psc_imputed(end+1)  = Psc_val;
    Uk_imputed(end+1)   = Uk_pct_val;
end

% -------------------------------------------------------------------------
%  Build fill table (all 27 types)
% -------------------------------------------------------------------------
fill_kVA    = [];
fill_R      = [];
fill_X      = [];
fill_Uk     = [];
fill_Psc    = [];
fill_source = {};

% Known types — use mean of valid entries
for i = 1:length(kVA_known)
    kva    = kVA_known(i);
    idx    = T.kVA == kva;
    R_vals = T.R_pu(idx);
    X_vals = T.X_pu(idx);
    R_valid = R_vals(R_vals > 0 & ~isnan(R_vals));
    X_valid = X_vals(~isnan(X_vals));

    Zsc = sqrt(mean(R_valid)^2 + mean(X_valid)^2);

    fill_kVA(end+1)    = kva;
    fill_R(end+1)      = mean(R_valid);
    fill_X(end+1)      = mean(X_valid);
    fill_Uk(end+1)     = Zsc * 100;
    fill_Psc(end+1)    = mean(R_valid) * (kva * 1000);
    fill_source{end+1} = 'measured_mean';
end

% Imputed types
for i = 1:length(kVA_imputed)
    fill_kVA(end+1)    = kVA_imputed(i);
    fill_R(end+1)      = R_imputed(i);
    fill_X(end+1)      = X_imputed(i);
    fill_Uk(end+1)     = Uk_imputed(i);
    fill_Psc(end+1)    = Psc_imputed(i);
    fill_source{end+1} = 'imputed';
end

% Sort by kVA
[fill_kVA_s, sort_idx] = sort(fill_kVA);
fill_R_s      = fill_R(sort_idx);
fill_X_s      = fill_X(sort_idx);
fill_Uk_s     = fill_Uk(sort_idx);
fill_Psc_s    = fill_Psc(sort_idx);
fill_source_s = fill_source(sort_idx);

transformer_fill_table = table(fill_kVA_s', fill_R_s', fill_X_s', ...
    fill_Uk_s', fill_Psc_s', fill_source_s', ...
    'VariableNames', {'kVA','R_pu_fill','X_pu_fill','Uk_pct','Psc_W','source'});

save(fullfile('output', 'transformer_fill_table.mat'), 'transformer_fill_table');

% -------------------------------------------------------------------------
%  Figure — diagnostic plots
% -------------------------------------------------------------------------
R_pu_known_mean = arrayfun(@(k) mean(T.R_pu(T.kVA == k & T.R_pu > 0)), kVA_known);
RX_known        = arrayfun(@(k) ...
    mean(T.R_pu(T.kVA == k & T.R_pu > 0)) / ...
    mean(T.X_pu(T.kVA == k & ~isnan(T.X_pu))), kVA_known);

fig = figure('Visible', 'off');

% 1 — Uk% vs kVA
subplot(2,3,1);
plot(kVA_known, Uk_known, 'bo-', 'LineWidth', 1.5); hold on;
plot(kVA_imputed, Uk_imputed, 'r^--', 'LineWidth', 1.5);
yline(4, 'k:', '4%', 'LabelHorizontalAlignment', 'left');
yline(6, 'k--', '6%', 'LabelHorizontalAlignment', 'left');
xlabel('kVA'); ylabel('Uk% (%)');
title('Uk% vs kVA');
legend('Known','Imputed','Location','best');
grid on;

% 2 — Psc vs kVA
subplot(2,3,2);
plot(kVA_known,   Psc_known,   'bo-', 'LineWidth', 1.5, 'DisplayName', 'Known'); hold on;
plot(kVA_imputed, Psc_imputed, 'r^--','LineWidth', 1.5, 'DisplayName', 'Imputed');
xlabel('kVA'); ylabel('Psc (W)');
title('Psc vs kVA');
legend('Location','best');
grid on;

% 3 — R p.u. vs kVA
subplot(2,3,3);
plot(kVA_known,   R_pu_known_mean, 'bo-', 'LineWidth', 1.5, 'DisplayName', 'Known'); hold on;
plot(kVA_imputed, R_imputed,       'r^--','LineWidth', 1.5, 'DisplayName', 'Imputed');
xlabel('kVA'); ylabel('R (p.u.)');
title('R p.u. vs kVA');
legend('Location','best');
grid on;

% 4 — R/X ratio vs kVA
subplot(2,3,4);
plot(kVA_known,   RX_known,             'bo-', 'LineWidth', 1.5, 'DisplayName', 'Known'); hold on;
plot(kVA_imputed, R_imputed./X_imputed, 'r^--','LineWidth', 1.5, 'DisplayName', 'Imputed');
xlabel('kVA'); ylabel('R/X (-)');
title('R/X ratio vs kVA');
legend('Location','best');
grid on;

% 5 — N_ok vs N_zer per kVA type (bar)
subplot(2,3,5);
bar(1:n_types, [N_ok_all, N_zer_all], 'stacked');
set(gca, 'XTick', 1:n_types, 'XTickLabel', arrayfun(@num2str, kVA_vals, 'UniformOutput', false));
xtickangle(45);
xlabel('kVA');ylabel('Count');
title('Valid vs Missing R per kVA type');
legend('Valid','Missing','Location','best');
grid on;

% 6 — CoV of R per known type
CoV_R = nan(length(kVA_known), 1);
for i = 1:length(kVA_known)
    R_v = T.R_pu(T.kVA == kVA_known(i) & T.R_pu > 0);
    if numel(R_v) >= 2 && mean(R_v) > 0
        CoV_R(i) = (std(R_v) / mean(R_v)) * 100;
    end
end
subplot(2,3,6);
bar(CoV_R, 'FaceColor', [0.2 0.6 0.8]);
set(gca, 'XTick', 1:length(kVA_known), ...
    'XTickLabel', arrayfun(@num2str, kVA_known, 'UniformOutput', false));
xtickangle(45);
% yline(20, 'r--', '20% threshold', 'LabelHorizontalAlignment', 'left');
xlabel('kVA');ylabel('CoV R (%)');
title('Coefficient of Variation of R — known types');
grid on;

sgtitle('Transformer Parameter Analysis', 'FontWeight', 'bold', 'Interpreter', 'none');

saveas(fig, fullfile('sanity-check-website', 'docs', 'transformer_analysis.png'));
close(fig);

% -------------------------------------------------------------------------
%  Markdown
% -------------------------------------------------------------------------
 md_transformer(transformer_fill_table, T, kVA_known, kVA_imputed, ...
    N_tot_all, N_ok_all, N_zer_all, R_mean_all, R_std_all, ...
    X_mean_all, Uk_known, Psc_known, kVA_vals);

end