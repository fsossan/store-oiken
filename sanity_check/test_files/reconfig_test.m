% reconfig test case
clear
close all

addpath(pwd)
network = ["S1","S2","S";
    "S2","TR1","T";
    "TR1","S4","S";
    "TR1","S3","S";
    "S4","L1"," ";
    "L1","L3"," ";
    "S4","L2"," ";
    "L2","L4"," ";
    "S3","L6"," ";
    ];
from = network(:,1);
to = network(:,2);
obj_label = network(:,3);
plot_topology(from,to,[],obj_label,true)

% Original full graph
G = digraph(from, to);

% find the idx of switch edges
S_edge_indices = find(obj_label == "S");

% % Step 1: Build S-only subgraph
% S_from = from(S_edge_indices);
% S_to   = to(S_edge_indices);
% G_S = digraph(S_from, S_to);
updated_network = strings(size(network));
iter = 0;
rm_edges =[];
for edge=1:length(from)
    if ~ismember(edge,rm_edges)
        iter = iter+1;
        if ismember(edge,S_edge_indices)

            parent_nodes = predecessors(G,edge);
            children_nodes = successors(G,edge+1);
            if edge == 1
                updated_network(iter,1) = from(edge);
                for ch_nodes = 1:length(children_nodes)

                    updated_network(iter,2) = to(children_nodes(ch_nodes)-1);
                    updated_network(iter,3:end) = network(children_nodes(ch_nodes)-1,3:end)
                    rm_edges = [rm_edges;children_nodes(ch_nodes)-1];
                end

            else
                updated_network(iter,1) = from(edge);
                for ch_nodes = 1:length(children_nodes)

                    updated_network(iter,2) = to(children_nodes(ch_nodes));
                    updated_network(iter,3:end) = network(children_nodes(ch_nodes)-1,3:end)
                    rm_edges = [rm_edges;children_nodes(ch_nodes)-1];
                end
            end
        else
            updated_network(iter,:) = network(edge,:);
        end
    end

end