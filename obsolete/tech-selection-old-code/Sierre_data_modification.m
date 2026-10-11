function Sierre_data_modification (lookup,Sierre)
% clc
% clear
% 
% addpath('/Users/fozi/Desktop/codes/Sanity_check_v2/network_data/mat_data') 
% 
% % Load lookup data
% load('lookup_data.mat')
% lookup = lookup.data{:};
% 
% % Load sierre data
% load('Sierre_dat.mat')
data = Sierre.LV_grid;
sheet_name = Sierre.LV_grid_id;



ID_updated_lines =[];
default_R = 0.001; % ohm
default_X = 0.001; % ohm
default_L = 1; % meter
default_A = 100; % ampere

for i = 1:numel(data)
    % Extract the table for the current network
    network_table = data{i};

    % removing dublicate entries
    [~, unique_idx] = unique(network_table(:,1:2), 'rows','stable');
    % % Check if duplicates were detected and display a message
    num_duplicates = size(network_table, 1) - size(unique_idx, 1);
    if num_duplicates > 0
        % fprintf('Duplicates detected and removed %d\n', num_duplicates);
        network_table = network_table(unique_idx,:);
    end
    % char amp to Nan (ampacity)
    if iscell(network_table.Ampacity_A_) && all(cellfun(@isempty, network_table.Ampacity_A_))
        network_table.Ampacity_A_ = NaN(height(network_table),1);
    end 

    section = network_table.Section_mm2_;
    ampacity = network_table.Ampacity_A_;
    material = network_table.Cu_Al; % for now i dont consider Al and Cu seperate
    cable_id = network_table.Line;
    Length = network_table.Length_m_;
    Resistance = network_table.R_Ohm_km_;
    Reactance = network_table.X_Ohm_km_;
    substation_str = sheet_name{i};  % Extract string from cell
    substation_num = str2double(regexp(substation_str, '\d+', 'match', 'once'));

    if any(isnan(network_table{:,4:7}) | any(network_table{:,4:7} == 0),'all') % check if missing length,impedance or ampacity
        if any(~isnan(section))||any(section~=0) % check if the cross-section is present
            % missing ampacity
            if any(isnan(ampacity))||any(ampacity==0) % detect missing ampacity value
                idx_mis_amp = isnan(ampacity)|(ampacity==0);
                missingRows = find(idx_mis_amp);
                for k=1:numel(missingRows)
                    rowID = missingRows(k);
                    csValue = section(rowID);

                    % Find the closest cross-section from your 'lookup' table

                    [~, idxNearest] = min(abs(lookup.cross_section - csValue));

                    % Fill the ampacity from 'lookup'
                    network_table.Ampacity_A_(rowID) = lookup.ampacity(idxNearest);


                    % record modified line id
                    if isempty(ID_updated_lines) || ~ismember(cable_id(rowID), ID_updated_lines)
                        ID_updated_lines = [ID_updated_lines;cable_id(rowID)];
                    end
                end
            end
            % missing impedance
            if any(Resistance == 0) || any(Reactance == 0) || any(isnan(Resistance)) || any(isnan(Reactance))
                idx_mis_imp = (Resistance == 0) | (Reactance == 0) | (isnan(Resistance)) |(isnan(Reactance));
                missingRows = find(idx_mis_imp);
                for k=1:numel(missingRows)
                    rowID = missingRows(k);
                    csValue = section(rowID);

                    % Find the closest cross-section from your 'lookup' table
                    [~, idxNearest] = min(abs(lookup.cross_section - csValue));

                    % Fill the impedance from 'lookup'
                    network_table.R_Ohm_km_(rowID) = lookup.R(idxNearest);
                    network_table.X_Ohm_km_(rowID) = lookup.X(idxNearest);
                    % record modified line id
                    if isempty(ID_updated_lines) || ~ismember(cable_id(rowID), ID_updated_lines)
                        ID_updated_lines = [ID_updated_lines;cable_id(rowID)];
                    end
                end
            end
            % missing length
            if any(isnan(Length))||any(Length==0) % detect missing length
                idx_mis_len = isnan(Length)|(Length==0);
                missingRows = find(idx_mis_len);
                for k=1:numel(missingRows)
                    rowID = missingRows(k);
                    % Fill the length with a default of 1 meter
                    network_table.Length_m_(rowID) = default_L;
                    % record modified line id
                    if isempty(ID_updated_lines) || ~ismember(cable_id(rowID), ID_updated_lines)
                        ID_updated_lines = [ID_updated_lines;cable_id(rowID)];
                    end
                end
            end

        else % if cross-section is missing fill missing values with default values;

            % missing ampacity
            if any(isnan(ampacity))||any(ampacity==0) % detect missing ampacity value
                idx_mis_amp = isnan(ampacity)|(ampacity==0);
                missingRows = find(idx_mis_amp);
                for k=1:numel(missingRows)
                    rowID = missingRows(k);
                    % Fill the ampacity from 'lookup'
                    network_table.Ampacity_A_(rowID) = default_A;
                    % record modified line id
                    if isempty(ID_updated_lines) || ~ismember(cable_id(rowID), ID_updated_lines)
                        ID_updated_lines = [ID_updated_lines;cable_id(rowID)];
                    end
                end
            end
            % missing impedance
            if any(Resistance == 0) || any(Reactance == 0) || any(isnan(Resistance)) || any(isnan(Reactance))
                idx_mis_imp = (Resistance == 0) | (Reactance == 0) | (isnan(Resistance)) |(isnan(Reactance));
                missingRows = find(idx_mis_imp);
                for k=1:numel(missingRows)
                    rowID = missingRows(k);
                    network_table.R_Ohm_km_(rowID) = default_R;
                    network_table.X_Ohm_km_(rowID) = default_X;
                    % record modified line id
                    if isempty(ID_updated_lines) || ~ismember(cable_id(rowID), ID_updated_lines)
                        ID_updated_lines = [ID_updated_lines;cable_id(rowID)];
                    end
                end
            end
            % missing length
            if any(isnan(Length))||any(Length==0) % detect missing length
                idx_mis_len = isnan(Length)|(Length==0);
                missingRows = find(idx_mis_len);
                for k=1:numel(missingRows)
                    rowID = missingRows(k);
                    network_table.Length_m_(rowID) = default_L;
                    % record modified line id
                    if isempty(ID_updated_lines) || ~ismember(cable_id(rowID), ID_updated_lines)
                        ID_updated_lines = [ID_updated_lines;cable_id(rowID)];
                    end
                end
            end
        end


    end

    % Restore Slack Bus Placeholders in Their Original Positions
    % for j = 1:numel(slack_positions)
    %     pos = slack_positions(j);
    %     network_table = [network_table(1:pos-1, :); slack_rows(j, :); network_table(pos:end, :)];
    % end
    data{i}=network_table; % updated the network data



end

Sierre.LV_grid = data;
filename = 'Sierre_v2.mat'
save(filename,'Sierre');
disp('Sierre missing line parameters updated')
end


