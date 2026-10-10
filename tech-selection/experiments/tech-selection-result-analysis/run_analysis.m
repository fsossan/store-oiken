% RUN_ANALYSIS  Standalone driver for the tech-selection-result-analysis
%               directory: load (or solve + save) one network's result,
%               then run the existing analyze_* diagnostics against it and
%               export the resulting figures as PNG + TikZ.
%
% This directory is meant to eventually become its own project. For now it
% deliberately reuses the existing util/analyze_*.m functions rather than
% forking them -- that's only possible because save_tech_selection_result.m
% embeds the exact cfg used (out.cfg) into each saved result file, so the
% analyze_* calls below never depend on the live state of
% config/sizing_cfg.json / config/technology_cfg.json. The trade-off (noted
% during planning) is that util/ still has to be on the MATLAB path -- true
% decoupling would mean copying the analyze_* logic in here instead.

this_dir  = fileparts(mfilename('fullpath'));
repo_root = fullfile(this_dir, '..', '..');
addpath(repo_root);
proj = setup_paths();   % src/ on the path; no relative paths are used any more, so no cd
results_dir_abs = fullfile(proj.results, 'experiments', 'tech-selection-result-analysis', 'results');
figures_dir_abs = fullfile(proj.results, 'experiments', 'tech-selection-result-analysis', 'figures');

% =========================================================================
%  RUN PARAMETERS
% =========================================================================
network_id   = "LV_Grid_101";
horizon      = [];           % [] = full day
enable_plots = false;        % pipeline's own temporal-profile figure; the
                              % analyze_* figures below are called explicitly

run_opts = struct( ...
    'verbose_debug', true, ...
    'MAX_LIN_ITER',  1);

results_dir = results_dir_abs;
figures_dir = figures_dir_abs;

net_num = str2double(regexp(network_id, '\d+', 'match', 'once'));
fname   = fullfile(results_dir, sprintf('%d-tech-selec-res.mat', net_num));

% =========================================================================
%  SOLVE + SAVE (skip if already saved)
% =========================================================================
if ~isfile(fname)
    save_tech_selection_result(network_id, horizon, enable_plots, run_opts, [], results_dir);
end

% =========================================================================
%  SELECTIVE LOAD
% =========================================================================
% analyze_voltage_current needs out.gm.lm.Vmag0/Imag0 (initial operating
% point), so 'gm' has to be loaded for this default full-diagnostic-suite
% run -- the selective-load win (save(fname,'-struct',out) makes each field
% independently loadable) matters when a later script only wants e.g.
% sizing+costs for a portfolio-level scan and can skip 'gm' entirely.
out = load(fname, 'summary', 'sizing', 'injections', 'costs', 'grid', ...
    'diagnostics', 'meta', 'cfg', 'gm');
cfg = out.cfg;

% =========================================================================
%  ANALYSIS  (mirrors util/run_seq_lin_loop_ess.m's analyze_* call site)
% =========================================================================
close all

analyze_tech_selection(out, cfg);
analyze_losses(out, cfg);
analyze_voltage_current(out);
if cfg.flags.curtailment_activate
    analyze_curtailment(out, cfg);
end
analyze_charge_discharge_exclusivity(out, cfg);
analyze_loadflow_convergence(out);

% =========================================================================
%  EXPORT FIGURES
% =========================================================================
export_open_figures(sprintf('%d', net_num), figures_dir);
