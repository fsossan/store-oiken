function results = test_charge_referred_penalty(eps_list, network_id)
% TEST_CHARGE_REFERRED_PENALTY  Does the charge-referred exclusivity penalty
%   ('charge_referred') restore agreement with the exact (binary) formulation
%   where the plain penalty ('plain') is predicted to pick the wrong
%   technology at large cha_dis_penalty_eps? See
%   docs/relaxed-penalty-substandard-tech-selection.md for the derivation.
%
%   PV-only (demand+PV, no EV) so the bug's predicted mechanism applies
%   (charge-driven violation -- see the doc's "why only PV-only nodes"
%   section). Both LiIon and NaIon available. Runs, for each eps in
%   eps_list: exact binary (ground truth, eps irrelevant but run once),
%   relaxed+plain, relaxed+charge_referred. throughput_penalty is ON
%   (min_loss off) so F^eff is actually in the objective -- the mechanism
%   this bug depends on.
%
%   results = test_charge_referred_penalty()                 % eps = [50 500 2000]
%   results = test_charge_referred_penalty(eps_list, network_id)

this_dir  = fileparts(mfilename('fullpath'));
repo_root = fileparts(this_dir);
addpath(repo_root);
proj = setup_paths();   % src/ on the path + project folder layout (proj.results, ...)

if nargin < 1 || isempty(eps_list);   eps_list   = [50 500 2000]; end
if nargin < 2 || isempty(network_id); network_id = "LV_Grid_230"; end

ctx0 = load_ess_selection_context('sc1_2040');
n_idx = find(ismember(string(ctx0.data_SFOE.LV_grid_id), network_id), 1);
Sb = ctx0.config.PU_values.Sb;
bp_ph = (Sb/1000) * 3;

ctx0.cfg.horizon.days = 1;
ctx0.cfg.demand_profile = struct('enabled', true);
ctx0.cfg.pv_profile     = struct('enabled', true, 'series', "clearsky", 'scale', 1);
ctx0.cfg.ev_profile     = struct('enabled', false);   % PV-only, per the doc's mechanism
ctx0.cfg.flags.siting_activate      = true;
ctx0.cfg.flags.curtailment_activate = false;
ctx0.cfg.flags.min_loss             = false;
ctx0.cfg.flags.throughput_penalty   = true;   % F^eff must be active -- the mechanism needs it
ctx0.cfg.tech = local_tech(bp_ph);
ctx0.cfg.J = 2; ctx0.tech_names = ctx0.cfg.tech.names; ctx0.J = 2;

run_opts = struct('MAX_LIN_ITER', 1, 'verbose_debug', false, 'log_fid', []);
results = struct([]);

% ---- ground truth: exact binary formulation ----
ctx = ctx0;
ctx.cfg.flags.cha_dis_bin_activate = true;
fprintf('\n--- EXACT (binary), ground truth ---\n');
row = run_one(ctx, n_idx, run_opts, "exact", NaN, bp_ph);
results = row;

% ---- relaxed, plain vs charge_referred, at each eps ----
for eps = eps_list
    for form = ["plain", "charge_referred"]
        ctx = ctx0;
        ctx.cfg.flags.cha_dis_bin_activate = false;
        ctx.cfg.solver.cha_dis_penalty_eps  = eps;
        ctx.cfg.solver.cha_dis_penalty_form = char(form);
        fprintf('\n--- RELAXED, form=%s, eps=%g ---\n', form, eps);
        row = run_one(ctx, n_idx, run_opts, form, eps, bp_ph);
        results(end+1) = row; %#ok<AGROW>
    end
end

fprintf('\n=== Summary: installed technology per node ===\n');
exact_row = results(1);   % exact run is always appended first, by construction
fprintf('exact (ground truth): %s\n', tech_map_str(exact_row));
for k = 2:numel(results)
    matches = isequal(results(k).node_tech_map, exact_row.node_tech_map);
    fprintf('%-16s eps=%-6g : %-40s  MATCHES EXACT? %d\n', ...
        results(k).label, results(k).eps, tech_map_str(results(k)), matches);
end

out_dir = fullfile(proj.results, 'experiments');
if ~isfolder(out_dir); mkdir(out_dir); end
save(fullfile(out_dir, 'test_charge_referred_penalty_results.mat'), 'results');
end

% -------------------------------------------------------------------------
function row = run_one(ctx, n_idx, run_opts, label, eps, bp_ph)
row = struct('label', label, 'eps', eps, 'status', "", 'total_kCHF', NaN, ...
    'node_tech_map', struct(), 'error_msg', "");
try
    [status, result] = solve_network_tech_selection(ctx, n_idx, [], false, run_opts);
    row.status = string(status);
    if strcmp(status, 'solved')
        out = result.out;
        I_inst = out.sizing.Installation;
        node_id = out.sizing.demand_node_id;
        [n_, j_] = find(I_inst);
        m = struct();
        for i = 1:numel(n_)
            m.(sprintf('n%d', node_id(n_(i)))) = out.sizing.tech_names{j_(i)};
        end
        row.node_tech_map = m;
        row.total_kCHF = out.costs.total/1000;
        fprintf('  status=solved  total=%.4f kCHF  %s\n', row.total_kCHF, tech_map_str(row));
    else
        fprintf('  status=%s\n', status);
    end
catch ME
    row.status = "error";
    row.error_msg = string(ME.message);
    fprintf('  ERROR: %s\n', ME.message);
end
end

function s = tech_map_str(row)
f = fieldnames(row.node_tech_map);
if isempty(f); s = '(none installed)'; return; end
parts = cellfun(@(k) sprintf('%s=%s', k, row.node_tech_map.(k)), f, 'UniformOutput', false);
s = strjoin(parts, ', ');
end

function tech = local_tech(bp_ph)
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
