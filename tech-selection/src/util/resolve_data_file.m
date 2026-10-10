function f = resolve_data_file(name, default_dir, what)
%RESOLVE_DATA_FILE  Turn a config file name into an existing absolute path.
%
%   f = resolve_data_file(name, default_dir, what)
%
%   name        : file name or path as written in a config
%                 (e.g. 'pv_profiles_year.mat')
%   default_dir : folder to look in when `name` is not itself an existing path
%   what        : short description for the error message
%
%   Resolution order: `name` as given (absolute, or relative to the current
%   directory), then fullfile(default_dir, name). Errors with a message that
%   names both locations and points at data/README.md if neither exists.

name = char(name);
if isfile(name)
    f = name;
    return
end
cand = fullfile(default_dir, name);
if isfile(cand)
    f = cand;
    return
end
error('resolve_data_file:notFound', ...
    ['%s not found.\n  looked for: %s\n  and:        %s\n' ...
     'See data/README.md for where this file comes from and where to put it.'], ...
    what, name, cand);
end
