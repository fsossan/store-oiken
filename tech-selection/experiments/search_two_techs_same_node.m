function results = search_two_techs_same_node(cI_list, cost_fn, network_id, cE_li_list, c_rate_li)
% SEARCH_TWO_TECHS_SAME_NODE  Look for a scenario where the optimal siting puts
%   two technologies (LiIon + NaIon) at the same node, i.e. where dropping
%   sum(I(n,:)) <= 1 matters. Sweeps the fixed installation cost cI (a second
%   unit at a node costs another cI). Demand+PV(clearsky x1)+EV, 1 day, exact
%   charge/discharge exclusivity. Preprocessing runs once; each case is only
%   the MILP. For every cI it solves constraint-OFF, then constraint-ON if the
%   OFF solution has a node with two units (to price what the split saves).
%
%   results = search_two_techs_same_node()                  % cI = [2000 500 100 0]
%   results = search_two_techs_same_node(cI_list, cost_fn)  % cost_fn: 'Finv' |
%                                                           % 'Finv_Sloss' | 'Finv_Sloss_Eloss'

this_dir  = fileparts(mfilename('fullpath'));
repo_root = fileparts(this_dir);
addpath(repo_root);
proj = setup_paths();   % src/ on the path + project folder layout (proj.results, ...)

if nargin < 1 || isempty(cI_list);   cI_list = [2000 500 100 0]; end
if nargin < 2 || isempty(cost_fn);   cost_fn = 'Finv_Sloss_Eloss'; end
if nargin < 3 || isempty(network_id); network_id = "LV_Grid_230"; end
if nargin < 4 || isempty(cE_li_list); cE_li_list = 300; end   % LiIon CHF/kWh (NaIon stays 300)
if nargin < 5 || isempty(c_rate_li); c_rate_li = 1.1; end

ctx = load_ess_selection_context('sc1_2040');
n_idx = find(ismember(string(ctx.data_SFOE.LV_grid_id), network_id), 1);
net_id  = string(ctx.data_SFOE.LV_grid_id{n_idx});
net_num = str2double(regexp(net_id, '\d+', 'match', 'once'));
bp_ph = (ctx.config.PU_values.Sb/1000) * 3;

cf = struct('Finv', [false false], 'Finv_Sloss', [true false], 'Finv_Sloss_Eloss', [true true]);
flags_mm = cf.(cost_fn);

ctx.cfg.horizon.days = 1;
ctx.cfg.demand_profile = struct('enabled', true);
ctx.cfg.pv_profile     = struct('enabled', true, 'series', "clearsky", 'scale', 1);
ctx.cfg.ev_profile     = struct('enabled', true);
ctx.cfg.flags.min_loss             = flags_mm(1);
ctx.cfg.flags.throughput_penalty   = flags_mm(2);
ctx.cfg.flags.siting_activate      = true;
ctx.cfg.flags.cha_dis_bin_activate = true;
ctx.cfg.flags.curtailment_activate = false;
ctx.cfg.tech = local_tech(bp_ph, 2000);
ctx.cfg.J = 2;  ctx.tech_names = ctx.cfg.tech.names;  ctx.J = 2;

% ---- preprocess once (same seeding as solve_network_tech_selection) ----
rng(1234 + net_num);
t0 = tic;
[gm, dims, ~] = preprocess_network(ctx.data_SFOE, n_idx, ctx.config, ctx.cfg, []);
prepros_time = toc(t0);
grid_params = struct('R_TNd_toNdT', dims.R_TNd_toNdT, 'CABLE_AMP', dims.CABLE_AMP, ...
    'slack_S_mag_pu', dims.slack_S_mag_pu, 'R_TNpv_toNpvT', dims.R_TNpv_toNpvT, ...
    'PV_avail_pu_stacked', dims.PV_avail_pu_stacked);
net_meta = struct('scenario', ctx.scenario, 'net_id', net_id, 'net_num', net_num, ...
    'tech_names', {ctx.tech_names}, 'MAX_LIN_ITER', 1);
run_opts = struct('MAX_LIN_ITER', 1, 'verbose_debug', false, 'log_fid', [], 'enable_plots', false);
Ts = ctx.cfg.horizon.Ts_h;  T = dims.T;

