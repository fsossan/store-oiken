
function grid = get_OIKEN_grid(MV_LV_sub,LV_grid)

% Load configuration file
config = jsondecode(fileread('general_config.json'));
gridFunc= @grid;
% PU values
%----
Sb = config.PU_values.Sb; %[VA] Sample - Yaser
Vb = config.PU_values.Vb;%/sqrt(3); %[V]
Ib = Sb/Vb; %[A]
Zb = Vb^2/Sb;%Vb^2/(Sb); %[Ohm]
demand_factor=config.demand_level.demand_factor;
jay = sqrt(-1);
V0=config.PU_values.Vsl;
n_of_phases =config.network_properties.n_of_phases;


% load network data
[net,graph_data]=combined_lv_sub(MV_LV_sub,LV_grid,Zb);


% Line data
L=table2array(net(:,4:7));

% removing dublicate entries
unique_cols = net(:, 1:2);
[~, unique_idx] = unique(unique_cols, 'rows','stable');
% Check if duplicates were detected and display a message
num_duplicates = size(net, 1) - size(unique_idx, 1);
if num_duplicates > 0
    fprintf('Duplicates detected and removed %d\n', num_duplicates);
end
net = net(unique_idx, :);

line_id = str2double(regexp(table2array(net(:,3)), '\d+', 'match', 'once'));
% negligible impedance for switches
L(L(:,2)==0,2)=0.00001;%mean(L(:,2)); % Resistance
L(L(:,3)==0,3)=0.00001;%mean(L(:,3));% Inductance

% end


line_db = {};
line_db.ampacity = L(:,4);
amp_limit=line_db.ampacity;
linedata = table2array(net(:,[1 2]));
% mapping the random ID of Oiken network
from=linedata(:,1)';
to=linedata(:,2)';

n_lines = length(linedata(:,1));
n_nodes = max(max(linedata(:,1)),max(linedata(:,2)));
y_i_ih = zeros(n_nodes,n_nodes);
[y_ih,y_i_ih,y_i ]  = deal([]); % initialize
for k = 1:n_lines
    linedata(k,3) = L(k,2);% adding the resistance of the line
    linedata(k,4 )= L(k,3);% adding the reactance of the line
    linedata(k,5) = 0;

    y_ih(k,1) = 1./(L(k,2)+jay*L(k,3));% placing the line data in column vector
    %i dont think the follwoingli do anything
    y_i_ih(linedata(k,1),linedata(k,2)) = linedata(k,5)*1i/2;
    y_i_ih(linedata(k,2),linedata(k,1)) = linedata(k,5)*1i/2;
end


for k = 1:n_nodes
    y_i(k) = sum(y_i_ih(k,:));
end
Yp = diag( [y_ih.',y_i]); %basically forms a matrix in which the first 14 by 14 is diagnoal of Y_ih, and the rest is 15 by 15 of Y_i

A = zeros(n_lines+n_nodes,n_nodes);

for k = 1:n_lines
    A(k,linedata(k,1)) = 1; %placing 1 for the corresponding from node
    A(k,linedata(k,2)) = -1; %placing -1 for the corresponding from node
end
for k = 1:n_nodes
    A(n_lines+k,k) = 1;
end



Y = A.'*Yp*A;

lines_puimpedance = (L(:,2)+jay*L(:,3));

fromto = linedata(:,[1:2]);
VoltageToCurrent_pu = [];
index_to_nphases = @(x) (x-1)*n_of_phases + (1:n_of_phases);

for k = 1:n_lines
    subm = zeros(n_of_phases, n_nodes * n_of_phases);
    subm(:, index_to_nphases(fromto(k, 1))) = eye(n_of_phases) * inv( lines_puimpedance(k) );
    subm(:, index_to_nphases(fromto(k, 2))) = -eye(n_of_phases) * inv( lines_puimpedance(k) );

    VoltageToCurrent_pu = vertcat(VoltageToCurrent_pu, subm);
end
VoltageToCurrent = VoltageToCurrent_pu * Ib;

[~,unique_nodes] = unique(linedata(:,2),'stable');
demand = table2array(net(:,8:12));
nodal_nominal_power=demand_factor*(demand(unique_nodes,1)/3+jay*demand(unique_nodes,2)/3);%
nodal_PV_SFOE = demand_factor*demand(unique_nodes,4)/3; % PV from SFOE allocation
nodal_N_EV = demand(unique_nodes,5);  % EV from SFOE allocation 

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
grid.voltageToBranchCurrent = VoltageToCurrent;
grid.voltageToBranchCurrent_pu = VoltageToCurrent_pu;
grid.lines_puimpedance = lines_puimpedance;
grid.N1N2Y = horzcat (linedata(:, [1,2]), lines_puimpedance);
% grid.topology=[newFrom;newTo];
% grid.network_type = network_type;
% grid.unique_nodes = unique_nodes;
% grid.ID=sheet_name{1,i};
Swye_pu=(demand(unique_nodes,3)*0.7-nodal_nominal_power)/(Sb/1000);%+nodal_PV_power/(Sb/1000);
[ Vk1, I, S ] = loadflow_FPIs(Y, V0, Swye_pu, n_of_phases, VoltageToCurrent_pu);
slacbus_power=(S);
V=abs(Vk1);
%     [Ls,S]=shiftAndPrepend(S,Swye_pu);
V=[V0;V];
P=-demand_factor*demand(:,1);
Q=-demand_factor*demand(:,2);
PV=demand_factor*demand(:,3);
% Combine the data into a matrix
bar_data = [P, Q, PV];

I=abs(I)*Ib;
%slack current
index_conn=find(VoltageToCurrent_pu(:, 1));
I_slack=0;
for n=1:numel(index_conn)
    I_temp(n) = VoltageToCurrent_pu(index_conn(n), :) * [V0;Vk1];
    I_slack=I_slack+I_temp(n);
end
I_slack=abs(I_slack)*Ib;
I=I./amp_limit;

% for analysis
grid.I_spatial = I;
grid.V_spatial = V; 
grid.P_max_tot = sum(nodal_nominal_power);

%I=I*Ib;
% Create a figure with a larger size
% figure;
% % Plot the first subplot (top-left)
% subplot(2, 2, 1)
% %bar(L,V')
% plot(V)
% xlabel('Nodes in the network')
% ylabel('Voltage magnitude in p.u')
% title('Voltage behavior of the network: Vbase 230V')
% gridFunc('on');
% 
% subplot(2, 2, 2)
% plot(I)
% xlabel('Lines in the network')
% ylabel('Observed Current*')
% title('Line Currents in the Network/Line ampacity rating')
% gridFunc('on');
% 
% subplot(2, 2, [3 4])
% filtered_bar_data=any(bar_data(:,1),2); % filter non-zero demand
% if sum(filtered_bar_data)== 1 % solution for one data entry match
%     bar([bar_data(filtered_bar_data,:);zeros(1,3)])
% else
%     bar(bar_data(filtered_bar_data,:))
% end
% xlabel('Nodes in the network')
% ylabel('nodal power demand ')
% legend({'real power:kW','reactive power:kVAR','PV capacity:kW'}, 'Location', 'northeast')
% title('Power demand of the network ')
% gridFunc('on');
% 
% % update x-axis ticks and labels
% non_zero_indices=find(filtered_bar_data);
% xticks(1:length(non_zero_indices));
% xticklabels(string(non_zero_indices+1)); % adding 1 to account for the slackbus
% 



end

