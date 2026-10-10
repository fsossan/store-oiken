function k = kw_per_pu_of(x)
%KW_PER_PU_OF  pu -> real three-phase kW / kWh factor, from a result or a config.
%
%   k = kw_per_pu_of(out)   reads out.meta.kW_per_pu  (stamped by build_network_result)
%   k = kw_per_pu_of(cfg)   reads cfg.units.kW_per_pu (set by load_ess_selection_config,
%                           = Sb/1000 * 3 phases)
%
%   Falls back to 300 (Sb = 100 kVA single-phase x 3 phases) for results and
%   configs that predate the field, so result .mat files saved before
%   2026-10-10 still analyse unchanged. Every "x300" conversion in the
%   pipeline goes through here, so a change of Sb in general_config.json
%   propagates to the run log and all analyze_* figures.

k = 300;
if isstruct(x)
    if isfield(x, 'meta') && isfield(x.meta, 'kW_per_pu') && ~isempty(x.meta.kW_per_pu)
        k = x.meta.kW_per_pu;
    elseif isfield(x, 'units') && isfield(x.units, 'kW_per_pu') && ~isempty(x.units.kW_per_pu)
        k = x.units.kW_per_pu;
    end
end
end
