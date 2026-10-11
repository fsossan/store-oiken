function [is_valid, error_type] = validate_network_topology(net, network_id)
%VALIDATE_NETWORK_TOPOLOGY Checks if network has valid topology for loadflow
%
%   Inputs:
%       net        - Network table from combined_lv_sub
%       network_id - String ID for logging purposes
%
%   Outputs:
%       is_valid   - Boolean: true if topology is valid
%       error_type - String: "" if valid, otherwise error description

% Extract connectivity
linedata = table2array(net(:,[1 2]));

% Check for disconnected components
G_check = graph(linedata(:,1), linedata(:,2));
bins = conncomp(G_check);
n_components = max(bins);

% Check if slack node (node 1) exists in network
all_nodes = unique([linedata(:,1); linedata(:,2)]);
slack_in_network = ismember(1, all_nodes);

% check for loop edges (short circuit lines)
self_loops = linedata(:,1) == linedata(:,2);
has_self_loops = any(self_loops);

% Validate
if n_components > 1
    fprintf('Network %s: Topology error - %d disconnected components\n', ...
        network_id, n_components);
    is_valid = false;
    error_type = "topology_error_disconnected";

elseif ~slack_in_network
    fprintf('Network %s: Topology error - slack node (1) not in network\n', ...
        network_id);
    is_valid = false;
    error_type = "topology_error_no_slack";

elseif has_self_loops
    n_self = sum(self_loops);
    fprintf('Network %s: Topology error - %d self-loop line(s) detected\n', ...
        network_id, n_self);
    is_valid = false;
    error_type = "topology_error_self_loop";

else
    % Valid topology
    is_valid = true;
    error_type = "";
end
end