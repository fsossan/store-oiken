# lv-screening

Stage 1 of the OIKEN LV study in Python: the data sanity check of the 1116
low-voltage networks of Sion and Sierre, the scenario screening (daily load
flow with SFOE 2030/2040 PV and EV injections), and an HTML dashboard. It
replaces the MATLAB stages 4–7 of `../obsolete/sanity_check` and the stage-1 report of
`../tech-selection`; the storage MILP (stage 3) stays in MATLAB.

No server, no database: pure numpy/pandas, one results folder per run, static
HTML pages. The whole portfolio runs in 8 s (one-shot) or 30 s (three cases of
a scenario) on a laptop.

## Setup

```bash
cd lv-screening
python3 -m pip install -r requirements.txt
python3 -m lvgrid fit-demand          # once: fits the household demand model (40 s, needs the 163 MB training file)
```

`data/` already holds everything else a clone needs (grid export, PV year,
node coordinates, fitted demand model); see "Data" below.

## Commands

```bash
python3 -m lvgrid oneshot                              # sanity check of every network -> results/<stamp>_oneshot/
python3 -m lvgrid new-scenario sc1_2040                # stage 1: scenarios/sc1_2040/config.json (edit it)
python3 -m lvgrid new-scenario sc1_2040 --name sc1_2040_pv150   # a second configuration to edit under its own name
python3 -m lvgrid generate sc1_2040                    # stage 2: allocation + daily/yearly injections (CSV), ~20 min with the yearly files
python3 -m lvgrid screen --scenario sc1_2040           # stage 3: screening of all networks, 3 cases, 25 s
python3 -m lvgrid screen --scenario sc1_2040 --networks @results/<oneshot run>   # only networks that passed the sanity check
python3 -m lvgrid dashboard results/<run>              # -> results/<run>/dashboard/index.html (+ one page per flagged network)
python3 -m lvgrid dashboard results/<run> --networks all --max-pages 2000
python3 -m lvgrid geo                                  # rebuild data/geo/node_coordinates.csv from nodes_db.csv
python3 -m lvgrid mv-map                               # which HV/MV substation feeds each LV network -> data/mv/lv_to_hvmv.csv
python3 -m lvgrid aggregate results/<run>              # a run's injections summed per HV/MV substation (subtransmission view)
python3 -m lvgrid clearsky --tilt 30 --azimuth 180 --year 2025 --day 2025-06-21   # clear-sky PV profile (pvlib)
python3 -m lvgrid <command> -h                         # options
python3 -m pytest tests                                # smoke tests (15 s)
```

`--out` names the results folder; without it, `results/<timestamp>_<label>/`.
Nothing is overwritten unless you reuse `--out`.

## The three stages

```
1. scenario configuration     scenarios/<name>/config.json          new-scenario (from the SFOE table in config.json), then edit
2. scenario generation        scenarios/<name>/allocation.csv       generate: config + grid tables -> injections as CSV
                              scenarios/<name>/daily/<network>.csv      per-node series of the representative day(s)
                              scenarios/<name>/yearly/<network>.csv     per-network sums over the year
3. LV screening               results/<run>/                        screen: load flow of every network from the daily CSVs
                                                                    -> dashboard, aggregate (HV/MV substations)
```

**Scenario configuration** (`config.json` of the scenario): the SFOE figures
(national PV MW and EV fleet, populations), the horizon (`step_min`, number
of `days` in the daily product, whether and at which resolution the `yearly`
product is written), the demand settings (`demand_factor`, demand model file,
seed), the PV settings (profile file, series, season, scale) and the EV
charging settings. `new-scenario` fills it from `scenario_defaults` and the
`sfoe` table of the global `config.json`; everything after that is per
scenario and lives in that file.

