function [scenarios, days_to_keep, cluster_gmm, residuals_orig] = generate_nodal_scenarios_2(train_data, nodal_powers, model_params, opts)
%GENERATE_NODAL_SCENARIOS Summary of this function goes here
%   Detailed explanation goes here
arguments (Input)
    train_data
    nodal_powers
    model_params
    opts.weekday (1,1) string {mustBeMember(opts.weekday, ...
        ["weekday", "weekend", "all"])}
    opts.season  (1,1) string {mustBeMember(opts.season, ...
        ["winter","spring","summer","autumn","all"])} = "all"
end

arguments (Output)
    scenarios
    days_to_keep
    cluster_gmm
    residuals_orig
end


cluster_idx = train_data.cluster_idx;
X = train_data.X;
time = train_data.time;

[n_samples_per_day, n_days, n_houses] = size(X);
% delta_T = 24/n_samples_per_day; % hours

dates = dateshift(time(1:n_samples_per_day:end), 'start', 'day'); % get only the day part of the date
days = weekday(dates);
months = dates.Month;

if opts.weekday == "weekday"
    day_idx = days > 1 & days < 7;
elseif opts.weekday == "weekend"
    day_idx = days == 1 | days == 7;
else
    day_idx = ones(size(days));
end

if opts.season == "winter"
    month_idx = ismember(months, [1 2 12]);
elseif opts.season == "spring"
    month_idx = ismember(months, [3 4 5]);
elseif opts.season == "summer"
    month_idx = ismember(months, [6 7 8]);
elseif opts.season == "autumn"
    month_idx = ismember(months, [9 10 11]);
else
    month_idx = ones(size(months));
end

days_to_keep = day_idx & month_idx;
n_days_to_keep = sum(days_to_keep);

n_clusters = max(cluster_idx);
cluster_prob = zeros(n_clusters, 1);
% min and max value per timestep
cluster_LB = zeros(n_clusters, n_samples_per_day);
cluster_UB = zeros(n_clusters, n_samples_per_day);
cluster_means = zeros(n_clusters, n_samples_per_day); % mean of cluster

% Preallocate array of gmdistribution objects without using 'empty' (which errors)
cluster_gmm = cell(n_clusters, 1);

residuals_orig = [];
for i=3

    n_houses_i = sum(cluster_idx == i);

    X_all_cluster = X(:, :, cluster_idx == i);

    X_i = X_all_cluster(:, days_to_keep, :);
    
    max_powers = max(reshape(X_all_cluster, n_samples_per_day*n_days, n_houses_i));
    max_powers_rep = repmat(max_powers, n_days_to_keep, 1);
    X_i = X_i ./ reshape(max_powers_rep, 1, n_days_to_keep, n_houses_i);

    % Probability of generating a scenario from each cluster
    cluster_prob(i) = n_houses_i / n_houses;

    X_i = reshape(X_i, n_samples_per_day, n_houses_i*n_days_to_keep); % stack all measurements together
    
    X_i(X_i <= 0) = min(X_i(X_i > 0)); % remove negatives
    
    X_i(:, any(isnan(X_i), 1)) = []; % remove days containing nan
    mu = median(X_i, 2, "omitnan");
    cluster_means(i, :) = mu;

    if model_params.log_residuals
        detrend = log(X_i./mu);
    else
        detrend = X_i./mu;
    end
    
    residuals_orig = [residuals_orig detrend];

    % compute bounds for generating the residuals for each cluster
    cluster_LB(i, :) = prctile(detrend, model_params.p_LB, 2);
    cluster_UB(i, :) = prctile(detrend, model_params.p_UB, 2);

    cluster_gmm{i} = fitgmdist(detrend', model_params.GMM_order, 'RegularizationValue', 1e-6); % GMM with two components
end

n_nodes = length(nodal_powers);

nodal_clusters = randsample(n_clusters, n_nodes, true, cluster_prob);

% Generate residuals from mean
residuals = zeros(n_nodes, n_samples_per_day);
for i=1:n_nodes
    residuals(i, :) = random(cluster_gmm{nodal_clusters(i)});
end

% Bound residuals to avoid extreme values
if model_params.clip_residuals
    residuals = clip(residuals, cluster_LB(nodal_clusters, :), cluster_UB(nodal_clusters, :));
end

% Add residuals to mean
if model_params.log_residuals
    scenarios = cluster_means(nodal_clusters, :) .* exp(residuals);
else
    scenarios = cluster_means(nodal_clusters, :) .* residuals;
end

scenarios = nodal_powers .* scenarios;

end