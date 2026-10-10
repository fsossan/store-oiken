function [t, P_EV_ind, arrival_times] = EV_uncontrolled_profile(N_EV, dt_minutes, seed, charger_kw)
% EV_uncontrolled_profile
%
% Returns INDIVIDUAL EV charging profiles
%
% OUTPUTS:
%   t             : time vector [h]          (T x 1)
%   P_EV_ind      : EV charging profiles     (T x N_EV), REAL kW per vehicle
%                   (charger_kw is the physical charger rating -- NOT yet
%                   converted to this repo's single-phase-equivalent pu
%                   convention; that conversion is applied by the caller,
%                   generate_ev_profile.m, matching how demand/PV's peaks
%                   are already divided by 3 before reaching their own
%                   generators -- see get_grid_SFOE.m:132-134 and docs/DEVELOPMENT_NOTES.md.
%                   Assumes charger_kw is a 3-phase-total rating, same
%                   assumption as demand/PV; a genuinely single-phase-only
%                   charger that shouldn't be divided is a separate,
%                   not-yet-modeled case -- deferred as future work.)
%   arrival_times : arrival time of each EV  (N_EV x 1)
%
% All units: hours, kW
%
%   charger_kw (optional, default 3.7): real per-vehicle charger rating,
%   kW. Normally sourced from sizing_cfg.json's ev_profile.charger_kw via
%   generate_ev_profile.m -- see that function's docstring.
%
%   seed (optional): if given, arrival times are drawn from a LOCAL rng
%   state seeded with this value, then the caller's ambient rng state is
%   restored immediately after -- same save/seed/restore pattern as
%   generate_nodal_scenarios_4.m's nodal_clusters (util/generate_load_profile.m
%   docstring). Without this, arrival times depend on however many prior
%   random draws happened to occur in the ambient stream before this call,
%   so e.g. changing N_EV (as when the per-node-count fix changed the total
%   vehicle count) reshuffles EVERY arrival time, not just the added
%   vehicles' -- confounding any before/after comparison. With a fixed seed,
%   requesting N_EV=11 reproduces the exact same first 9 arrivals as
%   N_EV=9 did, plus 2 more; the realization and the count vary
%   independently.

%% Parameters
if nargin < 4 || isempty(charger_kw); charger_kw = 3.7; end
P_ev     = charger_kw;    % kW per EV
T_charge = 4;             % hours

% Arrival time distribution (residential evening)
mu    = 18;        % mean arrival time [h]
sigma = 0.6;       % std dev [h]
t_min = 17;        % earliest arrival
t_max = 21;        % latest arrival

%% Time grid
dt = dt_minutes / 60;
t  = (0:dt:24-dt)';
Nt = length(t);

%% Draw staggered arrival times (truncated normal)
if nargin >= 3 && ~isempty(seed)
    prev_rng = rng;              % save the caller's ambient rng state
    rng(seed, 'twister');
end

arrival_times = zeros(N_EV,1);
k = 1;
while k <= N_EV
    a = mu + sigma*randn;
    if a >= t_min && a <= t_max
        arrival_times(k) = a;
        k = k + 1;
    end
end

if nargin >= 3 && ~isempty(seed)
    rng(prev_rng);                % restore, so the caller's own stream is untouched
end

%% Build individual charging profiles
P_EV_ind = zeros(Nt, N_EV);

for i = 1:N_EV
    charging_idx = (t >= arrival_times(i)) & ...
                   (t <  arrival_times(i) + T_charge);
    P_EV_ind(charging_idx, i) = P_ev;
end

end