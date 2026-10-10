function idx = select_representative_day(X, mask)
%SELECT_REPRESENTATIVE_DAY  Pick the single day closest in shape to the mean
%                            of the candidate days (RMSE distance).
%
%   idx = select_representative_day(X, mask)
%
%   X    : [S x Ndays]  one column per calendar day, native resolution
%   mask : [Ndays x 1]  logical, candidate days (e.g. from season_month_mask)
%
%   idx  : scalar column index into X (into the full 1..Ndays range, not
%          into the masked subset) of the selected representative day.
%
%   The winning day's data is returned UNMODIFIED by the caller -- this
%   function only ranks real days by closeness to the seasonal mean shape,
%   it does not average or otherwise alter any day's trace, so whatever
%   ramps/troughs that day actually had are preserved.

mask = logical(mask(:));
cand = find(mask);
if isempty(cand)
    error('select_representative_day:noCandidates', ...
        'No days match the requested season.');
end
mu   = mean(X(:, cand), 2);
dist = sqrt(mean((X(:, cand) - mu).^2, 1));
[~, k] = min(dist);
idx = cand(k);
end
