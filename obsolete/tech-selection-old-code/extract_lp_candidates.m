function [candidates, cand_info] = extract_lp_candidates(lp_out, dims, cfg)
% EXTRACT_LP_CANDIDATES  Identify candidate BESS nodes from LP solution.
%
%   Nodes whose total LP energy capacity across all technologies exceeds
%   E_nom_thresh_pu are selected as candidates for the MILP stage.
%
%   The fallback floor is expressed as a fraction of Nd (min_candidates_frac)
%   rather than an absolute count, so it scales correctly for small networks.
%   The hard minimum is always 1 — zero candidates is never allowed.
%
%   If fewer than floor(min_candidates_frac * Nd) nodes pass the threshold
%   and fallback_all_nodes is true, all Nd nodes are used instead.
%
%   [candidates, cand_info] = extract_lp_candidates(lp_out, dims, cfg)
%
%   Inputs
%   ------
%   lp_out : struct   output of solve_lp_relaxation
%   dims   : struct   dimension struct
%   cfg    : struct   sizing config
%
%   Outputs
%   -------
%   candidates : [Nd x 1] logical   true = candidate node
%   cand_info  : struct
%       .Nc                  scalar    number of candidate nodes
%       .candidate_idx       [Nc x 1]  indices into 1:Nd
%       .threshold_used      scalar    E_nom threshold actually applied
%       .min_cands_floor     scalar    computed floor for this network
%       .fallback_triggered  logical   true if floor was hit and fallback used
%       .lp_E_nom_full       [Nd x J]  full LP energy result (provenance)

thresh   = double(cfg.lp_screening.E_nom_thresh_pu);
frac     = double(cfg.lp_screening.min_candidates_frac);  % e.g. 0.10
fallback = logical(cfg.lp_screening.fallback_all_nodes);
Nd       = dims.Nd;

% floor scales with network size; never below 1
min_cands_floor = max(1, floor(frac * Nd));

% sum energy across technologies for each node  [Nd x 1]
E_total = sum(lp_out.E_nom_node_pu, 2);

candidates = E_total > thresh;
Nc         = sum(candidates);

fallback_triggered = false;
if Nc == 0
    if fallback
        warning('extract_lp_candidates: %d/%d nodes above threshold %.2e (floor=%d). Falling back to all nodes.', ...
                Nc, Nd, thresh, min_cands_floor);
        candidates         = true(Nd, 1);
        Nc                 = Nd;
        fallback_triggered = true;
    else
        warning('extract_lp_candidates: %d/%d nodes above threshold %.2e (floor=%d). Proceeding with reduced set.', ...
                Nc, Nd, thresh, min_cands_floor);
    end
end

cand_info.Nc                 = Nc;
cand_info.candidate_idx      = find(candidates);
cand_info.threshold_used     = thresh;
cand_info.min_cands_floor    = min_cands_floor;
cand_info.fallback_triggered = fallback_triggered;
cand_info.lp_E_nom_full      = lp_out.E_nom_node_pu;

end