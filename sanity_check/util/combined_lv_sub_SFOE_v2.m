function [net, graph_data] = combined_lv_sub_SFOE_v2(MV_LV_sub, LV_grid, Zb, config)

graph_data = struct();


% ------------------------------------------------------------------
% 1. Identify element types
% ------------------------------------------------------------------
obj_labels = extractBetween(string(MV_LV_sub.Object), 1, 1);
is_trafo   = obj_labels == "T";
is_MV      = min(MV_LV_sub.From_Voltage_kV_, MV_LV_sub.To_Voltage_kV_) >= 1;
is_LV_sw   = ~is_trafo & ~is_MV;

trafo_rows = MV_LV_sub(is_trafo, :);
lv_sw_rows = MV_LV_sub(is_LV_sw, :);

if isempty(trafo_rows)
    error('combined_lv_sub: No transformer found in MV_LV_sub.');
end

% Transformer Z p.u adjusted for Sb from config
Zb_transfo        = (config.PU_values.Vb^2)./((trafo_rows.RatedPower_kVA_*1e3)/3); 
Z_conv_factor     = Zb_transfo ./ Zb;
trafo_rows.R_p_u_ = trafo_rows.R_p_u_ .* Z_conv_factor;
trafo_rows.X_p_u_ = trafo_rows.X_p_u_ .* Z_conv_factor;

% ------------------------------------------------------------------
% 2. Slack = shared MV busbar
% ------------------------------------------------------------------
is_mv_side = trafo_rows.From_Voltage_kV_ >= 1;
TrM_nodes  = strings(height(trafo_rows), 1);
TrM_nodes( is_mv_side) = string(trafo_rows.From( is_mv_side));
TrM_nodes(~is_mv_side) = string(trafo_rows.To(  ~is_mv_side));

mv_sw_rows = MV_LV_sub(is_MV, :);
shared_MV  = "";
for k = 1:height(mv_sw_rows)
    if ismember(string(mv_sw_rows.To(k)), TrM_nodes)
        shared_MV = string(mv_sw_rows.From(k));
        break
    end
end
if shared_MV == ""
    if numel(unique(TrM_nodes)) == 1
        shared_MV = TrM_nodes(1);
    else
        [~, best] = max(trafo_rows.RatedPower_kVA_);
        shared_MV = TrM_nodes(best);
        warning('combined_lv_sub: Could not find shared MV bus — using %s', shared_MV);
    end
end

% ------------------------------------------------------------------
% 3. Build node collapse map — undirected BFS from each TrL_ node
% ------------------------------------------------------------------
is_lv_side = trafo_rows.To_Voltage_kV_ == 0.4;
TrL_nodes  = strings(height(trafo_rows), 1);
TrL_nodes( is_lv_side) = string(trafo_rows.To( is_lv_side));
TrL_nodes(~is_lv_side) = string(trafo_rows.From(~is_lv_side));

% Use closed LV switches only for connectivity
closed_lv = lv_sw_rows(lv_sw_rows.On_OffState == 1, :);
sw_from   = string(closed_lv.From);
sw_to     = string(closed_lv.To);

collapse_map = containers.Map('KeyType','char','ValueType','char');

for t = 1:numel(TrL_nodes)
    trl     = TrL_nodes(t);
    visited = string({trl});
    queue   = string({trl});

    while ~isempty(queue)
        curr  = queue(1);
        queue = queue(2:end);

        % Undirected: find neighbours in both From and To
        nb_forward  = sw_to(sw_from == curr);
        nb_backward = sw_from(sw_to == curr);
        neighbours  = [nb_forward; nb_backward];

        for n = 1:numel(neighbours)
            nb = neighbours(n);
            if ~ismember(nb, visited)
                visited(end+1) = nb;
                queue(end+1)   = nb;
                collapse_map(char(nb)) = char(trl);
            end
        end
    end
end

% ------------------------------------------------------------------
% 4. Apply collapse map to LV_grid From/To
% ------------------------------------------------------------------
lv_from = string(LV_grid.From);
lv_to   = string(LV_grid.To);

for k = 1:numel(lv_from)
    if isKey(collapse_map, char(lv_from(k)))
        lv_from(k) = string(collapse_map(char(lv_from(k))));
    end
end
for k = 1:numel(lv_to)
    if isKey(collapse_map, char(lv_to(k)))
        lv_to(k) = string(collapse_map(char(lv_to(k))));
    end
end

% ------------------------------------------------------------------
% 5. Prune dead subtrees (off-state LV switches)
% ------------------------------------------------------------------
dead_sw       = lv_sw_rows(lv_sw_rows.On_OffState == 0, :);
orig_from     = string(LV_grid.From);
orig_to       = string(LV_grid.To);
dead_lv_nodes = string(dead_sw.To);

changed = true;
while changed
    new_dead = orig_to(ismember(orig_from, dead_lv_nodes));
    new_dead = setdiff(new_dead, dead_lv_nodes);
    changed  = ~isempty(new_dead);
    dead_lv_nodes = [dead_lv_nodes; new_dead];
end

live_mask = ~ismember(orig_from, dead_lv_nodes);
if sum(~live_mask) > 0
    fprintf('combined_lv_sub: Pruned %d dead feeder rows.\n', sum(~live_mask));
end
LV_grid = LV_grid(live_mask, :);
lv_from = lv_from(live_mask);
lv_to   = lv_to(live_mask);

% ------------------------------------------------------------------
% 6. Build net
% ------------------------------------------------------------------
R_lv = (LV_grid.R_Ohm_km_ .* LV_grid.Length_m_ / 1e3) ./ Zb;
X_lv = (LV_grid.X_Ohm_km_ .* LV_grid.Length_m_ / 1e3) ./ Zb;

