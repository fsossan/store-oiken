function bfs_order = plot_topology_graph(from_idx, to_idx, slack_node_idx, ...
                         demand_index, edge_labels, edge_type, ...
                         show_edge_labels, node_labels)

    G         = graph(from_idx, to_idx);
    nodeCount = numnodes(G);

    if nargin < 8 || isempty(node_labels)
        node_labels = string((1:nodeCount)');
    else
        node_labels = string(node_labels(:));
    end
    edge_labels = string(edge_labels(:));

    % BFS order
    if ~isempty(slack_node_idx)
        bfs_order = bfsearch(G, slack_node_idx);
        missing   = setdiff((1:nodeCount)', bfs_order);
        if ~isempty(missing)
            fprintf('WARNING: %d node(s) unreachable from slack\n', numel(missing));
            bfs_order = [bfs_order; missing];
        end
    else
        bfs_order = (1:nodeCount)';
    end

    % Edge groups via edge_type vector
    primary_trafo_mask   = edge_type == 1;
    secondary_trafo_mask = edge_type == 2;
    lv_mask              = edge_type == 0;

    primary_edges   = findedge(G, from_idx(primary_trafo_mask),   to_idx(primary_trafo_mask));
    secondary_edges = findedge(G, from_idx(secondary_trafo_mask), to_idx(secondary_trafo_mask));
    lv_edges        = findedge(G, from_idx(lv_mask),              to_idx(lv_mask));

    primary_edges   = primary_edges(primary_edges > 0);
    secondary_edges = secondary_edges(secondary_edges > 0);
    lv_edges        = lv_edges(lv_edges > 0);

    % Plot
    figure('Color', 'w');
    p = plot(G, 'Layout', 'layered', 'Direction', 'down', ...
             'Sources', slack_node_idx);

    p.NodeColor    = [0.18 0.35 0.60];
    p.MarkerSize   = 6;
    p.NodeFontSize = 9;
    p.NodeFontName = 'Helvetica';
    p.EdgeColor    = [0.6 0.6 0.6];
    p.LineWidth    = 1.2;
    p.EdgeFontSize = 9;
    p.EdgeFontName = 'Helvetica';

    labelnode(p, 1:nodeCount, node_labels);

    % LV feeders — dark green
    if ~isempty(lv_edges)
        highlight(p, 'Edges', lv_edges, ...
            'EdgeColor', [0.0 0.55 0.25], 'LineWidth', 1.5);
    end

    % Secondary transformers — steel blue, medium
    if ~isempty(secondary_edges)
        highlight(p, 'Edges', secondary_edges, ...
            'EdgeColor', [0.18 0.35 0.60], 'LineWidth', 2.0);
    end

    % Primary transformer — black, thickest
    if ~isempty(primary_edges)
        highlight(p, 'Edges', primary_edges, ...
            'EdgeColor', [0.1 0.1 0.1], 'LineWidth', 3.0);
    end

    % Load/PV nodes — red
    red_nodes = unique(to_idx(demand_index == 1));
    if ~isempty(red_nodes)
        highlight(p, red_nodes, 'NodeColor', [0.85 0.15 0.15], 'MarkerSize', 7);
    end

    % Slack node — black
    if ~isempty(slack_node_idx)
        highlight(p, slack_node_idx, 'NodeColor', [0.1 0.1 0.1], 'MarkerSize', 8);
    end

    % Transformer labels — text annotation at midpoint
    trafo_mask = edge_type >= 1;
    trafo_pos  = find(trafo_mask);
    for k = 1:numel(trafo_pos)
        e    = trafo_pos(k);
        n1   = from_idx(e);
        n2   = to_idx(e);
        xmid = (p.XData(n1) + p.XData(n2)) / 2;
        ymid = (p.YData(n1) + p.YData(n2)) / 2;
        text(xmid + 0.08, ymid, edge_labels(e), ...
            'FontSize', 9, 'FontName', 'Helvetica', ...
            'FontWeight', 'bold', 'Color', [0.1 0.1 0.1], ...
            'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle');
    end

    % Other edge labels
    if show_edge_labels
        display_labels = edge_labels;
        display_labels(trafo_mask) = "";
        labeledge(p, from_idx, to_idx, display_labels);
    end

    axis off
    box  off
end