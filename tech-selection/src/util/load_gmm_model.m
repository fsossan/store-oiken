function model = load_gmm_model(params, fit_if_missing)
%LOAD_GMM_MODEL  Cached demand GMM: load from data/derived/load_gmm/, or fit and save.
%
%   model = load_gmm_model(params)          % fit if not cached (needs the training file)
%   model = load_gmm_model(params, false)   % cache only; returns [] if absent
%
%   params : generate_load_profile's params (train_file, num_clusters,
%            GMM_order, p_LB, p_UB, clip_residuals, log_residuals, weekday,
%            season, fit_seed)
%
%   The cache file name spells out every fit parameter, so a config change
%   fits a new model instead of silently reusing a stale one. The training
%   file's byte size is stored in the model and re-checked whenever the file
%   is present; a mismatch triggers a refit. When the training file is absent
%   but a cache exists, the cache is used: a clone that has
%   data/derived/load_gmm/ does not need the 163 MB training set unless it
%   changes the fit parameters.

if nargin < 2 || isempty(fit_if_missing); fit_if_missing = true; end

paths     = project_paths();
cache_dir = fullfile(paths.data_derived, 'load_gmm');
[~, base] = fileparts(char(params.train_file));
name = sprintf('%s__K%d_G%d_log%d_clip%d_p%g-%g_%s_%s_seed%d.mat', base, ...
    params.num_clusters, params.GMM_order, params.log_residuals, params.clip_residuals, ...
    params.p_LB, params.p_UB, char(string(params.weekday)), char(string(params.season)), ...
    params.fit_seed);
cache_file = fullfile(cache_dir, name);

train_file = '';
try
    train_file = resolve_data_file(params.train_file, paths.data_external, 'Demand training data');
catch
end

if isfile(cache_file)
    S     = load(cache_file, 'model');
    model = S.model;
    if isempty(train_file)
        return                                   % no training file around: trust the cache
    end
    info = dir(train_file);
    if isfield(model, 'training') && info.bytes == model.training.bytes
        return
    end
    warning('load_gmm_model:stale', ...
        'Training file size differs from the cached fit (%s); refitting.', cache_file);
end

if ~fit_if_missing
    model = [];
    return
end
if isempty(train_file)
    % raises resolve_data_file's own message, which names both locations tried
    resolve_data_file(params.train_file, paths.data_external, 'Demand training data');
end

fprintf('Fitting demand GMM (%s) ... ', name);
t0 = tic;
training_data = load(train_file).training_data;
model = fit_load_gmm(training_data, params);
info  = dir(train_file);
model.training = struct('file', char(params.train_file), 'bytes', info.bytes, 'mtime', info.date);
if ~isfolder(cache_dir); mkdir(cache_dir); end
save(cache_file, 'model');
fprintf('done in %.0f s, cached at %s\n', toc(t0), cache_file);
end
