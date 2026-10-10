% MAIN  Single-stage ESS technology-selection entry point.
%
%   Run from anywhere: setup_paths resolves the repo root from its own
%   location, puts src/ on the MATLAB path and returns the folder layout.
%   Results go to a new folder results/<timestamp>_<scenario>/ (see
%   run_ess_selection_portfolio and README.md).

clear; clc; close all
setup_paths();

rng(1234);
warning('on', 'all');
set(0, 'DefaultFigureVisible', 'on');

% =========================================================================
%  RUN PARAMETERS  (the knobs main.m owns)
% =========================================================================
scenario     = 'sc1_2030';         % key of config/general_config.json "scenarios"
network_id   = "LV_Grid_101";      % LV_Grid id(s) to run, or "ALL" for the full sane portfolio
horizon      = [];                 % [] = full day; e.g. 1:32 for a short intra-day debug window
enable_plots = true;               % temporal-profile / tech-selection / losses diagnostic figures

% Simulated day count (D) and time-step (Ts_h) live in config/sizing_cfg.json
% under "horizon": { "days": ..., "Ts_h": ... }.  steps_per_day = 24 / Ts_h,
% and T = days * steps_per_day.  Ts_h must match the native resolution of the
% demand/PV/EV input data (build_temporal_profiles errors otherwise).

% -------------------------------------------------------------------------
%  advanced run options (rarely changed)
% -------------------------------------------------------------------------
run_opts = struct( ...
    'verbose_debug',        true, ...
    'skip_solved',          false, ...   % only meaningful together with run_dir (resume)
    'MAX_LIN_ITER',         1, ...
    'allow_mult_instances', false, ...   % parallelize "ALL" across 4 MATLAB sessions
    'instance_id',          4, ...       % which of the 4 splits this session runs (1-4)
    'run_dir',              '');         % '' -> new results/<timestamp>_<scenario>/ folder.
                                         % Set to an existing run folder to resume it
                                         % (with skip_solved) or to make the 4
                                         % multi-instance sessions share one folder.

% =========================================================================
%  LOAD CONTEXT AND RUN
% =========================================================================
ctx = load_ess_selection_context(scenario);

run_ess_selection_portfolio(ctx, network_id, horizon, enable_plots, run_opts);
