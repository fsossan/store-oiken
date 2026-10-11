function index_content(scenario_name)
% INDEX_CONTENT  Generates the index.md file for the MkDocs static website.
%   Reads network data, configuration, and scenario metadata internally.
%   Requires Sierre_v2.mat, Sion_v2.mat, and general_config.json to exist.
%
%   INPUT:
%     scenario_name  - SFOE scenario tag (e.g. 'sc1_2040'). If omitted,
%                      the temporal load flow section indicates no scenario
%                      has been run.
%
%   EXAMPLE:
%     index_content('sc1_2040')

if nargin < 1
    scenario_name = [];
end

% --- Load configuration ---
config            = jsondecode(fileread('general_config.json'));
demand_factor     = config.demand_level.demand_factor;
generation_factor = config.demand_level.generation_factor;
time_step         = config.Temporal_loads.time_step_min;

% --- Load and combine network data ---
Sierre_v2 = load('Sierre_v2.mat');
Sion_v2   = load('Sion_v2.mat');
data      = combine_struct_data(Sierre_v2.Sierre, Sion_v2.Sion);
n_total   = length(data.LV_grid);

% --- Output path ---
index_path = fullfile(pwd, 'sanity-check-website', 'docs', 'index.md');

% --- Build scenario block ---
if ~isempty(scenario_name) && isfield(config.scenarios, scenario_name)
    sc = config.scenarios.(scenario_name);
    scenario_block = {
        sprintf('> **Scenario:** %s — %s', scenario_name, sc.SFOE_scenario)
        sprintf('> **Year:** %d &nbsp;|&nbsp; **PV:** %g MW &nbsp;|&nbsp; **EV:** %g thousand units &nbsp;|&nbsp; ', ...
        sc.year, sc.PV_national_MW, sc.EV_national_thousands)
        ''
        sprintf('| Report | Link |')
        '|---|---|'
        sprintf('| Temporal Load Flow Results | [%s Report](temporal_analysis_%s.md) |', scenario_name, scenario_name)
        ''
        };
else
    scenario_block = {
        '> No scenario has been run yet. Set `settings.temporal_loadflow = true` in `main.m` to generate results.'
        ''
        };
end

% --- Assemble full content ---
lines = [
    {
    '# OIKEN LV Network Sanity Check'
    ''
    '---'
    ''
    '## Overview'
    ''
    sprintf('This documentation presents the results of an automated analysis of **%d low-voltage (LV)', n_total)
    'distribution networks** across the Sion and Sierre regions operated by OIKEN.'
    ''
    'The analysis pipeline covers three sequential stages:'
    ''
    '| Stage | Description |'
    '|---|---|'
    '| **1. Power Mix Analysis** | Pre-load flow characterization of DER penetration and loading |'
    '| **2. One-Shot Load Flow** | Single-snapshot load flow validation under maximum loading |'
    '| **3. Temporal Load Flow** | Time-series loadflow validation based on SFOE scenarios |'
    ''
    '---'
    ''
    '## Results'
    ''
    '### Stage 1 — Power Mix Analysis'
    ''
    'Pre-load flow statistics on network loading and distributed energy resource (DER) penetration,'
    'based on the applied coincidence factors across all LV networks.'
    ''
    '| Report | Link |'
    '|---|---|'
    '| Power Mix Analysis — All LV Networks | [View Report](all_LV_grid_power_mix_analysis.md) |'
    ''
    '---'
    ''
    '### Stage 2 — One-Shot Load Flow'
    ''
    'One-shot load flow results under maximum loading conditions across all LV networks.'
    'Networks that fail to converge or show violations in operational limits (nodal voltages, line amperage and transformer congestion) are flagged for further analysis.'
    ''
    '| Report | Link |'
    '|---|---|'
    '| Load Flow Results — All LV Networks | [View Report](oneshot_lf_all_LV_networks.md) |'
    '| Statistical Analysis | [View Analysis](One_shot_loadflow_analysis.md) |'
    ''
    '---'
    ''
    '### Stage 3 — Temporal Load Flow'
    ''
    sprintf('Time-series load flow simulations at **%d-minute resolution** using SFOE electricity', time_step)
    'framework scenarios. Simulations are performed on networks that passed the one-shot load flow.'
    ''
    }
    scenario_block
    {
    '---'
    ''
    '## Methodology'
    ''
    '### Coincidence Factors'
    ''
    'The maximum rated fuse current serves as the basis for network loading.'
    'The following coincidence factors are applied as advised by OIKEN:'
    ''
    '| Parameter | Factor |'
    '|---|---|'
    sprintf('| Demand | %.2f |', demand_factor)
    sprintf('| Generation (PV) | %.2f |', generation_factor)
    ''
    '### Missing Line Parameters Overview'
    ''
    'Line characteristics and ampacity ratings absent from the OIKEN dataset have been'
    'identified, compiled, and resolved using a lookup table approach.'
    ''
    '| Document | Link |'
    '|---|---|'
    '| Missing Data Report | [View Report](Missing_Data.md) |'
    ''
    '### Substation & Transformer Overview'
    ''
    'Network-level substation characteristics including transformer counts, installed'
    'capacity, and data quality flags across all LV networks.'
    ''
    '| Document | Link |'
    '|---|---|'
    '| Substation Summary & Details | [View Report](Substation_summary.md) |'
    '| Transformer Parameter Analysis | [View Report](Transformer_summary.md) |'  
    '| Transformer Parameter Details | [View Details](Transformer_details.md) |'  
    ''
    '---'
    ''
    '## How to Navigate This Documentation'
    ''
    '- Use the **stage links above** to explore results in sequence.'
    '- **Network Search:** Enter a network ID in the search bar to locate a specific substation.'
    '- **Voltage Violation Search:** Enter a voltage threshold (p.u.) to identify networks'
    '  with under-voltage violations below that value.'
    }
    ];

% --- Write to file ---
fid = fopen(index_path, 'w');
if fid == -1
    error('Could not open index.md for writing: %s', index_path);
end
for i = 1:length(lines)
    fprintf(fid, '%s\n', lines{i});
end
fclose(fid);

fprintf('Successfully written index.md | Networks: %d | Demand factor: %.2f | Generation factor: %.2f | Scenario: %s\n', ...
    n_total, demand_factor, generation_factor, string(scenario_name));
end