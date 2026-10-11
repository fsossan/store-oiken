function [net, graph_data] = combined_lv_sub(MV_LV_sub, LV_grid, Zb)
%COMBINED_LV_SUB Combine MV-LV substation and LV grid into one row-aligned
%network table with stable numeric node indices.
%
% Output:
%   net.from / net.to      -> stable internal node indices
%   graph_data.node_names  -> original node labels for each internal index
%
% Important:
%   - Branch row order is preserved.
%   - Parallel lines are preserved.
%   - Plotting is separated from computational indexing.

    graph_data = struct();

    %% ---------------------------------------------------------------
    % 1) Preprocess MV/LV substation data and detect slack node
    %% ---------------------------------------------------------------
    [MV_LV_sub, slack_node_name] = transformer_modeling(MV_LV_sub);

    % Remove open switches
    off_switch_idx = find(MV_LV_sub.On_OffState == 0);
    MV_LV_sub(off_switch_idx, :) = [];

    %% ---------------------------------------------------------------
    % 2) Extract original branch endpoints and labels
    %% ---------------------------------------------------------------
    % MV-LV substation part
    from_lv_sub = string(MV_LV_sub.From);
    to_lv_sub   = string(MV_LV_sub.To);
    label_lv_sub = extractBetween(string(MV_LV_sub.Object), 1, 1);
    demand_index_MV = zeros(numel(from_lv_sub), 1);

    % LV grid part
    from_lv = string(LV_grid.From);
    to_lv   = string(LV_grid.To);
    label_lv_grid = repmat(" ", height(LV_grid), 1);
    demand_index_LV = double(LV_grid.PLmax_kW_ > 0 | LV_grid.QLmax_kVar_ > 0 | LV_grid.Pg_kW_ > 0);

    % Combined branch lists (row order preserved)
    from_comb = [from_lv_sub; from_lv];
    to_comb   = [to_lv_sub;   to_lv];
    demand_index_comb = [demand_index_MV; demand_index_LV];
    label_comp = [label_lv_sub; label_lv_grid];

    % Refine transformer/switch labels for edge display
    for r = 1:numel(label_lv_sub)
        if label_comp(r) == "T"
            label_comp(r) = "T" + string(MV_LV_sub.RatedPower_kVA_(r));
        elseif label_comp(r) == "S"
            label_comp(r) = "";
        end
    end

    %% ---------------------------------------------------------------
    % 3) Build one stable node map from original node names
    %% ---------------------------------------------------------------
    [from_idx, to_idx, node_names] = map_nodes_to_indices(from_comb, to_comb);

    % Convert slack node name to internal index
    if ~isempty(slack_node_name)
        slack_node_idx = find(node_names == string(slack_node_name), 1, 'first');
    else
        slack_node_idx = [];
    end

    %% ---------------------------------------------------------------
    % 4) Build row-aligned electrical data
    %% ---------------------------------------------------------------
    Line = [string(MV_LV_sub.Object); string(LV_grid.Line)];
    Length = [0.01 + zeros(height(MV_LV_sub),1); LV_grid.Length_m_];

    R_pu = [
        MV_LV_sub.R_p_u_;
        (LV_grid.R_Ohm_km_ .* LV_grid.Length_m_ / 1e3) ./ Zb
    ];

    X_pu = [
        MV_LV_sub.X_p_u_;
        (LV_grid.X_Ohm_km_ .* LV_grid.Length_m_ / 1e3) ./ Zb
    ];

    MV_amp_rat = MV_ampacity(MV_LV_sub);
    Ampacity = [MV_amp_rat(:); LV_grid.Ampacity_A_];

    P_rat = [zeros(height(MV_LV_sub),1); LV_grid.PLmax_kW_];
    Q_rat = [zeros(height(MV_LV_sub),1); LV_grid.QLmax_kVar_];
    PV_rat = [zeros(height(MV_LV_sub),1); LV_grid.Pg_kW_];

    %% ---------------------------------------------------------------
    % 5) Build computational network table
    %% ---------------------------------------------------------------
    net = table(from_idx, to_idx, Line, Length, R_pu, X_pu, Ampacity, P_rat, Q_rat, PV_rat, ...
        'VariableNames', {'from','to','Line','Length','R_pu','X_pu','Ampacity','P_rat','Q_rat','PV_rat'});

    %% ---------------------------------------------------------------
    % 6) Plot topology only for visualization
    %% ---------------------------------------------------------------
    bfs_order = plot_topology( ...
        from_idx, ...
        to_idx, ...
        slack_node_idx, ...
        demand_index_comb, ...
        label_comp, ...
        true, ...
        node_names ...         % currently show original IDs for verification
    );

    %% ---------------------------------------------------------------
    % 7) Store graph metadata
    %% ---------------------------------------------------------------
    graph_data.from = from_idx;
    graph_data.to = to_idx;
    graph_data.from_comb = from_comb;
    graph_data.to_comb = to_comb;
    graph_data.node_names = node_names;          % internal idx -> original node ID
    graph_data.slack_node_name = slack_node_name;
    graph_data.slack_node_idx = slack_node_idx;
    graph_data.demand_index_comb = demand_index_comb;
    graph_data.label_comp = label_comp;
    graph_data.bfs_order = bfs_order;

    %% ===============================================================
    % Local helper: transformer modeling
    %% ===============================================================
    function [MV_LV_sub_out, slack_node_id] = transformer_modeling(MV_LV_sub_in)
        % Detect primary-side switch branch(es) and infer slack node.
        % Keep original node names here.

        MV_LV_sub_out = MV_LV_sub_in;

        [~, prim_sw_id] = setdiff(MV_LV_sub_out.From, MV_LV_sub_out.To);

        if ~isempty(prim_sw_id) && all(MV_LV_sub_out(prim_sw_id,:).To == MV_LV_sub_out(prim_sw_id(1),:).To)
            slack_node_id = string(MV_LV_sub_out(prim_sw_id(1),:).To);
            MV_LV_sub_out(prim_sw_id,:) = [];   % remove primary-side switches
        else
            slack_node_id = [];
        end
    end

    %% ===============================================================
    % Local helper: MV branch ampacity
    %% ===============================================================
    function MV_amp_rat = MV_ampacity(MV_LV_sub_in)
        label_sub = extractBetween(string(MV_LV_sub_in.Object), 1, 1);
        MV_amp_rat = zeros(height(MV_LV_sub_in),1);

        for rr = 1:height(MV_LV_sub_in)
            if label_sub(rr) == "T"
                MV_amp_rat(rr) = MV_LV_sub_in.RatedPower_kVA_(rr) / ...
                    (sqrt(3) * MV_LV_sub_in.To_Voltage_kV_(rr));
            else
                MV_amp_rat(rr) = 1500;
            end
        end
    end
end