function data = patch_transformer_params(fill_table, data)
% PATCH_TRANSFORMER_PARAMS  Fills missing transformer R and X in the combined
%   data struct using a pre-computed fill table.
%
%   Only fills entries where R=0 or NaN — never overwrites existing valid data.
%
%   Inputs:
%     fill_table  — table with columns: kVA, R_pu_fill, X_pu_fill, Uk_pct, Psc_W, source
%                   (produced by transformer_parameter_analysis)
%     data        — combined data struct with field MV_LV_sub
%
%   Output:
%     data        — updated data struct (caller saves to disk)
%
%   Called by patch_grid_data. Do not call directly.

n_filled = 0;
n_skipped_no_match = 0;

for i = 1:numel(data.MV_LV_sub)
    tbl = data.MV_LV_sub{i};

    % Identify transformer rows
    objects        = vertcat(tbl.Object);
    is_transformer = contains(objects, 'Tr_');

    if ~any(is_transformer)
        continue
    end

    tr_idx = find(is_transformer);

    for k = 1:numel(tr_idx)
        row = tr_idx(k);
        R   = tbl.R_p_u_(row);
        X   = tbl.X_p_u_(row);
        kva = tbl.RatedPower_kVA_(row);

        % Only fill if R is missing (0 or NaN)
        R_missing = (isnan(R) || R == 0);
        if ~R_missing
            continue
        end

        % Look up fill values by kVA
        match = fill_table.kVA == kva;
        if ~any(match)
            n_skipped_no_match = n_skipped_no_match + 1;
            continue
        end

        tbl.R_p_u_(row) = fill_table.R_pu_fill(match);
        tbl.X_p_u_(row) = fill_table.X_pu_fill(match);
        n_filled = n_filled + 1;
    end

    data.MV_LV_sub{i} = tbl;
end

fprintf('patch_transformer_params: %d transformers filled, %d skipped (no kVA match)\n', ...
    n_filled, n_skipped_no_match);

end