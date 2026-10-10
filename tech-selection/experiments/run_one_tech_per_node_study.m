function results = run_one_tech_per_node_study(network_id, scenario)
% RUN_ONE_TECH_PER_NODE_STUDY  Does the "at most one technology per node"
%   constraint (solve_ess_milp.m, sum(I(n,:)) <= 1) change ESS technology
%   selection? Demand + PV (clearsky, x1) + EV, one native day (T=96,
%   Ts=15 min), both technologies available (LiIon + NaIon). Sweeps
%   3 objective variants x {constraint on, constraint off} = 6 runs.
%
%   results = run_one_tech_per_node_study()
%   results = run_one_tech_per_node_study(network_id, scenario)
%
%   Pinned in memory (independent of the live sizing_cfg.json):
%     siting_activate=true, cha_dis_bin_activate=true (exact charge/discharge
%     exclusivity, so phantom throughput cannot contaminate the comparison),
%     curtailment_activate=false, horizon.days=1.
%   Left at the live config: economics/prices, converter/transformer boxes,
%   solver tolerances (Gurobi tolerances live in the CVX install dir).
%   Technology definitions are hardcoded (same as run_pvev_costterm_tech_study.m),
%   not read from config/technology_cfg.json.
%
%   Writes output/one_tech_per_node_study/results.mat after every run.

this_dir  = fileparts(mfilename('fullpath'));
repo_root = fileparts(this_dir);
addpath(repo_root);
proj = setup_paths();   % src/ on the path + project folder layout (proj.results, ...)

if nargin < 1 || isempty(network_id); network_id = "LV_Grid_230"; end
if nargin < 2 || isempty(scenario);   scenario   = "sc1_2040";    end

ctx0 = load_ess_selection_context(char(scenario));
n_idx = find(ismember(string(ctx0.data_SFOE.LV_grid_id), network_id), 1);
if isempty(n_idx)
    error('run_one_tech_per_node_study:netNotFound', 'Network %s not found.', network_id);
end
Sb    = ctx0.config.PU_values.Sb;
bp_ph = (Sb/1000) * 3;   % pu -> real kWh/kW (=300 at Sb=100kVA)

ctx0.cfg.horizon.days = 1;

pp = struct('demand', struct('enabled', true), ...
            'pv',     struct('enabled', true, 'series', "clearsky", 'scale', 1), ...
            'ev',     struct('enabled', true));

cost_fn_variants = struct( ...
    'Finv',              struct('min_loss', false, 'throughput_penalty', false), ...
    'Finv_Sloss',        struct('min_loss', true,  'throughput_penalty', false), ...
    'Finv_Sloss_Eloss',  struct('min_loss', true,  'throughput_penalty', true) ...
);
cost_fn_names = fieldnames(cost_fn_variants);
constraint_variants = [true, false];   % one_tech_per_node

run_opts = struct('MAX_LIN_ITER', ctx0.cfg.solver.MAX_LIN_ITER_milp, ...
    'verbose_debug', false, 'log_fid', []);
Ts = ctx0.cfg.horizon.Ts_h;
tech = local_build_tech_cfg(bp_ph);

n_combo = numel(cost_fn_names) * numel(constraint_variants);
results = struct([]);
k = 0;

out_dir = fullfile(proj.results, 'experiments', 'one_tech_per_node_study');
if ~isfolder(out_dir); mkdir(out_dir); end

