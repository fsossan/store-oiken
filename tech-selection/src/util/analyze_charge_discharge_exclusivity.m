function report = analyze_charge_discharge_exclusivity(out, cfg, make_plots, rating_thresh)
% ANALYZE_CHARGE_DISCHARGE_EXCLUSIVITY  Explain simultaneous charge/discharge
%                                        behaviour for one solved network.
%
%   report = analyze_charge_discharge_exclusivity(out)
%   report = analyze_charge_discharge_exclusivity(out, cfg)   % cfg optional,
%                                                              % adds penalty context
%                                                              % AND is required for
%                                                              % the rating-normalized
%                                                              % metric (needs cfg.tech.c_rate)
%   report = analyze_charge_discharge_exclusivity(out, cfg, make_plots)
%                                                              % make_plots optional,
%                                                              % default true; set
%                                                              % false for batch/sweep
%                                                              % use (report struct only)
%   report = analyze_charge_discharge_exclusivity(out, cfg, make_plots, rating_thresh)
%                                                              % rating_thresh optional;
%                                                              % default sourced from
%                                                              % cfg.solver.cha_dis_rating_thresh
%                                                              % (config/sizing_cfg.json), else 0.01
%                                                              % (1% of c_rate*E_nom cap) if no cfg
%
%   Two violation metrics are reported, on purpose -- they answer different
%   questions and neither replaces the other:
%     - phantom_pct: sum(B_exc)/sum(B_plus+B_minus), i.e. % of this node's own
%       total dispatched ENERGY over the whole horizon that was phantom. Not
%       comparable across nodes -- a low-throughput node makes a small
%       violation look huge (%), a high-throughput node hides a real one.
%     - rating_frac(t) = B_exc(t) / (c_rate*E_nom): per-timestep phantom power
%       as a fraction of that node's own individual charge/discharge CAP
%       (c_rate*E_nom, solve_ess_milp.m:183-184), bounded in [0,1] by
%       construction (B_plus,B_minus are each already box-constrained to that
%       cap individually). Comparable across nodes regardless of how much
%       that battery happened to cycle -- "1% of cap" means the same thing
%       everywhere. max_rating_frac_k / n_exceed_k (count of timesteps over
%       rating_thresh) are the per-pair summaries of this.
%       NOTE: this is NOT kP*S_conv -- that box only bounds the NET dispatch
%       B_bat_var = B_plus-B_minus (solve_ess_milp.m:197-204), so it does not
%       cap B_plus/B_minus individually and is the wrong denominator here (an
%       earlier version of this function used kP*S_conv and produced
%       fractions >100%, which is how this was caught).
%
%   Call after loading a solved .mat (or right after run_seq_lin_loop_ess),
%   same convention as analyze_curtailment(out, cfg) / analyze_losses(out).
%
%   Only meaningful when the linear charge/discharge penalty relaxation is
%   active (opts.cha_dis_bin_activate = false, see solve_ess_milp_v2.m) --
%   when the exact binary formulation is used instead, exclusivity is
%   enforced by construction and this should report ~0 violations
%   everywhere, which doubles as a self-consistency check.
%
%   Scoped to installed (node, technology) pairs only (out.sizing.Installation),
%   not to every technology column blindly summed over all Nd nodes -- a
%   technology that was never sited anywhere has B_plus=B_minus=0 by
%   construction (Big-M + C-rate box), so including it just pads every
%   denominator with a vacuous "0/T pass" that isn't a real check of
%   anything. Reuses out.injections.B_exc = min(B_plus, B_minus) and
%   out.diagnostics.cha_dis_vio (already computed by build_network_result.m
%   for every solve).
%
%   "Phantom throughput" = sum(min(B_plus, B_minus)): the portion of
%   reported charge+discharge activity that happens at the same node, same
%   technology, same timestep in both directions at once -- something a real
%   battery cannot physically do. It only shows up because the relaxed (non-
%   binary) formulation doesn't enforce exact either/or dispatch; it's an
%   artifact of the LP relaxation, not real net battery throughput.
%
%   Produces two figures:
%     1. Phantom-throughput fraction (%) per installed (node, technology) pair
%     2. Small-multiples grid, one panel per installed (node, technology)
%        pair: B_plus, B_minus, min(B_plus,B_minus) in kW (pu * 300, the
%        bp*ph single-phase-pu -> 3-phase-kW factor used throughout this
%        repo -- see docs/DEVELOPMENT_NOTES.md). Each panel title also reports that node's
%        total phantom energy in kWh (pu * 300 * Ts).
%
%   Console report and both figures are in real 3-phase kW/kWh (pu * 300,
%   energy sums additionally * Ts), not pu -- pu is meaningless to read
%   directly. Returns a struct with both the pu numbers (.total_throughput,
%   .total_phantom, .max_violation, .per_node.*_pu -- kept as-is for
%   existing callers, e.g. the exact-vs-relaxed horizon-scaling study) and
%   the same quantities in real units (.total_throughput_kWh,
%   .total_phantom_kWh, .max_violation_kW, .per_node.throughput_kWh,
%   .per_node.phantom_kWh, .per_node.max_violation_kW). .per_tech has been
%   replaced by .per_node (see field list at the bottom).

