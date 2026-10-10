function grid = get_grid_SFOE(varargin)

% check for input
if nargin == 0
    error('No grid data detected')
else
    data = varargin{1};
    n_idx = varargin{2};
    config = varargin{3};
end

gridFunc = @grid;

%----
% PU values
%----
Sb = config.PU_values.Sb;
Vb = config.PU_values.Vb;
Ib = Sb/Vb;
Zb = Vb^2/Sb;

demand_factor = config.demand_level.demand_factor;
generation_factor = config.demand_level.generation_factor;
jay = sqrt(-1);
V0 = config.PU_values.Vsl;
n_of_phases = config.network_properties.n_of_phases;

sheet_name = data.LV_grid_id;
network_id = string(regexp(sheet_name, '\d+', 'match', 'once'));


% Load network data
[net, graph_data] = combined_lv_sub_SFOE(data.MV_LV_sub{1,n_idx}, data.LV_grid{1,n_idx}, Zb,config);

% Remove duplicate entries
unique_cols = net(:, 1:3); % line_id uniqueness is problematic (:,3)
[~, unique_idx] = unique(unique_cols, 'rows', 'stable');
num_duplicates = size(net, 1) - size(unique_idx, 1);
if num_duplicates > 0
    fprintf('Duplicates detected and removed: %d\n', num_duplicates);
end
net = net(unique_idx, :);

L = table2array(net(:,4:7));
line_id = str2double(regexp(table2array(net(:,3)), '\d+', 'match', 'once'));

% Negligible impedance for switches
L(L(:,2)==0, 2) = 0.00001;
L(L(:,3)==0, 3) = 0.00001;

% Line database
line_db = {};
line_db.ampacity = L(:,4);
amp_limit = line_db.ampacity;
linedata = table2array(net(:,[1 2]));

% Network topology
from = linedata(:,1)';
to = linedata(:,2)';

n_lines = length(linedata(:,1));
n_nodes = max(max(linedata(:,1)), max(linedata(:,2)));

% Build admittance matrices
y_i_ih = zeros(n_nodes, n_nodes);
[y_ih, y_i_ih, y_i] = deal([]);

for k = 1:n_lines
    linedata(k,3) = L(k,2);
    linedata(k,4) = L(k,3);
    linedata(k,5) = 0;

    y_ih(k,1) = 1./(L(k,2) + jay*L(k,3));
    y_i_ih(linedata(k,1), linedata(k,2)) = linedata(k,5)*1i/2;
    y_i_ih(linedata(k,2), linedata(k,1)) = linedata(k,5)*1i/2;
end

for k = 1:n_nodes
    y_i(k) = sum(y_i_ih(k,:));
end

Yp = diag([y_ih.', y_i]);

% Incidence matrix
A = zeros(n_lines + n_nodes, n_nodes);
for k = 1:n_lines
    A(k, linedata(k,1)) = 1;
    A(k, linedata(k,2)) = -1;
end
for k = 1:n_nodes
    A(n_lines+k, k) = 1;
end

Y = A.' * Yp * A;

lines_puimpedance = (L(:,2) + jay*L(:,3));

% Voltage to current transformation
fromto = linedata(:,[1:2]);
VoltageToCurrent_pu = [];
index_to_nphases = @(x) (x-1)*n_of_phases + (1:n_of_phases);

for k = 1:n_lines
    subm = zeros(n_of_phases, n_nodes * n_of_phases);
    subm(:, index_to_nphases(fromto(k, 1))) = eye(n_of_phases) * inv(lines_puimpedance(k));
    subm(:, index_to_nphases(fromto(k, 2))) = -eye(n_of_phases) * inv(lines_puimpedance(k));
    VoltageToCurrent_pu = vertcat(VoltageToCurrent_pu, subm);
end
VoltageToCurrent = VoltageToCurrent_pu * Ib;

% Network type
if n_lines == n_nodes-1
    network_type = 'radial';
else
    network_type = 'mesh';
end

%% CORRECTED LOAD FLOW PREPARATION
% Create demand array for ALL nodes (not just unique destinations)
demand = table2array(net(:,8:12));
nodal_demand_all = zeros(n_nodes, 5);

% Aggregate demand by destination node
% only assign once per unique To-node
[~, ia, ~] = unique(linedata(:,2), 'stable');  % one row per unique To-node
for k = ia'
    to_node = linedata(k, 2);
    nodal_demand_all(to_node, :) = demand(k, :);  % assign, not accumulate
end

% Calculate nodal power for ALL nodes except slack (node 1)
nodal_nominal_power = demand_factor * (nodal_demand_all(2:end, 1)/3 + jay*nodal_demand_all(2:end, 2)/3);
nodal_PV_power = generation_factor * (nodal_demand_all(2:end, 3)/3);
nodal_PV_SFOE = nodal_demand_all(2:end,4)/3; % PV from SFOE allocation
nodal_N_EV = nodal_demand_all(2:end,5);  % EV from SFOE allocation 



%% Run load flow
% [Vk1, I, S] = loadflow_FPIs(Y, V0, Swye_pu, n_of_phases, VoltageToCurrent_pu);
Swye_pu = (-nodal_nominal_power + nodal_PV_power) / (Sb/1000);
[Vk1, I, S,convergance,iter_num] = loadflow_FPIs_convergance(Y, V0, Swye_pu, n_of_phases, VoltageToCurrent_pu);

slacbus_power = S;
V = abs(Vk1);
V = [V0; V];
I = abs(I) * Ib;


% failed loadflow
if anynan(V)
    network_type = "failed loadflow";
end
%%


% Grid data
grid.Y = Y;
grid.basepower = Sb;
grid.basevoltage = Vb;
grid.basecurrent = Ib;
grid.baseimpedance = Zb;
grid.ampacities = amp_limit;
grid.n_of_phases = 1;
grid.nodal_nominal_power = nodal_nominal_power;
grid.nodal_PV_SFOE = nodal_PV_SFOE;
grid.nodal_N_EV  = nodal_N_EV;
grid.nodal_PLmax_kW   = nodal_demand_all(2:end, 1);   % fuse-rated peak per node, 3-phase kW, before demand_factor
grid.nodal_QLmax_kVar = nodal_demand_all(2:end, 2);
grid.line_length_m    = table2array(net(:, 4));       % per line, m (transformer rows carry a nominal 0.01)
grid.voltageToBranchCurrent = VoltageToCurrent;
grid.voltageToBranchCurrent_pu = VoltageToCurrent_pu;
grid.lines_puimpedance = lines_puimpedance;
grid.N1N2Y = horzcat (linedata(:, [1,2]), lines_puimpedance);
% for analysis
grid.I_spatial = I;
grid.V_spatial = V; 
grid.P_max_tot = sum(nodal_nominal_power);
grid.graph_data = graph_data;
grid.net_id   = network_id(n_idx);








end