function LV_SanityCheck(varargin)

% check for input
if nargin == 0
    error('No LV data input detected')
else
    data = varargin{:};
end
% figures directory
figure_dir = 'sanity-check-website/docs/figures';
if (~isfolder(figure_dir))
    mkdir(figure_dir);
end

% output directory
out_dir = 'output';
if (~isfolder(out_dir))
    mkdir(out_dir);
end

% Load configuration file
config = jsondecode(fileread('general_config.json'));
gridFunc= @grid;

% load input data
sheet_name = data.LV_grid_id;

% Initialize storage variables
report_data = cell(numel(sheet_name), 10);

all_LV_oneshot_lf = struct([]);
oneshot_count = 1;
data_error_ids = [];
data_undervolt = [];
data_sane_idx = [];

disp("An Oiken Grid consisting of "+numel(sheet_name)+" substations detected")
disp(" -- Sanity check for data in progress ..... --")

for i = 1:numel(sheet_name)
    fprintf('currently running network %d out of %d\n', i, numel(sheet_name))

    % Initialize num_duplicates in case of early error
    num_duplicates = 0;
    convergance = false; % start lf convergance flag

    try
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
        network_id = string(regexp(sheet_name{i}, '\d+', 'match', 'once'));

        % Load network data
        [net, graph_data] = combined_lv_sub_v2(data.MV_LV_sub{1,i}, data.LV_grid{1,i}, Zb,config);


        %  Topology sanity check
        [topology_valid, topology_error] = validate_network_topology(net, network_id);

        if ~topology_valid
            report_data{i, 1} = network_id;
            report_data{i, 2} = NaN;
            report_data{i, 3} = sprintf('%.2f %d', NaN, 0);
            report_data{i, 4} = sprintf('%.2f %d', NaN, 0);
            report_data{i, 5} = sprintf('%d / %d', 0, 0);
            report_data{i, 6} = NaN;
            report_data{i, 7} = NaN;
            report_data{i, 8} = sprintf('%.0f, %.0f', 0, 0);
            report_data{i, 9} = 0;  % num_duplicates not computed yet
            report_data{i, 10} = 'topology error';

            exportgraphics(gcf, fullfile(figure_dir, sprintf('%s_topology.png', network_id)),'Resolution',150);
            close(gcf);  % Close topology plot if already opened
            continue;    % Skip to next network
        end

        % Save topology figure
        exportgraphics(gcf, fullfile(figure_dir, sprintf('%s_topology.png', network_id)),'Resolution',150);
        close(gcf);



        % Remove duplicate entries
        unique_cols = net(:, 1:3);
        [~, unique_idx] = unique(unique_cols, 'rows', 'stable');
        num_duplicates = size(net, 1) - size(unique_idx, 1);
        if num_duplicates > 0
            fprintf('Duplicates detected and removed: %d\n', num_duplicates);
        end
        net = net(unique_idx, :);

        L = table2array(net(:,4:7));
        line_id = str2double(regexp(table2array(net(:,3)), '\d+', 'match', 'once'));

        % Negligible impedance for switches
        L(L(:,2) == 0, 2) = 1e-5;   % Resistance
        L(L(:,3) == 0, 3) = 1e-5;   % Reactance

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

        % -----------------------------
        % Build admittance matrix
        % -----------------------------
        y_i_ih = zeros(n_nodes, n_nodes);
        [y_ih, y_i_ih, y_i] = deal([]);

        for k = 1:n_lines
            linedata(k,3) = L(k,2);   % Resistance
            linedata(k,4) = L(k,3);   % Reactance
            linedata(k,5) = 0;        % Shunt susceptance (currently unused)

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

        % -----------------------------
        % Voltage-to-current transform
        % -----------------------------
        fromto = linedata(:,[1:2]);
        VoltageToCurrent_pu = [];
        index_to_nphases = @(x) (x-1)*n_of_phases + (1:n_of_phases);

        for k = 1:n_lines
            subm = zeros(n_of_phases, n_nodes * n_of_phases);
            y_line = 1 / lines_puimpedance(k);

            subm(:, index_to_nphases(fromto(k,1))) =  y_line * eye(n_of_phases);
            subm(:, index_to_nphases(fromto(k,2))) = -y_line * eye(n_of_phases);

            VoltageToCurrent_pu = vertcat(VoltageToCurrent_pu, subm);
        end
        VoltageToCurrent = VoltageToCurrent_pu * Ib;

        % Network type
        if n_lines == n_nodes-1
            network_type = 'radial';
        else
            network_type = 'mesh';
        end

        % -----------------------------
        % Load flow preparation
        % -----------------------------
        demand = table2array(net(:,8:10));   % [P_rat, Q_rat, PV_rat]
        nodal_demand_all = zeros(n_nodes, 3);

        % Aggregate demand by destination node
        % only assign once per unique To-node
        [~, ia, ~] = unique(linedata(:,2), 'stable');  % one row per unique To-node
        for k = ia'
            to_node = linedata(k, 2);
            nodal_demand_all(to_node, :) = demand(k, :);  % assign, not accumulate
        end

        % Exclude slack node 1
        nodal_nominal_power = demand_factor * ...
            (nodal_demand_all(2:end,1) / 3 + jay * nodal_demand_all(2:end,2) / 3);

        nodal_PV_power = generation_factor * ...
            (nodal_demand_all(2:end,3) / 3);

        Swye_pu = (-nodal_nominal_power + nodal_PV_power) / (Sb / 1000);

        % Run load flow

        [Vk1, I, S,convergance,iter_num] = loadflow_FPIs_convergance(Y, V0, Swye_pu, n_of_phases, VoltageToCurrent_pu);
        %[Vmat, Imat, Smat, conv_mat] = loadflow_matpower(linedata, L, nodal_demand_all, Sb, Vb, V0, demand_factor, generation_factor);

        slacbus_power = S;
        V = abs(Vk1);
        V = [V0; V];
        I = abs(I) * Ib;


        % failed loadflow
        if anynan(V)
            network_type = "failed loadflow";
        end

        % Slack current
        index_conn = find(VoltageToCurrent_pu(:,1));
        I_slack = 0;
        I_temp = zeros(numel(index_conn), 1);

        for n = 1:numel(index_conn)
            I_temp(n) = VoltageToCurrent_pu(index_conn(n), :) *  V;
            I_slack = I_slack + I_temp(n);
        end

        I_slack = abs(I_slack) * Ib;
        % Normalize line currents by ampacity
        I = I ./ amp_limit;

        % -----------------------------
        % Bar chart data
        % -----------------------------
        has_demand = any(nodal_demand_all, 2);
        load_node_ids = find(has_demand);

        P_loads  = -demand_factor    * nodal_demand_all(load_node_ids, 1);
        Q_loads  = -demand_factor    * nodal_demand_all(load_node_ids, 2);
        PV_loads =  generation_factor * nodal_demand_all(load_node_ids, 3);

        % Use stable original node names for verification
        %demand_node_names = graph_data.node_names(load_node_ids);
        demand_node_names = string(load_node_ids);
        bar_data = [P_loads, Q_loads, PV_loads];
        %% PLOTTING
        figure('Visible', 'off', 'Position', [100, 100, 1300, 750]);

        % Voltage plot
        subplot(2, 2, 1)
        plot(V)
        xlabel('Nodes in the network')
        ylabel('Voltage magnitude in p.u')
        title('Voltage behavior of the network: Vbase 230V')
        gridFunc('on');

        % Current plot
        subplot(2, 2, 2)
        plot(I)
        xlabel('Lines in the network')
        ylabel('Observed Current*')
        title('Line Currents in the Network/Line ampacity rating')
        gridFunc('on');

        % Power demand bar chart
        subplot(2,2,[3 4])
        if numel(load_node_ids) == 1
            bar([bar_data; zeros(1,3)])
            xticks([1, 2])
            xticklabels([demand_node_names; ""])
        else
            bar(bar_data)
            xticks(1:length(load_node_ids))
            xticklabels(demand_node_names)
        end

        xlabel('Nodes in the network')
        ylabel('nodal power demand')
        legend({'real power:kW','reactive power:kVAR','PV capacity:kW'}, 'Location', 'northeast')
        title('Power demand of the network')
        gridFunc('on');

        exportgraphics(gcf, fullfile(figure_dir, sprintf('%s_figures.png', network_id)),'Resolution',150);
        close(gcf);

        %% RESULTS ANALYSIS
        [overvoltage_deviation, Vmax_idx] = max(real(abs(Vk1)));
        [undervoltage_deviation, Vmin_idx] = min(real(abs(Vk1)));
        [current_deviation, Imax_idx] = max(I);

        overvoltage_deviation = round(overvoltage_deviation, 3);
        undervoltage_deviation = round(undervoltage_deviation, 3);
        current_deviation = round(current_deviation, 3);

        % Store results
        report_data{i, 1} = network_id;
        report_data{i, 2} = round(overvoltage_deviation, 2);
        report_data{i, 3} = sprintf('%.2f %d', undervoltage_deviation, to(Vmin_idx));
        report_data{i, 4} = sprintf('%.2f %d', current_deviation, line_id(Imax_idx, 1));
        report_data{i, 5} = sprintf('%d / %d', sum(I > 1), numel(I));
        report_data{i, 6} = round(I_slack);
        report_data{i, 7} = round(3 * (abs(slacbus_power) * (Sb) / 1000));
        report_data{i, 8} = sprintf('%.0f, %.0f', round(sum(P_loads) + sum(PV_loads)), round(sum(Q_loads)));
        report_data{i, 9} = num_duplicates;
        report_data{i, 10} = sprintf('%s', network_type);

        % if undervoltage_deviation <= 0.9
        %     data_undervolt = [data_undervolt; network_id];
        % else
        %     data_sane_idx = [data_sane_idx; network_id];
        % end

    catch ME
        fprintf('ERROR in network %s: %s\n', network_id, ME.message);

        report_data{i, 1} = network_id;
        report_data{i, 2} = 0;
        report_data{i, 3} = sprintf('%.2f %d', 0.00, 0);
        report_data{i, 4} = sprintf('%.2f %d', 0.00, 0);
        report_data{i, 5} = sprintf('%d / %d', 0, 0);
        report_data{i, 6} = 0;
        report_data{i, 7} = 0;
        report_data{i, 8} = sprintf('%.0f, %.0f', 0.00, 0.00);
        report_data{i, 9} = num_duplicates;
        report_data{i, 10} = "error miscellaneous";
        % data_error_ids = [data_error_ids; network_id];
        close all;
    end

    % Store one-shot lf result - data
    all_LV_oneshot_lf(oneshot_count).network_id = network_id;
    all_LV_oneshot_lf(oneshot_count).topology  = graph_data;
    all_LV_oneshot_lf(oneshot_count).V = V;
    all_LV_oneshot_lf(oneshot_count).I = I;
    all_LV_oneshot_lf(oneshot_count).S = S;
    all_LV_oneshot_lf(oneshot_count).P_loads = P_loads;
    all_LV_oneshot_lf(oneshot_count).Q_loads = Q_loads;
    all_LV_oneshot_lf(oneshot_count).PV = PV_loads;
    all_LV_oneshot_lf(oneshot_count).config = config;
    all_LV_oneshot_lf(oneshot_count).grid_data = net;
    all_LV_oneshot_lf(oneshot_count).convergance = convergance;
    all_LV_oneshot_lf(oneshot_count).conv_iter_num = iter_num;

    oneshot_count = oneshot_count + 1;

end

%% GENERATE REPORT
report_table = cell2table(report_data, 'VariableNames', {...
    'SubstationID', ...
    'Highest recorded Voltage (p.u) ', ...
    'Lowest recorded Voltage (p.u) / NodeID', ...
    'Maximum observed Current* / LineID', ...
    'Number of overloaded lines / Total number of lines', ...
    'Slack bus current (A) ', ...
    'Slackbus Power (kVA)', ...
    'Nominal demand (kW,KVAR)', ...
    'Data verification - Duplicates', ...
    'Network type'});

filename = 'output/all_LV_oneshot_result.mat';
save(filename,'all_LV_oneshot_lf');

% filename = 'output/data_error_ids.mat';
% save(filename, 'data_error_ids');
%
% filename2 = 'output/data_undervoltage.mat';
% save(filename2, 'data_undervolt');
%
% filename3 = 'output/data_sane_networks.mat';
% save(filename3, 'data_sane_idx');

disp(" -- Sanity Check SUCCESS --")
generateMarkdown_all_LV(report_table);
disp(" -- Markdown file SUCCESS --")
end