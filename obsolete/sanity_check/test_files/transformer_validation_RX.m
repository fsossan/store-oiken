% transformer_RX_validation.m
% -------------------------------------------------------------------------
% Validates transformer R and X p.u. values per kVA rating.
% Reads table T with columns: kVA, R_pu, X_pu
%
% Checks:
%   1. Count of valid / zero / NaN entries per type
%   2. Mean, std, min, max of R and X for valid entries
%   3. R/X ratio sanity check (expected 0.10 - 0.30 for LV transformers)
%   4. Flags types with high R variance (std/mean > 0.2)
%   5. Comparison against IEC 60076 typical short-circuit voltage (Uk%)
%      and copper loss (Psc) reference values
% -------------------------------------------------------------------------
clc 
close all
clear

load('Transformers_RX_data.mat')

kVA_vals = unique(T.kVA);
kVA_vals = kVA_vals(~isnan(kVA_vals));

% IEC 60076 typical reference values (approximate, for cross-check)
% Source: EN 60076-1, distribution transformer typical values
% Uk% ~ short-circuit voltage percentage -> Z_sc(p.u.) = Uk/100
% Psc (W) -> R_sc(p.u.) = Psc / (S_kVA * 1000)
% These are indicative only — actual values vary by manufacturer
IEC_ref = [
%  kVA    Uk%   Psc_W
    50,   4.0,   875;
   100,   4.0,  1475;
   160,   4.0,  2000;
   200,   4.0,  2350;
   250,   4.0,  2750;
   315,   4.0,  3250;
   400,   4.0,  3850;
   500,   4.0,  4600;
   630,   4.0,  5400;
   800,   6.0,  7000;
  1000,   6.0,  8400;
  1250,   6.0,  9700;
];
IEC_kVA  = IEC_ref(:,1);
IEC_Uk   = IEC_ref(:,2);
IEC_Psc  = IEC_ref(:,3);
IEC_Z    = IEC_Uk  / 100;
IEC_R    = IEC_Psc ./ (IEC_kVA * 1000);   % R = Psc / S_rated
IEC_X    = sqrt(IEC_Z.^2 - IEC_R.^2);

% -------------------------------------------------------------------------
% Header
% -------------------------------------------------------------------------
fprintf('\n');
fprintf('%-8s  %-6s  %-6s  %-6s  %-8s  %-8s  %-8s  %-8s  %-8s  %-8s  %-6s  %-8s  %-8s\n', ...
    'kVA', 'N_tot', 'N_ok', 'N_zer', 'R_mean', 'R_std', 'R_min', 'R_max', ...
    'X_mean', 'X_std', 'R/X', 'IEC_R', 'IEC_X');
fprintf('%s\n', repmat('-', 1, 120));

% -------------------------------------------------------------------------
% Per kVA type
% -------------------------------------------------------------------------
warn_high_var  = {};
warn_RX_ratio  = {};
warn_IEC_dev   = {};

for i = 1:length(kVA_vals)
    kva = kVA_vals(i);
    idx = T.kVA == kva;

    R_all = T.R_pu(idx);
    X_all = T.X_pu(idx);
    n_tot = sum(idx);

    % Separate valid / zero / NaN
    n_nan_R  = sum(isnan(R_all));
    n_zero_R = sum(R_all == 0 & ~isnan(R_all));
    n_ok_R   = sum(R_all > 0  & ~isnan(R_all));

    R_valid  = R_all(R_all > 0 & ~isnan(R_all));
    X_valid  = X_all(~isnan(X_all));

    % Stats
    if n_ok_R >= 1
        R_mean = mean(R_valid);
        R_std  = std(R_valid);
        R_min  = min(R_valid);
        R_max  = max(R_valid);
    else
        R_mean = NaN; R_std = NaN; R_min = NaN; R_max = NaN;
    end

    if ~isempty(X_valid)
        X_mean = mean(X_valid);
        X_std  = std(X_valid);
    else
        X_mean = NaN; X_std = NaN;
    end

    % R/X ratio
    if ~isnan(R_mean) && ~isnan(X_mean) && X_mean > 0
        RX = R_mean / X_mean;
    else
        RX = NaN;
    end

    % IEC reference lookup
    iec_idx = find(IEC_kVA == kva, 1);
    if ~isempty(iec_idx)
        iec_R = IEC_R(iec_idx);
        iec_X = IEC_X(iec_idx);
    else
        iec_R = NaN;
        iec_X = NaN;
    end

    % Print row
    fprintf('%-8g  %-6d  %-6d  %-6d  %-8.4f  %-8.4f  %-8.4f  %-8.4f  %-8.4f  %-8.4f  %-6.3f  %-8.4f  %-8.4f\n', ...
        kva, n_tot, n_ok_R, n_zero_R + n_nan_R, ...
        R_mean, R_std, R_min, R_max, ...
        X_mean, X_std, RX, iec_R, iec_X);

    % --- Warnings ---
    % High R variance: std/mean > 0.2
    if n_ok_R >= 2 && ~isnan(R_mean) && R_mean > 0 && (R_std/R_mean) > 0.2
        warn_high_var{end+1} = sprintf('  kVA=%-6g  R_std/R_mean=%.3f  (high variance)', ...
            kva, R_std/R_mean);
    end

    % R/X ratio out of [0.10, 0.30]
    if ~isnan(RX) && (RX < 0.10 || RX > 0.30)
        warn_RX_ratio{end+1} = sprintf('  kVA=%-6g  R/X=%.3f  (expected 0.10-0.30)', kva, RX);
    end

    % IEC deviation > 30%
    if ~isnan(R_mean) && ~isnan(iec_R) && iec_R > 0
        dev = abs(R_mean - iec_R) / iec_R;
        if dev > 0.30
            warn_IEC_dev{end+1} = sprintf('  kVA=%-6g  R_data=%.4f  IEC_R=%.4f  dev=%.1f%%', ...
                kva, R_mean, iec_R, dev*100);
        end
    end
end

% -------------------------------------------------------------------------
% Warning summary
% -------------------------------------------------------------------------
fprintf('\n=== WARNINGS ===\n');

if ~isempty(warn_high_var)
    fprintf('\n[High R variance — std/mean > 20%%]\n');
    for w = warn_high_var; fprintf('%s\n', w{1}); end
else
    fprintf('\n[High R variance] None\n');
end

if ~isempty(warn_RX_ratio)
    fprintf('\n[R/X ratio outside 0.10-0.30]\n');
    for w = warn_RX_ratio; fprintf('%s\n', w{1}); end
else
    fprintf('\n[R/X ratio] All within expected range\n');
end

if ~isempty(warn_IEC_dev)
    fprintf('\n[IEC 60076 deviation > 30%%]\n');
    for w = warn_IEC_dev; fprintf('%s\n', w{1}); end
else
    fprintf('\n[IEC 60076 deviation] All within 30%% of reference\n');
end

fprintf('\n=== END VALIDATION ===\n\n');