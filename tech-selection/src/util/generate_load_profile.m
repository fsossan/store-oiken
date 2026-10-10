function [X_kw, S_native, nodal_cluster] = generate_load_profile(node_power_kw, D, params, seed)
%GENERATE_LOAD_PROFILE  Synthetic nodal demand from the cached GMM sampler.
%
%   [X_kw, S_native, nodal_cluster] = generate_load_profile(node_power_kw, D, params, seed)
%
%   Inputs
%   ------
%   node_power_kw : [Nd x 1] nominal per-node demand magnitude, kW per phase
%                   (complex P + jQ from get_grid_SFOE: demand_factor * PLmax/3 ...)
%   D             : number of synthetic days per node
%   params        : struct, all fields optional (defaults shown):
%       .train_file     'load_consumption_train_heapo.mat'  (resolved in data/external/)
%       .fact           -1        sign/scale applied to the output (-1: load = negative injection)
%       .p_LB / .p_UB   0 / 99    residual clipping percentiles
%       .clip_residuals true
%       .GMM_order      4
%       .log_residuals  true
%       .num_clusters   5
%       .weekday        "all"     "weekday" | "weekend" | "all"
%       .season         "all"     "winter" | "spring" | "summer" | "autumn" | "all"
%       .fit_seed       1         rng seed of the (cached) GMM fit
%       .enabled        true      false -> all-zero stream at the native resolution
%   seed          : integer; with the model, fully determines the draw (sample_load_gmm)
%
%   Outputs
%   -------
%   X_kw          : [Nd x S_native x D]  demand, kW per phase, sign from .fact
%   S_native      : native steps/day of the training data
%   nodal_cluster : [Nd x 1] cluster assigned to each node
%
%   The GMM is fitted once per parameter set and cached in
%   data/derived/load_gmm/ (load_gmm_model), then sampled per network
%   (sample_load_gmm). Both are deterministic: the fit by params.fit_seed, the
%   draw by `seed`; neither touches the caller's rng state. Before 2026-10-10
%   the model was refitted inside every solve (~47 s, with fitgmdist's random
%   initialisation taken from whatever rng state the caller left), so every
%   network effectively used its own fit and results were reproducible only
%   with an identical call order. Demand realisations therefore differ from
%   results produced before that date.

if nargin < 3 || isempty(params); params = struct(); end
if nargin < 4 || isempty(seed);   seed = 0; end

params = set_default(params, 'train_file',     'load_consumption_train_heapo.mat');
params = set_default(params, 'fact',           -1);
params = set_default(params, 'p_LB',           0);
params = set_default(params, 'p_UB',           99);
params = set_default(params, 'clip_residuals', true);
params = set_default(params, 'GMM_order',      4);
params = set_default(params, 'log_residuals',  true);
params = set_default(params, 'num_clusters',   5);
params = set_default(params, 'weekday',        "all");
params = set_default(params, 'season',         "all");
params = set_default(params, 'fit_seed',       1);
params = set_default(params, 'enabled',        true);

Nd = numel(node_power_kw);

if ~params.enabled
    % Only the native resolution is needed: from the cache when it exists,
    % otherwise from the training file itself.
    model = load_gmm_model(params, false);
    if ~isempty(model)
        S_native = model.n_samples_per_day;
    else
        paths      = project_paths();
        train_file = resolve_data_file(params.train_file, paths.data_external, ...
            'Demand training data (demand_profile.train_file)');
        S_native = size(load(train_file).training_data.X, 1);
    end
    X_kw          = zeros(Nd, S_native, D);
    nodal_cluster = zeros(Nd, 1);
    return
end

model = load_gmm_model(params, true);
[X, nodal_cluster] = sample_load_gmm(model, node_power_kw, D, seed);   % [Nd x D x S]

X        = params.fact .* X;
S_native = size(X, 3);
X_kw     = permute(X, [1 3 2]);   % -> [Nd x S_native x D]
end
