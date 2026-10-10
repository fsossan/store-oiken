function [sOut, tOut] = plot_error_topology(newFrom,newTo,sl_node,demand_index,label,labelmode)
figure('Visible', 'on',  'Position', [100, 100, 1300, 750]);

if ~isempty(sl_node)
    order = bfsearch(digraph(newFrom,newTo),sl_node);
    G = digraph(newFrom, newTo,[],order);
else
    G = digraph(newFrom,newTo);
end
p=plot(G,'Layout','layered');
p.Interpreter = "none";
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

for k = 1:length(label)
    if label(k) == " "
        highlight(p, newFrom(k),newTo(k), 'EdgeColor', 'g'); % Change node color to red
    end
end
if labelmode
    edgeLabels = (label);  % You can customize this label

    % Apply edge labels
    labeledge(p, newFrom, newTo, edgeLabels);
end

hold off; % Release the plot hold
[sOut,tOut] = findedge(G);
fromto = [sOut tOut];
end
