function [X_kw, S_native] = generate_ev_profile(node_ev_counts, D, params, seed)
%GENERATE_EV_PROFILE  Uncontrolled EV charging via EV_uncontrolled_profile,
%                      one individual vehicle profile per EV (not per node),
%                      summed onto each EV-hosting node, then tiled
%                      identically across all D days.
%
%   [X_kw, S_native] = generate_ev_profile(node_ev_counts, D, params, seed)
%
%   Inputs
%   ------
%   node_ev_counts : [Nev x 1]  number of EVs at each EV-hosting node
%                    (grid.nodal_N_EV(nodes_with_EV) at the call site --
%                    every entry is >= 1, since nodes_with_EV already
%                    filters to nodal_N_EV > 0)
%   D              : scalar  number of days to tile the generated day across
%   params : struct, optional fields:
%       .dt_minutes  15     charging-profile time step, minutes
%       .enabled     true   false -> skip EV_uncontrolled_profile entirely
%                    and return an all-zero stream at the correct native
%                    resolution instead
%       .charger_kw  3.7    real per-vehicle charger rating, kW -- forwarded
%                    to EV_uncontrolled_profile; sourced from sizing_cfg.json's
%                    ev_profile.charger_kw via preprocess_network. Assumed to
%                    be a 3-phase-total rating (divided by 3 below, same as
%                    demand/PV) -- see the docstring note on that division.
%       .force_single_ev_per_node  false   TEST/COMPARISON FLAG. true ->
%                    every EV-hosting node is treated as if it had exactly 1
%                    EV, regardless of its real grid.nodal_N_EV count --
%                    reproduces this function's pre-fix behavior exactly (see
%                    docs/DEVELOPMENT_NOTES.md's "EV charging demand didn't scale with the
%                    number of EVs" note). false (default) -> current,
%                    correct per-node-count behavior. For A/B comparison
%                    only; leave false for real results.
%       .synchronized_arrivals  false   SCENARIO FLAG. true -> every vehicle
%                    at a given node shares ONE arrival time (drawn once per
%                    node, not once per vehicle), so a multi-EV node's
%                    profile is a single flat block of height
%                    count*charger_kw/3 for the full 4h window, instead of a
%                    staircase from staggered, partially-overlapping
%                    individual arrivals. Same total daily energy either way
%                    -- only the peak power / timing changes. Useful for a
%                    worst-case "all EVs at this node plug in at once"
%                    stress test (e.g. for the C-rate / tech-selection
%                    sensitivity this was built to study). false (default)
%                    keeps today's realistic staggered-arrival behavior.
%   seed : optional, forwarded to EV_uncontrolled_profile so arrival times
%          are reproducible independent of vehicle count -- see that
%          function's docstring. Omit to fall back to the ambient rng state
%          (matching demand's own documented caveat in generate_load_profile.m).
%
%   Output
%   ------
%   X_kw     : [Nev x S_native x D]  EV charging demand, single-phase-
%              equivalent kW (sign applied: negative = load, matching the
%              existing convention). Node k's slice is the SUM of
%              node_ev_counts(k) independent single-vehicle profiles (each
%              with its own random arrival time), not a single vehicle's
%              profile -- see the "one profile per node regardless of EV
%              count" bug this replaces, noted in docs/DEVELOPMENT_NOTES.md.
%
%              Divided by 3 (phases) below: EV_uncontrolled_profile returns
%              the REAL physical charger rating (params.charger_kw/vehicle),
%              but every other stream feeding slice_day_contiguous_pu
%              (demand, PV) is ALREADY single-phase-equivalent before it
%              gets there -- get_grid_SFOE.m:132-134 divides
%              nodal_nominal_power/nodal_PV_SFOE by 3 from their SFOE-sourced
%              3-phase totals. Without this division, EV was 3x too large
%              relative to demand/PV once reported back through this repo's
%              uniform bp*ph=300 "real 3-phase kW" factor (at the default
%              3.7kW: 3.7kW -> 0.037pu -> 11.1kW, not 3.7kW) -- confirmed by
%              direct arithmetic, see docs/DEVELOPMENT_NOTES.md. This assumes charger_kw is
%              meant as a 3-phase-total quantity, consistent with demand/PV's
%              convention, not as an already-single-phase physical charger
%              draw -- flag if that assumption is wrong for this dataset
%              (a genuinely single-phase-only charger is a separate,
%              not-yet-modeled case, deferred as future work).
%
%   S_native : scalar  native steps/day = 24*60/params.dt_minutes
%
%   No day-to-day variation: EV_uncontrolled_profile generates ONE day, and
%   it is tiled unchanged across every day in the horizon -- an explicit,
%   deliberate simplification (see build_temporal_profiles header), not a
%   placeholder for missing functionality.

if nargin < 3 || isempty(params); params = struct(); end
if nargin < 4; seed = []; end
params = set_default(params, 'dt_minutes', 15);
params = set_default(params, 'enabled',    true);
params = set_default(params, 'charger_kw', 3.7);
params = set_default(params, 'force_single_ev_per_node', false);
params = set_default(params, 'synchronized_arrivals', false);
params = set_default(params, 'synchronize_across_nodes', false);   % only meaningful if synchronized_arrivals=true

node_ev_counts = node_ev_counts(:);
n_ev_nodes = numel(node_ev_counts);

if params.force_single_ev_per_node
    node_ev_counts = ones(n_ev_nodes, 1);   % test-only override, see docstring
end

if ~params.enabled
    S_native = round(24*60 / params.dt_minutes);
    X_kw = zeros(n_ev_nodes, S_native, D);
    return
end

if params.synchronized_arrivals
    if params.synchronize_across_nodes
        % ONE arrival draw for the WHOLE NETWORK -- every vehicle at every
        % node shares it (stronger stress test than per-node sync: all EVs
        % everywhere plug in at the same instant).
        [~, P_EV_single, ~] = EV_uncontrolled_profile(1, params.dt_minutes, seed, params.charger_kw);   % [S_native x 1], real kW
        P_EV_single = repmat(P_EV_single, 1, n_ev_nodes);   % broadcast to every node
    else
        % One arrival draw PER NODE (not per vehicle): every vehicle at node k
        % shares that single arrival, so node k's profile is just its one-vehicle
        % shape scaled by node_ev_counts(k) -- a flat block, not a staircase.
        [~, P_EV_single, ~] = EV_uncontrolled_profile(n_ev_nodes, params.dt_minutes, seed, params.charger_kw);   % [S_native x n_ev_nodes], real kW
    end
    S_native = size(P_EV_single, 1);
    P_EV_node = (-1 * P_EV_single / 3 .* node_ev_counts(:)').';   % [n_ev_nodes x S_native], single-phase-equivalent
else
    total_vehicles = sum(node_ev_counts);
    [~, P_EV_ind, ~] = EV_uncontrolled_profile(total_vehicles, params.dt_minutes, seed, params.charger_kw);   % [S_native x total_vehicles], real kW
    P_EV_ind = -1 * P_EV_ind / 3;   % single-phase-equivalent (see docstring above)
    S_native = size(P_EV_ind, 1);

    % Sum each node's own vehicles' columns into that node's row -- node k owns
    % the next node_ev_counts(k) consecutive vehicle columns (the assignment
    % order is arbitrary since all vehicles are drawn from the same i.i.d.
    % arrival-time distribution; only the per-node SUM matters here).
    P_EV_node = zeros(n_ev_nodes, S_native);
    col = 0;
    for k = 1:n_ev_nodes
        idx = col + (1:node_ev_counts(k));
        P_EV_node(k, :) = sum(P_EV_ind(:, idx), 2).';
        col = col + node_ev_counts(k);
    end
end

X_kw = repmat(reshape(P_EV_node, n_ev_nodes, S_native, 1), 1, 1, D);   % [Nev x S_native x D]

end
