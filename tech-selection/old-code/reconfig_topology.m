function updated_topology = reconfig_topology(From,To,label)
figure('Visible', 'on',  'Position', [100, 100, 1300, 750])

G = digraph(From, To);
p=plot(G,'Layout','layered');
% Get the number of nodes
nodeCount = numnodes(G);
% Label nodes with their respective IDs
labelnode(p, 1:nodeCount, string(1:nodeCount));
%highlight nodes with demand
hold on;
for i = 1:length(demand_index)
    if demand_index(i) == 1
        % Highlight the node in B that corresponds to the i-th position in C
        highlight(p, newTo(i), 'NodeColor', 'r'); % Change node color to red
    end
end

hold off; % Release the plot hold
end