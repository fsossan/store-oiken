
function Sion_SanityCheck(Sion)


% Disable figure visibility
% set(0, 'DefaultFigureVisible', 'off');

% figures directory

figure_dir = 'sanity-check-website/docs/figures';  % Directory to save figures
if (~exist(figure_dir,'dir'))
    mkdir(figure_dir);
end
%delete([figure_dir '/*'])

% Load configuration file
config = jsondecode(fileread('general_config.json'));

gridFunc = @grid;

% load input data
% load("Sion_v2.mat")
sheet_name = Sion.LV_grid_id;
data=Sion.LV_grid;
% Initialize storage variables
report_data = cell(numel(sheet_name), 10);

Sion_error_ids = [];
Sion_undervolt = [];
disp("An Oiken Grid consisting of "+numel(sheet_name)+" substations detected")
% grids=cell(1,numel(sheet_name));
disp(" -- Sanity check for Sion in progress ..... --")
for i=1:numel(sheet_name)
    fprintf('currently running network %d out of %d\n',i,numel(sheet_name))
    %%% Determine the 1-ph impedance matrix of the OIKEN network
    try
        %----
        % PU values
        %----
        Sb = config.PU_values.Sb; %[VA] Sample - Yaser
        Vb = config.PU_values.Vb;%/sqrt(3); %[V]
        Ib = Sb/Vb; %[A]
        Zb = Vb^2/Sb;%Vb^2/(Sb); %[Ohm]
        demand_factor=config.demand_level.demand_factor;
        generation_factor=config.demand_level.generation_factor;
        jay = sqrt(-1);
        V0=config.PU_values.Vsl;
        n_of_phases =config.network_properties.n_of_phases;
         network_id = string(regexp(sheet_name{i}, '\d+', 'match', 'once'));
        

        % load network data
        [net,graph_data]=combined_lv_sub(Sion.MV_LV_sub{1,i},Sion.LV_grid{1,i},Zb);

        % save topology figure
        saveas(gcf, fullfile(figure_dir, sprintf('%s_topology.png', (network_id)))); % Save at 300 dpi
        close(gcf);

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

        if n_lines == n_nodes-1
            network_type = 'radial';
            % disp('Radial network')
        else
            network_type = 'mesh';
            % disp('Meshed network')
        end
        [~,unique_nodes] = unique(linedata(:,2),'stable');
        demand = table2array(net(:,8:10));
        nodal_nominal_power=demand_factor*(demand(unique_nodes,1)/3+jay*demand(unique_nodes,2)/3);%
        nodal_PV_power=generation_factor*(demand(unique_nodes,3)/3);%;

        Swye_pu=(-nodal_nominal_power+nodal_PV_power)/(Sb/1000);%+nodal_PV_power/(Sb/1000);
        [ Vk1, I, S ] = loadflow_FPIs(Y, V0, Swye_pu, n_of_phases, VoltageToCurrent_pu);
        slacbus_power=(S);
        V=abs(Vk1);
        %     [Ls,S]=shiftAndPrepend(S,Swye_pu);
        [L,V]=shiftAndPrepend(V0,V);
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
        % Extract numeric ID using regexp and str2double
       
        %I=I*Ib;
        % Create a figure with a larger size
        figure('Visible', 'off',  'Position', [100, 100, 1300, 750]);
        % Create and save figures

        % Plot the first subplot (top-left)
        subplot(2, 2, 1)
        %bar(L,V')
        plot(V)
        xlabel('Nodes in the network')
        ylabel('Voltage magnitude in p.u')
        title('Voltage behavior of the network: Vbase 230V')
        gridFunc('on');
        %     saveas(gcf, fullfile(figure_dir, sprintf('%s_voltage.png', sheet_name{i})));
        %     close(gcf);
        %     %xticks(L)
        %     % Plot the second subplot (top-right)
        %
        %     figure('Position', [100, 100, 1000, 600]);
        subplot(2, 2, 2)
        %bar(I')
        plot(I)
        xlabel('Lines in the network')
        ylabel('Observed Current*')
        title('Line Currents in the Network/Line ampacity rating')
        gridFunc('on');
        %     saveas(gcf, fullfile(figure_dir, sprintf('%s_current.png', sheet_name{i})));
        %     close(gcf);
        %xticks(L)
        % Plot the third subplot (center bottom)
        subplot(2, 2, [3 4])
        %     figure('Position', [100, 100, 1000, 600]);
        filtered_bar_data=any(bar_data(:,1),2); % filter non-zero demand
        if sum(filtered_bar_data)== 1 % solution for one data entry match
            bar([bar_data(filtered_bar_data,:);zeros(1,3)])
        else
            bar(bar_data(filtered_bar_data,:))
        end
        xlabel('Nodes in the network')
        ylabel('nodal power demand ')
        legend({'real power:kW','reactive power:kVAR','PV capacity:kW'}, 'Location', 'northeast')
        title('Power demand of the network ')
        gridFunc('on');

        % update x-axis ticks and labels
        non_zero_indices=find(filtered_bar_data);
        xticks(1:length(non_zero_indices));
        xticklabels(string(non_zero_indices+1)); % adding 1 to account for the slackbus
        saveas(gcf, fullfile(figure_dir, sprintf('%s_figures.png', (network_id))));
        close(gcf);

        [overvoltage_deviation,Vmax_idx] = max(real(abs(Vk1)) ); % Assuming rated voltage is 1 p.u.
        [undervoltage_deviation,Vmin_idx] = min(real(abs(Vk1))); % Assuming rated voltage is 1 p.u.
        [current_deviation, Imax_idx]= max(I); % Deviations above normalized value of 1
        overvoltage_deviation=round(overvoltage_deviation,3);
        undervoltage_deviation=round(undervoltage_deviation,3);
        current_deviation=round(current_deviation,3);

        % Store results in the report data array
        report_data{i, 1} = network_id; % Substation ID
        report_data{i, 2} = round(overvoltage_deviation,2); % Max overvoltage deviation
        report_data{i, 3} = sprintf('%.2f %d',undervoltage_deviation,to(Vmin_idx)); % Max undervoltage deviation
        report_data{i, 4} = sprintf('%.2f %d',current_deviation,line_id(Imax_idx,1)); % Max current deviation above 1
        report_data{i, 5} = sprintf('%d / %d', sum(I > 1), numel(I)); % Overloaded lines / Total lines

        report_data{i, 6} = round(I_slack);
        report_data{i, 7} = round(3*(abs(slacbus_power)*(Sb)/1000));
        report_data{i, 8} = sprintf('%.0f, %.0f',round(sum(P)+sum(PV)),round(sum(Q)));
        report_data{i,9} = num_duplicates;
        report_data{i,10} = sprintf('%s',network_type);
        % verify current on the slack bus
        slack_ampere=(abs(slacbus_power)*(Sb))/Vb;
        %     fprintf('calc S_ampere %f vs loaflow S_ampere %f',slack_ampere,I_slack)
        %     fprintf('\n')
        %     fprintf('Total network demand %f vs S_Power %f',3*sum(abs(nodal_nominal_power)),3*(abs(slacbus_power)*(Sb)/1000))
        %     fprintf('\n')
        %     %     fprintf('voltageToCurrent %f',abs(VoltageToCurrent(1,1)))
        %     fprintf('\n')
        if undervoltage_deviation <= 0.9
            Sion_undervolt = [Sion_undervolt;network_id];
        end 
    catch ME
    %
    
    %   % Store results in the report data array
    % 
        report_data{i, 1} = network_id; % Substation ID
        report_data{i, 2} = round(0.00); % Max overvoltage deviation
        report_data{i, 3} = sprintf('%.2f %d',0.00); % Max undervoltage deviation
        report_data{i, 4} = sprintf('%.2f %d',0.00); % Max current deviation above 1
        report_data{i, 5} = sprintf('%d / %d', 0,0); % Overloaded lines / Total lines

        report_data{i, 6} = round(0.00);
        report_data{i, 7} = round(0.00);
        report_data{i, 8} = sprintf('%.0f, %.0f',0.00,0.00);
        report_data{i,9} = num_duplicates;
        report_data{i,10} = sprintf('%s','Error');

        % plot_error_topology(graph_data.from_comb,graph_data.to_comb,[],graph_data.demand_index_comb,graph_data.label_comp,true);
        % saveas(gcf, fullfile(figure_dir, sprintf('%s_topology.png', network_id))); % Save at 300 dpi
        % close(gcf);
        Sion_error_ids = [Sion_error_ids;network_id];
    end
end


report_table = cell2table(report_data, 'VariableNames', {'SubstationID', 'Highest recorded Voltage (p.u) ', 'Lowest recorded Voltage (p.u) / NodeID', 'Maximum observed Current* / LineID', 'Number of overloaded lines / Total number of lines','Slack bus current (A) ', 'Slackbus Power (kVA)', 'Nominal demand (kW,KVAR)','Data verification - Duplicates','Network type'});
filename = 'Sion_error_ids.mat';
save(filename,'Sion_error_ids');
filename2 = 'Sion_undervoltage.mat';
save(filename2,'Sion_undervolt');


% generate markdown file
disp(" -- Sanity Check SUCCESS --")
generateMarkdown_Sion(report_table);
disp(" -- Markdown file SUCCESS --")
end

