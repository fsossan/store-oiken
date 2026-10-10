function [X, nodal_clusters] = sample_load_gmm(model, nodal_powers, D, seed)
%SAMPLE_LOAD_GMM  Draw D synthetic days per node from a fitted demand model.
%
%   [X, nodal_clusters] = sample_load_gmm(model, nodal_powers, D, seed)
%
%   model        : from fit_load_gmm / load_gmm_model
%   nodal_powers : [n x 1] per-node magnitude the dimensionless day shape is
%                  multiplied by (may be complex P + jQ -> complex X)
%   D            : number of days per node
%   seed         : non-negative integer; with the model, fully determines X
%
%   X              : [n x D x S]  nodal_powers(i) * shape(i, d, :)
%   nodal_clusters : [n x 1]      cluster assigned to each node
%
%   Reproducibility: everything is drawn from a local mrg32k3a stream seeded
%   with `seed`; the caller's global stream is restored afterwards, so the
%   result does not depend on how many random numbers were drawn before the
%   call. Substream 1 assigns clusters; day d of node i always uses substream
%   1 + i*SUB_PER_NODE + d, so day 1 of a D=7 run equals the D=1 day for every
%   node (draws are nested across horizon lengths, which the original
%   generate_nodal_scenarios_4 was not). Needs only base MATLAB: the model
%   stores the mixtures as weights / means / Cholesky factors (fit_load_gmm).

SUB_PER_NODE = 10000;   % substreams reserved per node (D must stay below this)

n = numel(nodal_powers);
S = model.n_samples_per_day;
K = model.n_clusters;
if D >= SUB_PER_NODE
    error('sample_load_gmm:tooManyDays', ...
        'D=%d exceeds the %d substreams reserved per node.', D, SUB_PER_NODE);
end

prev_stream = RandStream.getGlobalStream();
rs = RandStream('mrg32k3a', 'Seed', seed);
RandStream.setGlobalStream(rs);
restore_stream = onCleanup(@() RandStream.setGlobalStream(prev_stream));

rs.Substream   = 1;
cp             = cumsum(model.cluster_prob(:)).';              % [1 x K]
nodal_clusters = min(sum(rand(n, 1) > cp, 2) + 1, K);          % inverse-CDF draw (no toolbox)

residuals = zeros(n, D, S);
for i = 1:n
    c  = model.comp(nodal_clusters(i));
    cw = cumsum(c.w);
    for d = 1:D
        rs.Substream = 1 + i*SUB_PER_NODE + d;
        k = find(rand < cw, 1);                      % mixture component
        if isempty(k); k = numel(cw); end            % guard against cw(end) < 1 by rounding
        residuals(i, d, :) = c.mu(k, :) + randn(1, S) * c.L(:, :, k).';   % x = mu + L z
    end
end

if model.clip_residuals
    lb = reshape(model.cluster_LB(nodal_clusters, :), n, 1, S);
    ub = reshape(model.cluster_UB(nodal_clusters, :), n, 1, S);
    residuals = min(max(residuals, lb), ub);
end

mu = reshape(model.cluster_means(nodal_clusters, :), n, 1, S);
if model.log_residuals
    shape = mu .* exp(residuals);
else
    shape = mu .* residuals;
end

X = nodal_powers(:) .* shape;
end
