function bfs_order = plot_topology(from_idx, to_idx, slack_node_idx, demand_index, edge_labels, labelmode, node_labels)
node_labels = string(1:numel(node_labels))'; % testing
   figure('Visible', 'off',  'Position', [100, 100, 1300, 750])

    % Build graph directly from stable internal indices
    G = digraph(from_idx, to_idx);
    p = plot(G, 'Layout', 'layered');
    p.Interpreter = "none";

    nodeCount = numnodes(G);

    % Node labels
    if nargin < 7 || isempty(node_labels)
        node_labels = string(1:nodeCount)';
    else
        node_labels = string(node_labels(:));
    end
    labelnode(p, 1:nodeCount, node_labels);

    % BFS order only for reporting / later use
    if ~isempty(slack_node_idx)
        bfs_order = bfsearch(G, slack_node_idx);
        all_nodes = (1:nodeCount)';
        missing_nodes = setdiff(all_nodes, bfs_order);
        if ~isempty(missing_nodes)
            fprintf('WARNING: %d node(s) unreachable from slack bus - appending to order\n', numel(missing_nodes));
            bfs_order = [bfs_order; missing_nodes];
        end
    else
        bfs_order = (1:nodeCount)';
    end

    hold on

    % Highlight demand nodes (destination nodes of rows with demand)
    red_nodes = unique(to_idx(demand_index == 1));
    if ~isempty(red_nodes)
        highlight(p, red_nodes, 'NodeColor', 'r');
    end

    % Highlight LV edges in green using EDGE INDICES, not (s,t)
    if nargin >= 5 && ~isempty(edge_labels)
        edge_labels = string(edge_labels(:));

        for k = 1:min(numel(edge_labels), numel(from_idx))
            if edge_labels(k) == " "
                edge_id = findedge(G, from_idx(k), to_idx(k));

                % findedge can return 0 if not found
                edge_id = edge_id(edge_id > 0);

                if ~isempty(edge_id)
                    highlight(p, 'Edges', edge_id, 'EdgeColor', 'g');
                end
            end
        end
    end

    % Edge labels
    if labelmode
        % This is okay as long as the graph was built from the same from/to
        labeledge(p, from_idx, to_idx, edge_labels);
    end

    hold off
end