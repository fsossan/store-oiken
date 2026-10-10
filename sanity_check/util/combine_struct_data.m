function combined = combine_struct_data(varargin)
%COMBINE_REGION_DATA Combine Sierre, Sion, etc. data structures
%
%   combined = combine_region_data(Sierre, Sion)
%   combined = combine_region_data(Sierre, Sion, ...)

if nargin == 0
    error('Must provide at least one struct');
end

% Initialize with first struct's field names
combined = struct();
fields = fieldnames(varargin{1});

for f = 1:length(fields)
    field = fields{f};
    
    % Check what type of data this field contains
    first_value = varargin{1}.(field);
    
    if iscell(first_value)
        % Cell array - horizontal concatenation
        all_cells = cell(1, nargin);
        for i = 1:nargin
            all_cells{i} = varargin{i}.(field);
        end
        combined.(field) = [all_cells{:}];
    else
        % Unknown type - just collect in cell array
        warning('Field %s has unexpected type - storing as cell array', field);
        combined.(field) = cell(1, nargin);
        for i = 1:nargin
            combined.(field){i} = varargin{i}.(field);
        end
    end
end

end