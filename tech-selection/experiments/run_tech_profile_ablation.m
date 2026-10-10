function T_summary = run_tech_profile_ablation(network_id, scenario, enable_plots, pv_series)
% RUN_TECH_PROFILE_ABLATION  Short-horizon (D=1) 3x3 ablation over profile
%                              composition (PV / EV / PV+EV, baseline demand
%                              always on) x technology availability
%                              (LiIon-only / NaIon-only / both), on a single
%                              network -- for the paper's Results section
%                              (technology-selection case study).
%
%   T_summary = run_tech_profile_ablation()
%   T_summary = run_tech_profile_ablation(network_id, scenario, enable_plots, pv_series)
%
%   Inputs (all optional)
%   ------
%   network_id   : string   LV_Grid id, default "LV_Grid_230" (N=41, Nd=13,
%                            known EV/PV-driven violations, confirmed 100%
%                            load-flow convergence under demand+PV, demand+EV,
%                            and demand+PV+EV -- see chat log / docs/DEVELOPMENT_NOTES.md).
%   scenario     : string   SFOE scenario, default "sc1_2040"
%   enable_plots : logical  per-run temporal/tech-selection figures, default
%                            false (9 runs; turn on for a single re-run of
%                            whichever combination is interesting)
%   pv_series    : string   "clearsky" (default) | "measured" -- forwarded to
%                            load_pv_profile.m. The first run of this study
%                            used "measured" and found PV had ~zero effect on
%                            baseline violations or sizing on this network's
%                            selected representative day (D=1, season="all");
%                            "clearsky" removes weather/cloud attenuation to
%                            give the PV axis its strongest, cleanest signal.
%                            Results save to a series-tagged subfolder so
%                            different series' runs never collide.
%
%   Design notes
%   ------------
%   - Does NOT touch sizing_cfg.json or technology_cfg.json on disk. Every
%     axis is overridden in-memory on a per-call copy of ctx.cfg, exactly
%     like test_hard_stop.m's pattern this session. Safe to run alongside
%     someone else's own main.m/live-config run without collision.
%   - Demand realization is identical across all 9 runs "for free", with NO
%     manual caching needed: solve_network_tech_selection.m calls
%     rng(1234+net_num) once, before anything else, and
%     build_temporal_profiles.m always generates demand FIRST (before PV/EV)
%     -- verified directly this session (experiments/test_load_profile_determinism.m).
%   - horizon.days is forced to 1 here regardless of the live sizing_cfg.json
%     value, per "short horizon of a day" -- native 96-step day (Ts_h=0.25).
%   - Technology definitions (LiIon, NaIon) are hardcoded below from
%     config/technology_cfg.json's last-committed values (commit 0ef0899) --
%     NaIon is currently missing from the live working-tree JSON (flagged
%     separately). Both techs share identical cost coefficients
%     (cE=300 CHF/kWh, cS=100 CHF/kW, cI=2000 CHF); only c_rate/efficiency
%     differ, so this script reuses LiIon's already pu-scaled cE/cS/cI
%     (via load_ess_selection_config's bp/ph scaling) rather than
%     re-deriving them.
%   - opts.{min_loss,curtailment_activate,throughput_penalty} and
%     opts.cha_dis_bin_activate are left at whatever the live sizing_cfg.json
%     says (NOT overridden here) so this run matches the same formulation
%     the user's own parallel run uses, for a like-for-like comparison.
%   - Results saved per-combination under output/tech_profile_ablation/, so
%     they never collide with output/OPF_result/out_dir_*/ from a normal
%     main.m run.
%
%   Output
%   ------
%   T_summary : table, one row per combination -- status, costs, sizing
%               counts, no-ESS baseline violation severity, solve time.
%               Also saved to output/tech_profile_ablation/summary.csv and
%               .mat (with the full per-combination result structs).

this_dir  = fileparts(mfilename('fullpath'));
repo_root = fileparts(this_dir);
addpath(repo_root);
proj = setup_paths();   % src/ on the path + project folder layout (proj.results, ...)

if nargin < 1 || isempty(network_id);   network_id   = "LV_Grid_230"; end
if nargin < 2 || isempty(scenario);     scenario     = "sc1_2040";    end
if nargin < 3 || isempty(enable_plots); enable_plots = false;         end
if nargin < 4 || isempty(pv_series);    pv_series    = "clearsky";    end

out_dir = fullfile(proj.results, 'experiments', "tech_profile_ablation_" + pv_series);
if ~isfolder(out_dir); mkdir(out_dir); end

fprintf('=== run_tech_profile_ablation: %s / %s / PV series=%s ===\n', network_id, scenario, pv_series);

ctx0 = load_ess_selection_context(char(scenario));
n_idx = find(ismember(string(ctx0.data_SFOE.LV_grid_id), network_id), 1);
if isempty(n_idx)
    error('run_tech_profile_ablation:netNotFound', 'Network %s not found.', network_id);
end
net_num = str2double(regexp(network_id, '\d+', 'match', 'once'));
Sb = ctx0.config.PU_values.Sb;

% Force short horizon: D=1, full native day (steps_per_day already 96 from
% sizing_cfg.json's Ts_h=0.25; not touched here).
ctx0.cfg.horizon.days = 1;

% -------------------------------------------------------------------
%  Profile-composition axis: demand always on, PV/EV toggled
% -------------------------------------------------------------------
% series="clearsky": ideal-sky PV generation (no weather/cloud attenuation),
% used here instead of "measured" so the PV axis exercises a strong, clean
% generation signal rather than whatever a single representative
% measured/cloudy day happens to contain (see the ablation write-up for the
% "measured" run's near-zero PV effect that motivated this switch).
profile_scenarios = struct( ...
    'PV',   struct('demand', struct('enabled', true), ...
                    'pv',     struct('enabled', true, 'series', "clearsky"), ...
                    'ev',     struct('enabled', false)), ...
    'EV',   struct('demand', struct('enabled', true), ...
                    'pv',     struct('enabled', false), ...
                    'ev',     struct('enabled', true)), ...
    'PVEV', struct('demand', struct('enabled', true), ...
                    'pv',     struct('enabled', true, 'series', "clearsky"), ...
                    'ev',     struct('enabled', true)) ...
);
profile_names = fieldnames(profile_scenarios);

% -------------------------------------------------------------------
%  Technology axis
% -------------------------------------------------------------------
tech_variants = ["LiIon", "NaIon", "Both"];

run_opts = struct('MAX_LIN_ITER', ctx0.cfg.solver.MAX_LIN_ITER_milp, ...
    'verbose_debug', false, 'log_fid', []);

n_combo = numel(profile_names) * numel(tech_variants);
rows = cell(n_combo, 1);
k = 0;

for p = 1:numel(profile_names)
    pname = profile_names{p};
    pp = profile_scenarios.(pname);

    for tvi = 1:numel(tech_variants)
        tv = tech_variants(tvi);
        k = k + 1;
        label = sprintf('%s_%s', pname, tv);
        fprintf('\n--- [%d/%d] %s ---\n', k, n_combo, label);

        ctx = ctx0;
        ctx.cfg.demand_profile = pp.demand;
        ctx.cfg.pv_profile     = set_default(pp.pv, 'season', "all");
        ctx.cfg.ev_profile     = set_default(pp.ev, 'dt_minutes', 15);

        tech = build_tech_cfg(tv, ctx.cfg, Sb);
        ctx.cfg.tech    = tech;
        ctx.cfg.J       = numel(tech.names);
        ctx.tech_names  = tech.names;
        ctx.J           = ctx.cfg.J;

        row = struct('profile', pname, 'tech', char(tv), 'label', label, ...
            'status', "", 'solve_time_s', nan, ...
            'costE', nan, 'costS', nan, 'costI', nan, 'costL', nan, 'costCurt', nan, 'costTotal', nan, ...
            'n_sites', nan, 'E_tot_pu', nan, 'S_tot_pu', nan, ...
            'n_LiIon_sites', nan, 'n_NaIon_sites', nan, ...
            'baseline_vmag_viol_frac', nan, 'baseline_imag_viol_frac', nan, ...
            'error_msg', "");

        t0 = tic;
        try
            [status, result] = solve_network_tech_selection(ctx, n_idx, [], enable_plots, run_opts);
            row.status = string(status);

            switch status
                case 'solved'
                    out = result.out;
                    row.costE     = out.costs.E;
                    row.costS     = out.costs.S;
                    row.costI     = out.costs.I;
                    row.costL     = out.costs.L;
                    row.costCurt  = out.costs.Curt;
                    row.costTotal = out.costs.total;

                    I_inst = out.sizing.Installation;   % [Nd x J]
                    row.n_sites = sum(any(I_inst, 2));
                    row.E_tot_pu = sum(out.sizing.E_nom_node_pu(:));
                    row.S_tot_pu = sum(out.sizing.S_conv_node_pu(:));
                    for jn = 1:numel(tech.names)
                        n_site_j = sum(I_inst(:, jn));
                        if strcmp(tech.names{jn}, 'LiIon'); row.n_LiIon_sites = n_site_j; end
                        if strcmp(tech.names{jn}, 'NaIon'); row.n_NaIon_sites = n_site_j; end
                    end

                    % No-ESS baseline violation severity (pre-ESS operating
                    % point, already stored in gm.lm -- no extra load flow needed).
                    Vmag0 = out.gm.lm.Vmag0;   % [N x T]
                    Imag0_pu = abs(out.gm.lm.Imag0) ./ (out.gm.grid.ampacities ./ out.gm.grid.basecurrent);
                    row.baseline_vmag_viol_frac = mean(Vmag0(:) < 0.9 | Vmag0(:) > 1.1);
                    row.baseline_imag_viol_frac = mean(Imag0_pu(:) > 1);

                    save(fullfile(out_dir, label + ".mat"), 'result', 'row', '-v7.3');

                case 'thresh'
                    fprintf('  SKIPPED (voltage guard failed): Vmag0 in [%.4g, %.4g]\n', ...
                        result.Vmag0_min, result.Vmag0_max);
                    save(fullfile(out_dir, label + ".mat"), 'result', 'row');

                case 'subopt'
                    fprintf('  SUBOPTIMAL only (no threshold-passing CVX solution)\n');
                    save(fullfile(out_dir, label + ".mat"), 'result', 'row');
            end

        catch ME
            row.status    = "error";
            row.error_msg = string(ME.message);
            fprintf('  ERROR: [%s] %s\n', ME.identifier, ME.message);
        end
        row.solve_time_s = toc(t0);

        fprintf('  status=%s  time=%.1fs', row.status, row.solve_time_s);
        if row.status == "solved"
            fprintf('  costTotal=%.2f CHF  n_sites=%d (LiIon=%d, NaIon=%d)', ...
                row.costTotal, row.n_sites, row.n_LiIon_sites, row.n_NaIon_sites);
        end
        fprintf('\n');

        rows{k} = row;
    end
end

T_summary = struct2table([rows{:}]);
writetable(T_summary, fullfile(out_dir, 'summary.csv'));
save(fullfile(out_dir, 'summary.mat'), 'T_summary');

fprintf('\n=== DONE: %d/%d combinations solved ===\n', sum(T_summary.status == "solved"), n_combo);
disp(T_summary);

end

% -------------------------------------------------------------------------
function tech = build_tech_cfg(which, cfg, Sb)
% Build a cfg.tech-shaped struct for the requested technology subset,
% reusing load_ess_selection_config.m's bp/ph pu-scaling convention.
% NaIon params are hardcoded from technology_cfg.json's last-committed
% values (commit 0ef0899) since it is currently absent from the live
% working-tree JSON; both techs share identical cost coefficients so NaIon
% reuses LiIon's already-scaled cE/cS/cI (no need to redo the bp/ph math).

li_idx = find(strcmp(cfg.tech.names, 'LiIon'), 1);
if isempty(li_idx)
    error('build_tech_cfg:noLiIon', 'LiIon not found in cfg.tech.names -- check technology_cfg.json.');
end

LiIon = struct('name', 'LiIon', ...
    'c_rate', cfg.tech.c_rate(li_idx), 'eta_ch', cfg.tech.eta_ch(li_idx), ...
    'eta_dis', cfg.tech.eta_dis(li_idx), 'Emax_pu', cfg.tech.Emax_pu(li_idx), ...
    'Smax_pu', cfg.tech.Smax_pu(li_idx), 'cE', cfg.tech.cE(li_idx), ...
    'cS', cfg.tech.cS(li_idx), 'cI', cfg.tech.cI(li_idx), ...
    'cE_per_kWh', cfg.tech.cE_per_kWh(li_idx), 'cS_per_kW', cfg.tech.cS_per_kW(li_idx), ...
    'cI_fixed', cfg.tech.cI_fixed(li_idx));

NaIon = struct('name', 'NaIon', ...
    'c_rate', 5, 'eta_ch', 0.85, 'eta_dis', 0.85, ...
    'Emax_pu', LiIon.Emax_pu, 'Smax_pu', LiIon.Smax_pu, ...
    'cE', LiIon.cE, 'cS', LiIon.cS, 'cI', LiIon.cI, ...
    'cE_per_kWh', LiIon.cE_per_kWh, 'cS_per_kW', LiIon.cS_per_kW, ...
    'cI_fixed', LiIon.cI_fixed);   % identical costs to LiIon

switch which
    case "LiIon"; picks = {LiIon};
    case "NaIon"; picks = {NaIon};
    case "Both";  picks = {LiIon, NaIon};
    otherwise
        error('build_tech_cfg:badWhich', 'Unknown technology variant "%s".', which);
end

J = numel(picks);
tech.names      = cellfun(@(s) s.name, picks, 'UniformOutput', false);
tech.c_rate     = cellfun(@(s) s.c_rate,  picks);
tech.eta_ch     = cellfun(@(s) s.eta_ch,  picks);
tech.eta_dis    = cellfun(@(s) s.eta_dis, picks);
tech.Emax_pu    = cellfun(@(s) s.Emax_pu, picks);
tech.Smax_pu    = cellfun(@(s) s.Smax_pu, picks);
tech.cE         = cellfun(@(s) s.cE, picks);
tech.cS         = cellfun(@(s) s.cS, picks);
tech.cI         = cellfun(@(s) s.cI, picks);
tech.cE_per_kWh = cellfun(@(s) s.cE_per_kWh, picks);
tech.cS_per_kW  = cellfun(@(s) s.cS_per_kW,  picks);
tech.cI_fixed   = cellfun(@(s) s.cI_fixed,   picks);

assert(numel(tech.names) == J);

end
