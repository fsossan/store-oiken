function mask = season_month_mask(months, season)
%SEASON_MONTH_MASK  Boolean day mask for a meteorological season.
%
%   mask = season_month_mask(months, season)
%
%   months : [Ndays x 1]  calendar month (1-12) of each day
%   season : "winter" | "spring" | "summer" | "autumn" | "all"
%
%   mask   : [Ndays x 1]  logical
%
%   Same meteorological month grouping (winter=DJF, spring=MAM, summer=JJA,
%   autumn=SON) as generate_nodal_scenarios_4.m's inline season filter --
%   kept as a separate copy here (not shared code) rather than editing that
%   WIP demand sampler, so PV's season filter matches demand's convention
%   without touching it.

switch string(season)
    case "winter"; mask = ismember(months, [12 1 2]);
    case "spring"; mask = ismember(months, [3 4 5]);
    case "summer"; mask = ismember(months, [6 7 8]);
    case "autumn"; mask = ismember(months, [9 10 11]);
    case "all";    mask = true(size(months));
    otherwise
        error('season_month_mask:badSeason', ...
            'season must be one of "winter","spring","summer","autumn","all" (got "%s").', ...
            string(season));
end
mask = mask(:);
end
