function mdoflineparamter(lookup_table)
output_file = './sanity-check-website/docs/Line_parameter_analysis.md';  % Path to save the markdown file

% Open file for writing
fid = fopen(output_file, 'w');
filters = [
    "**Filter:**"
    "<select id=""dataFilter"" onchange=""applyFilter()"">"
    "  <option value="""">Select Filter</option>"
    "  <option value=""missingAmpacity"">Show Missing Ampacity (0 or NaN)</option>"
    "  <option value=""missingImpedance"">Show Missing Impedance (Resistance or Reactance = 0 or NaN)</option>"
    "  <option value=""missingLength"">Show Missing Length (0 or NaN)</option>"
    "  <option value=""missingCrossSection"">Show Missing Cross-Section (0 or NaN)</option>"
    "  <option value=""missingCrossSectionAmpacity"">Show Missing Cross-Section & Ampacity</option>"
    "  <option value=""missingCrossSectionAmpacityImpedance"">"
    "    Show Missing Cross-Section, Ampacity & Impedance"
    "  </option>"
    "</select>"
    "<p id=""filterCount""></p>"
];
for i = 1:height(filters)
    fprintf(fid, '%s\n', filters(i));
end
fprintf(fid, '\n');  % Add a blank line before the table

fprintf(fid, '**Total lines (rows): %d**\n\n', height(lookup_table));
% Write the table header
fprintf(fid, '| station Id         | length(m)           |    resistance (ohm)   | reactance (ohm)      |ampacity (A)     |    cross_section (mm2) | material        |cable_id          |cable type          |\n');
fprintf(fid, '|  ------------------|  ------------------ | ------------------     | ------------------    |------------------ |------------------    |---------------|------------------|--------------------|\n');


% Loop through each row in the table and write the data
for i = 1:height(lookup_table)
    % Access the table values and convert to string where necessary
    station_id = num2str(lookup_table.substation_ID(i));
    length = num2str(lookup_table.Length(i));
    resistance = num2str(lookup_table.Resistance(i));
    reactance = num2str(lookup_table.Reactance(i));
    ampacity = num2str(lookup_table.ampacity(i));
    section = num2str(lookup_table.section(i));
    
    material = lookup_table.material{i};  % Material is already a string (cell)
    
    cable_id = num2str(lookup_table.cable_id(i));
    cable_type =  string(lookup_table.cable_type(i));
    

    % Write the row to the markdown file
    fprintf(fid, '| %s                 | %s                 | %s                 | %s                 |%s                 | %s         |%s                 | %s                 |%s                 |\n', ...
        station_id,length,resistance,reactance,ampacity,section,material,cable_id,cable_type);
end

% Close the file
fclose(fid);
disp('Line parameter analysis md file success')
end