**Generation** (`generate <name>`): the allocation (below), then per network
the demand, PV and EV series of every rated node. `daily/<network>.csv` is
wide, one row per step and one column per node and stream
(`<node>:demand_kw`, `:demand_kvar`, `:pv_kw`, `:ev_kw`, consumption
positive, 3-phase kW); `yearly/<network>.csv` sums the nodes over the full
year at `yearly.step_min` (hourly by default; 8760 rows, 1116 files, about
450 MB per scenario). The daily product is the yearly series on the
representative PV day, so both are consistent, and every (network, day) has
its own seed, so a day does not change when more days are generated.
`scenario.json` records totals, the PV day, sizes, hashes of `config.json`
and `allocation.csv` and the version. MATLAB reads the same files with
`readtable`. Generated folders are not in git (regenerate with `generate`);
the configurations are.

**Screening** (`screen --scenario <name>`): reads `daily/<network>.csv`,
runs the three cases and records the scenario name and hashes in `run.json`
(flagged `edited_after_generation` if the config or allocation changed after
the files were generated).

## What the runs do

**One-shot sanity check** (`oneshot`). The DSO planning snapshot: every
connection draws `demand_factor` (6 %) of its fuse-rated peak at a 0.9 power
factor, all at the same instant, plus `generation_factor` (0) of the existing
PV. One load flow per network. Its purpose is to catch data and model errors
(non-convergence, absurd voltages or currents, missing transformers, nodes not
connected to the slack), not to represent a real operating point. Status per
network: `ok`, `violation` (voltage outside 0.9–1.1 pu, line or transformer
above its rating), `not_converged`, `topology_error`, `build_error`.

**Allocation** (part of `generate`). The SFOE national PV capacity and EV
fleet of the scenario are scaled to Sion+Sierre by population, split between
networks in proportion to their fuse-rated peak and within a network in
proportion to each node's PLmax (EVs as integers, largest remainder). The PV
day is the real day of the yearly profile closest to the season's mean shape.

**Scenario screening** (`screen`). The daily product (96 steps of 15 min per
day) of every network with three nested cases, so a violation can be
attributed to its driver:

| case | injections |
|---|---|
| `demand` | household demand only: 6 % of the fuse-rated peak per node times a synthetic household day (GMM fitted on Swiss smart-meter data, one random cluster per node and one day draw per node and day) |
| `demand+pv` | plus the scenario PV: node kWp times the normalised PV profile of the day |
| `demand+pv+ev` | plus the scenario EVs: each vehicle charging at 11 kW for 4 h after a truncated-normal arrival (mean 18:00, σ 0.6 h, 17:00–21:00), drawn per day |

Seeds derive from the network number and the day, so a network sees the same
demand and EV realisation in every scenario (with the same seed offsets);
scenarios differ only by PV kWp and EV counts.

**Model.** Single-phase equivalent, Sb = 100 kVA, Vb = 230 V; the MV side of
the transformer is the slack at 1.0 pu; closed LV switches of the substation
collapse onto the transformer's LV node; feeders behind open switches are
pruned; transformer R/X are rebased to the common base; constant-power loads;
fixed-point (Z-bus) load flow with damping 0.7, vectorised over the 96 steps.
This is a port of the MATLAB `combined_lv_sub_SFOE` / `get_grid_SFOE` /
`loadflow_FPIs_convergance` chain with three deliberate changes: the slack is
always internal node 0 (the MATLAB code assumed node 1, wrong for 15 networks
whose transformer row is stored LV→MV); transformers whose LV nodes sit on the
same closed-switch busbar are connected in parallel (103 of the 194
multi-transformer networks; the MATLAB code hung every feeder on the last
transformer and left the others idle); and a step is declared non-converged
only after 100 iterations or a non-finite voltage (the MATLAB abort on a
growing error killed heavily loaded but solvable networks). Transformer
import/export and losses (I²R over all branches) come from the load flow.
Small print: EV sessions are cut at midnight (arrivals up to 21:00 + 4 h), so
about 1.5 % of the EV energy is lost; PV and EVs allocated to nodes behind
open switches or in networks that cannot be built are not simulated
(`run.json` lists target and applied totals).

