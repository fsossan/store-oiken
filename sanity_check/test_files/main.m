addpath(genpath(pwd))
close all
clear
warning('off','all')
mkdocs_path =  '/Library/Frameworks/Python.framework/Versions/3.13/bin/mkdocs';
mkdocs_dir_name = 'sanity-check-website';
index_path = [pwd '/' mkdocs_dir_name '/docs/' 'index.md'];
yml_path = [pwd '/' mkdocs_dir_name '/' 'mkdocs.yml'];

% load original data data
load('Sierre_dat.mat');
load('Sion_dat.mat');
% lood look up data (for missing line parameters)
lookup = load('lookup_data.mat');

% read Sierre data (from excel to mat)
activate_reading_data = false;
if activate_reading_data
    read_data_sierre();
    read_data_sion();
end


% initialize the mkdocs static website folder
initialize_mkdocs = false;
if initialize_mkdocs
 set_up_static_website(mkdocs_path,mkdocs_dir_name);
 % write mkdocs.yml file
 yml_content(yml_path)
 % write index.md file
 index_content(index_path);
 % write Missing_Data.md
  Missing_Data(['./sanity-check-website/docs/Missing_Data.md']);
end

% line parameter analysis 
activate_line_parameter_analysis = false;
if activate_line_parameter_analysis
line_parameter_analysis(Sion,Sierre);
end
% LV substation analysis
substation_analysis(Sion, Sierre)

% update missing line paramters
update_missing_line_params = false;
if update_missing_line_params
    Sierre_data_modification(lookup.data{:},Sierre)
    Sion_data_modification(lookup.data{:},Sion)
end

% load updated network data
Sierre_v2= load('Sierre_v2.mat');
Sion_v2 = load('Sion_v2.mat');
data = combine_struct_data(Sierre_v2.Sierre,Sion_v2.Sion); % all LV data

% Analyze power mix BEFORE loadflow
activate_power_mix_analysis = false;
if activate_power_mix_analysis
analyze_power_mix_raw_ALL_LV(data);
end


% one-shot loadflow 
Sion_loadflow_activate = false;
Sierre_loadflow_activate = false;

LV_sanitycheck_activate = false;



if Sion_loadflow_activate | Sierre_loadflow_activate | LV_sanitycheck_activate  % empty fig dir for subsequent loadflow output
    figures_folder_warning()
    LV_SanityCheck(data)
end



% if Sierre_loadflow_activate
% Sierre_SanityCheck(Sierre_v2.Sierre)
% end
% 
% if Sion_loadflow_activate
% Sion_SanityCheck(Sion_v2.Sion)
% end

% one-shot loadflow analysis
load('Sierre_oneshot_result.mat')
load('Sion_oneshot_result.mat')
load('all_LV_oneshot_result.mat')

one_shot_lf_analysis_activate = false;
if one_shot_lf_analysis_activate
% analyze_loadflow_results(Sierre_oneshot_lf,Sion_oneshot_lf)
analyze_loadflow_results(all_LV_oneshot_lf)
end

%% Temporal loadflow anaysis (based on SFOE scenario)
temporal_lf_activate = false;

if temporal_lf_activate
scenario_name = 'sc1_2040'; % scenario from the electricity framework
sane_networks = "healthy"; % analysis on only healthy network (successfully passed the one-shot lf analysis)

temporal_loadflow_main(data,scenario_name,sane_networks) % SFOE-scenario based temporal loadflow

% Analyze results
fprintf('\nAnalyzing temporal results...\n');
temporal_output_dir = sprintf('output/scenario_%s/temporal_results',string(scenario_name));
stats = analyze_temporal_results(temporal_output_dir, scenario_name);

% Generate reports
fprintf('\nGenerating markdown reports...\n');
generate_temporal_markdown(stats, scenario_name);
end