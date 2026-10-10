function cfg = load_ess_selection_config(sizing_json_path, tech_json_path, Sb)
% LOAD_ESS_SELECTION_CONFIG  Load and normalize ESS tech-selection settings.

sizing_cfg = jsondecode(fileread(sizing_json_path));
tech_cfg   = jsondecode(fileread(tech_json_path));

tech_list = tech_cfg.tech;
J = numel(tech_list);

tech_names = cell(J, 1);
c_rate_j   = zeros(1, J);
eta_ch_j   = zeros(1, J);
eta_dis_j  = zeros(1, J);
Emax_j     = zeros(1, J);
Smax_j     = zeros(1, J);
cE_kWh     = zeros(1, J);
cS_kW      = zeros(1, J);
cI_fixed   = zeros(1, J);

for j = 1:J
    item = tech_list(j);
    tech_names{j} = char(string(item.name));
    c_rate_j(j)    = item.c_rate;
    eta_ch_j(j)    = item.eta_ch;
    eta_dis_j(j)   = item.eta_dis;
    Emax_j(j)      = item.Emax_pu;
    Smax_j(j)      = item.Smax_pu;
    cE_kWh(j)      = item.costs.cE_per_kWh;
    cS_kW(j)       = item.costs.cS_per_kW;
    cI_fixed(j)    = item.costs.cI_fixed;
end

bp  = Sb / 1000;   % kW per pu (single-phase base)
bph = 1/bp;
ph  = 3;           % phases: pu quantities are single-phase, reported kW/kWh are 3-phase
cfg = sizing_cfg;
cfg.units.Sb        = Sb;
cfg.units.kW_per_pu = bp * ph;   % pu -> real 3-phase kW/kWh (300 for Sb = 100 kVA); the single
                                 % source for every former "x300" conversion downstream
cfg.tech.names      = tech_names;
cfg.tech.c_rate     = c_rate_j;
cfg.tech.eta_ch     = eta_ch_j;
cfg.tech.eta_dis    = eta_dis_j;
cfg.tech.Emax_pu    = Emax_j;
cfg.tech.Smax_pu    = Smax_j;
cfg.tech.cE_per_kWh = cE_kWh;
cfg.tech.cS_per_kW  = cS_kW;
cfg.tech.cI_fixed   = cI_fixed;
cfg.tech.cE         = (cE_kWh / bph)*ph;
cfg.tech.cS         = cS_kW / bph*ph;
cfg.tech.cI         = cI_fixed;

cfg.costs.cE_per_kWh = cE_kWh;
cfg.costs.cS_per_kW  = cS_kW;
cfg.costs.cI_fixed   = cI_fixed;
cfg.costs.cE         = (cE_kWh / bph)*ph;
cfg.costs.cS         = (cS_kW / bph)*ph;
cfg.costs.cI         = cI_fixed ;

% economics.* (cfg.economics.{energy_price_CHF_per_kWh,curtailment_price_CHF_per_kWh})
% already copied verbatim from sizing_cfg.json via `cfg = sizing_cfg` above;
% add the pu-scaled versions used directly in solve_ess_milp.m's objective.
cfg.economics.cL    = (cfg.economics.energy_price_CHF_per_kWh     / bph)*ph;
cfg.economics.cCurt = (cfg.economics.curtailment_price_CHF_per_kWh / bph)*ph;
cfg.economics.cThroughputLoss = (cfg.economics.throughput_loss_price_CHF_per_kWh / bph)*ph;

% Maintain the derived solver constants from the original loader.
kP = cfg.converter.kP;
cfg.converter.kQ_conv = sqrt(1 - kP^2);
cfg.converter.kPF     = tan(acos(kP));

kP_tr = cfg.transformer.kP_tr;
cfg.transformer.kQ_tr  = sqrt(1 - kP_tr^2);

cfg.J = J;

% ------------------------------------------------------------------------
%  Horizon / time-step (day count D and step size Ts_h now live in JSON)
% ------------------------------------------------------------------------
%  cfg.horizon.days          : number of simulated days D (T = days * steps_per_day)
%  cfg.horizon.Ts_h          : time-step in hours (source of truth for Ts everywhere)
%  cfg.horizon.steps_per_day : derived, 24 / Ts_h; must match the native
%                              resolution of the demand/PV/EV input data
%                              (checked in build_temporal_profiles).
if ~isfield(cfg, 'horizon') || ~isfield(cfg.horizon, 'Ts_h') || ~isfield(cfg.horizon, 'days')
    error('load_ess_selection_config:missingHorizon', ...
        'sizing_cfg.json must define a "horizon" block with "days" and "Ts_h".');
end
steps_per_day = 24 / cfg.horizon.Ts_h;
if abs(steps_per_day - round(steps_per_day)) > 1e-9
    error('load_ess_selection_config:badTs', ...
        'horizon.Ts_h = %g does not divide 24h into a whole number of steps.', ...
        cfg.horizon.Ts_h);
end
cfg.horizon.steps_per_day = round(steps_per_day);

% Mirror Ts_h into solver.* so any consumer still reading the old location
% keeps working (JSON keeps it in one place: the horizon block).
cfg.solver.Ts_h = cfg.horizon.Ts_h;

end