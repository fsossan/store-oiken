function results = run_pvev_costterm_tech_study(network_id, scenario)
% RUN_PVEV_COSTTERM_TECH_STUDY  Base loads + PV + EV, short horizon (D=1),
%                                 clearsky PV (factor 1). Sweeps 3 objective
%                                 variants (F^inv, F^inv+F^Sloss,
%                                 F^inv+F^Sloss+F^Eloss) x 3 technology
%                                 variants (LiIon-only/NaIon-only/Both) --
%                                 the exact grid used in
%                                 experiments/Tech-selection.md's "EV
%                                 charging profiles" section, continued here
%                                 for "Base loads + PV + EV".
%
%   results = run_pvev_costterm_tech_study()
%   results = run_pvev_costterm_tech_study(network_id, scenario)
%
%   Cost pricing: uses whatever sizing_cfg.json currently has live
%   (cfg.economics.cL, cfg.economics.cThroughputLoss, etc.) -- NOT
%   overridden here -- so this reproduces the same pricing basis as the
%   doc's earlier EV-only section. Only opts.min_loss / opts.throughput_penalty
%   are toggled per objective variant (that IS the swept axis); everything
%   else (siting_activate, curtailment_activate=false, cha_dis_bin_activate,
%   current_mag_cstr) is left at the live config's value.
%
%   Does not touch sizing_cfg.json/technology_cfg.json on disk -- same
%   in-memory-override pattern as run_tech_profile_ablation.m.
%
%   Output
%   ------
%   results : struct array, 9 entries (3 cost-fn x 3 tech), each with
%             .cost_fn_name .tech_name .status .out (full struct incl.
%             out.gm for the pre-ESS baseline) .per_node (table of
%             node_id/E_kWh/S_kW/throughput_kWh) .costs .lin_error

this_dir  = fileparts(mfilename('fullpath'));
repo_root = fileparts(this_dir);
addpath(repo_root);
proj = setup_paths();   % src/ on the path + project folder layout (proj.results, ...)

if nargin < 1 || isempty(network_id); network_id = "LV_Grid_230"; end
if nargin < 2 || isempty(scenario);   scenario   = "sc1_2040";    end

ctx0 = load_ess_selection_context(char(scenario));
n_idx = find(ismember(string(ctx0.data_SFOE.LV_grid_id), network_id), 1);
if isempty(n_idx)
    error('run_pvev_costterm_tech_study:netNotFound', 'Network %s not found.', network_id);
end
Sb = ctx0.config.PU_values.Sb;
bp_ph = (Sb/1000) * 3;   % pu -> real kWh/kW (=300 at Sb=100kVA)

ctx0.cfg.horizon.days = 1;   % short horizon, native day (Ts_h=0.25 -> T=96)

pp = struct('demand', struct('enabled', true), ...
            'pv',     struct('enabled', true, 'series', "clearsky", 'scale', 1), ...
            'ev',     struct('enabled', true));

cost_fn_variants = struct( ...
    'Finv',              struct('min_loss', false, 'throughput_penalty', false), ...
    'Finv_Sloss',        struct('min_loss', true,  'throughput_penalty', false), ...
    'Finv_Sloss_Eloss',  struct('min_loss', true,  'throughput_penalty', true) ...
);
cost_fn_names = fieldnames(cost_fn_variants);
tech_variants = ["LiIon", "NaIon", "Both"];

run_opts = struct('MAX_LIN_ITER', ctx0.cfg.solver.MAX_LIN_ITER_milp, ...
    'verbose_debug', false, 'log_fid', []);

Ts = ctx0.cfg.horizon.Ts_h;

n_combo = numel(cost_fn_names) * numel(tech_variants);
results = struct([]);
k = 0;