**Results folder.** `summary.csv` has one row per network and case: static
data (nodes, lines, transformer kVA, fuse-rated peak, nominal demand, existing
PV, scenario PV kWp and EV count, data issues) and metrics (converged steps,
min/max voltage with node and step, under/over-voltage node counts, highest
line loading with line id, overloaded lines, transformer loading, peak
import/export, losses, violation types, status). `run.json` is the settings
snapshot. `details/<id>.npz` keeps the per-step voltages and loadings for the
dashboard.

**Dashboard.** `index.html`: KPI row (ok / violation / not converged, nominal
demand, PV, EVs, share of demand in violated networks), status per case,
violation kinds per case, distributions of lowest voltage and highest loading,
a PV-vs-nominal-demand scatter (marker size = transformer rating), a map of
the substations coloured by status (click opens the network page), and a
sortable table of all networks. One page per flagged network (or `--networks
all`): network facts and penetration ratios, case comparison, topology on an
OpenStreetMap background (nodes by lowest voltage, lines by highest loading;
a layout drawing when a network has no coordinates), aggregate injections,
per-case envelopes of voltage, line and transformer loading over the day, and
installed capacity vs transformer rating. Map tiles need internet access;
everything else is local.

## Subtransmission view (HV/MV substations)

The export also holds the MV level: the MV lines (one sheet per HV/MV
substation area), 245 MV switching stations and the 11 HV/MV substations
(65/16 kV transformers of 12–20 MVA with their switchgear), exported once by
`tools/export_mv_tables.py` to `data/mv/`. `python -m lvgrid mv-map` builds
the graph of all MV lines plus every closed switch (MV stations, HV/MV
substations, MV side of the LV substations) and finds, for each LV network,
the HV/MV transformer its own transformer is connected to: 1098 of the 1116
networks reach exactly one HV/MV substation (none reaches two, so the MV grid
is operated radially), 18 have gaps in the MV data and stay unmapped. Sheet
membership alone would not do: a third of the LV substations have switches
into two MV areas (normally open ties), and for 30 % of the networks the sheet
id is not the feeding substation. Results: `data/mv/lv_to_hvmv.csv` (network,
substation, status) and `data/mv/hvmv.csv` (substation, city, transformers,
MVA, networks fed, name and position from the DB node table).

`python -m lvgrid aggregate results/<run>` then sums a run's per-network
series per HV/MV substation and case: `aggregate_hvmv_series.csv` (demand,
PV, EV and transformer import per step), `aggregate_hvmv.csv` (networks,
nominal demand, PV kWp, EVs, peak import/export, daily energies, peak over the
HV/MV rating) and `aggregate_hvmv.html` (daily curves). The import is the
load-flow import of the LV transformers where the load flow converged (losses
included) and the injection sum elsewhere; the column
`missing_loadflow_steps` counts the substitutions. Not modelled: MV lines and
their losses, MV-connected customers and generators, the HV/MV transformer
itself. For sc1_2040 the evening EV peak reaches 0.6–2.0 times the HV/MV
rating and the midday PV export 60 % of it.

## Node coordinates

The grid export has no coordinates, but the node names are the DSO database's
node ids (`N_<id_NOD>`), and the network ids are the substations' node ids.
`tools/extract_nodes_from_bak.py` reads the node table (`noeud_NOD`: id,
code, name, class, Swiss national coordinates) directly from the SQL Server
backup in `../oiken-db-extraction/` by scanning its uncompressed 8 KB data
pages, so no SQL Server is needed. `python -m lvgrid geo` then writes

* `data/geo/nodes_db.csv` – 104,394 nodes of the whole database (69,001 with coordinates), LV95 E/N
* `data/geo/substations.csv` – the 1116 networks' substations: DSO code, name, LV95, WGS84 (all located)
* `data/geo/node_coordinates.csv` – every (network, node): 56 % with their own
  DB coordinates, 16 % substation-internal nodes (`N_Fus_`, `N_JbL_`, `N_TrL_`,
  …) placed at their substation, 28 % without coordinates in the DB; the
  dashboard draws those at the nearest located neighbour.

