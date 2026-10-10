function p = project_paths()
%PROJECT_PATHS  Absolute paths of the project folders, resolved from this file.
%
%   p = project_paths()
%
%   Fields
%   ------
%   root            repo root (the folder holding main.m / setup_paths.m)
%   config          JSON configuration files
%   data            data root
%   data_raw        tracked input data, never written by code
%   data_external   large inputs not stored in git (see data/README.md)
%   data_derived    tracked caches derived from raw data
%   results         everything the code writes (git-ignored, created on demand)
%   lv_grids_file, pv_profiles_file, load_train_file
%                   the three data files the pipeline reads
%
%   Everything in the pipeline that touches the file system goes through
%   this struct, so nothing depends on MATLAB's current directory or on
%   which folders happen to be on the path.

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % src/util -> src -> root

p.root          = root;
p.config        = fullfile(root, 'config');
p.data          = fullfile(root, 'data');
p.data_raw      = fullfile(root, 'data', 'raw');
p.data_external = fullfile(root, 'data', 'external');
p.data_derived  = fullfile(root, 'data', 'derived');
p.results       = fullfile(root, 'results');

p.lv_grids_file    = fullfile(p.data_raw,      'lv_grids.mat');
p.pv_profiles_file = fullfile(p.data_raw,      'pv_profiles_year.mat');
p.load_train_file  = fullfile(p.data_external, 'load_consumption_train_heapo.mat');
end
