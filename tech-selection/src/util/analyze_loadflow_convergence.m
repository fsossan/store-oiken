function report = analyze_loadflow_convergence(out, make_plots)
%ANALYZE_LOADFLOW_CONVERGENCE  Report/plot load-flow convergence: base
%                               operating point vs. solved-dispatch
%                               verification.
%
%   report = analyze_loadflow_convergence(out)
%   report = analyze_loadflow_convergence(out, make_plots)   % default true
%
%   Reads out.gm.lm.lf_summary (base operating point, recorded by
%   linear_grid_model) and out.diagnostics.lf_summary (solved-dispatch
%   verification, recorded by OPF_verification via run_seq_lin_loop_ess) --
%   see summarize_lf_convergence for the summary struct shape and
%   loadflow_FPIs for what "converged" means per timestep. Either may be
%   absent on a result saved before this tracking was added; reported as
%   such, not an error.
%
%   The solved-dispatch verification figure is the one that matters most
%   for trusting a result -- it's the actual operating point being
%   reported, not just the base case.
%
%   Console: PASS/WARN per stage, % converged, mean/max iterations used.
%   Figure (if make_plots): iterations-to-converge per timestep for each
%   stage available, failed timesteps marked, iteration cap shown as a
%   reference line.

if nargin < 2 || isempty(make_plots); make_plots = true; end

has_base   = isfield(out, 'gm') && isfield(out.gm, 'lm') && isfield(out.gm.lm, 'lf_summary');
has_solved = isfield(out, 'diagnostics') && isfield(out.diagnostics, 'lf_summary');

net_id = '';
if isfield(out, 'meta') && isfield(out.meta, 'network_id_str')
    net_id = string(out.meta.network_id_str);
elseif isfield(out, 'summary') && isfield(out.summary, 'network_id')
    net_id = string(out.summary.network_id);
end

fprintf('\n=== Load-flow convergence: network %s ===\n', net_id);

report = struct('base', [], 'solved', []);

if has_base
    report.base = out.gm.lm.lf_summary;
    print_stage('Base operating point', report.base);
else
    fprintf('  (base operating point convergence not recorded -- result predates this tracking)\n');
end

if has_solved
    report.solved = out.diagnostics.lf_summary;
    print_stage('Solved-dispatch verification', report.solved);
else
    fprintf('  (solved-dispatch verification convergence not recorded -- result predates this tracking)\n');
end
fprintf('\n');

if make_plots && (has_base || has_solved)
    figure('Name', 'Load-flow Convergence', 'Color', 'w');
    n_panels = has_base + has_solved;
    tiledlayout(n_panels, 1, 'Padding', 'compact', 'TileSpacing', 'compact');

    if has_base
        plot_iter_panel(out.gm.lm.lf_num_iter, out.gm.lm.lf_converged, 'Base operating point');
    end
    if has_solved
        plot_iter_panel(out.diagnostics.lf_num_iter, out.diagnostics.lf_converged, 'Solved-dispatch verification');
    end
    sgtitle(sprintf('Network %s — Load-flow Convergence', strrep(net_id, '_', '\_')), ...
        'FontWeight', 'bold');
end

end

% =========================================================================
function print_stage(label, s)
if s.all_converged
    fprintf('  %-30s PASS -- 100%% converged (T=%d, mean %.1f iter, max %d)\n', ...
        [label ':'], s.n_total, s.mean_iter, s.max_iter);
else
    n_fail = s.n_total - s.n_converged;
    fprintf('  %-30s WARN -- %.2f%% converged (%d/%d), %d failed. First failed idx: %s\n', ...
        [label ':'], s.pct_converged, s.n_converged, s.n_total, n_fail, ...
        mat2str(s.failed_idx(1:min(5, numel(s.failed_idx)))));
end
end

% =========================================================================
function plot_iter_panel(num_iter, converged, label)
N_OF_ITER = 20;   % must match loadflow_FPIs.m's iteration cap -- reference line only

nexttile;
t = 1:numel(num_iter);
hold on;
plot(t, num_iter, '-', 'Color', [0.2 0.4 0.85], 'LineWidth', 1, 'DisplayName', 'Iterations used');
yline(N_OF_ITER, 'k--', 'iteration cap', 'FontSize', 7, 'HandleVisibility', 'off');
if any(~converged)
    plot(t(~converged), num_iter(~converged), 'rx', 'MarkerSize', 8, 'LineWidth', 1.5, ...
        'DisplayName', 'Did not converge');
end
hold off;
xlabel('Timestep'); ylabel('Iterations to converge');
title(label, 'FontSize', 9);
grid on;
legend('Location', 'best', 'FontSize', 7);
end