for c = 1:numel(cost_fn_names)
    cf_name = cost_fn_names{c};
    cf = cost_fn_variants.(cf_name);

    for tvi = 1:numel(tech_variants)
        tv = tech_variants(tvi);
        k = k + 1;
        label = sprintf('%s_%s', cf_name, tv);
        fprintf('\n--- [%d/%d] %s ---\n', k, n_combo, label);

        ctx = ctx0;
        ctx.cfg.demand_profile = pp.demand;
        ctx.cfg.pv_profile     = pp.pv;
        ctx.cfg.ev_profile     = pp.ev;
        ctx.cfg.flags.min_loss           = cf.min_loss;
        ctx.cfg.flags.throughput_penalty = cf.throughput_penalty;

        tech = local_build_tech_cfg(tv, bp_ph);
        ctx.cfg.tech    = tech;
        ctx.cfg.J       = numel(tech.names);
        ctx.tech_names  = tech.names;
        ctx.J           = ctx.cfg.J;

        row = struct('cost_fn', cf_name, 'tech', char(tv), 'label', label, ...
            'status', "", 'out', [], 'per_node', [], 'error_msg', "");

        try
            [status, result] = solve_network_tech_selection(ctx, n_idx, [], false, run_opts);
            row.status = string(status);

            if strcmp(status, 'solved')
                out = result.out;
                row.out = out;

                I_inst = out.sizing.Installation;      % [Nd x J]
                E_kWh  = out.sizing.E_nom_node_pu  * bp_ph;
                S_kW   = out.sizing.S_conv_node_pu * bp_ph;
                B_plus  = out.injections.B_plus;        % [T*Nd x J]
                B_minus = out.injections.B_minus;
                node_id = out.sizing.demand_node_id;    % [Nd x 1]

                T  = ctx.cfg.horizon.steps_per_day * ctx.cfg.horizon.days;
                Nd = numel(node_id);

                installed_idx = find(any(I_inst, 2));
                per_node = table();
                for ii = 1:numel(installed_idx)
                    n = installed_idx(ii);
                    j = find(I_inst(n,:), 1);
                    Idx = (n-1)*T + (1:T);
                    throughput_kWh = (sum(B_plus(Idx,j)) + sum(B_minus(Idx,j))) * Ts * bp_ph;
                    per_node = [per_node; table(node_id(n), string(tech.names{j}), ...
                        E_kWh(n,j), S_kW(n,j), throughput_kWh, ...
                        'VariableNames', {'node_id','tech','E_kWh','S_kW','throughput_kWh'})]; %#ok<AGROW>
                end
                row.per_node = per_node;

                row.costs = out.costs;
                row.lin_error = struct('V_pu', out.summary.volt_error, 'I_pu', out.summary.curr_error);

                fprintf('  status=solved  total=%.3f kCHF  n_sites=%d\n', out.costs.total/1000, height(per_node));
                disp(per_node);
            else
                fprintf('  status=%s\n', status);
            end
        catch ME
            row.status = "error";
            row.error_msg = string(ME.message);
            fprintf('  ERROR: [%s] %s\n', ME.identifier, ME.message);
        end

        if isempty(results); results = row; else; results(end+1) = row; end %#ok<AGROW>
    end
end

out_dir = fullfile(proj.results, 'experiments', 'pvev_costterm_tech_study');
if ~isfolder(out_dir); mkdir(out_dir); end
save(fullfile(out_dir, 'results.mat'), 'results', '-v7.3');
fprintf('\nSaved: %s\n', fullfile(out_dir, 'results.mat'));

end

% -------------------------------------------------------------------------
function tech = local_build_tech_cfg(which, bp_ph)
% Hardcoded from experiments/Tech-selection.md's own "Input params" table
% (Li-Ion: eta=0.9/0.9, C-rate=1.1; Na-Ion: eta=0.85/0.85, C-rate=5; both
% cE=300 CHF/kWh, cS=100 CHF/kW, cI=2000 CHF fixed; Emax/Smax=40 pu from the
% originally-committed technology_cfg.json, commit 0ef0899) -- NOT read from
% the live config/technology_cfg.json, which is currently left in a modified
% single-entry state (NaIon with C-rate overwritten to 1.1) from the doc's
% own C-rate-equalized controlled comparison at the end of the EV section.
% Decoupling from the live file keeps this script's technology definitions
% stable regardless of what experimental state that file is left in.
mk = @(name, c_rate, eta) struct('name', name, 'c_rate', c_rate, ...
    'eta_ch', eta, 'eta_dis', eta, 'Emax_pu', 40, 'Smax_pu', 40, ...
    'cE', 300*bp_ph, 'cS', 100*bp_ph, 'cI', 2000, ...
    'cE_per_kWh', 300, 'cS_per_kW', 100, 'cI_fixed', 2000);
LiIon = mk('LiIon', 1.1, 0.90);
NaIon = mk('NaIon', 5,   0.85);
switch which
    case "LiIon"; picks = {LiIon};
    case "NaIon"; picks = {NaIon};
    case "Both";  picks = {LiIon, NaIon};
end
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
end
