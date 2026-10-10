function paths = setup_paths()
%SETUP_PATHS  Put the project code on the MATLAB path and return its folder layout.
%
%   paths = setup_paths()
%
%   Call once per MATLAB session, from anywhere -- the repo root is resolved
%   from this file's own location, not from the current directory:
%
%       run('/path/to/tech-selection/setup_paths.m')     % or: cd there; setup_paths
%
%   Adds src/ (and experiments/, if present) recursively to the path, makes
%   sure the archived old-code/ tree is NOT on the path, and returns the
%   struct from project_paths (root, config, data_*, results, data files).
%
%   Missing data files only produce a warning here; the function that
%   actually needs a file raises the hard error with the full path it looked
%   for (see resolve_data_file and data/README.md).

root = fileparts(mfilename('fullpath'));

addpath(root);                                   % main.m / setup_paths.m themselves
addpath(genpath(fullfile(root, 'src')));
if isfolder(fullfile(root, 'experiments'))
    addpath(genpath(fullfile(root, 'experiments')));
end

% Archived code must never shadow the active tree.
old_code = fullfile(root, 'old-code');
p        = strsplit(path, pathsep);
on_path  = p(startsWith(p, old_code));
if ~isempty(on_path)
    rmpath(on_path{:});
end

paths = project_paths();

required = {paths.lv_grids_file, paths.pv_profiles_file, paths.load_train_file};
for k = 1:numel(required)
    if ~isfile(required{k})
        warning('setup_paths:missingData', ...
            'Data file not found: %s\nSee data/README.md for where it comes from.', required{k});
    end
end
end
