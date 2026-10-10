function grids=getOIKEN_Grid_Sc1 (workbook)



[~,sheet_name]=xlsfinfo(workbook);

for k=1:numel(sheet_name)
  data{k}=readtable(workbook,'sheet',sheet_name{k});
  clc % clear annoyiing warning till solution 
end
disp("An Oiken Grid consisting of "+numel(sheet_name)+" substations detected")
grids=cell(1,numel(sheet_name));
disp(" -- constructing the admittance matrix --")
for i=1:numel(sheet_name)
net=data{1,i};
net=table2array(net(:,1:10));
% P=net(:,8);
% %
% save('P.mat','P')
% removing dublicate entries
unique_cols = net(:, 1:2);
[~, unique_idx] = unique(unique_cols, 'rows','stable');
net = net(unique_idx, :);
% [Sc1 ,Sc2, Sc3 ]=PV_projections(net);
EVs=EV_projections(net);
PV=PV_projections_Sc1(net);

%net(:,10);
%%% Determine the 1-ph impedance matrix of the OIKEN network

%----
% PU values
%----
Sb = 100e3; %[VA] Sample - Yaser
Vb = 230;%/sqrt(3); %[V]
Ib = Sb/Vb; %[A]
Zb = Vb^2/Sb;%Vb^2/(Sb); %[Ohm]

jay = sqrt(-1);
n_of_phases = 1; 
L=(net(:,4:7));
%set empty line data to average value 
L(L(:,2)==0,2)=0.00001;%mean(L(:,2)); % Resistance
L(L(:,3)==0,3)=0.00001;%mean(L(:,3));% Inductance
L(isnan(L(:,4))==1,4)=1; % Ampacity
if any(L(:,1)==0)
    L(L(:,1)==0, 1) = 0.00001;
end
% L( ,4)=mean(L(:,4)>=1&& isnan(L(:,4))~=1); 


% from ohm/km, to ohm
L(:,2)=L(:,2).*(L(:,1)/1000);
L(:,3)=L(:,3).*(L(:,1)/1000);

% p.u. conversion
L(:,2)=L(:,2)./Zb;
L(:,3)=L(:,3)./Zb;

line_db = {};
line_db.ampacity = L(:,4);
amp_limit=line_db.ampacity;
linedata = net(:,[1 2]);
% mapping the random ID of Oiken network
from=linedata(:,1)';
to=linedata(:,2)';
[newFrom,newTo]=mapId(from,to);
linedata=[newFrom' newTo'];
n_lines = length(linedata(:,1));
n_nodes = max(max(linedata(:,1)),max(linedata(:,2)));
y_i_ih = zeros(n_nodes,n_nodes);

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



