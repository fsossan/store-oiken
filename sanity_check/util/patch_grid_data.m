function patch_grid_data(lookup, fill_table, data)
% PATCH_GRID_DATA  Patches missing line parameters and transformer R/X
%   in the combined data struct and saves data_v2.mat
%
%   Inputs:
%     lookup      — line parameter lookup struct (from lookup_data.mat)
%     fill_table  — transformer fill table (from transformer_fill_table.mat)
%     data        — combined raw data struct (from combine_struct_data)
%
%   Output:
%     saves data_v2.mat with patched line and transformer parameters
%
%   Call from main.m:
%     fill_table = load('output/transformer_fill_table.mat').transformer_fill_table;
%     patch_grid_data(lookup.data{:}, fill_table, data);

% Step 1 — patch missing line parameters (R, X, length, ampacity)
data = patch_line_params(lookup, data);

% Step 2 — patch missing transformer R and X
data = patch_transformer_params(fill_table, data);

% Save once
save('data_v2.mat', 'data');
fprintf('data_v2.mat saved with patched line and transformer parameters\n');

end