function analyze_CDF(vmag, V_lf, Imag, I_lf)
% ANALYZE_CDF Compute and plot empirical CDFs for voltage and current errors
%
% Usage:
%   analyze_CDF(vmag, V_lf, Imag, I_lf)
%
% Inputs:
%   vmag - Linearized OPF voltage magnitudes (N×1, pu)
%   V_lf - Nonlinear loadflow voltages for the same injections (N×1, pu)
%   Imag - Linearized OPF line currents (L×1, pu)
%   I_lf - Nonlinear loadflow line currents for the same injections (L×1, pu)
%
% Outputs:
%   Plots and printed summary statistics for both voltage and current errors.

    %% --- Voltage error analysis ---
    v_err = vmag(:) - V_lf(:);
    abs_v_err = abs(v_err);
    N_v = numel(v_err);

    % Empirical CDF (absolute)
    [sorted_abs_v_err, ~] = sort(abs_v_err);
    cdf_v_abs = (1:N_v)' / N_v;

    % Plot absolute voltage error CDF
    % figure;
    % plot(sorted_abs_v_err, cdf_v_abs, 'LineWidth', 1.5);
    % xlabel('Absolute nodal voltage error (pu)');
    % ylabel('CDF');
    % grid on;
    % title('CDF of absolute nodal voltage error');

    % --- Voltage stats ---
    stats_v = compute_stats(v_err, abs_v_err);
    fprintf('\n=== Voltage Error Statistics ===\n');
    display_stats(stats_v);

    %% --- Current error analysis ---
    i_err = Imag(:) - I_lf(:);
    abs_i_err = abs(i_err);
    N_i = numel(i_err);

    % Empirical CDF (absolute)
    [sorted_abs_i_err, ~] = sort(abs_i_err);
    cdf_i_abs = (1:N_i)' / N_i;

    % Plot absolute current error CDF
    % figure;
    % plot(sorted_abs_i_err, cdf_i_abs, 'LineWidth', 1.5);
    % xlabel('Absolute line current error (pu)');
    % ylabel('CDF');
    % grid on;
    % title('CDF of absolute line current error');

    % --- Current stats ---
    stats_i = compute_stats(i_err, abs_i_err);
    fprintf('\n=== Current Error Statistics ===\n');
    display_stats(stats_i);

    %% --- Combined comparison plot ---
    % figure;
    % plot(sorted_abs_v_err, cdf_v_abs, 'LineWidth', 1.5);
    % hold on;
    % plot(sorted_abs_i_err, cdf_i_abs, 'LineWidth', 1.5);
    % grid on;
    % xlabel('Absolute error (pu)');
    % ylabel('CDF');
    % legend('Voltage magnitude error', 'Line current error', 'Location', 'best');
    % title('Comparison of voltage and current CDFs');
end


%% --- Helper: compute stats ---
function stats = compute_stats(err, abs_err)
    stats.max_abs = max(abs_err);
    stats.mean_signed = mean(err);
    stats.std_signed = std(err);
    stats.p90 = prctile(abs_err, 90);
    stats.p99 = prctile(abs_err, 99);
end

%% --- Helper: display stats nicely ---
function display_stats(stats)
    fprintf('Max abs error: %.4e pu\n', stats.max_abs);
    fprintf('Mean signed error: %.4e pu\n', stats.mean_signed);
    fprintf('Std signed error: %.4e pu\n', stats.std_signed);
    fprintf('90th percentile abs error: %.4e pu\n', stats.p90);
    fprintf('99th percentile abs error: %.4e pu\n', stats.p99);
end