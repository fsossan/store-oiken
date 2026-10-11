function setup_OPF_output_dir (varargin)

if nargin == 0

    error('Must provide the OPF result output directory path!!')

else
    dir_path = varargin{:};
end
answer = questdlg('Are you sure you want to empty the OPF result folder?', ...
    'Warning', ...
    'Continue', 'Cancel', 'Cancel');
if strcmp(answer, 'Continue')
    if isfolder(dir_path)
        rmdir(dir_path,'s')
        disp('OPF result folder emptied!')
    else
        mkdir(sprintf('%s/OPF_result/out_dir_solved',dir_path));
        mkdir(sprintf('%s/OPF_result/out_dir_error',dir_path))
        mkdir(sprintf('%s/OPF_result/out_dir_thresh',dir_path));
        mkdir(sprintf('%s/OPF_result/out_dir_subopt',dir_path));
        disp('Output director does not exist, creating a new one SUCCESS')
    end
else
    disp('Operation cancelled.')
end


end