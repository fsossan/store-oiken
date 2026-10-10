function data = patch_line_params(lookup, data)
% PATCH_LINE_PARAMS  Patches missing line parameters in the combined data struct.
%   For each network, fills missing ampacity, resistance, reactance, and length
%   using a lookup table keyed by cable cross-section. Falls back to default
%   values when cross-section is also missing.
%
%   Inputs:
%     lookup  — line parameter lookup struct with fields:
%                 cross_section, ampacity, R, X
%     data    — combined data struct with fields LV_grid, LV_grid_id
%
%   Output:
%     data    — updated data struct (caller saves to disk)
%
%   Called by patch_grid_data. Do not call directly.

sheet_name = data.LV_grid_id;

ID_updated_lines = [];
default_R = 0.001;   % ohm/km
default_X = 0.001;   % ohm/km
default_L = 1;       % meter
default_A = 100;     % ampere

for i = 1:numel(data.LV_grid)
    network_table = data.LV_grid{i};

    % Remove duplicate entries — include Line ID (col 3) to preserve parallel cables
    [~, unique_idx]  = unique(network_table(:, 1:3), 'rows', 'stable');
    num_duplicates   = size(network_table, 1) - numel(unique_idx);
    if num_duplicates > 0
        network_table = network_table(unique_idx, :);
    end

    % Convert empty cell ampacity to NaN
    if iscell(network_table.Ampacity_A_) && all(cellfun(@isempty, network_table.Ampacity_A_))
        network_table.Ampacity_A_ = NaN(height(network_table), 1);
    end

    section    = network_table.Section_mm2_;
    ampacity   = network_table.Ampacity_A_;
    cable_id   = network_table.Line;
    Length     = network_table.Length_m_;
    Resistance = network_table.R_Ohm_km_;
    Reactance  = network_table.X_Ohm_km_;

    % Only process if any missing values detected in cols 4-7
    if any(isnan(network_table{:, 4:7}) | network_table{:, 4:7} == 0, 'all')

        if any(~isnan(section)) || any(section ~= 0)
            % Cross-section available — use lookup table

            % Missing ampacity
            if any(isnan(ampacity)) || any(ampacity == 0)
                idx_mis = find(isnan(ampacity) | ampacity == 0);
                for k = 1:numel(idx_mis)
                    rowID = idx_mis(k);
                    [~, idxNearest] = min(abs(lookup.cross_section - section(rowID)));
                    network_table.Ampacity_A_(rowID) = lookup.ampacity(idxNearest);
                    if isempty(ID_updated_lines) || ~ismember(cable_id(rowID), ID_updated_lines)
                        ID_updated_lines = [ID_updated_lines; cable_id(rowID)];
                    end
                end
            end

            % Missing impedance
            if any(Resistance == 0) || any(Reactance == 0) || any(isnan(Resistance)) || any(isnan(Reactance))
                idx_mis = find(Resistance == 0 | Reactance == 0 | isnan(Resistance) | isnan(Reactance));
                for k = 1:numel(idx_mis)
                    rowID = idx_mis(k);
                    [~, idxNearest] = min(abs(lookup.cross_section - section(rowID)));
                    network_table.R_Ohm_km_(rowID) = lookup.R(idxNearest);
                    network_table.X_Ohm_km_(rowID) = lookup.X(idxNearest);
                    if isempty(ID_updated_lines) || ~ismember(cable_id(rowID), ID_updated_lines)
                        ID_updated_lines = [ID_updated_lines; cable_id(rowID)];
                    end
                end
            end

            % Missing length
            if any(isnan(Length)) || any(Length == 0)
                idx_mis = find(isnan(Length) | Length == 0);
                for k = 1:numel(idx_mis)
                    rowID = idx_mis(k);
                    network_table.Length_m_(rowID) = default_L;
                    if isempty(ID_updated_lines) || ~ismember(cable_id(rowID), ID_updated_lines)
                        ID_updated_lines = [ID_updated_lines; cable_id(rowID)];
                    end
                end
            end

        else
            % Cross-section missing — use default values

            % Missing ampacity
            if any(isnan(ampacity)) || any(ampacity == 0)
                idx_mis = find(isnan(ampacity) | ampacity == 0);
                for k = 1:numel(idx_mis)
                    rowID = idx_mis(k);
                    network_table.Ampacity_A_(rowID) = default_A;
                    if isempty(ID_updated_lines) || ~ismember(cable_id(rowID), ID_updated_lines)
                        ID_updated_lines = [ID_updated_lines; cable_id(rowID)];
                    end
                end
            end

            % Missing impedance
            if any(Resistance == 0) || any(Reactance == 0) || any(isnan(Resistance)) || any(isnan(Reactance))
                idx_mis = find(Resistance == 0 | Reactance == 0 | isnan(Resistance) | isnan(Reactance));
                for k = 1:numel(idx_mis)
                    rowID = idx_mis(k);
                    network_table.R_Ohm_km_(rowID) = default_R;
                    network_table.X_Ohm_km_(rowID) = default_X;
                    if isempty(ID_updated_lines) || ~ismember(cable_id(rowID), ID_updated_lines)
                        ID_updated_lines = [ID_updated_lines; cable_id(rowID)];
                    end
                end
            end

            % Missing length
            if any(isnan(Length)) || any(Length == 0)
                idx_mis = find(isnan(Length) | Length == 0);
                for k = 1:numel(idx_mis)
                    rowID = idx_mis(k);
                    network_table.Length_m_(rowID) = default_L;
                    if isempty(ID_updated_lines) || ~ismember(cable_id(rowID), ID_updated_lines)
                        ID_updated_lines = [ID_updated_lines; cable_id(rowID)];
                    end
                end
            end

        end
    end

    data.LV_grid{i} = network_table;
end

fprintf('patch_line_params: %d unique lines updated\n', numel(ID_updated_lines));

% Generate lookup table markdown report
md_of_lookup_table(lookup);

end