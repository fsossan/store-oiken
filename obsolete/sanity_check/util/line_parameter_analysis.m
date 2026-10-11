function line_parameter_analysis(Sion,Sierre)
%line_parameter_analysis 
% clear
% close all
% 
% addpath('/Users/fozi/Desktop/codes/Sanity_check_v2/network_data/mat_data') 
% 
% load('Sierre_dat.mat')
% load('Sion_dat.mat')

% % Combine both data sets (similar structure)
combined_data = [Sion.LV_grid Sierre.LV_grid];
combined_subs_ID = [Sion.LV_grid_id Sierre.LV_grid_id];

% Initialize an empty array to store all the extracted data
line_data =[];



% Loop over all the networks in the data cell array
for i = 1:numel(combined_data)
    % Extract the table for the current network
    network_table = combined_data{i};

   
    % removing dublicate entries
    [~, unique_idx] = unique(network_table(:,1:3), 'rows','stable');
    % % Check if duplicates were detected and display a message
    num_duplicates = size(network_table, 1) - size(unique_idx, 1);
    if num_duplicates > 0
        % fprintf('Duplicates detected and removed %d\n', num_duplicates);
        network_table = network_table(unique_idx,:);
    end

    % char amp to Nan (ampacity)
    if iscell(network_table.Ampacity_A_) && all(cellfun(@isempty, network_table.Ampacity_A_));
        network_table.Ampacity_A_ = NaN(height(network_table),1);
    end 

   

    section = network_table.Section_mm2_;
    ampacity = network_table.Ampacity_A_;
    material = network_table.Cu_Al;
    cable_id = network_table.Line;
    Length = network_table.Length_m_;
    Resistance = network_table.R_Ohm_km_;
    Reactance = network_table.X_Ohm_km_;
    substation_str = combined_subs_ID{i};  % Extract string from cell
    substation_num = str2double(regexp(substation_str, '\d+', 'match', 'once'));
    substation_ID = repmat((substation_num),numel(network_table(:,1)),1);
    cable_type = network_table.Cable_Line;
 

    
    line_data=[line_data;table(substation_ID,Length,Resistance,Reactance,ampacity,section,material,cable_id,cable_type)];
end

% save md file
mdoflineparamter(line_data);
generate_line_parameter_summary(line_data)
generate_line_parameter_details(line_data)

end