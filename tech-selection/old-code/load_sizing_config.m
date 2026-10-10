function cfg = load_sizing_config(json_path, Sb)
% LOAD_SIZING_CONFIG  Load and pre-process the BESS sizing configuration.
%
%   cfg = load_sizing_config(json_path, Sb)
%
%   Inputs
%   ------
%   json_path : char / string
%       Path to sizing_cfg.json.
%   Sb : scalar
%       Three-phase base power in kVA (from grid.basepower, which is Sb in
%       kVA).  Used to scale monetary costs from $/kWh and $/kW to pu.
%
%   Output
%   ------
%   cfg : struct
%       All fields from the JSON, plus pre-scaled cost coefficients:
%           cfg.costs.cE   [pu]  energy   cost coefficient
%           cfg.costs.cS   [pu]  converter cost coefficient
%           cfg.costs.cI   [pu]  installation cost coefficient
%       kQ_conv and kPF are re-derived from kP so they are always
%       self-consistent regardless of what is written in the JSON.

cfg = jsondecode(fileread(json_path));

% Per-phase kW base  (Sb is 3-phase kVA -> /3 -> per-phase kVA -> same kW)
bp = Sb / 1000;   % kW base  (Sb already in kVA, /1000 -> MW... wait:
%   convention in this codebase: basepower = Sb in kVA,
%   bp = Sb/1000 gives a normalisation factor such that
%   P_kW / bp = P_pu.  Keep consistent with main script.

cfg.costs.cE = cfg.costs.cE_per_kWh / bp;
cfg.costs.cS = cfg.costs.cS_per_kW  / bp;
cfg.costs.cI = cfg.costs.cI_fixed   / bp;

% Re-derive converter box fractions from kP for self-consistency
kP           = cfg.converter.kP;
cfg.converter.kQ_conv = sqrt(1 - kP^2);
cfg.converter.kPF     = tan(acos(kP));

kP_tr               = cfg.transformer.kP_tr;
cfg.transformer.kQ_tr  = sqrt(1 - kP_tr^2);
cfg.transformer.kPF_sl = tan(acos(0.9));   % fixed slack PF limit

% Convenience: expose tech count
cfg.J = numel(cfg.tech.names);

end
