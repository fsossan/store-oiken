function md_of_lookup_table(varargin)
% Function input is the lookup table
% function saves the md file of the lookup table


if nargin==0
    error('Lookup table input missing!!')
end

T = varargin{1}; % Extract the lookup table from input
docs_dir = fullfile(pwd,'sanity-check-website/docs');
lookup_table_file = fullfile(docs_dir,'lookup_table_avg.md');

fid = fopen(lookup_table_file, 'w');
fprintf(fid, '## Lookup table summary \n\n');
        fprintf(fid, '| Cross-section (mm2) | R (ohm)   | X (ohm) | Ampacity (A)   |\n');
        fprintf(fid, '|---------------------|-----------|---------|----------------|\n');
        for i = 1:height(T)
    fprintf(fid, '| %g | %g | %g | %g |\n', T.cross_section(i), T.R(i), T.X(i), T.ampacity(i));
        end
fclose(fid);
fprintf('\n Saved lookup table md file: %s\n',lookup_table_file);
end