WGS84 is obtained with swisstopo's approximate formulas (about 1 m). Mixed
LV03/LV95 values in the DB are normalised to LV95.

## Data

| file | origin | regenerate with |
|---|---|---|
| `data/lv_grids/lines.csv`, `substations.csv` | `../tech-selection/data/raw/lv_grids.mat` (= `../obsolete/sanity_check/data_v2.mat`, the patched OIKEN export) | `matlab -batch "run('tools/export_lv_grids.m')"` |
| `data/pv/pv_profiles_year.csv` | `../tech-selection/data/raw/pv_profiles_year.mat` (pvlib, 2019, Sion, 35° south; clear sky and PVGIS TMY) | `python3 tools/export_pv_profiles.py` |
| `data/pv/clearsky_sion_sierre_2019.csv` | `python -m lvgrid clearsky` (constant 20 °C air temperature: 5 % lower annual yield than the reference, same daily shape) | same |
| `data/demand_gmm.npz` | fitted from `../tech-selection/data/external/load_consumption_train_heapo.mat` (not in git); settings in `demand_model` of config.json | `python -m lvgrid fit-demand` |
| `data/demand_train_days.csv` | calendar of the training days, for weekday/season filters | `tools/export_demand_train_days.m` |
| `data/geo/*.csv` | DB backup `tndb_esr_test_03102024.bak` (not in git) | `tools/extract_nodes_from_bak.py` + `python -m lvgrid geo` |
| `data/mv/mv_lines.csv`, `mv_stations.csv`, `hvmv_substations.csv` | MV sheets of the OIKEN Excel export (`../obsolete/sanity_check/network_data/excel_data/`) | `python3 tools/export_mv_tables.py` |
| `data/mv/lv_to_hvmv.csv`, `hvmv.csv` | derived from the above and the LV substation tables | `python -m lvgrid mv-map` |

Global settings are in `config.json` (per-unit base, one-shot factors,
limits, load-flow tolerances, demand-model fit, scenario defaults, SFOE
table); everything specific to a scenario is in its own `config.json`.

## Checks against the MATLAB results

* One-shot, all 1116 networks: same classification as the MATLAB `sanity_check`
  (1036 ok, 47 violation, 24 + 2 not converged / no transformer, 7 topology
  errors); lowest voltages agree within the legacy table's rounding (median
  0.002 pu), overloaded-line counts are identical. Transformer loadings of the
  194 multi-transformer networks are lower than in MATLAB (parallel
  transformers, see "Model").
* sc1_2040 on the 1036 healthy networks: about 300 networks with violations
  (legacy 284), a dozen not fully converged (legacy 11); violation kinds of
  the order of 160 undervoltage / 40 overvoltage / 220 line / 190 transformer
  (legacy 147 / 45 / 263 / 163); the exact counts depend on the random
  realisation of demand and EV arrivals.
  The individual networks differ because demand and EV draws are different
  random realisations, because the legacy run charged one vehicle per EV node
  regardless of the allocated count, and because parallel transformers now
  share their load.
* Two networks (LV_Grid_442, LV_Grid_5490) are reported converged by the
  legacy table but oscillate at any damping here: they are loaded beyond the
  fixed-point method's limit (lowest voltage < 0.6 pu, several overloaded
  lines) and are flagged either way.

## Layout

```
config.json          all settings
lvgrid/              the package: config, data, network, loadflow, scenario,
                     profiles, injections, screening, dashboard, geo, mv, clearsky, __main__
tests/               pytest smoke tests
scenarios/<name>/    config.json tracked; generated files (allocation, daily/, yearly/, scenario.json) ignored
tools/               one-off exports: export_lv_grids.m, export_pv_profiles.py, export_mv_tables.py,
                     export_demand_train_days.m, extract_nodes_from_bak.py
data/                inputs in Python-readable form (tracked)
results/             runs (ignored by git)
```
