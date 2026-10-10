function model = fit_load_gmm(training_data, params)
%FIT_LOAD_GMM  Fit the per-cluster residual GMMs of the synthetic demand sampler.
%
%   model = fit_load_gmm(training_data, params)
%
%   training_data : struct from data/external/load_consumption_train_heapo.mat
%       .X           [S x Ndays x Nhouses]  measured consumption, S steps per day
%       .time        datetime [S*Ndays x 1]
%       .cluster_idx [Nhouses x 1]          household cluster id (1..num_clusters)
%   params : struct (see generate_load_profile for the defaults)
%       .num_clusters .GMM_order .p_LB .p_UB .clip_residuals .log_residuals
%       .weekday ("weekday"|"weekend"|"all")  .season ("winter"|...|"all")
%       .fit_seed    rng seed for fitgmdist's random initialisation
%
%   model : struct consumed by sample_load_gmm
%       .n_clusters, .cluster_prob [K x 1], .cluster_means/.cluster_LB/.cluster_UB [K x S]
%       .comp [K x 1] struct: .w [1 x G] weights, .mu [G x S] means,
%             .L [S x S x G] lower Cholesky factors of the covariances,
%             .converged, .n_iter (fitgmdist diagnostics)
%       .n_samples_per_day, .log_residuals,
%       .clip_residuals, .params, .n_days_used, .n_houses, .fitted_on
%
%   Same maths as the fit half of generate_nodal_scenarios_4 (the original
%   WIP sampler, kept for experiments/test_load_profile_determinism.m): per
%   cluster, normalise each house by its own maximum, keep the days matching
%   the weekday/season filter, detrend by the cluster-mean day (log-ratio by
%   default), bound the residuals by percentiles and fit one GMM. The fit is
%   independent of any network and takes about a minute, so load_gmm_model
%   caches it in data/derived/load_gmm/.

X           = training_data.X;
time        = training_data.time;
cluster_idx = training_data.cluster_idx(:);

[S, n_days, n_houses] = size(X);

dates  = dateshift(time(1:S:end), 'start', 'day');
wd     = weekday(dates);
months = dates.Month;

switch string(params.weekday)
    case "weekday"; day_idx = wd > 1 & wd < 7;
    case "weekend"; day_idx = wd == 1 | wd == 7;
    otherwise;      day_idx = true(size(wd));
end
days_to_keep = day_idx(:) & season_month_mask(months, params.season);
n_keep       = sum(days_to_keep);
if n_keep == 0
    error('fit_load_gmm:noDays', 'No training days match weekday=%s, season=%s.', ...
        string(params.weekday), string(params.season));
end

K = params.num_clusters;
cluster_prob  = zeros(K, 1);
cluster_LB    = zeros(K, S);
cluster_UB    = zeros(K, S);
cluster_means = zeros(K, S);
comp = struct('w', cell(K, 1), 'mu', cell(K, 1), 'L', cell(K, 1), ...
               'converged', cell(K, 1), 'n_iter', cell(K, 1));

% fitgmdist initialises randomly: pin it so the same data + params give the
% same model, and leave the caller's rng untouched.
prev_rng = rng;
rng(params.fit_seed, 'twister');
restore_rng = onCleanup(@() rng(prev_rng));

for i = 1:K
    in_cluster = cluster_idx == i;
    n_houses_i = sum(in_cluster);
    if n_houses_i == 0
        error('fit_load_gmm:emptyCluster', 'Cluster %d has no households in the training set.', i);
    end
    X_all = X(:, :, in_cluster);
    X_i   = X_all(:, days_to_keep, :);

    max_powers = max(reshape(X_all, S*n_days, n_houses_i));             % per-house maximum
    X_i = X_i ./ reshape(repmat(max_powers, n_keep, 1), 1, n_keep, n_houses_i);

    cluster_prob(i) = n_houses_i / n_houses;

    X_i = reshape(X_i, S, n_houses_i*n_keep);   % every (house, day) is one column
    X_i(X_i <= 0) = min(X_i(X_i > 0));          % no non-positives before the log
    X_i(:, any(isnan(X_i), 1)) = [];            % drop days containing NaN

    mu = mean(X_i, 2, "omitnan");
    cluster_means(i, :) = mu;

    if params.log_residuals
        detrend = log(X_i ./ mu);
    else
        detrend = X_i ./ mu;
    end

    cluster_LB(i, :) = prctile(detrend, params.p_LB, 2);
    cluster_UB(i, :) = prctile(detrend, params.p_UB, 2);

    g = fitgmdist(detrend', params.GMM_order, 'RegularizationValue', 1e-6);
    % Keep the mixture as plain arrays (weights, means, lower Cholesky factors
    % of the covariances) rather than the gmdistribution object: sampling then
    % needs only base MATLAB, and the cache loads on a machine without the
    % Statistics toolbox. Only this fit needs the toolbox.
    G = g.NumComponents;
    L = zeros(S, S, G);
    for c = 1:G
        L(:, :, c) = chol(g.Sigma(:, :, c), 'lower');
    end
    comp(i) = struct('w', g.ComponentProportion(:).', 'mu', g.mu, 'L', L, ...
        'converged', g.Converged, 'n_iter', g.NumIterations);
end

model.n_clusters        = K;
model.cluster_prob      = cluster_prob;
model.cluster_means     = cluster_means;
model.cluster_LB        = cluster_LB;
model.cluster_UB        = cluster_UB;
model.comp              = comp;
model.n_samples_per_day = S;
model.log_residuals     = logical(params.log_residuals);
model.clip_residuals    = logical(params.clip_residuals);
model.params            = params;
model.n_days_used       = n_keep;
model.n_houses          = n_houses;
model.fitted_on         = char(datetime('now'));
end
