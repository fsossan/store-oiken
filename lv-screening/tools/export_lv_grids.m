function export_lv_grids(mat_file, out_dir)
%EXPORT_LV_GRIDS  One-off export of the LV grid portfolio to CSV (Python-readable).
%
%   export_lv_grids()                       % defaults below
%   export_lv_grids(mat_file, out_dir)
%
%   lv_grids.mat stores MATLAB tables (class objects) that no other language
%   can read. This writes two flat CSV files, one row per line / substation
%   element, with a `network_id` column (the sheet name, e.g. LV_Grid_101):
%       <out_dir>/lines.csv         all LV_grid tables stacked
%       <out_dir>/substations.csv   all MV_LV_sub tables stacked
%   Column names are the original Excel headers in snake_case.
%
%   Run from the repo root:
%       matlab -batch "run('lv-screening/tools/export_lv_grids.m')"
%   or, inside MATLAB, cd to lv-screening/tools and call export_lv_grids.

here = fileparts(mfilename('fullpath'));
if nargin < 1 || isempty(mat_file)
    mat_file = fullfile(here, '..', '..', 'tech-selection', 'data', 'raw', 'lv_grids.mat');
end
if nargin < 2 || isempty(out_dir)
    out_dir = fullfile(here, '..', 'data', 'lv_grids');
end
if ~isfolder(out_dir); mkdir(out_dir); end

S    = load(mat_file, 'data');
data = S.data;
n    = numel(data.LV_grid);
assert(n == numel(data.MV_LV_sub), 'LV_grid and MV_LV_sub counts differ');

line_names = {'from','to','line','length_m','r_ohm_km','x_ohm_km','ampacity_a', ...
              'plmax_kw','qlmax_kvar','pg_kw','section_mm2','material','kind'};
sub_names  = {'from','to','object','on_off','r_pu','x_pu','rated_kva','from_kv','to_kv'};

lines = cell(n, 1);
subs  = cell(n, 1);
for k = 1:n
    T = data.LV_grid{k};
    assert(width(T) == numel(line_names), 'LV_grid %d has %d columns', k, width(T));
    T.Properties.VariableNames = line_names;
    T.from = string(T.from);  T.to = string(T.to);
    T.material = string(T.material);  T.kind = string(T.kind);
    T = addvars(T, repmat(string(data.LV_grid_id{k}), height(T), 1), 'Before', 1, 'NewVariableNames', 'network_id');
    lines{k} = T;

    U = data.MV_LV_sub{k};
    assert(width(U) == numel(sub_names), 'MV_LV_sub %d has %d columns', k, width(U));
    U.Properties.VariableNames = sub_names;
    U.from = string(U.from);  U.to = string(U.to);  U.object = string(U.object);
    U = addvars(U, repmat(string(data.LV_grid_id{k}), height(U), 1), 'Before', 1, 'NewVariableNames', 'network_id');
    subs{k} = U;
end
lines = vertcat(lines{:});
subs  = vertcat(subs{:});
writetable(lines, fullfile(out_dir, 'lines.csv'));
writetable(subs,  fullfile(out_dir, 'substations.csv'));
fprintf('Exported %d networks: %d line rows, %d substation rows -> %s\n', n, height(lines), height(subs), out_dir);
end
