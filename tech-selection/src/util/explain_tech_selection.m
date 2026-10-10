function selection = explain_tech_selection(best_iter, cfg)
% EXPLAIN_TECH_SELECTION  Summarize which ESS technology was selected and why.

selection = struct();
selection.tech_names = string(cfg.tech.names(:));

% Accept either the full out struct (with .sizing sub-struct) or a bare sizing struct
if nargin < 1 || isempty(best_iter)
    selection.selected_nodes = [];
    selection.tech_index = [];
    selection.tech_name = [];
    selection.reason = [];
    selection.cost = [];
    selection.required_c_rate = [];
    selection.feasible = [];
    selection.note = 'No solver output available yet.';
    return
end

if isfield(best_iter, 'sizing')
    sz = best_iter.sizing;
else
    sz = best_iter;
end

if ~isfield(sz, 'Installation')
    selection.selected_nodes = [];
    selection.tech_index = [];
    selection.tech_name = [];
    selection.reason = [];
    selection.cost = [];
    selection.required_c_rate = [];
    selection.feasible = [];
    selection.note = 'No solver output available yet.';
    return
end

Install = sz.Installation;
E_nom   = sz.E_nom_node_pu;
S_conv  = sz.S_conv_node_pu;

Nd = size(Install, 1);
J  = size(Install, 2);

selection.tech_index = zeros(Nd, 1);
selection.tech_name = repmat("None", Nd, 1);
selection.reason = repmat("No ESS installed", Nd, 1);
selection.cost = nan(Nd, J);
selection.required_c_rate = nan(Nd, J);
selection.feasible = false(Nd, J);

for n = 1:Nd
    tech_idx = find(Install(n, :) > 0.5, 1, 'first');
    if isempty(tech_idx)
        continue
    end

    selection.tech_index(n) = tech_idx;
    selection.tech_name(n) = string(cfg.tech.names{tech_idx});

    En = E_nom(n, tech_idx);
    Sn = S_conv(n, tech_idx);
    % Required C-rate = peak |dispatch| / E_nom, the ratio the MILP's C-rate
    % constraint bounds (B_plus, B_minus <= c_rate * E_nom); sizing.C_rate is
    % exactly that, computed by build_network_result. S_conv/E_nom (the old
    % definition here) is ~1/kP larger, since S_conv >= |B|/kP, and could flag
    % a feasible node as exceeding its limit.
    if isfield(sz, 'C_rate')
        req_c = sz.C_rate(n, tech_idx);
    else
        req_c = Sn / max(En, eps);
    end

    for j = 1:J
        selection.cost(n, j) = cfg.tech.cE(j) * En + cfg.tech.cS(j) * Sn + cfg.tech.cI(j);
        selection.required_c_rate(n, j) = req_c;
        selection.feasible(n, j) = req_c <= cfg.tech.c_rate(j) + 1e-9;
    end

    if selection.feasible(n, tech_idx)
        selection.reason(n) = sprintf('%s selected because it satisfies the required C-rate of %.2f and is the installed technology.', ...
            cfg.tech.names{tech_idx}, req_c);
    else
        selection.reason(n) = sprintf('%s selected, but the required C-rate %.2f exceeds the nominal limit %.2f; review solver data.', ...
            cfg.tech.names{tech_idx}, req_c, cfg.tech.c_rate(tech_idx));
    end
end

selection.selected_nodes = find(selection.tech_index > 0);

end