function row = summarize_network_injections(grid, inj, cfg)
%SUMMARIZE_NETWORK_INJECTIONS  One report row per network: topology, installed
%                              capacity, peak demand / PV / EV and net
%                              transformer loading, from the injections alone
%                              (no load flow).
%
%   row = summarize_network_injections(grid, inj, cfg)
%   row = summarize_network_injections([], [], cfg)   % template row (NaN / "")
%
%   grid : get_grid_SFOE output      inj : build_nodal_injections output
%   cfg  : load_ess_selection_config output (kW factor, Ts_h)
%
%   Fields (scalars only, so rows stack with struct2table):
%     status, scenario, net_id, net_num
%     n_nodes (incl. slack), n_lines, n_demand_nodes, n_pv_nodes, n_ev_nodes,
%     n_transformers, trafo_kVA, slack_is_node1, line_length_km
%     PLmax_sum_kW            fuse-rated peak summed over nodes (3-phase kW,
%                             before demand_factor)
%     demand_peak_kW          max over t of the aggregate demand
%     demand_energy_kWh_day, demand_peak_over_trafo, demand_min_pf
%     pv_kWp, pv_peak_kW, pv_energy_kWh_day, pv_kWp_over_demand_peak
%     ev_count, ev_peak_kW, ev_energy_kWh_day
%     net_peak_import_kW      max over t of transformer import (demand + EV - PV)
%     net_peak_export_kW      max over t of reverse flow (0 if never)
%     net_peak_over_trafo     max(import, export) / trafo_kVA
%     D, Ts_h, pv_dates (comma-joined), pv_series, demand_season, demand_weekday
%   Power in real 3-phase kW (kw_per_pu_of(cfg)); energies per day.

row = template_row();
if isempty(grid)
    return
end

kW = kw_per_pu_of(cfg);
Ts = cfg.horizon.Ts_h;
D  = inj.calendar.D;

Dkw   = (0 - real(inj.nodal_injections_D_pu))  * kW;   % "0 -" keeps an all-zero stream at +0, not -0   % [T x Nd]  consumption, positive
Dkvar = (0 - imag(inj.nodal_injections_D_pu))  * kW;
PVkw  =  real(inj.nodal_injections_PV_pu) * kW;   % [T x Npv] generation, positive
EVkw  = (0 - real(inj.nodal_injections_EV_pu)) * kW;   % [T x Nev] consumption, positive

agg_D  = sum(Dkw,   2);   % [T x 1]; an empty stream sums to zeros(T,1)
agg_Q  = sum(Dkvar, 2);
agg_PV = sum(PVkw,  2);
agg_EV = sum(EVkw,  2);
net    = agg_D + agg_EV - agg_PV;                 % transformer import, positive = import

S_agg = hypot(agg_D, agg_Q);
pf    = agg_D ./ max(S_agg, eps);
pf    = pf(agg_D > 1e-6);

gd        = grid.graph_data;
trafo_kVA = sum(gd.T_rat_kVA);

row.status         = "ok";
row.net_id         = "LV_Grid_" + string(grid.net_id);
row.net_num        = str2double(grid.net_id);
row.n_nodes        = numel(grid.nodal_nominal_power) + 1;
row.n_lines        = numel(grid.ampacities);
row.n_demand_nodes = inj.Nd;
row.n_pv_nodes     = sum(inj.nodes_with_PV);
row.n_ev_nodes     = sum(inj.nodes_with_EV);
row.n_transformers = gd.n_transformers;
row.trafo_kVA      = trafo_kVA;
row.slack_is_node1 = gd.slack_node_idx == 1;
if isfield(grid, 'line_length_m');  row.line_length_km = sum(grid.line_length_m) / 1000; end
if isfield(grid, 'nodal_PLmax_kW'); row.PLmax_sum_kW   = sum(grid.nodal_PLmax_kW);      end

row.demand_peak_kW         = max([agg_D; 0]);
row.demand_energy_kWh_day  = sum(agg_D) * Ts / D;
row.demand_peak_over_trafo = row.demand_peak_kW / trafo_kVA;
if isempty(pf)
    row.demand_min_pf = NaN;
else
    row.demand_min_pf = min(pf);
end

row.pv_kWp                  = sum(inj.magnitudes.pv_kWp);
row.pv_peak_kW              = max([agg_PV; 0]);
row.pv_energy_kWh_day       = sum(agg_PV) * Ts / D;
if row.demand_peak_kW > 0
    row.pv_kWp_over_demand_peak = row.pv_kWp / row.demand_peak_kW;
else
    row.pv_kWp_over_demand_peak = NaN;   % no demand stream: ratio undefined
end

row.ev_count          = sum(inj.magnitudes.ev_count);
row.ev_peak_kW        = max([agg_EV; 0]);
row.ev_energy_kWh_day = sum(agg_EV) * Ts / D;

row.net_peak_import_kW  = max([net; 0]);
row.net_peak_export_kW  = max([-net; 0]);
row.net_peak_over_trafo = max(row.net_peak_import_kW, row.net_peak_export_kW) / trafo_kVA;

row.D    = D;
row.Ts_h = Ts;
if isempty(inj.calendar.pv_dates)
    row.pv_dates = "";
else
    row.pv_dates = strjoin(string(inj.calendar.pv_dates), ",");
end
row.pv_series      = string(inj.calendar.pv_series);
row.demand_season  = string(inj.calendar.demand_season);
row.demand_weekday = string(inj.calendar.demand_weekday);
end

% =========================================================================
function row = template_row()
row = struct( ...
    'status', "", 'scenario', "", 'net_id', "", 'net_num', NaN, ...
    'n_nodes', NaN, 'n_lines', NaN, 'n_demand_nodes', NaN, 'n_pv_nodes', NaN, 'n_ev_nodes', NaN, ...
    'n_transformers', NaN, 'trafo_kVA', NaN, 'slack_is_node1', false, 'line_length_km', NaN, ...
    'PLmax_sum_kW', NaN, 'demand_peak_kW', NaN, 'demand_energy_kWh_day', NaN, ...
    'demand_peak_over_trafo', NaN, 'demand_min_pf', NaN, ...
    'pv_kWp', NaN, 'pv_peak_kW', NaN, 'pv_energy_kWh_day', NaN, 'pv_kWp_over_demand_peak', NaN, ...
    'ev_count', NaN, 'ev_peak_kW', NaN, 'ev_energy_kWh_day', NaN, ...
    'net_peak_import_kW', NaN, 'net_peak_export_kW', NaN, 'net_peak_over_trafo', NaN, ...
    'D', NaN, 'Ts_h', NaN, 'pv_dates', "", 'pv_series', "", 'demand_season', "", 'demand_weekday', "");
end
