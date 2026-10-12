# scenario-generation

Turns a scenario configuration and the grid portfolio into per-node injection
time series (CSV) for the LV networks of Sion and Sierre. Self-contained: one
script, the package `scengen/`, the scenario configurations in `scenarios/`,
the generated files in `output/`. Inputs come from the shared `../data/`.

```bash
cd scenario-generation
python3 -m pip install -r requirements.txt
python3 generate_scenario.py fit-demand                 # once: fit the household demand model (40 s, needs the 163 MB training file)
python3 generate_scenario.py new sc1_2040               # stage 1 -> scenarios/sc1_2040/config.json   (edit it)
python3 generate_scenario.py new sc1_2040 --name pv150  # a second configuration under its own name
python3 generate_scenario.py generate sc1_2040          # stage 2 -> output/sc1_2040/   (~20 min with the yearly files, ~500 MB)
python3 generate_scenario.py generate pv150 --networks 101,230   # a subset (tests, debugging)
python3 generate_scenario.py clearsky --tilt 30 --year 2025 --day 2025-06-21   # clear-sky PV profile (pvlib)
python3 -m pytest tests                                 # smoke tests (a few seconds)
```

## Scenario configuration (`scenarios/<name>/config.json`)

Written by `new` from the `sfoe` table and `scenario_defaults` of
`config.json`, then edited by hand:

| block | content |
|---|---|
| `sfoe` | SFOE Energy Perspectives 2050+ figures of the scenario: national PV MW, EV fleet, populations (national, Sion+Sierre) |
| `time` | `step_min` (15), `days` of the daily product (1), `yearly.enabled` / `yearly.step_min` (60) |
| `demand` | `demand_factor` (6 % of the fuse-rated peak, the DSO planning value), demand model file, seed offset |
| `pv` | yearly profile file, series (`clearsky` / `measured`), season for the representative day, scale |
| `ev` | charger kW, charging duration, truncated-normal arrival (mean, σ, window), seed offset |

Only these configurations are in git; `output/` is regenerated.

## What `generate` does

1. **Allocation** (port of the MATLAB `allocate_PV_EV_SFOE`): national PV and
   EVs scaled to Sion+Sierre by population, split between networks in
   proportion to their fuse-rated peak (sum of PLmax over the nodes), within a
   network in proportion to each node's PLmax; EVs as integers (largest
   remainder at both levels).
2. **Series per node**, 3-phase kW, consumption positive:
   - demand: `demand_factor` × fuse-rated peak (P and Q, constant power factor)
     times a synthetic household day from the demand model (Gaussian mixture
     fitted on HEAPO smart-meter data, Grammatikos/Ali/Sossan 2026): one
     household cluster per node, one day draw per node and day;
   - PV: node kWp times the normalised yearly profile (`../data/pv/`, pvlib,
     Sion, 35° south; per unit of installed DC peak);
   - EV: each vehicle charges at `charger_kw` for `duration_h` after a
     truncated-normal arrival, drawn per day; vehicles summed per node.
   Seeds are `(network number + seed_offset, day)`, so a network keeps its
   realisation across scenarios with the same offsets and a day does not
   change with the horizon.
3. **Products**: the daily product is the yearly series on the representative
   PV day (the real day closest to the season's mean shape, 2019-09-17 for
   `all`), so the two are consistent.

## Output (`output/<name>/`)

| file | content |
|---|---|
| `allocation.csv` | `network_id, node, plmax_kw, qlmax_kvar, pv_kwp, ev_count` (nodes with a fuse rating) |
| `networks.csv` | per network: nodes, fuse-rated peak, nominal demand, PV kWp, EVs |
| `pv_day.csv` | the normalised PV day of the daily product |
| `daily/<network_id>.csv` | one row per step (`step`, `hour`), one column per node and stream: `<node>:demand_kw`, `<node>:demand_kvar`, `<node>:pv_kw`, `<node>:ev_kw`; all-zero columns omitted |
| `yearly/<network_id>.csv` | `time, demand_kw, demand_kvar, pv_kw, ev_kw` summed over the network, at `yearly.step_min` (8760 rows hourly) |
| `scenario.json` | totals (regional and allocated), PV day, sizes, hashes of `config.json` and `allocation.csv`, version, timing |

Consumers: `../lv-screening` (`python -m lvgrid screen --scenario <name>`)
reads `daily/`; MATLAB reads any of the files with `readtable`
(`VariableNamingRule='preserve'` keeps the `node:stream` headers). The
`yearly/` files feed energy balances and the subtransmission view.

Small print: EV sessions are cut at midnight (arrivals up to 21:00 + 4 h,
about 1.5 % of the EV energy); the demand model has no calendar, so the
yearly demand is 365 independent days without seasonality; existing PV in
the grid data is not added to the scenario PV (the SFOE total is taken as
the total).

## Layout

```
generate_scenario.py   the script (new | generate | fit-demand | clearsky)
scengen/               config, data, profiles, generate, clearsky
config.json            demand-model fit settings, scenario defaults, SFOE table
scenarios/<name>/      config.json per scenario (tracked)
output/<name>/         generated files (ignored)
tools/                 one-off exports: export_pv_profiles.py, export_demand_train_days.m
tests/                 pytest smoke tests
```