%nodal_nominal_power_pu=nodal_nominal_power/(Sb;
% Power PV 
% Sc1=nodal_nominal_power*0.3323;
% nodal_PV_power=Sc3;
% nodal_PV_power=0.7*net(:,10)/3;
nodal_PV_power=PV;
%nodal_PV_power_pu=nodal_PV_power/Sb;
% Power Demand 
nodal_nominal_power=0.3*(net(:,8)/3+jay*net(:,9)/3)+(10/1e3); %adding 1 watt to avoid zero currents
nodal_EV_demand=EVs/3;
% nodal_nominal_power=nodal_nominal_power;%+(nodal_PV_power);
%% Organize output

grid.Y = Y;
grid.basepower = Sb;
grid.basevoltage = Vb;
grid.basecurrent = Ib;
grid.baseimpedance = Zb;
grid.ampacities = amp_limit;
grid.n_of_phases = 1;
grid.nodal_nominal_power = nodal_nominal_power;
% grid.nodal_nominal_pf = nodal_nominal_pf;
grid.nodal_PV_power = nodal_PV_power;
grid.nodal_EV_power=nodal_EV_demand;
grid.voltageToBranchCurrent = VoltageToCurrent;
grid.voltageToBranchCurrent_pu = VoltageToCurrent_pu;
grid.lines_puimpedance = lines_puimpedance;
grid.N1N2Y = horzcat (linedata(:, [1,2]), lines_puimpedance);
grid.topology=[newFrom;newTo];
grid.ID=sheet_name{1,i};
%% Spatial load flow analysis
% nodal_PV_power=0;
Swye_pu=(-nodal_nominal_power-nodal_EV_demand+nodal_PV_power)/(Sb/1000);%+nodal_PV_power/(Sb/1000);
V0=1;
n_phases=1;
[ Vk1, I, S ] = loadflow_FPIs(Y, V0, Swye_pu, n_phases, VoltageToCurrent_pu);
 V=abs(Vk1);
[Ls,S]=shiftAndPrepend(S,Swye_pu);
[L,V]=shiftAndPrepend(V0,V);
P=real(S)*(Sb/1000);
Q=imag(S)*(Sb/1000);
I=abs(I)*Ib;
I=I./amp_limit;
%I=I*Ib;
% Create a figure with a larger size
figure('Position', [100, 100, 1000, 600]);

% Plot the first subplot (top-left)
subplot(2, 2, 1)
%bar(L,V')
plot(V)
xlabel('Nodes in the network')
ylabel('Voltage magnitude in p.u')
title('Voltage behavior of the network: Vbase 230V')
%xticks(L)
% Plot the second subplot (top-right)
subplot(2, 2, 2)
%bar(I')
plot(I)
xlabel('Lines in the network')
ylabel('Current Utilization (Normalized by Ampacity)')
title('Line Current Utilization in the Network')
%xticks(L)
% Plot the third subplot (center bottom)
subplot(2, 2, [3 4])
bar(Ls,[P Q])
xlabel('Nodes in the network')
ylabel('nodal power demand ')
legend('real power:kW','reactive power:kVAR')
title('Power demand of the network ')
%%
grids{i}=grid;
plot_topology(newFrom,newTo);
clearvars -except grids n_networks demand gms gm OUT linear_modelss data sheet_name
end
% save(grids,'grids.mat')
disp(" -- admittance matrix SUCCESS --")
end
function plot_topology(newFrom,newTo)
G = digraph(newFrom, newTo);
figure;
p=plot(G,'Layout','layered');
 % Get the number of nodes
 nodeCount = numnodes(G);

    % Label nodes with their respective IDs
    labelnode(p, 1:nodeCount, string(1:nodeCount));
end
function P_new = PV_projections_Sc1(net)
    P = 0.3 * net(:, 8); % 0.3 coincidence factor OIKEN
    PV_installed = 0.7 * net(:, 10);

    % Calculate 56% of the sum of P minus installed PV capacity
    fifty_six_percent_sum = 0.33 * (sum(P / 3)) - sum(PV_installed / 3);

    % Identify the indices of non-zero elements in P
    non_zero_indices = find(P);
    
    % Identify the indices where PV_installed is zero
    zero_pv_indices = find(PV_installed == 0);

    % Combine non-zero P indices and zero PV indices
    combined_indices = intersect(non_zero_indices, zero_pv_indices);

    % Number of combined elements
    num_combined = length(combined_indices);

    % Generate random proportions that sum to 1 for the combined elements
    random_proportions = rand(num_combined, 1);
    random_proportions = random_proportions / sum(random_proportions);

    % Scale these proportions to the 56% value
    random_values = fifty_six_percent_sum * random_proportions;

    % Initialize P_new as a zero vector of the same length as P
    P_new = zeros(size(P));

    % Distribute the random values to the combined positions in P_new
    P_new(combined_indices) = random_values;

    % Identify where PV is installed
    pv_indices = find(PV_installed);

    % Keep the installed capacity
    P_new(pv_indices) = PV_installed(pv_indices) / 3;
end
function EVs=EV_projections(net)
% nodes with nominal demand
% load("P.mat")
P=net(:,8);
% Type 2 Mennekes connector
Ev_charger=11; % kw

% EVs for the network
OIKEN_load_nodes=41590;
Sc1_EVs=10417;
network_load_nodes=numel(find(P));
number_of_EVs=round((Sc1_EVs*network_load_nodes)/OIKEN_load_nodes); 

%EVs vector
EVs=zeros(size(P));
% Identify the indices of non-zero elements in P
non_zero_indices = find(P);
% Number of non-zero elements in P
num_non_zero = length(non_zero_indices);
% Check if there are enough non-zero elements to select the required number of EVs
if number_of_EVs > num_non_zero
    error('The number of EVs to assign exceeds the number of non-zero demand nodes.');
end

% Randomly select nodes with EVs from the non-zero indices
selected_indices = non_zero_indices(randperm(num_non_zero, number_of_EVs));

% Assign the EV charger to the selected nodes with nominal demand
EVs(selected_indices) = Ev_charger;

end