for c = 1:numel(cost_fn_names)
    cf_name = cost_fn_names{c};
    cf = cost_fn_variants.(cf_name);

    for cv = 1:numel(constraint_variants)
        one_tech = constraint_variants(cv);
        k = k + 1;
        label = sprintf('%s_oneTech%d', cf_name, one_tech);
        fprintf('\n--- [%d/%d] %s ---\n', k, n_combo, label);

        ctx = ctx0;
        ctx.cfg.demand_profile = pp.demand;
        ctx.cfg.pv_profile     = pp.pv;
        ctx.cfg.ev_profile     = pp.ev;
        ctx.cfg.flags.min_loss             = cf.min_loss;
        ctx.cfg.flags.throughput_penalty   = cf.throughput_penalty;
        ctx.cfg.flags.siting_activate      = true;
        ctx.cfg.flags.cha_dis_bin_activate = true;
        ctx.cfg.flags.curtailment_activate = false;
        ctx.cfg.flags.one_tech_per_node    = one_tech;

        ctx.cfg.tech   = tech;
        ctx.cfg.J      = numel(tech.names);
        ctx.tech_names = tech.names;
        ctx.J          = ctx.cfg.J;

        row = struct('cost_fn', cf_name, 'one_tech_per_node', one_tech, 'label', label, ...
            'status', "", 'out', [], 'per_node', [], 'costs', [], 'lin_error', [], ...
            'flags', ctx.cfg.flags, 'error_msg', "");

        try
            [status, result] = solve_network_tech_selection(ctx, n_idx, [], false, run_opts);
            row.status = string(status);

            if strcmp(status, 'solved')
                out = result.out;

                I_inst  = out.sizing.Installation;      % [Nd x J]
                E_kWh   = out.sizing.E_nom_node_pu  * bp_ph;
                S_kW    = out.sizing.S_conv_node_pu * bp_ph;
                B_plus  = out.injections.B_plus;        % [T*Nd x J]
                B_minus = out.injections.B_minus;
                node_id = out.sizing.demand_node_id;
                T  = ctx.cfg.horizon.steps_per_day * ctx.cfg.horizon.days;

                per_node = table();
                [inst_n, inst_j] = find(I_inst);
                [~, ord] = sort(node_id(inst_n));
                inst_n = inst_n(ord);  inst_j = inst_j(ord);
                for ii = 1:numel(inst_n)
                    n = inst_n(ii);  j = inst_j(ii);
                    Idx = (n-1)*T + (1:T);
                    thr = (sum(B_plus(Idx,j)) + sum(B_minus(Idx,j))) * Ts * bp_ph;
                    per_node = [per_node; table(node_id(n), string(tech.names{j}), ...
                        E_kWh(n,j), S_kW(n,j), thr, ...
                        'VariableNames', {'node_id','tech','E_kWh','S_kW','throughput_kWh'})]; %#ok<AGROW>
                end
                row.per_node  = per_node;
                row.costs     = out.costs;
                row.lin_error = struct('V_pu', out.summary.volt_error, 'I_pu', out.summary.curr_error);
                if isfield(out, 'gm'); out = rmfield(out, 'gm'); end   % keep the .mat small
                row.out = out;

                n_multi = sum(accumarray(findgroups(per_node.node_id), 1) > 1);
                fprintf('  status=solved  total=%.3f kCHF  n_units=%d  nodes_with_2_techs=%d\n', ...
                    row.costs.total/1000, height(per_node), n_multi);
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
        save(fullfile(out_dir, 'results.mat'), 'results', '-v7.3');
    end
end

fprintf('\nSaved: %s\n', fullfile(out_dir, 'results.mat'));
end

% -------------------------------------------------------------------------
function tech = local_build_tech_cfg(bp_ph)
% Li-Ion (eta 0.9/0.9, C-rate 1.1) and Na-Ion (eta 0.85/0.85, C-rate 5); both
% cE=300 CHF/kWh, cS=100 CHF/kW, cI=2000 CHF fixed, Emax/Smax=40 pu. Same
% values as run_pvev_costterm_tech_study.m; decoupled from the live
% config/technology_cfg.json.
mk = @(name, c_rate, eta) struct('name', name, 'c_rate', c_rate, ...
    'eta_ch', eta, 'eta_dis', eta, 'Emax_pu', 40, 'Smax_pu', 40, ...
    'cE', 300*bp_ph, 'cS', 100*bp_ph, 'cI', 2000, ...
    'cE_per_kWh', 300, 'cS_per_kW', 100, 'cI_fixed', 2000);
picks = {mk('LiIon', 1.1, 0.90), mk('NaIon', 5, 0.85)};
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