if nargin < 2; cfg = []; end
if nargin < 3 || isempty(make_plots); make_plots = true; end
if nargin < 4 || isempty(rating_thresh)
    if ~isempty(cfg) && isfield(cfg, 'solver') && isfield(cfg.solver, 'cha_dis_rating_thresh')
        rating_thresh = cfg.solver.cha_dis_rating_thresh;   % config/sizing_cfg.json
    else
        rating_thresh = 0.01;   % 1% of c_rate*E_nom, fallback for cfg-less calls
    end
end

have_crate = ~isempty(cfg) && isfield(cfg, 'tech') && isfield(cfg.tech, 'c_rate');
if have_crate
    c_rate = cfg.tech.c_rate;   % [1 x J]
else
    warning('analyze_charge_discharge_exclusivity:noCrate', ...
        'cfg.tech.c_rate not available -- skipping the rating-normalized metric (need cfg).');
end

tol = 1e-6;   % pu, matches build_network_result.m's tol_exc
kW_per_pu = kw_per_pu_of(out);   % pu -> real 3-phase kW/kWh (out.meta.kW_per_pu; 300 for old results)
if isfield(out, 'meta') && isfield(out.meta, 'Ts_h') && ~isempty(out.meta.Ts_h)
    Ts = out.meta.Ts_h;
elseif ~isempty(cfg) && isfield(cfg, 'solver') && isfield(cfg.solver, 'Ts_h')
    Ts = cfg.solver.Ts_h;
else
    Ts = 0.25;
end

T  = numel(out.injections.P_sloss);
Nd = out.grid.Nd;
J  = size(out.sizing.E_nom_node_pu, 2);

B_plus  = out.injections.B_plus;    % [T*Nd x J]
B_minus = out.injections.B_minus;   % [T*Nd x J]
B_exc   = out.injections.B_exc;     % [T*Nd x J], min(B_plus,B_minus)
E_pu    = out.sizing.E_nom_node_pu;  % [Nd x J], for the rating-normalized metric (c_rate*E_nom cap)

if isfield(out, 'sizing') && isfield(out.sizing, 'tech_names') && ~isempty(out.sizing.tech_names)
    tech_names = out.sizing.tech_names;
else
    tech_names = arrayfun(@(j) sprintf('tech%d', j), 1:J, 'UniformOutput', false);
end

% -------------------------------------------------------------------------
%  Per (node, technology) breakdown -- installed pairs only
% -------------------------------------------------------------------------
Installation   = out.sizing.Installation;    % [Nd x J] binary
[inst_n, inst_j] = find(Installation);
n_pairs = numel(inst_n);

node_id_k    = zeros(n_pairs, 1);
tech_k       = cell(n_pairs, 1);
throughput_k = zeros(n_pairs, 1);
phantom_k    = zeros(n_pairs, 1);
phantom_pct_k = zeros(n_pairs, 1);
max_vio_k    = zeros(n_pairs, 1);
n_vio_k      = zeros(n_pairs, 1);
row_idx_k    = cell(n_pairs, 1);
max_rating_frac_k = zeros(n_pairs, 1);   % max_t B_exc(t) / (c_rate*E_nom), NaN if !have_crate
n_exceed_k         = zeros(n_pairs, 1);  % count of timesteps with rating_frac >= rating_thresh

for k = 1:n_pairs
    n = inst_n(k);
    j = inst_j(k);
    Idx = (n-1)*T + (1:T);
    row_idx_k{k}      = Idx;
    node_id_k(k)      = out.sizing.demand_node_id(n);
    tech_k{k}         = tech_names{j};
    throughput_k(k)   = sum(B_plus(Idx,j)) + sum(B_minus(Idx,j));
    phantom_k(k)      = sum(B_exc(Idx,j));
    phantom_pct_k(k)  = 100 * phantom_k(k) / max(throughput_k(k), eps);
    max_vio_k(k)      = max(B_exc(Idx,j));
    n_vio_k(k)         = sum(B_exc(Idx,j) > tol);

    if have_crate
        cap = c_rate(j) * E_pu(n,j);
        rating_frac_vec = B_exc(Idx,j) / max(cap, eps);
        max_rating_frac_k(k) = max(rating_frac_vec);
        n_exceed_k(k)         = sum(rating_frac_vec >= rating_thresh);
    else
        max_rating_frac_k(k) = NaN;
        n_exceed_k(k)         = NaN;
    end
