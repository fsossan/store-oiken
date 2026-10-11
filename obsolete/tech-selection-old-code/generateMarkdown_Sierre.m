function generateMarkdown_Sierre(report_table)
output_file = 'sanity-check-website/docs/Sierre_networks.md';  % Path to save the markdown file


% Open file for writing
fid = fopen(output_file, 'w');
if fid == -1
    error('Cannot open file: %s', output_file);
end
% Write the main header for the markdown file
fprintf(fid, '# Substations Analysis\n\n');

%  Write the HTML and JavaScript Code Using fprintf
fprintf(fid, '**Search by Substation ID:**  \n');
fprintf(fid, '<input type="text" id="searchInput" placeholder="Search for ID..">  \n');
fprintf(fid, '<button onclick="searchTable()">Search</button>\n\n');

fprintf(fid, '**Filter by Voltage (< 0.95):**  \n');
fprintf(fid, '<input type="number" id="voltageFilter" placeholder="Enter max voltage">  \n');
fprintf(fid, '<button onclick="filterByVoltage()">Filter</button>\n');
fprintf(fid, '<p id="voltageCount">Total Networks fitting criteria: 0</p>\n\n');

fprintf(fid, '**Filter by Network Type ("mesh", "radial", "error"):**  \n');
fprintf(fid, '<input type="text" id="networkTypeFilter" placeholder="Enter network type">  \n');
fprintf(fid, '<button onclick="filterByNetworkType()">Filter</button>  \n');
fprintf(fid, '<p id="networkTypeCount">Total Networks matching type: 0</p>\n\n');

% Write the Markdown Table Header
fprintf(fid, '| Substation ID | Highest Voltage (p.u) | Lowest Voltage (p.u) / Node ID | Max Current* / Line ID | Overloaded Lines / Total Lines | Slack Bus Current (A) | Slackbus Power (kVA) | Nominal Demand (kW, kVAR) | Data Verification - Duplicates | Network Type | Load flow Figures | Network Topology |\n');
fprintf(fid, '| -------------- | --------------------- | ------------------------------ | ---------------------- | ------------------------------ | ---------------------- | --------------------- | -------------------------- | -------------------------------- | --------------- | --------------- | --------------- |\n');

% Loop through each row in the table and write the data
% Loop through each row in the table and write the data
% Loop through each row in the table and write the data
for i = 1:height(report_table)
    substation_id = report_table.SubstationID(i);
    substation_fig_link = sprintf('[Load flow Figures](figures/%s_figures.png)', substation_id);
    topology_fig_link = sprintf('[Network Topology](figures/%s_topology.png)', substation_id);

    fprintf(fid, '| %d | %.2f | %s | %s | %s | %.0f | %.0f | %s | %d | %s | %s | %s |\n', ...
        double(substation_id), report_table{i, 2}, report_table{i, 3}{1}, ...
        report_table{i, 4}{1}, report_table{i, 5}{1}, ...
        report_table{i, 6}, report_table{i, 7}, ...
        report_table{i, 8}{1}, report_table{i, 9}, report_table{i, 10}{1}, ...
        substation_fig_link, topology_fig_link);
end


fclose(fid);
end
