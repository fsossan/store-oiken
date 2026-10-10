addpath(genpath(pwd))
close all
clear
warning('off','all')

%% ========================================================================
%  USER SETTINGS — edit only this section
% =========================================================================

% --- Raw data ingestion (only needed when OIKEN provides updated Excel data) ---
settings.read_raw_data              = false;  % Stage 1: read Excel -> .mat (Sierre & Sion)
settings.line_params_analysis       = false;  % Stage 2a: diagnostic — inspect line/substation parameters
settings.transformer_param_analysis = false;  % Stage 2b: transformer parameter analysis
settings.patch_grid_data            = false;   % Stage 3: Patch grid data
% settings.update_line_params         = false;  % Stage 3: patch missing line parameters via lookup table


% --- Analysis pipeline ---
settings.power_mix_analysis        = false;  % Stage 4: pre-loadflow DER penetration analysis
settings.oneshot_loadflow          = false;  % Stage 5: one-shot load flow (sanity check)
settings.oneshot_lf_analysis       = false;  % Stage 6: analyze one-shot load flow results
settings.temporal_loadflow         = true;  % Stage 7a: temporal load flow (SFOE scenario-based)


% --- Temporal loadflow options (only used if temporal_loadflow = true) ---
settings.scenario                  = 'sc1_2040';  % SFOE scenario: 'sc1_2030' | 'sc1_2040'
settings.networks                  = 'healthy';   % 'healthy' (passed one-shot) | 'all'

% --- MkDocs index.md file
settings.update_index              = true;      % update index.md file always set true to load changes in config file

% =========================================================================
%  END OF USER SETTINGS — do not edit below this line
% =========================================================================
%% Update Index.md file
if settings.update_index
    index_content(settings.scenario);
end
%% Stage 1 — Raw data ingestion (Excel -> .mat)
% Produces: Sierre_dat.mat, Sion_dat.mat
if settings.read_raw_data
    read_data_sierre();
    read_data_sion();
end

% Load raw data (required for stages 2 and 3)
load('Sierre_dat.mat');
load('Sion_dat.mat');

lookup    = load('lookup_data.mat');
data      = combine_struct_data(Sierre, Sion);

%% Stage 2 — Line parameter diagnostics
% Uses: Sierre_dat, Sion_dat
if settings.line_params_analysis
    line_parameter_analysis(Sion, Sierre);
    substation_analysis(Sion, Sierre);
end

if settings.transformer_param_analysis
    T = load('output/transformer_data.mat').transformer_data;
    transformer_parameter_analysis(T);   % validates, imputes, saves fill table + md

end

%% Stage 3 — Patch missing line parameters
% Uses: data (combined Sierre and Sion) and lookup table
% Produces: data_v2.mat % line parameter estimations

if settings.patch_grid_data
    fill_table = load('output/transformer_fill_table.mat').transformer_fill_table;
    patch_grid_data(lookup.data{:}, fill_table, data);
end

% if settings.update_line_params
%     line_param_modification(lookup.data{:},data)
%     Sierre_data_modification(lookup.data{:}, Sierre);
%     Sion_data_modification(lookup.data{:}, Sion);
%     md_of_lookup_table(lookup.data{:});
% end

% load data_v2.mat for stage 4,5,6 and 7
data_v2 = load('data_v2.mat').data;


%% Stage 4 — Power mix analysis (pre-loadflow)
% Uses: data
if settings.power_mix_analysis
    analyze_power_mix_raw_ALL_LV(data_v2);
end

%% Stage 5 — One-shot load flow (sanity check)
% Uses: data
% Produces: Sierre_oneshot_result.mat, Sion_oneshot_result.mat, all_LV_oneshot_result.mat
if settings.oneshot_loadflow
    figures_folder_warning();
    LV_SanityCheck(data_v2);
end

% Load one-shot results (required for stages 6 and 7)

load('all_LV_oneshot_result.mat')

%% Stage 6 — One-shot load flow analysis
% Uses: all_LV_oneshot_lf
if settings.oneshot_lf_analysis
    analyze_loadflow_results(all_LV_oneshot_lf);
end

%% Stage 7 — Temporal load flow (SFOE scenario-based)
% Uses: data, settings.scenario, settings.networks
if settings.temporal_loadflow
    temporal_loadflow_main(data_v2, settings.scenario, settings.networks);

    fprintf('\nAnalyzing temporal results...\n');
    temporal_output_dir = sprintf('output/scenario_%s/temporal_results', settings.scenario);
    stats = analyze_temporal_results(temporal_output_dir, settings.scenario);

    fprintf('\nGenerating markdown reports...\n');
    generate_temporal_markdown(stats, settings.scenario);
end