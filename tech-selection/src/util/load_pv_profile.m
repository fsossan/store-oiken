function [X_kw, S_native, meta] = load_pv_profile(node_peak_kw, D, params)
%LOAD_PV_PROFILE  Load the yearly PV profile and select a D-day slice.
%
%   [X_kw, S_native] = load_pv_profile(node_peak_kw, D, params)
%
%   Inputs
%   ------
%   node_peak_kw : installed peak DC power per PV node, kW (whatever shape
%                  grid.nodal_PV_SFOE(nodes_with_PV) is -- passed through)
%   D            : scalar  number of days to return
%   params       : struct, all fields optional (defaults shown):
%       .file    'pv_profiles_year.mat'
%       .series  "clearsky"   "clearsky" | "measured"
%       .season  "all"        "winter" | "spring" | "summer" | "autumn" | "all"
%       .enabled true         false -> skip day selection and return an
%                              all-zero stream at the correct native
%                              resolution instead
%       .scale   1            multiplicative factor applied to the returned
%                              kW stream, e.g. 1.5 for a 50% PV oversizing
%                              sensitivity run. Applied after node_peak_kw
%                              scaling, before the pu conversion in
%                              build_temporal_profiles.
%
%   Output
%   ------
%   X_kw      : [Npv x S_native x D]  PV generation, kW, native resolution,
%               calendar order within each selected day
%   S_native  : scalar  native steps/day of the source file (for the
%               caller's dimension check against cfg.horizon.steps_per_day)
%
%   meta      : struct  provenance of the selected day(s): .day_idx (into the
%               source year), .dates (cellstr 'yyyy-MM-dd'), .months, .series,
%               .season, .file, .scale -- empty day_idx/dates when disabled
%
%   Day selection depends on D:
%     D == 1              -> single representative day: the real day whose
%                             shape is closest to the season's mean shape
%                             (select_representative_day)
%     D == 7  or D == 30   -> representative week/month: the real
%                             W-consecutive-day window whose daily-energy
%                             distribution best matches the season's, via
%                             the Finkelstein-Schafer statistic
%                             (select_representative_window); cyclic at the
%                             winter Dec->Jan boundary
%     D == Ndays (365)     -> full year, calendar order; params.season must
%                             be "all"
%     otherwise            -> first D consecutive calendar days from Jan 1,
%                             no season filter (legacy/debug behavior, e.g.
%                             ad-hoc D sweeps outside the {day,week,month,
%                             year} menu)
%
%   In every case the selected day(s)' data is used UNMODIFIED -- season/
%   representativeness only pick WHICH real days to use, they never average
%   or smooth the data itself, so real ramps/cloud transients are preserved.
%
%   pv_norm_* in the source file is p.u. of installed peak DC power (0..1);
%   this function returns real kW by scaling with node_peak_kw, matching the
%   normalisation of the old PV_prof_15mins.mat it replaces.

if nargin < 3 || isempty(params); params = struct(); end
params = set_default(params, 'file',   'pv_profiles_year.mat');
params = set_default(params, 'series', "clearsky");
params = set_default(params, 'season', "all");
params = set_default(params, 'enabled', true);
params = set_default(params, 'scale',  1);

paths   = project_paths();
pv_file = resolve_data_file(params.file, paths.data_raw, 'PV profile file (pv_profile.file)');
pv_raw  = load(pv_file);
switch string(params.series)
    case "clearsky"; pv_year = pv_raw.pv_norm_clearsky(:);
    case "measured"; pv_year = pv_raw.pv_norm_measured(:);
    otherwise
        error('load_pv_profile:badSeries', ...
            'params.series must be "clearsky" or "measured" (got "%s").', string(params.series));
end

% double(...): pv_profiles_year.mat is written by an external (pvlib)
% pipeline via a non-MATLAB save path, so numeric metadata fields can load
% as a non-double class (e.g. int32); leaving that class to propagate into
% S_native/Ndays breaks mod() below (mod() rejects a non-scalar double
% combined with a non-double scalar) for any D whose selection falls
% through to the legacy fallback branch.
S_native = round(24*60 / double(pv_raw.meta.timestep_minutes));

if ~params.enabled
    X_kw = zeros(numel(node_peak_kw), S_native, D);
    meta = pv_meta_struct([], {}, [], params);
    return
end

Ndays    = numel(pv_year) / S_native;
if abs(Ndays - round(Ndays)) > 1e-9
    error('load_pv_profile:badLength', ...
        '%s has %d samples, not a whole number of %d-step days.', ...
        params.file, numel(pv_year), S_native);
end
Ndays  = round(Ndays);
pv_mat = reshape(pv_year, S_native, Ndays);   % [S x Ndays], col d = calendar day d

% Month per calendar day, read directly from the "yyyy-MM-dd..." ISO
% timestamp of that day's first sample -- avoids trusting the numeric
% `datenum` field's convention (it may not be MATLAB's own datenum;
% pv_profiles_year.mat is produced by an external pvlib pipeline) or a
% datetime format-string match against the "+HHMM" offset suffix.
day_iso = pv_raw.time_iso(1:S_native:end, :);   % [Ndays x 24 char], one stamp per day
months  = str2double(cellstr(day_iso(:, 6:7)));  % chars 6-7 = "MM"

switch true
    case D == 1
        mask = season_month_mask(months, params.season);
        day_sel = select_representative_day(pv_mat, mask);
    case (D == 7 || D == 30)
        mask = season_month_mask(months, params.season);
        day_sel = select_representative_window(pv_mat, mask, D);
    case D == Ndays
        if string(params.season) ~= "all"
            error('load_pv_profile:yearSeason', ...
                'D == %d (full year) requires params.season == "all" (got "%s").', ...
                Ndays, string(params.season));
        end
        day_sel = (1:Ndays)';
    otherwise
        day_sel = mod((0:D-1)', Ndays) + 1;   % legacy: first D consecutive days, no season filter
end

pv_dc = pv_mat(:, day_sel);                          % [S x D], calendar order within selection
X_kw  = reshape(pv_dc, 1, S_native, D) .* node_peak_kw(:) * params.scale;   % [Npv x S_native x D]
meta  = pv_meta_struct(day_sel, cellstr(day_iso(day_sel, 1:10)), months(day_sel), params);

end

% =========================================================================
function meta = pv_meta_struct(day_idx, dates, months, params)
meta.day_idx = day_idx(:);
meta.dates   = dates(:);
meta.months  = months(:);
meta.series  = string(params.series);
meta.season  = string(params.season);
meta.file    = string(params.file);
meta.scale   = params.scale;
end
