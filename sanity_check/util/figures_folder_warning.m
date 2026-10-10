function figures_folder_warning 


    answer = questdlg('Are you sure you want to empty the figures folder?', ...
                      'Warning', ...
                      'Continue', 'Cancel', 'Cancel');
    if strcmp(answer, 'Continue')
        if isfolder('sanity-check-website/docs/figures')
        rmdir('sanity-check-website/docs/figures','s')
        disp('figures directory deleted!')
        else
        disp('figures directory does NOT exist!')
        end
    else
        disp('Operation cancelled.')
    end
end


