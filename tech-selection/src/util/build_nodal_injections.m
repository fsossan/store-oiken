function inj = build_nodal_injections(grid, horizon, D, steps_per_day, profile_params)
% BUILD_NODAL_INJECTIONS  Nodal demand / PV / EV injection time series for one network.
%
%   inj = build_nodal_injections(grid)
%   inj = build_nodal_injections(grid, horizon)
%   inj = build_nodal_injections(grid, horizon, D)
%   inj = build_nodal_injections(grid, horizon, D, steps_per_day)
%   inj = build_nodal_injections(grid, horizon, D, steps_per_day, profile_params)
%
%   (formerly build_temporal_profiles; that name still works as a wrapper)
%
%   Terminology: a PROFILE is a dimensionless shape over the day (the PV year
%   in pu of kWp, the demand GMM's cluster means, the EV charging block). The
%   INJECTIONS are those shapes multiplied by each node's magnitude: the power
%   at every node per time step, in pu, with the load flow's sign convention
%   (negative = consumption). This is what the load flow, the screening and
%   the MILP consume.
%
%   Inputs
%   ------
%   grid           : struct  from get_grid_SFOE (nodal_nominal_power,
%                    nodal_PV_SFOE, nodal_N_EV, basepower, net_id)
%   horizon        : vector  timestep indices into the native day to keep,
%                    e.g. 1:96 (full day) or 1:32 for a shorter debug window.
%                    [] or omitted -> full native day.
%   D              : scalar  number of days. [] or omitted -> 1. What D means
%                    to each stream is decided by its generator: demand draws
%                    D days per node (nested: day 1 is the same for any D),
%                    PV picks a representative day/week/month/year
%                    (load_pv_profile), EV tiles one day D times.
%   steps_per_day  : scalar  expected native steps/day (= 24/Ts_h from
%                    config/sizing_cfg.json). Checked against each stream's
%                    native resolution; [] or omitted -> no check. Demand and
%                    PV can be block-averaged down to it instead of erroring
%                    (profile_params.demand/.pv .allow_ts_downsample).
%   profile_params : struct  optional, fields .demand / .pv / .ev forwarded to
%                    generate_load_profile / load_pv_profile /
%                    generate_ev_profile (see those for the knobs). Normally
%                    the demand_profile / pv_profile / ev_profile blocks of
%                    sizing_cfg.json. Each accepts .enabled (default true).
%
%   Output
%   ------
%   inj : struct
%       .T, .Nd
%       .nodal_injections_D_pu    [T x Nd]   demand (negative), complex P + jQ
%       .nodal_injections_PV_pu   [T x Npv]  PV (positive)
%       .nodal_injections_EV_pu   [T x Nev]  EV charging (negative)
%       .to_all_nodes_D/_PV/_EV   [N x Nx]   pinv(make_M(mask)) expansions
%       .nodes_with_demand/_PV/_EV [N x 1]   logical masks
%       .demand_cluster           [Nd x 1]   GMM cluster per demand node
%       .magnitudes   per-node magnitudes the shapes were scaled by:
%                     .PLmax_kW [Nd] fuse-rated 3-phase peak (if grid carries it),
%                     .nominal_kW [Nd] 3-phase kW after demand_factor,
%                     .pv_kWp [Npv], .ev_count [Nev]
%       .calendar     .D .horizon .steps_per_day .pv_day_idx .pv_dates
%                     .pv_series .pv_season .demand_season .demand_weekday
%       .seeds        .demand .ev   the per-network seeds actually used
%
%   Determinism: for the same grid, scenario allocation and profile_params the
%   output is identical on every call and in every MATLAB session. Demand and
%   EV draw from their own seeded streams (sample_load_gmm,
%   EV_uncontrolled_profile) and restore the caller's rng afterwards; PV is
%   deterministic. The report (run_portfolio_report) and the MILP
%   (preprocess_network) therefore see the same injections with no file
%   exchange. Seeds are net_num + demand_profile.seed_offset (default 1236)
%   and net_num + ev_profile.seed_offset (default 5678); keep the two offsets
%   different, or demand clusters and EV arrivals stop being independent.
%
%   Time axis: DAY-CONTIGUOUS. Each generator returns [Nx x S x D]
%   (node x step x day); this function slices to `horizon` and reshapes so
%   timesteps run day1[1..H], day2[1..H], ... (slice_day_contiguous_pu). The
%   MILP's sequential SOE recursion relies on that ordering.

if nargin < 2; horizon = []; end
if nargin < 3 || isempty(D); D = 1; end
if nargin < 4; steps_per_day = []; end
if nargin < 5 || isempty(profile_params); profile_params = struct(); end
profile_params = set_default(profile_params, 'demand', struct());
profile_params = set_default(profile_params, 'pv',     struct());
profile_params = set_default(profile_params, 'ev',     struct());

% ---- node masks ----
nodes_with_demand = grid.nodal_nominal_power > 0;
nodes_with_PV     = grid.nodal_PV_SFOE > 0;
nodes_with_EV     = grid.nodal_N_EV > 0;
Nd = sum(nodes_with_demand);

% ---- seeds: one per stream, derived from the network id ----
profile_params.demand = set_default(profile_params.demand, 'seed_offset', 1236);
profile_params.ev     = set_default(profile_params.ev,     'seed_offset', 5678);
net_num     = str2double(grid.net_id);
demand_seed = net_num + profile_params.demand.seed_offset;
ev_seed     = net_num + profile_params.ev.seed_offset;

% ---- generate each stream at native resolution, [Nx x S x D] ----
[D_kw, S_d, nodal_cluster] = generate_load_profile( ...
    grid.nodal_nominal_power(nodes_with_demand), D, profile_params.demand, demand_seed);

[PV_kw, S_pv, pv_meta] = load_pv_profile( ...
    grid.nodal_PV_SFOE(nodes_with_PV), D, profile_params.pv);

[EV_kw, S_ev] = generate_ev_profile( ...
    grid.nodal_N_EV(nodes_with_EV), D, profile_params.ev, ev_seed);

% ---- optional block-average of demand / PV down to steps_per_day ----
% Workaround for running at a coarser Ts_h than the native 15-min data
% without resampling the sources. Block-averaging conserves daily energy but
% understates peaks, so peak-driven results at a coarse Ts_h are not directly
% comparable to a native run. Only integer-factor downsampling is supported.
profile_params.demand = set_default(profile_params.demand, 'allow_ts_downsample', false);
profile_params.pv     = set_default(profile_params.pv,     'allow_ts_downsample', false);
if ~isempty(steps_per_day) && S_d ~= steps_per_day && profile_params.demand.allow_ts_downsample
    [D_kw, S_d] = block_average_downsample(D_kw, S_d, steps_per_day, D, 'demand_profile');
end
if ~isempty(steps_per_day) && S_pv ~= steps_per_day && profile_params.pv.allow_ts_downsample
    [PV_kw, S_pv] = block_average_downsample(PV_kw, S_pv, steps_per_day, D, 'pv_profile');
end

% ---- horizon default: full native day, from demand's resolution ----
if isempty(horizon)
    horizon = 1:S_d;
end

% ---- dimension check: every enabled stream vs the configured steps_per_day ----
if ~isempty(steps_per_day)
    check_steps_per_day('demand', S_d, steps_per_day);
    pv_enabled = ~isfield(profile_params.pv, 'enabled') || profile_params.pv.enabled;
    ev_enabled = ~isfield(profile_params.ev, 'enabled') || profile_params.ev.enabled;
    if pv_enabled
        check_steps_per_day('PV', S_pv, steps_per_day);
    end
    if ev_enabled
        check_steps_per_day('EV', S_ev, steps_per_day);
    end
end

% ---- slice to horizon, day-contiguous, pu ----
nodal_injections_D_pu  = slice_day_contiguous_pu(D_kw,  horizon, grid.basepower);
nodal_injections_PV_pu = slice_day_contiguous_pu(PV_kw, horizon, grid.basepower);
nodal_injections_EV_pu = slice_day_contiguous_pu(EV_kw, horizon, grid.basepower);

% ---- mapping matrices ----
to_all_nodes_D  = pinv(make_M(nodes_with_demand));
to_all_nodes_PV = pinv(make_M(nodes_with_PV));
to_all_nodes_EV = pinv(make_M(nodes_with_EV));

% ---- pack ----
inj.T  = numel(horizon) * D;
inj.Nd = Nd;

inj.nodal_injections_D_pu  = nodal_injections_D_pu;
inj.nodal_injections_PV_pu = nodal_injections_PV_pu;
inj.nodal_injections_EV_pu = nodal_injections_EV_pu;

inj.to_all_nodes_D  = to_all_nodes_D;
inj.to_all_nodes_PV = to_all_nodes_PV;
inj.to_all_nodes_EV = to_all_nodes_EV;

inj.nodes_with_demand = nodes_with_demand;
inj.nodes_with_PV     = nodes_with_PV;
inj.nodes_with_EV     = nodes_with_EV;

inj.demand_cluster = nodal_cluster;

% ---- provenance for reports ----
inj.magnitudes.nominal_kW = 3 * real(grid.nodal_nominal_power(nodes_with_demand));
if isfield(grid, 'nodal_PLmax_kW')
    inj.magnitudes.PLmax_kW = grid.nodal_PLmax_kW(nodes_with_demand);
else
    inj.magnitudes.PLmax_kW = [];
end
inj.magnitudes.pv_kWp   = 3 * grid.nodal_PV_SFOE(nodes_with_PV);
inj.magnitudes.ev_count = grid.nodal_N_EV(nodes_with_EV);

inj.calendar.D              = D;
inj.calendar.horizon        = horizon;
inj.calendar.steps_per_day  = S_d;
inj.calendar.pv_day_idx     = pv_meta.day_idx;
inj.calendar.pv_dates       = pv_meta.dates;
inj.calendar.pv_series      = pv_meta.series;
inj.calendar.pv_season      = pv_meta.season;
inj.calendar.demand_season  = string(get_or(profile_params.demand, 'season',  "all"));
inj.calendar.demand_weekday = string(get_or(profile_params.demand, 'weekday', "all"));

inj.seeds.demand = demand_seed;
inj.seeds.ev     = ev_seed;

end

% =========================================================================
function v = get_or(s, f, default)
if isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = default;
end
end

% =========================================================================
function check_steps_per_day(label, s_native, s_expected)
if s_native ~= s_expected
    error('build_nodal_injections:tsMismatch', ...
        ['sizing_cfg.json horizon.Ts_h implies %d steps/day, but the %s ' ...
         'stream is natively %d steps/day. Resample the input data or ' ...
         'set horizon.Ts_h = %g.'], s_expected, label, s_native, 24/s_native);
end
end

% =========================================================================
function [X_kw, s_new] = block_average_downsample(X_kw, s_native, s_expected, D, cfg_field)
% Block-average [Nx x s_native x D] down to [Nx x s_expected x D].
if mod(s_native, s_expected) ~= 0 || s_expected > s_native
    error('build_nodal_injections:resampleUnsupported', ...
        ['%s.allow_ts_downsample is true, but the native %d steps/day does not ' ...
         'divide evenly into the configured %d steps/day (only integer-factor ' ...
         'downsampling is supported, not upsampling).'], cfg_field, s_native, s_expected);
end
ratio = s_native / s_expected;
Nx    = size(X_kw, 1);
X_kw  = reshape(mean(reshape(X_kw, Nx, ratio, s_expected, D), 2), Nx, s_expected, D);
s_new = s_expected;
end