n_trafo = height(trafo_rows);
n_lv    = height(LV_grid);

lv_volt    = min(trafo_rows.To_Voltage_kV_, trafo_rows.From_Voltage_kV_);
T_ampacity = trafo_rows.RatedPower_kVA_ ./ (sqrt(3) .* lv_volt);

if n_trafo == 1
    slack_node = TrM_nodes(1);

    from_comb = [string(trafo_rows.From); lv_from];
    to_comb   = [string(trafo_rows.To);   lv_to  ];
    Line      = [string(trafo_rows.Object); string(LV_grid.Line)];
    Length    = [0.01;                      LV_grid.Length_m_   ];
    R_pu      = [trafo_rows.R_p_u_;         R_lv                ];
    X_pu      = [trafo_rows.X_p_u_;         X_lv                ];
    Ampacity  = [T_ampacity;                LV_grid.Ampacity_A_ ];
    P_rat     = [0;                         LV_grid.PLmax_kW_   ];
    Q_rat     = [0;                         LV_grid.QLmax_kVar_ ];
    PV_rat    = [0;                         LV_grid.Pg_kW_      ];
    PV_SFOE   = [0;                         LV_grid.PV_kW_      ];
    N_EV      = [0;                         LV_grid.EV_count    ];
    edge_type = [2;                         zeros(n_lv,1)       ];

else
    slack_node = shared_MV;

    TrM_R = zeros(n_trafo, 1);
    TrM_X = ones(n_trafo, 1) * 1e-4;

    from_comb = [repmat(slack_node,n_trafo,1); string(trafo_rows.From); lv_from];
    to_comb   = [TrM_nodes;                    string(trafo_rows.To);   lv_to  ];
    Line      = [repmat("MV_bus",n_trafo,1);   string(trafo_rows.Object); string(LV_grid.Line)];
    Length    = [zeros(n_trafo,1);             repmat(0.01,n_trafo,1);  LV_grid.Length_m_];
    R_pu      = [TrM_R;                        trafo_rows.R_p_u_;       R_lv  ];
    X_pu      = [TrM_X;                        trafo_rows.X_p_u_;       X_lv  ];
    Ampacity  = [T_ampacity;                   T_ampacity;              LV_grid.Ampacity_A_];
    P_rat     = [zeros(n_trafo,1);             zeros(n_trafo,1);        LV_grid.PLmax_kW_  ];
    Q_rat     = [zeros(n_trafo,1);             zeros(n_trafo,1);        LV_grid.QLmax_kVar_];
    PV_rat    = [zeros(n_trafo,1);             zeros(n_trafo,1);        LV_grid.Pg_kW_     ];
    PV_SFOE   = [zeros(n_trafo,1);             zeros(n_trafo,1);        LV_grid.PV_kW_     ];
    N_EV      = [zeros(n_trafo,1);             zeros(n_trafo,1);        LV_grid.EV_count   ];
    edge_type = [ones(n_trafo,1)*3;            ones(n_trafo,1)*2;       zeros(n_lv,1)      ];
end

% ------------------------------------------------------------------
% 7. Map to integer indices
% ------------------------------------------------------------------
[from_idx, to_idx, node_names] = map_nodes_to_indices(from_comb, to_comb);

slack_node_idx = find(node_names == slack_node, 1, 'first');
if isempty(slack_node_idx)
    error('combined_lv_sub: Slack node %s not found.', slack_node);
end

% ------------------------------------------------------------------
% 8. Build net table
% ------------------------------------------------------------------
net = table(from_idx, to_idx, Line, Length, R_pu, X_pu, Ampacity, ...
    P_rat, Q_rat, PV_rat,PV_SFOE,N_EV, ...
    'VariableNames', {'from','to','Line','Length','R_pu','X_pu', ...
    'Ampacity','P_rat','Q_rat','PV_rat','PV_SFOE','N_EV'});

% ------------------------------------------------------------------
% 9. Demand index and edge labels
% ------------------------------------------------------------------
n_edges      = height(net);
demand_index = zeros(n_edges, 1);
lv_mask_net  = edge_type == 0;
demand_index(lv_mask_net) = double( ...
    LV_grid.PLmax_kW_   > 0 | ...
    LV_grid.QLmax_kVar_ > 0 | ...
    LV_grid.Pg_kW_      > 0);

edge_labels   = repmat(" ", n_edges, 1);
trafo_indices = find(edge_type == 2);
for k = 1:n_trafo
    edge_labels(trafo_indices(k)) = "T" + string(trafo_rows.RatedPower_kVA_(k));
end

% ------------------------------------------------------------------
% 10. Node labels
% ------------------------------------------------------------------
if config.visualization.show_original_node_ids
    plot_node_labels = string(node_names);
else
    plot_node_labels = string((1:numel(node_names))');
end

% ------------------------------------------------------------------
% 11. Plot
% ------------------------------------------------------------------
bfs_order = plot_topology_graph(from_idx, to_idx, slack_node_idx, ...
    demand_index, edge_labels, edge_type, ...
    true, plot_node_labels);

% ------------------------------------------------------------------
% 12. graph_data
% ------------------------------------------------------------------
graph_data.from            = from_idx;
graph_data.to              = to_idx;
graph_data.node_names      = node_names;
graph_data.slack_node_name = slack_node;
graph_data.slack_node_idx  = slack_node_idx;
graph_data.demand_index    = demand_index;
graph_data.edge_labels     = edge_labels;
graph_data.edge_type       = edge_type;
graph_data.n_transformers  = n_trafo;
graph_data.T_rat_kVA       = trafo_rows.RatedPower_kVA_;
graph_data.T_ampacity      = T_ampacity;
graph_data.bfs_order       = bfs_order;
graph_data.tr_branch_idx   = find(edge_type == 2);

end