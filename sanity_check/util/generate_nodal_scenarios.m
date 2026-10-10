function scenarios = generate_nodal_scenarios(X, cluster_idx, nodal_powers)
%GENERATE_NODAL_SCENARIOS Summary of this function goes here
%   Detailed explanation goes here
arguments (Input)
    X
    cluster_idx
    nodal_powers
end

arguments (Output)
    scenarios
end

[n_samples_per_day, n_days, n_houses] = size(X);
delta_T = 24/n_samples_per_day; % hours

n_clusters = max(cluster_idx);
cluster_prob = zeros(n_clusters, 1);
 % min and max value per timestep
cluster_LB = zeros(n_clusters, n_samples_per_day);
cluster_UB = zeros(n_clusters, n_samples_per_day);
cluster_means = zeros(n_clusters, n_samples_per_day); % mean of cluster
cluster_detrend_variance = zeros(n_clusters, n_samples_per_day);
cluster_detrend_skewness = zeros(n_clusters, n_samples_per_day);

cluster_detrend_means = zeros(n_clusters, n_samples_per_day);
cluster_detrend_cov = zeros(n_clusters, n_samples_per_day, n_samples_per_day);
for i=1:n_clusters

    n_houses_i = sum(cluster_idx == i);

    X_i = X(:, :, cluster_idx == i);

    energy = sum(X_i, 1) * delta_T;

    % X_reshape = reshape(X_i, n_samples_per_day, n_days*n_houses_i);
    
    max_powers = max(reshape(X_i, n_samples_per_day*n_days, n_houses_i));
    max_powers_rep = repmat(max_powers, n_days, 1);

    % X_i = X_i ./ energy;

    % Probability of generating a scenario from each cluster
    cluster_prob(i) = n_houses_i / n_houses;

    X_i = reshape(X_i, n_samples_per_day, n_houses_i*n_days); % stack all measurements together
    X_i = X_i ./ max_powers_rep(:)';
    
    X_i(X_i <= 0) = min(X_i(X_i > 0)); % remove negatives
    
    X_i(:, any(isnan(X_i), 1)) = []; % remove days containing nan
    mu = mean(X_i, 2);
    cluster_means(i, :) = mu;

    detrend = log(X_i./mu);
    detrend(detrend < -4) = -4;
    % detrend = X_i./mu;

    % compute bounds for generating the residuals for each cluster
    cluster_LB(i, :) = prctile(detrend, 0, 2);
    cluster_UB(i, :) = prctile(detrend, 100, 2);

    cluster_detrend_variance(i, :) = var(detrend, [], 2);
    cluster_detrend_means(i, :) = mean(detrend, 2);
    cluster_detrend_cov(i, :, :) = cov(detrend');
    cluster_detrend_skewness(i, :) = skewness(detrend, [], 2);
end

n_nodes = length(nodal_powers);

nodal_clusters = randsample(n_clusters, n_nodes, true, cluster_prob);

% Generate residuals from mean
% Uniform distribution
% residuals = cluster_LB(nodal_clusters, :) + (cluster_UB(nodal_clusters, :) - cluster_LB(nodal_clusters, :)) .* rand(n_nodes, n_samples_per_day);

% Gaussian distribution
% residuals = cluster_detrend_variance(nodal_clusters, :) .* randn(n_nodes, n_samples_per_day);

% Log-normal distribution
% residuals = lognrnd(cluster_detrend_means(nodal_clusters, :), sqrt(cluster_detrend_variance(nodal_clusters, :)));

% Multivariate Gaussian distribution
residuals = zeros(n_nodes, n_samples_per_day);
for i=1:n_nodes
    residuals(i, :) = mvnrnd(cluster_detrend_means(nodal_clusters(i), :), squeeze(cluster_detrend_cov(nodal_clusters(i), :, :)));
end

% Bound residuals to avoid extreme values
% residuals = clip(residuals, -10*sqrt(cluster_detrend_variance(nodal_clusters, :)), 2*sqrt(cluster_detrend_variance(nodal_clusters, :)));
residuals = clip(residuals, -inf, cluster_UB(nodal_clusters, :));

% Add residuals to mean
scenarios = cluster_means(nodal_clusters, :) .* exp(residuals);
% scenarios = cluster_means(nodal_clusters, :) .* residuals;
% scenarios = clip(scenarios, cluster_LB(nodal_clusters, :), cluster_UB(nodal_clusters, :));

scenarios = nodal_powers .* scenarios;

end