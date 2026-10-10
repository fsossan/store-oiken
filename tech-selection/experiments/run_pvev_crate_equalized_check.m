function results = run_pvev_crate_equalized_check(network_id, scenario)
% RUN_PVEV_CRATE_EQUALIZED_CHECK  Controlled comparison for the "Base loads
%                                   + PV + EV" section of Tech-selection.md:
%                                   same C-rate (1.1) for both technologies,
%                                   Li-Ion-only vs Na-Ion-only, under
%                                   F^inv AND F^inv+F^Sloss+F^Eloss -- same
%                                   experimental design as the EV-only
%                                   section's original hypothesis test
%                                   (there: F^inv only, investment cost
%                                   alone), extended here to also check
%                                   under the loss-priced objective, since
%                                   "wasting energy" is specifically the
%                                   F^Eloss story.
%
%   results = run_pvev_crate_equalized_check()
%   results = run_pvev_crate_equalized_check(network_id, scenario)
%
%   Same profile (demand+PV(clearsky,scale=1)+EV), same in-memory-override
%   pattern, same hardcoded base tech params as
%   experiments/run_pvev_costterm_tech_study.m -- only difference: Na-Ion's
%   c_rate is forced to 1.1 (matching Li-Ion) instead of its real value (5).

this_dir  = fileparts(mfilename('fullpath'));
repo_root = fileparts(this_dir);
addpath(repo_root);
proj = setup_paths();   % src/ on the path + project folder layout (proj.results, ...)

if nargin < 1 || isempty(network_id); network_id = "LV_Grid_230"; end
if nargin < 2 || isempty(scenario);   scenario   = "sc1_2040";    end

ctx0 = load_ess_selection_context(char(scenario));
n_idx = find(ismember(string(ctx0.data_SFOE.LV_grid_id), network_id), 1);
Sb = ctx0.config.PU_values.Sb;
bp_ph = (Sb/1000) * 3;

ctx0.cfg.horizon.days = 1;

pp = struct('demand', struct('enabled', true), ...
            'pv',     struct('enabled', true, 'series', "clearsky", 'scale', 1), ...
            'ev',     struct('enabled', true));

cost_fn_variants = struct( ...
    'Finv',             struct('min_loss', false, 'throughput_penalty', false), ...
    'Finv_Sloss_Eloss', struct('min_loss', true,  'throughput_penalty', true) ...
);
cost_fn_names = fieldnames(cost_fn_variants);
tech_variants = ["LiIon", "NaIon_Crate1p1"];

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

                I_inst = out.sizing.Installation;
                E_kWh  = out.sizing.E_nom_node_pu  * bp_ph;
                S_kW   = out.sizing.S_conv_node_pu * bp_ph;
                B_plus  = out.injections.B_plus;
                B_minus = out.injections.B_minus;
                node_id = out.sizing.demand_node_id;
                T = ctx.cfg.horizon.steps_per_day * ctx.cfg.horizon.days;

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

                fprintf('  status=solved  total=%.3f kCHF (E=%.3f S=%.3f I=%.3f L=%.3f BESSLoss=%.3f)\n', ...
                    out.costs.total/1000, out.costs.E/1000, out.costs.S/1000, out.costs.I/1000, ...
                    out.costs.L/1000, out.costs.BESSLoss/1000);
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

out_dir = fullfile(proj.results, 'experiments', 'pvev_crate_equalized_check');
if ~isfolder(out_dir); mkdir(out_dir); end
save(fullfile(out_dir, 'results.mat'), 'results', '-v7.3');
fprintf('\nSaved: %s\n', fullfile(out_dir, 'results.mat'));

end

function tech = local_build_tech_cfg(which, bp_ph)
mk = @(name, c_rate, eta) struct('name', name, 'c_rate', c_rate, ...
    'eta_ch', eta, 'eta_dis', eta, 'Emax_pu', 40, 'Smax_pu', 40, ...
    'cE', 300*bp_ph, 'cS', 100*bp_ph, 'cI', 2000, ...
    'cE_per_kWh', 300, 'cS_per_kW', 100, 'cI_fixed', 2000);
switch which
    case "LiIon";          picks = {mk('LiIon', 1.1, 0.90)};
    case "NaIon_Crate1p1"; picks = {mk('NaIon', 1.1, 0.85)};   % C-rate forced to match LiIon
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