results = struct([]);
for cE_li = cE_li_list
for cI = cI_list
    cfg = ctx.cfg;
    cfg.tech = local_tech(bp_ph, cI, cE_li, c_rate_li);
    for one_tech = [false true]
        if one_tech && ~(~isempty(results) && results(end).n_multi > 0 ...
                && results(end).cI == cI && results(end).cE_li == cE_li)
            continue   % only price the split when the OFF run actually used one
        end
        fl = cfg.flags;  fl.one_tech_per_node = one_tech;
        opts = struct('current_mag_cstr', cfg.solver.current_mag_cstr, ...
            'siting_activate', fl.siting_activate, 'cha_dis_bin_activate', fl.cha_dis_bin_activate, ...
            'min_loss', fl.min_loss, 'curtailment_activate', fl.curtailment_activate, ...
            'throughput_penalty', fl.throughput_penalty, 'one_tech_per_node', one_tech);
        fprintf('\n--- cE_Li=%g cI=%g  one_tech_per_node=%d ---\n', cE_li, cI, one_tech);
        [status, out] = run_seq_lin_loop_ess(gm, dims, grid_params, opts, cfg, net_meta, prepros_time, run_opts);
        row = struct('cI', cI, 'cE_li', cE_li, 'cost_fn', cost_fn, 'one_tech', one_tech, 'status', string(status), ...
            'total_kCHF', NaN, 'units', table(), 'n_multi', 0);
        if strcmp(status, 'solved')
            I_inst = out.sizing.Installation;
            E = out.sizing.E_nom_node_pu * bp_ph;  S = out.sizing.S_conv_node_pu * bp_ph;
            nid = out.sizing.demand_node_id;
            [n_, j_] = find(I_inst & (E > 0.01 | S > 0.01));   % ignore empty (I=1, E=S=0) units
            [~, o] = sort(nid(n_));  n_ = n_(o);  j_ = j_(o);
            u = table();
            for i = 1:numel(n_)
                Idx = (n_(i)-1)*T + (1:T);
                thr = (sum(out.injections.B_plus(Idx,j_(i))) + sum(out.injections.B_minus(Idx,j_(i)))) * Ts * bp_ph;
                u = [u; table(nid(n_(i)), string(cfg.tech.names{j_(i)}), E(n_(i),j_(i)), S(n_(i),j_(i)), thr, ...
                    'VariableNames', {'node_id','tech','E_kWh','S_kW','throughput_kWh'})]; %#ok<AGROW>
            end
            row.units = u;  row.total_kCHF = out.costs.total/1000;
            if ~isempty(u); row.n_multi = sum(accumarray(findgroups(u.node_id), 1) > 1); end
            fprintf('  total=%.4f kCHF  units=%d  nodes_with_2_techs=%d\n', row.total_kCHF, height(u), row.n_multi);
            disp(u);
        end
        if isempty(results); results = row; else; results(end+1) = row; end %#ok<AGROW>
    end
end
end
out_dir = fullfile(proj.results, 'experiments', 'one_tech_per_node_study');
if ~isfolder(out_dir); mkdir(out_dir); end
save(fullfile(out_dir, sprintf('search_%s.mat', cost_fn)), 'results');
end

function tech = local_tech(bp_ph, cI, cE_li, c_rate_li)
if nargin < 3; cE_li = 300; end
if nargin < 4; c_rate_li = 1.1; end
mk = @(name, c_rate, eta, cE) struct('name', name, 'c_rate', c_rate, 'eta_ch', eta, 'eta_dis', eta, ...
    'Emax_pu', 40, 'Smax_pu', 40, 'cE', cE*bp_ph, 'cS', 100*bp_ph, 'cI', cI, ...
    'cE_per_kWh', cE, 'cS_per_kW', 100, 'cI_fixed', cI);
p = {mk('LiIon', c_rate_li, 0.90, cE_li), mk('NaIon', 5, 0.85, 300)};
tech.names = cellfun(@(s) s.name, p, 'UniformOutput', false);
for f = {'c_rate','eta_ch','eta_dis','Emax_pu','Smax_pu','cE','cS','cI','cE_per_kWh','cS_per_kW','cI_fixed'}
    tech.(f{1}) = cellfun(@(s) s.(f{1}), p);
end
end
