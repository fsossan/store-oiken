function generate_line_parameter_summary(line_data)
% GENERATE_LINE_PARAMETER_SUMMARY  Generates Line_parameter_summary.md for the MkDocs website.
%   Called automatically at the end of line_parameter_analysis after line_data is assembled.
%   Computes missing parameter statistics at both line and network level.
%
%   INPUT:
%     line_data  - MATLAB table produced by line_parameter_analysis, containing:
%                  substation_ID, Length, Resistance, Reactance, ampacity,
%                  section, material, cable_id, cable_type

    % --- Output path ---
    output_path = fullfile(pwd, 'sanity-check-website', 'docs', 'Line_parameter_summary.md');

    % --- Basic counts ---
    n_lines    = height(line_data);
    n_networks = numel(unique(line_data.substation_ID));

    % --- Missing flags (0 or NaN treated as missing) ---
    miss_length  = isnan(line_data.Length)      | (line_data.Length == 0);
    miss_R       = isnan(line_data.Resistance)  | (line_data.Resistance == 0);
    miss_X       = isnan(line_data.Reactance)   | (line_data.Reactance == 0);
    miss_amp     = isnan(line_data.ampacity)    | (line_data.ampacity == 0);
    miss_section = isnan(line_data.section)     | (line_data.section == 0);
    miss_RX      = miss_R | miss_X;

    % --- Combined missing flags ---
    miss_amp_section        = miss_section & miss_amp;
    miss_section_RX         = miss_section & miss_RX;
    miss_amp_RX             = miss_amp & miss_RX;
    miss_section_amp_RX     = miss_section & miss_amp & miss_RX;
    miss_all                = miss_section & miss_amp & miss_RX & miss_length;

    % --- Helper: affected network count ---
    net_count = @(flag) numel(unique(line_data.substation_ID(flag)));

    % --- Helper: percentage ---
    pct_lines = @(n) n / n_lines * 100;
    pct_nets  = @(n) n / n_networks * 100;

    % --- Build rows: {label, n_lines_missing, n_networks_affected} ---
    rows = {
        'Length',                                   sum(miss_length),       net_count(miss_length)
        'Resistance (R)',                            sum(miss_R),            net_count(miss_R)
        'Reactance (X)',                             sum(miss_X),            net_count(miss_X)
        'Ampacity',                                  sum(miss_amp),          net_count(miss_amp)
        'Cross-Section',                             sum(miss_section),      net_count(miss_section)
        'Ampacity & Cross-section'                   sum(miss_amp_section)   net_count(miss_amp_section)
        'Cross-Section & R/X',                       sum(miss_section_RX),   net_count(miss_section_RX)
        'Ampacity & R/X',                            sum(miss_amp_RX),       net_count(miss_amp_RX)
        'Cross-Section, Ampacity & R/X',             sum(miss_section_amp_RX), net_count(miss_section_amp_RX)
        'Cross-Section, Ampacity, R/X & Length',     sum(miss_all),          net_count(miss_all)
    };

    % --- Write file ---
    fid = fopen(output_path, 'w');
    if fid == -1
        error('Could not open Line_parameter_summary.md for writing: %s', output_path);
    end

    % Header
    fprintf(fid, '# Line Parameter Summary\n\n');
    fprintf(fid, 'Auto-generated from the most recent run of the line parameter analysis.\n\n');
    fprintf(fid, '---\n\n');

    % Portfolio overview
    fprintf(fid, '## Portfolio Overview\n\n');
    fprintf(fid, '| Metric | Value |\n');
    fprintf(fid, '|---|---|\n');
    fprintf(fid, '| Total lines (unique, duplicates removed) | %d |\n', n_lines);
    fprintf(fid, '| Total networks | %d |\n\n', n_networks);
    fprintf(fid, '---\n\n');

    % Data completeness
    fprintf(fid, '## Data Completeness\n\n');
    fprintf(fid, 'A line is flagged as missing if its value is 0 or NaN.\n\n');
    fprintf(fid, '| Parameter | Missing Lines | %% of Lines | Affected Networks | %% of Networks |\n');
    fprintf(fid, '|---|---|---|---|---|\n');
    for i = 1:size(rows, 1)
        label    = rows{i, 1};
        n_miss   = rows{i, 2};
        n_nets   = rows{i, 3};
        fprintf(fid, '| %s | %d | %.2f%% | %d | %.2f%% |\n', ...
            label, n_miss, pct_lines(n_miss), n_nets, pct_nets(n_nets));
    end
    fprintf(fid, '\n---\n\n');

    % Further detail
    fprintf(fid, '## Further Detail\n\n');
    fprintf(fid, '| Document | Link |\n');
    fprintf(fid, '|---|---|\n');
    fprintf(fid, '| Full Line Parameter Table | [View Details](Line_parameter_details.html) |\n');
    fprintf(fid, '| Lookup Table | [View Lookup Table](lookup_table_avg.md) |\n');
    fprintf(fid, '| Manufacturer Data | [View Manufacturer Data](lookup_table_input.md) |\n');

    fclose(fid);

    fprintf('Successfully written Line_parameter_summary.md | Lines: %d | Networks: %d\n', ...
        n_lines, n_networks);
end