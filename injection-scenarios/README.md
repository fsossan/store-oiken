# injection-scenarios

Turns a scenario configuration and the grid portfolio into per-node injection
time series (CSV) for the LV networks of Sion and Sierre. Self-contained: one
script, the package `scengen/`, the scenario configurations in `scenarios/`,
the generated files in `output/`. Inputs come from the shared `../data/`.

```bash
cd injection-scenarios
python3 -m pip install -r requirements.txt
python3 generate_scenario.py fit-demand                 # once: fit the household demand model (40 s, needs the 163 MB training file)
python3 generate_scenario.py new sc1_2040               # stage 1 -> scenarios/sc1_2040/config.json   (edit it)
python3 generate_scenario.py new sc1_2040 --name pv150  # a second configuration under its own name
python3 generate_scenario.py generate sc1_2040          # stage 2 -> output/sc1_2040/   (a few minutes with the yearly files, ~500 MB)
python3 generate_scenario.py generate pv150 --networks 101,230   # a subset (tests, debugging)
python3 generate_scenario.py clearsky --tilt 30 --year 2025 --day 2025-06-21   # clear-sky PV profile (pvlib)
python3 generate_scenario.py dashboard                  # scenario browser on http://127.0.0.1:8050 (read-only)
python3 -m pytest tests                                 # smoke tests (a few seconds)
```

## Scenario configuration (`scenarios/<name>/config.json`)

Written by `new` from the `sfoe` table and `scenario_defaults` of
`config.json`, then edited by hand:

| block | content |
|---|---|
| `sfoe` | SFOE Energy Perspectives 2050+ figures of the scenario: national PV MW, EV fleet, populations (national, Sion+Sierre) |
| `time` | `step_min` (15), `days` of the daily product (1), `yearly.enabled` / `yearly.step_min` (60) |
| `demand` | `demand_factor`: each connection's P_max as a share of its fuse-rated power (0.22, so that the median network of 27 connections peaks at the DSO planning value of 6 %; see `tools/demand_aggregation_demo.ipynb`), demand model file, seed offset |
| `pv` | yearly profile file, series (`clearsky` / `measured`), season for the representative day, scale |
| `ev` | charger kW, arrival time and energy per session (truncated normal or GEV, see below), seed offset |

Only these configurations are in git; `output/` is regenerated: `generate`
replaces `daily/` and `yearly/` of the folder, so a `--networks` subset run
leaves only that subset. Unknown blocks are rejected (typos).

EV distributions: `arrival_h` [h] and `energy_kwh` [kWh per vehicle and day]
are each truncated to `[min, max]` (inverse-CDF sampling) and take one of

```json
{"dist": "normal", "mean": 18, "std": 0.6, "min": 17, "max": 21}
{"dist": "gev", "shape": 0.1, "loc": 12, "scale": 6, "min": 1, "max": 80}
```

`std: 0` gives a fixed value. The GEV `shape` is ξ (ξ > 0 heavy upper tail,
ξ = 0 Gumbel, ξ < 0 bounded above), i.e. `k` of MATLAB `gevrnd(k, sigma, mu)`;
scipy's `genextreme` uses `c = -ξ`. Arrivals are drawn before energies, so
changing the energy distribution leaves the arrivals unchanged. The defaults
(arrival N(18 h, 0.6 h) in 17-21 h, 44 kWh fixed = 4 h at 11 kW) are the
former EV model; the draws differ from earlier outputs (inverse-CDF
sampling, step-averaged power), with the same energy and peaks.

## What `generate` does

Each stream comes from one model in `scengen/models/` (see *Models* below);
`generate` runs the models whose block is in the scenario configuration.

1. **Allocation** (port of the MATLAB `allocate_PV_EV_SFOE`): national PV and
   EVs scaled to Sion+Sierre by population, split between networks in
   proportion to their fuse-rated peak (sum of PLmax over the nodes), within a
   network in proportion to each node's PLmax; EVs as integers (largest
   remainder at both levels).
2. **Series per node**, 3-phase kW, each stream in its own sign (demand and EV
   consumption positive, PV production positive):
   - demand: `demand_factor` × fuse-rated peak (P and Q, constant power factor)
     times a synthetic household day from the demand model (Gaussian mixture
     fitted on HEAPO smart-meter data, Grammatikos/Ali/Sossan 2026): one
     household cluster per node, one day draw per node and day;
   - PV: node kWp times the normalised yearly profile (`../data/pv/`, pvlib,
     Sion, 35° south; per unit of installed DC peak);
   - EV: each vehicle charges once a day at `charger_kw` from its arrival
     until its energy is delivered (power as step averages, so each
     session delivers exactly its energy); arrival and energy drawn per
     vehicle and day; vehicles summed per node.
   Seeds are `(network number + seed_offset, day)`, so a network keeps its
   realisation across scenarios with the same offsets and a day does not
   change with the horizon.
3. **Products**: the daily product is the yearly series on the representative
   PV day (the real day closest to the season's mean shape, 2019-09-17 for
   `all`), so the two are consistent.

## Models (`scengen/models/`)

One module per stream, all with the same interface (`models/__init__.py`):

| | |
|---|---|
| `NAME`, `SIGN` | config block and stream name; `load` (consumption positive) or `generation` |
| `allocate(nodes, sfoe, cfg)` | adds the model's per-node columns to `allocation.csv` (`pv_kwp`, `ev_count`), returns its totals |
| `prepare(cfg, step_min)` | once per run: read data, check settings |
| `series(state, rows, days, net_num)` | the network's per-node series per column (`<NAME>_kw`, optionally `_kvar`), `[nodes x days x steps]` |

