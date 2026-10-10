function plot_gm_temporal_profiles(gm, net_id, scenario_name, fig_dir)
%PLOT_GM_TEMPORAL_PROFILES  Temporal diagnostic figure straight off linear_grid_model.
%
%   plot_gm_temporal_profiles(gm, net_id, scenario_name)
%   plot_gm_temporal_profiles(gm, net_id, scenario_name, fig_dir)   % also saves PNG
%
% Creates a 6-subplot figure from a `gm` struct (output of linear_grid_model):
%   1. Demand profiles          (kW, 3-phase, positive = consumption)
%   2. PV generation profiles   (kW, 3-phase)
%   3. EV charging profiles     (kW, 3-phase, positive = consumption)
%   4. Aggregate nodal power    (kW, 3-phase, net injection: +export/-consume)
%   5. Nodal voltages           (p.u.)
%   6. Line currents            (p.u. of ampacity rating)

if nargin < 4
    fig_dir = '';
end

T = size(gm.injections_D_pu, 1);

% 3-phase kW scaling: Sb = 100 kVA single-phase -> x3 for 3-phase, /1000 for kW
scale = (gm.grid.basepower / 1000) * 3;

D_kW  =  real(gm.injections_D_pu)         * scale;   % [T x Nd], positive = consumption
PV_kW =  real(gm.injectinos_PV_pu)        * scale;   % [T x Npv], positive = generation
EV_kW =  real(gm.injections_EV_pu)        * scale;   % [T x Nev], positive = consumption

P0_mat     = lm_stack(gm.lm.P0).';        % [T x N], net active power injection (pu)
Aggr_kW    = P0_mat * scale;

Vmag_mat   = lm_stack(gm.lm.Vmag0).';     % [T x N], p.u.
Imag_mat   = abs(lm_stack(gm.lm.Imag0).'); % [T x L], p.u. of base current
CABLE_AMP  = gm.grid.ampacities ./ gm.grid.basecurrent;   % [L x 1], p.u.
I_pu_ampac = Imag_mat ./ repmat(CABLE_AMP.', T, 1);       % [T x L]

fig = figure;

%% 1. Demand profiles
subplot(3, 2, 1);
if ~isempty(D_kW)
    plot(D_kW);
    title('Nodal Demand Profiles');
    ylabel('Power (kW)');
    xlabel('Time (15-min intervals)');
    grid on;
else
    text(0.5, 0.5, 'No demand nodes', 'HorizontalAlignment', 'center');
    title('Nodal Demand Profiles');
    axis off;
end

%% 2. PV generation
subplot(3, 2, 2);
if ~isempty(PV_kW) && any(PV_kW(:) ~= 0)
    plot(PV_kW);
    title('PV Generation Profiles');
    ylabel('Power (kW)');
    xlabel('Time (15-min intervals)');
    grid on;
else
    text(0.5, 0.5, 'No PV in this network', 'HorizontalAlignment', 'center');
    title('PV Generation Profiles');
    axis off;
end

%% 3. EV charging
subplot(3, 2, 3);
if ~isempty(EV_kW) && any(EV_kW(:) ~= 0)
    plot(EV_kW);
    title('EV Charging Profiles');
    ylabel('Power (kW)');
    xlabel('Time (15-min intervals)');
    grid on;
else
    text(0.5, 0.5, 'No EVs in this network', 'HorizontalAlignment', 'center');
    title('EV Charging Profiles');
    axis off;
end

%% 4. Aggregate power
subplot(3, 2, 4);
plot(Aggr_kW);
title('Aggregate Nodal Power (net injection)');
ylabel('Power (kW)');
xlabel('Time (15-min intervals)');
grid on;

%% 5. Voltage timeseries
subplot(3, 2, 5);
plot(Vmag_mat);
hold on;
yline(0.9, 'r--', 'LineWidth', 1.5);
yline(1.1, 'r--', 'LineWidth', 1.5);
hold off;
title('Nodal Voltages');
ylabel('Voltage (p.u.)');
xlabel('Time (15-min intervals)');
grid on;

%% 6. Line currents
subplot(3, 2, 6);
plot(I_pu_ampac);
hold on;
yline(1.0, 'r--', 'LineWidth', 1.5);
hold off;
title('Line Currents');
ylabel('Current (p.u. of ampacity)');
xlabel('Time (15-min intervals)');
grid on;

%% Overall title
net_id_display       = strrep(string(net_id), '_', '\_');
scenario_name_display = strrep(string(scenario_name), '_', '\_');
sgtitle(sprintf('Temporal Analysis (%s): %s', scenario_name_display, net_id_display), ...
    'FontWeight', 'bold', 'FontSize', 14);

%% Save (optional)
if ~isempty(fig_dir)
    if ~isfolder(fig_dir)
        mkdir(fig_dir);
    end
    fig_path = fullfile(fig_dir, sprintf('%s_temporal.png', net_id));
    saveas(fig, fig_path);
end

end
