function temporal_figures_folder_warning(varargin)
if nargin == 0
    error('Temporal figure directory path not provided');
end

fig_dir = varargin{1};
res_dir = varargin{2};

try
    answer = questdlg('Are you sure you want to empty the temporal figures and result folders?', ...
                      'Warning', 'Continue', 'Cancel', 'Cancel');
catch
    answer = 'Cancel';
    fprintf('No GUI available — defaulting to Cancel.\n');
end

if strcmp(answer, 'Continue')
   for dir_path = {fig_dir, res_dir}
        if isfolder(dir_path{1})
            rmdir(dir_path{1}, 's');
            mkdir(dir_path{1});
            fprintf('Cleared and recreated: %s\n', dir_path{1});
        else
            mkdir(dir_path{1});
            fprintf('Created: %s\n', dir_path{1});
        end
    end
else
    disp('Operation cancelled.');
end
end