function [t, P_EV_ind, arrival_times] = EV_uncontrolled_profile(N_EV, dt_minutes)
% EV_uncontrolled_profile
%
% Returns INDIVIDUAL EV charging profiles 
%
% OUTPUTS:
%   t             : time vector [h]          (T x 1)
%   P_EV_ind      : EV charging profiles     (T x N_EV)
%   arrival_times : arrival time of each EV  (N_EV x 1)
%
% All units: hours, kW

%% Parameters
P_ev     = 3.7;    % kW per EV
T_charge = 4;      % hours

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
arrival_times = zeros(N_EV,1);
k = 1;
while k <= N_EV
    a = mu + sigma*randn;
    if a >= t_min && a <= t_max
        arrival_times(k) = a;
        k = k + 1;
    end
end

%% Build individual charging profiles
P_EV_ind = zeros(Nt, N_EV);

for i = 1:N_EV
    charging_idx = (t >= arrival_times(i)) & ...
                   (t <  arrival_times(i) + T_charge);
    P_EV_ind(charging_idx, i) = P_ev;
end

end