end

% -------------------------------------------------------------------------
%  Overall (reuses build_network_result.m's already-computed diagnostics)
% -------------------------------------------------------------------------
total_throughput = sum(throughput_k);
total_phantom    = sum(phantom_k);
pct_phantom      = 100 * total_phantom / max(total_throughput, eps);
is_clean         = ~out.diagnostics.cha_dis_vio;

if n_pairs > 0
    [max_vio, max_k] = max(max_vio_k);
    max_node_id = node_id_k(max_k);
    max_tech    = tech_k{max_k};
else
    max_vio = 0; max_node_id = []; max_tech = '';
end

if n_pairs > 0 && have_crate
    [max_rating_frac_overall, max_rk] = max(max_rating_frac_k);
    max_rating_node_id = node_id_k(max_rk);
    max_rating_tech    = tech_k{max_rk};
else
    max_rating_frac_overall = NaN; max_rating_node_id = []; max_rating_tech = '';
end

% Real-unit conversions for display: throughput/phantom are sums of power
% samples over T steps, so *Ts turns them into energy (kWh); max_vio is a
% single-timestep value, so it stays a power (kW). kW_per_pu = bp*ph = 300
% (single-phase pu -> real 3-phase, see docs/DEVELOPMENT_NOTES.md).
throughput_kWh_k = throughput_k * kW_per_pu * Ts;
phantom_kWh_k    = phantom_k    * kW_per_pu * Ts;
max_vio_kW_k     = max_vio_k    * kW_per_pu;
total_throughput_kWh = total_throughput * kW_per_pu * Ts;
total_phantom_kWh    = total_phantom    * kW_per_pu * Ts;
max_vio_kW            = max_vio          * kW_per_pu;

% -------------------------------------------------------------------------
%  Console report
% -------------------------------------------------------------------------
fprintf('\n=== Charge/discharge exclusivity diagnostics: network %s ===\n', ...
    string(out.meta.network_id_str));
if is_clean
    fprintf('  PASS -- no simultaneous charge/discharge above tol=%.1e pu (%.4f kW) detected.\n', tol, tol*kW_per_pu);
else
    fprintf('  WARN -- simultaneous charge/discharge detected.\n');
end
fprintf('  Total phantom throughput: %.3f kWh (%.3f%% of %.3f kWh total dispatch, %d installed node-tech pair(s))\n', ...
    total_phantom_kWh, pct_phantom, total_throughput_kWh, n_pairs);
if n_pairs > 0
    fprintf('  Worst single violation:   %.3f kW at node %d, tech %s\n', max_vio_kW, max_node_id, max_tech);
end
if n_pairs > 0 && have_crate
    fprintf('  Worst rating-relative:    %.3f%% of c_rate*E_nom at node %d, tech %s (threshold=%.2f%%)\n', ...
        100*max_rating_frac_overall, max_rating_node_id, max_rating_tech, 100*rating_thresh);
end
fprintf('  --- per installed (node, technology) pair ---\n');
if n_pairs == 0
    fprintf('  (no technology installed at any node -- nothing to check)\n');
end
for k = 1:n_pairs
    if have_crate
        rating_str = sprintf('  max_rating_frac=%.3f%%  n_exceed(%.0f%%)=%d/%d', ...
            100*max_rating_frac_k(k), 100*rating_thresh, n_exceed_k(k), T);
    else
        rating_str = '';
    end
    fprintf('  [node %3d, %s] throughput=%.3f kWh  phantom=%.3f kWh (%.3f%%)  max_vio=%.3f kW  n_violations=%d/%d%s\n', ...
        node_id_k(k), tech_k{k}, throughput_kWh_k(k), phantom_kWh_k(k), phantom_pct_k(k), max_vio_kW_k(k), n_vio_k(k), T, rating_str);
end
if ~isempty(cfg) && isfield(cfg, 'solver') && isfield(cfg.solver, 'cha_dis_penalty_eps')
    fprintf('  (relaxed-formulation penalty eps used: %.2e)\n', cfg.solver.cha_dis_penalty_eps);
end
fprintf('\n');

% -------------------------------------------------------------------------
%  Figures
% -------------------------------------------------------------------------
if make_plots && n_pairs > 0
    % --- Figure 1: phantom-throughput fraction per installed (node, tech) pair ---
    figure('Name', 'Charge/Discharge Exclusivity — Overview')
    labels = arrayfun(@(k) sprintf('N%d-%s', node_id_k(k), tech_k{k}), 1:n_pairs, 'UniformOutput', false);
    if have_crate
        bar(categorical(labels, labels), [phantom_pct_k, 100*max_rating_frac_k])
        ylabel('Violation (%)'); grid on
        legend({'phantom / own throughput', 'max phantom / (c_{rate}E_{nom})'}, 'Location', 'best')
        title(sprintf('Exclusivity violation by installed node/technology (overall %.3f%% throughput, %.3f%% rating)', ...
            pct_phantom, 100*max_rating_frac_overall))
    else
        bar(categorical(labels, labels), phantom_pct_k)
        ylabel('Phantom throughput (% of dispatch)'); grid on
        title(sprintf('Exclusivity violation by installed node/technology (overall %.3f%%)', pct_phantom))
    end

    % --- Figure 2: small multiples, one panel per installed (node, tech) pair ---
    figure('Name', 'Charge/Discharge Exclusivity — Per-node dispatch')
    ncols = min(3, n_pairs);
    nrows = ceil(n_pairs / ncols);
    tiledlayout(nrows, ncols, 'TileSpacing', 'compact', 'Padding', 'compact')
    t = (1:T)';
    for k = 1:n_pairs
        nexttile
        Idx = row_idx_k{k};
        j   = inst_j(k);
        Bp_kW  = B_plus(Idx,j)  * kW_per_pu;
        Bm_kW  = B_minus(Idx,j) * kW_per_pu;
        Bexc_kW = B_exc(Idx,j)  * kW_per_pu;
        hold on
        plot(t, Bp_kW,  'DisplayName', 'B_{plus} (charge)')
        plot(t, Bm_kW,  'DisplayName', 'B_{minus} (discharge)')
        plot(t, Bexc_kW, 'k--', 'LineWidth', 1.5, 'DisplayName', 'min(B_{plus},B_{minus})')
        hold off
        legend('Location', 'best', 'FontSize', 7)
        xlabel('Time step (15 min)'); ylabel('kW (3-phase)'); grid on
        if have_crate
            title(sprintf('Node %d, %s (phantom: %.3f kWh, %.2f%% throughput, %.2f%% rating)', ...
                node_id_k(k), tech_k{k}, phantom_kWh_k(k), phantom_pct_k(k), 100*max_rating_frac_k(k)), 'FontSize', 9)
        else
            title(sprintf('Node %d, %s (phantom: %.3f kWh, %.2f%%)', ...
                node_id_k(k), tech_k{k}, phantom_kWh_k(k), phantom_pct_k(k)), 'FontSize', 9)
        end
    end

    sgtitle(sprintf('Network %s — Charge/Discharge Exclusivity', string(out.meta.network_id_str)), ...
        'FontSize', 13, 'FontWeight', 'bold')
elseif make_plots && n_pairs == 0
    fprintf('  (skipping plots -- no technology installed at any node)\n');
end

% -------------------------------------------------------------------------
%  Return struct
% -------------------------------------------------------------------------
report.is_clean          = is_clean;
report.total_throughput  = total_throughput;       % pu (kept for existing callers)
report.total_phantom     = total_phantom;          % pu
report.total_throughput_kWh = total_throughput_kWh;
report.total_phantom_kWh    = total_phantom_kWh;
report.pct_phantom       = pct_phantom;
report.max_violation     = max_vio;                % pu (kept for existing callers)
report.max_violation_kW  = max_vio_kW;
report.max_violation_node = max_node_id;
report.max_violation_tech = max_tech;
report.have_rating_metric      = have_crate;
report.rating_thresh           = rating_thresh;
report.max_rating_frac_overall = max_rating_frac_overall;   % NaN if !have_crate
report.max_rating_frac_node    = max_rating_node_id;
report.max_rating_frac_tech    = max_rating_tech;
report.per_node.node_id        = node_id_k;
report.per_node.tech           = tech_k(:);
report.per_node.throughput_pu  = throughput_k;
report.per_node.phantom_pu     = phantom_k;
report.per_node.throughput_kWh = throughput_kWh_k;
report.per_node.phantom_kWh    = phantom_kWh_k;
report.per_node.phantom_pct    = phantom_pct_k;
report.per_node.max_violation  = max_vio_k;        % pu (kept for existing callers)
report.per_node.max_violation_kW = max_vio_kW_k;
report.per_node.n_violations   = n_vio_k;
report.per_node.T_checked      = T * ones(n_pairs, 1);
report.per_node.max_rating_frac = max_rating_frac_k;   % NaN column if !have_crate
report.per_node.n_exceed_rating = n_exceed_k;          % NaN column if !have_crate

end
