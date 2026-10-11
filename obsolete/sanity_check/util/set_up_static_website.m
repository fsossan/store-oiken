function set_up_static_website(mkdocs_path,dirname)
system([mkdocs_path ' new ' dirname]);

% initialize a js directory in the mkdocs folder
mkdir(fullfile('./',dirname,'docs','js'))



end