`demand` and `pv` are required (PV defines the calendar and the day of the
daily product); further models are optional, so configurations without the
block of a newer model stay valid (an `ev` block in the format before
2026-10-13 is rejected with a pointer to the new one). To add one, e.g. heat pumps: write `models/heat.py` with this
interface, append it to `MODELS`, add a `heat` block to `scenario_defaults` in
`config.json` (and to the scenarios that should have it). `scenario.json`
then lists it under `streams`, and `../lv-screening` adds a
`demand+pv+ev+heat` case, its peak and energy columns, the HV/MV sums and the
dashboard curves without code changes. (Checked on 2026-10-13 with a
throwaway constant model through generation, screening, aggregation and
dashboard.)

## Output (`output/<name>/`)

| file | content |
|---|---|
| `allocation.csv` | `network_id, node, plmax_kw, qlmax_kvar, pv_kwp, ev_count` (nodes with a fuse rating) |
| `networks.csv` | per network: nodes, fuse-rated peak, nominal demand, PV kWp, EVs |
| `pv_day.csv` | the normalised PV day of the daily product |
| `daily/<network_id>.csv` | one row per step (`step`, `hour`), one column per node and stream: `<node>:demand_kw`, `<node>:demand_kvar`, `<node>:pv_kw`, `<node>:ev_kw` (`<node>:<stream>_kw` / `_kvar` in general); all-zero columns omitted |
| `yearly/<network_id>.csv` | `time, demand_kw, demand_kvar, pv_kw, ev_kw` (one column per stream column) summed over the network, at `yearly.step_min` (8760 rows hourly) |
| `scenario.json` | `streams` (name -> `load` / `generation`, the contract read by the screening), totals (regional and allocated), PV day, sizes, hashes of `config.json` and `allocation.csv`, version, timing |

Consumers: `../lv-screening` (`python -m lvgrid screen --scenario <name>`)
reads `daily/`; MATLAB reads any of the files with `readtable`
(`VariableNamingRule='preserve'` keeps the `node:stream` headers). The
`yearly/` files feed energy balances and the subtransmission view.

Small print: EV sessions are cut at midnight (0.002 % of the EV energy with
the defaults; it grows with late arrivals and heavy-tailed energies); the
demand model has no calendar, so the yearly demand is 365 independent days
without seasonality; existing PV in
the grid data is not added to the scenario PV (the SFOE total is taken as
the total).

## Scenario browser (`dashboard`)

A local Dash app (`scengen/dashboard.py`) on everything a scenario produced:
demand, PV, EV and any further stream listed in `scenario.json`. Net load =
loads − generation; below zero the network feeds back through its
transformer (reverse flow). Pick a scenario, and optionally a second one
under *compare with*. A badge tells whether `output/<name>/` still matches
`scenarios/<name>/config.json` (hash in `scenario.json`) and the current
generator version, or has not been generated; the configuration is one click
away. It never starts a generation; reload the page after one.

- **Overview**: key figures (energy per stream, kWh per connection, PV
  full-load hours, kWh per vehicle, regional peak and largest reverse flow,
  networks above their transformer rating, networks with reverse flow); the
  regional day (representative, peak, reverse-flow or mean day; streams
  stacked, net load, and the compared scenario's net load); the hourly year
  with a range slider; energy per month; duration curves; the net-load
  heatmap (day × hour, red = reverse flow).
- **Networks**: every network on two selectable axes (default: largest
  reverse flow against peak net load, both in % of the transformer, with the
  100 % lines) and a sortable, filterable table (energy per stream, peak and
  lowest net load, transformer loading, reverse-flow hours; above 100 % in
  red). A point or a row opens the network.
- **Network**: fuses, transformer, PV, EVs, energy and peaks; a day of its
  streams against the transformer rating (the representative day at the
  daily step, or the peak, reverse-flow or mean day from the yearly file);
  each connection's demand, PV or EV in % of its own fuse power, with the
  coincidence factor; the hourly year, duration curves, heatmap; a link to
  the network in the grid data explorer (`python3 -m lvgrid explore`).
- **Compare**: key figures of both scenarios with the change, the regional
  net load over the day (mean and 5-95 % band) and its duration curve, and
  every network's value in one scenario against the other (selectable).

Links take `?scenario=`, `?compare=`, `?tab=` (`overview`, `networks`,
`network`, `compare`) and `?network=`, e.g.
`http://127.0.0.1:8050/?scenario=sc1_2040&compare=sc1_2030&tab=compare`.
The yearly files are hourly means (peaks within the hour are higher; the
screening uses the daily product). They are read once per scenario (2-3 s
for the 1081 networks) and kept in memory for the last two scenarios.

## Layout

```
generate_scenario.py   the script (new | generate | fit-demand | clearsky | dashboard)
scengen/               config, data, generate, clearsky, dashboard (scenario browser)
scengen/models/        one module per stream: demand, pv, ev (+ common allocation helpers)
config.json            demand-model fit settings, scenario defaults, SFOE table
scenarios/<name>/      config.json per scenario (tracked)
output/<name>/         generated files (ignored)
tools/                 one-off exports (export_pv_profiles.py, export_demand_train_days.m) and
                       demand_aggregation_demo.ipynb (notebook: spatial smoothing of the demand model, T(n))
tests/                 pytest smoke tests
```
