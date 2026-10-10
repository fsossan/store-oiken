function idx = select_representative_window(X, mask, W)
%SELECT_REPRESENTATIVE_WINDOW  Pick a W-consecutive-calendar-day window whose
%                               daily-energy distribution best matches the
%                               season's, via the Finkelstein-Schafer
%                               statistic -- the same idea the Sandia/NREL
%                               TMY method uses for month selection, sized
%                               down to W days and one variable (irradiance).
%
%   idx = select_representative_window(X, mask, W)
%
%   X    : [S x Ndays]
%   mask : [Ndays x 1]  logical, candidate days for the season
%   W    : scalar       window length in days (e.g. 7 = week, 30 = month)
%
%   idx  : [W x 1]  column indices into X, in calendar order, of the winning
%          window. Cyclic: a window may wrap past Ndays back to 1 (so a
%          winter window can span Dec -> Jan), since a single reference year
%          of PV data represents a repeating annual climatology, not one
%          specific chronology.
%
%   Candidates are every W-day window fully contained in the season (all W
%   days pass `mask`). Windows are scored by how closely their own (small,
%   W-point) empirical CDF of daily energy matches the full season's
%   empirical CDF -- NOT by averaging, so the winning window's real
%   day-to-day variability (cloud transients etc.) is preserved unmodified.

mask  = logical(mask(:));
Ndays = numel(mask);

E_season = sum(X(:, mask), 1).';   % [Ncand x 1] daily energies, season-wide

best_fs = Inf;
idx = [];
starts = find(mask)';               % only windows starting in-season are worth scoring
for s = starts
    w_idx = mod(s - 1 + (0:W-1), Ndays) + 1;   % cyclic window, calendar order
    if ~all(mask(w_idx))
        continue                                % window must stay fully inside the season
    end
    E_w = sum(X(:, w_idx), 1).';
    fs  = fs_statistic(E_w, E_season);
    if fs < best_fs
        best_fs = fs;
        idx = w_idx(:);
    end
end

if isempty(idx)
    error('select_representative_window:noCandidates', ...
        'No %d-day window fits entirely inside the requested season.', W);
end
end

% =========================================================================
function d = fs_statistic(sample, ref)
% Finkelstein-Schafer distance between the empirical CDFs of `sample`
% (small, W points) and `ref` (the full seasonal population), evaluated on
% their pooled set of values.
grid = sort([sample(:); ref(:)]);
F_s  = arrayfun(@(x) mean(sample <= x), grid);
F_r  = arrayfun(@(x) mean(ref    <= x), grid);
d = mean(abs(F_s - F_r));
end
