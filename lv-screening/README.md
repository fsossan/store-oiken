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
python3 -m lvgrid screen --scenario sc1_2040           # scenario screening, all networks, 3 cases
python3 -m lvgrid screen --scenario sc1_2040 --networks @results/<oneshot run>   # only networks that passed the sanity check
python3 -m lvgrid screen --scenario sc1_2030 --networks 101,230 --days 7
python3 -m lvgrid dashboard results/<run>              # -> results/<run>/dashboard/index.html (+ one page per flagged network)
python3 -m lvgrid dashboard results/<run> --networks all --max-pages 2000
python3 -m lvgrid geo                                  # rebuild data/geo/node_coordinates.csv from nodes_db.csv
python3 -m lvgrid clearsky --tilt 30 --azimuth 180 --year 2025 --day 2025-06-21   # clear-sky PV profile (pvlib)
python3 -m lvgrid <command> -h                         # options
```

`--out` names the results folder; without it, `results/<timestamp>_<label>/`.
Nothing is overwritten unless you reuse `--out`.

## What the runs do

**One-shot sanity check** (`oneshot`). The DSO planning snapshot: every
connection draws `demand_factor` (6 %) of its fuse-rated peak at a 0.9 power
factor, all at the same instant, plus `generation_factor` (0) of the existing
PV. One load flow per network. Its purpose is to catch data and model errors
(non-convergence, absurd voltages or currents, missing transformers, nodes not
connected to the slack), not to represent a real operating point. Status per
network: `ok`, `violation` (voltage outside 0.9–1.1 pu, line or transformer
above its rating), `not_converged`, `topology_error`, `build_error`.

**Scenario screening** (`screen`). One synthetic day (96 steps of 15 min) per
network with three nested cases, so a violation can be attributed to its driver:

| case | injections |
|---|---|
| `demand` | household demand only: 6 % of the fuse-rated peak per node times a synthetic household day (GMM fitted on Swiss smart-meter data, one random cluster and day per node) |
| `demand+pv` | plus the scenario PV: national SFOE capacity scaled to Sion+Sierre by population, split over networks and nodes in proportion to fuse-rated peak, times one representative clear-sky day |
| `demand+pv+ev` | plus the scenario EVs: same allocation (integers), each vehicle charging at 11 kW for 4 h after a truncated-normal arrival (mean 18:00, σ 0.6 h, 17:00–21:00) |

Seeds derive from the network number, so a network sees the same demand and
EV realisation in every scenario; scenarios differ only by PV kWp and EV counts.
`--days N` draws N demand days per node and repeats the PV and EV day.

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
| `data/demand_gmm.npz` | fitted from `../tech-selection/data/external/load_consumption_train_heapo.mat` (not in git) | `python -m lvgrid fit-demand` |
| `data/demand_train_days.csv` | calendar of the training days, for weekday/season filters | `tools/export_demand_train_days.m` |
| `data/geo/*.csv` | DB backup `tndb_esr_test_03102024.bak` (not in git) | `tools/extract_nodes_from_bak.py` + `python -m lvgrid geo` |

All settings are in `config.json` (per-unit base, one-shot factors, limits,
load-flow tolerances, demand/PV/EV profile parameters, SFOE scenario table).

## Checks against the MATLAB results

* One-shot, all 1116 networks: same classification as the MATLAB `sanity_check`
  (1036 ok, 47 violation, 24 + 2 not converged / no transformer, 7 topology
  errors); lowest voltages agree within the legacy table's rounding (median
  0.002 pu), overloaded-line counts are identical. Transformer loadings of the
  194 multi-transformer networks are lower than in MATLAB (parallel
  transformers, see "Model").
* sc1_2040 on the 1036 healthy networks: 305 networks with violations (legacy
  284), 12 not fully converged (legacy 11); violation kinds 159 undervoltage /
  39 overvoltage / 221 line / 193 transformer (legacy 147 / 45 / 263 / 163).
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
lvgrid/              the package: config, data, network, loadflow, allocation,
                     profiles, injections, screening, dashboard, geo, clearsky, __main__
tools/               one-off exports: export_lv_grids.m, export_pv_profiles.py,
                     export_demand_train_days.m, extract_nodes_from_bak.py
data/                inputs in Python-readable form (tracked)
results/             runs (ignored by git)
```
