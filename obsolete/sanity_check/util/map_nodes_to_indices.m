function [from_idx, to_idx, node_names] = map_nodes_to_indices(from_nodes, to_nodes)
%MAP_NODES_TO_INDICES Create one stable node-name <-> internal-index map.
%
% Inputs:
%   from_nodes, to_nodes : string/cellstr vectors of original node names
%
% Outputs:
%   from_idx             : numeric indices for from_nodes
%   to_idx               : numeric indices for to_nodes
%   node_names           : node_names(k) = original name of internal node k

    from_nodes = string(from_nodes(:));
    to_nodes   = string(to_nodes(:));

    % Unique node list, preserving first appearance
    node_names = unique([from_nodes; to_nodes], 'stable');

    from_idx = zeros(numel(from_nodes),1);
    to_idx   = zeros(numel(to_nodes),1);

    for k = 1:numel(node_names)
        from_idx(from_nodes == node_names(k)) = k;
        to_idx(to_nodes == node_names(k)) = k;
    end
end