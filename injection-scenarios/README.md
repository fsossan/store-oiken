# injection-scenarios

Applies a scenario to the grid and writes injection time series (CSV) for
every connection of the LV networks of Sion and Sierre. Self-contained: the package
`scengen/` with two front ends, the notebook `scenario.ipynb` and the script
`generate_scenario.py`; the scenario configurations in `scenarios/`, the
generated files in `output/`. Inputs come from the shared `../data/`.

Four steps, one module each, the same in both front ends:

```python
grid       = load_grid()                  # scengen/grid.py        the LV portfolio and the region's population: fixed inputs
scenario   = load_scenario("sc1_2040")    # scengen/scenario.py    what is assumed: national figures, time, model settings
injections = prepare(grid, scenario)      # scengen/injections.py  allocation, calendar and any network's series, in memory
write(injections)                         # scengen/output.py      the files of output/sc1_2040/nl7/ (--level nl4: nl4/)
```

| | holds | comes from |
|---|---|---|
| grid | `connections` (every connection point with a fuse rating), `networks` (per network: connections, fuse-rated power, transformer kVA, the HV/MV substation feeding it), `population` of the region per year | `../data/lv_grids/` (`lines.csv`, `substations.csv`, `region.json`), `../data/mv/lv_to_hvmv.csv` |
| scenario | national SFOE figures, time, one block per model. No grid facts | `scenarios/<name>/config.json` |
| injections | the allocation per connection (nominal demand, PV kWp, EVs), the calendar, the prepared models | `prepare` |

A *connection* is a connection point with a fuse rating; its *node* is where
it connects in its network, and names it in the files (`node`, `<node>:<stream>`).

**Notebook** (`scenario.ipynb`, Jupyter or VS Code): look at the grid, pick or
create a configuration and edit it, see its allocation, the rule and the
sanity check behind `demand_factor`, EV sessions, the regional day, one
day per season, the energy per season and over the year (PV also at a
realistic capacity factor, see below), every network's transformer loading
and any one network (the daily product of the whole portfolio, computed in
memory in about a second), then write the
configuration and generate. Nothing is written before its last section, which
shows how the configuration differs from the file on disk; generating writes
the configuration as well, so `output/<name>/` always has its configuration
next to it. Clear its outputs before committing: they show per-network values.

**Script**, for batch runs and regeneration:

```bash
cd injection-scenarios
python3 -m pip install -r requirements.txt
python3 generate_scenario.py fit-demand                 # once: fit the household demand model (40 s, needs the 163 MB training file)
python3 generate_scenario.py new sc1_2040               # the scenario -> scenarios/sc1_2040/config.json   (edit it)
python3 generate_scenario.py new sc1_2040 --name pv150  # a second configuration under its own name
python3 generate_scenario.py generate sc1_2040          # applied to the grid -> output/sc1_2040/nl7/   (a few minutes with the yearly files, ~500 MB)
python3 generate_scenario.py generate sc1_2040 --level nl4   # the same at the HV/MV substations -> output/sc1_2040/nl4/   (2 s, 7 MB)
python3 generate_scenario.py generate pv150 --networks 101,230   # a subset (tests, debugging; nl7 only)
python3 generate_scenario.py clearsky --tilt 30 --year 2025 --day 2025-06-21   # clear-sky PV profile (pvlib)
python3 generate_scenario.py dashboard                  # scenario browser on http://127.0.0.1:8050 (read-only)
python3 -m pytest tests                                 # smoke tests (a few seconds)
```

## Scenario configuration (`scenarios/<name>/config.json`)

Written by `new` from the `sfoe` table and `scenario_defaults` of
`config.json`, then edited by hand:

| block | content |
|---|---|
| `sfoe` | SFOE Energy Perspectives 2050+ figures of the scenario, all national: year, PV MW, EV fleet, population; and `to_region`, how PV and EV are scaled to the region (`population`, see *What `generate` does*) |
| `time` | `step_min` (15), `days` of the daily product (1), `yearly.enabled` / `yearly.step_min` (60) |
| `demand` | `demand_factor`: each connection's P_max as a share of its fuse-rated power (0.22; see *Where `demand_factor` comes from* below), demand model file, seed offset |
| `pv` | `split`, how the regional kWp is split over the connections (`fuse` / `connections`, see *What `generate` does*); yearly profile file, series (`clearsky` / `measured`), season for the representative day, scale |
| `ev` | `split` (as for PV, in whole vehicles); charger kW, arrival time and energy per session (truncated normal or GEV, see below), seed offset |

Only these configurations are in git; `output/` is regenerated: `generate`
replaces `daily/` and `yearly/` of the level folder, so a `--networks` subset run
leaves only that subset. Unknown blocks and unknown or missing keys inside a
block are rejected before anything is computed (typos), and so is a
configuration that still carries `sfoe.population_sion_sierre` (delete the
key: the population is a fact of the grid). A configuration written before
2026-11-14 lacks `sfoe.to_region`, `pv.split` and `ev.split`: add
`"to_region": "population"` and `"split": "fuse"`, which is what it did.

**Where `demand_factor` comes from.** It is not an SFOE figure. A rule on the
peak sets it and a sanity check on the energy tests it. The parameters are in
`config.json` (`demand_factor_basis`), the derivation is in
`demand_factor.ipynb`, and `scenario.ipynb` (section 3) prints both for the
scenario at hand (`scengen/demand_check.py`, tested).

- *Rule (sets it).* The DSO plans a network for a peak of 6 % of its
  fuse-rated power (`planning_peak`). Houses do not peak together: in the
  demand model, a network of median size (27 connections) peaks at 0.28 × the
  sum of its connections' P_max. Hence `demand_factor` = 0.06 / 0.28 ≈ 0.21,
  set to 0.22.
- *Sanity check (changes nothing).* 0.22 gives about 310 GWh per year for all
  connections. Swiss consumption (`ch_consumption_twh`, 57 TWh) prorated to
  the region by population is about 630 GWh. Households (`share_households`,
  35 %) take about 220 GWh of it, households plus services (`share_services`,
  27 % more) about 390 GWh. LV connections are households and part of the
  services, so the 310 GWh should lie between the two, and it does. The two
  shares only draw these bounds. The three figures are still to be verified
  against the SFOE electricity statistics.
- *To do.* Match it with smart-meter measurements of the connections instead
  of a fixed share of the fuse rating.

**PV at a realistic capacity factor.** The PV profiles are ideal systems
(south at 35°, no shading, no system losses): 2,470 kWh/kWp a year for
`clearsky` (capacity factor 0.28), 1,475 for `measured` (PVGIS TMY). The
notebook and the scenario browser show the PV energy next to it at a
realistic capacity factor, `pv_realistic.capacity_factor` in `config.json`
(0.11: the Swiss fleet averaged 954 ± 36 kWh/kWp a year over 2013-2022,
Hostettler 2022, cited in Frontiers in Energy Research 2024; Sion is sunnier,
so it is the low end). Display only: the generated series keep the profile.

EV distributions: `arrival_h` [h] and `energy_kwh` [kWh per vehicle and day]
are each truncated to `[min, max]` (inverse-CDF sampling) and take one of

```json
{"dist": "normal", "mean": 18, "std": 0.6, "min": 17, "max": 21}
{"dist": "gev", "shape": 0.1, "loc": 12, "scale": 6, "min": 1, "max": 80}
```

`std: 0` gives a fixed value. The GEV `shape` is ξ (ξ > 0 heavy upper tail,
ξ = 0 Gumbel, ξ < 0 bounded above), i.e. `k` of MATLAB `gevrnd(k, sigma, mu)`;
scipy's `genextreme` uses `c = -ξ`. Arrivals are drawn before energies, so
changing the energy distribution leaves the arrivals unchanged.

Defaults: arrival N(18 h, 0.6 h) in 17-21 h, as in the former MATLAB model;
energy GEV(ξ 0.2, loc 3.4, scale 2.0) in 0.5-60 kWh, i.e. mean 5.1, median
4.2, 99th percentile 18.6 kWh per vehicle and day (a median session of 23 min
at 11 kW). The mean is the daily driving of a car charged at home: 30.0 km
per resident and day in Switzerland, 69 % of it by car (FSO mobility
microcensus 2021), 1.56 persons per car (2015) and ~0.54 cars per resident
give ~25 km per car and day, at ~0.2 kWh/km at the plug; the shape (moderate
upper tail) is a modelling choice to calibrate on metered charging data. Until
2026-11-13 the energy was a fixed 44 kWh (4 h at 11 kW, the former MATLAB
model): ~220 km per car and day, more EV energy than household demand.

## What `generate` does

Each stream comes from one model in `scengen/models/` (see *Models* below);
`generate` runs the models whose block is in the scenario configuration.

1. **Allocation**, one column per model and connection. Nominal demand:
   `demand_factor` × the connection's fuse-rated power; no national figure,
   so neither population nor a split comes into it. PV and EVs, in two steps,
   both named in the configuration:
   - *national → region*, `sfoe.to_region`. `population`: the national
     figure × the region's population in the scenario year
     (`../data/lv_grids/region.json`) / `population_national`. The only
     method so far.
   - *region → connections*, `pv.split` and `ev.split`, each its own: the
     regional total is split between networks in proportion to the sum of
     their connections' weights, and within a network in proportion to each
     connection's weight. `fuse`: the weight is the connection's fuse-rated
     power (PLmax), the port of the MATLAB `allocate_PV_EV_SFOE` and the
     default; `connections`: the same weight for every connection. EVs are
     integers (largest remainder at both levels).

   `scenario.json` records both (`to_region`, `region_share`, `pv_split`,
   `ev_split`). A new split method is one entry in `SPLITS` of
   `scengen/models/common.py` (a function connections → weights).
2. **Series per connection**, 3-phase kW, each stream in its own sign (demand and EV
   consumption positive, PV production positive):
   - demand: the connection's nominal demand (Q at the power factor of its
     fuse rating) times a synthetic household day from the demand model (Gaussian mixture
     fitted on HEAPO smart-meter data, Grammatikos/Ali/Sossan 2026): one
     household cluster per connection, one day draw per connection and day;
   - PV: the connection's kWp times the normalised yearly profile (`../data/pv/`, pvlib,
     Sion, 35° south; per unit of installed DC peak);
   - EV: each vehicle charges once a day at `charger_kw` from its arrival
     until its energy is delivered (power as step averages, so each
     session delivers exactly its energy); arrival and energy drawn per
     vehicle and day; vehicles summed per connection.
   Seeds are `(network number + seed_offset, day)`, so a network keeps its
   realisation across scenarios with the same offsets and a day does not
   change with the horizon.
3. **Products**: the calendar is the year of the PV profile file; the daily
   product is the yearly series on the representative PV day (the real day
   closest to the season's mean shape, 2019-09-17 for `all`), so the two are
   consistent.

## Models (`scengen/models/`)

One module per stream, all with the same interface (`models/__init__.py`):

| | |
|---|---|
| `NAME`, `SIGN` | config block and stream name; `load` (consumption positive) or `generation` |
| `REQUIRED`, `OPTIONAL`, `NATIONAL` | the keys of the model's config block, and the national figures (keys of `sfoe`) it scales to the region |
| `allocate(connections, cfg, national)` | adds the model's column per connection to `allocation.csv` (`nominal_demand_kw`, `pv_kwp`, `ev_count`), returns its totals; `national.to_region(key)` is a national figure scaled to the region (by `sfoe.to_region`), `common.split(connections, total, cfg["split"])` splits it over the connections |
| `prepare(cfg, step_min)` | once per run: read data, check settings; returns the model's state (a small dataclass) |
| `series(state, connections, days, net_num)` | one network's series per connection and column (`<NAME>_kw`, optionally `_kvar`), `[connections x days x steps]` |
| `expected(state, rows, days, samples)` | level `nl4`: what `series` summed over many connections converges to, per row of the allocation summed per HV/MV substation, `[rows x days x steps]`; `samples` sizes any Monte Carlo expectation |

`demand` and `pv` are required (the PV profile file gives the year and the
day of the daily product); further models are optional, so configurations without the
block of a newer model stay valid. To add one, e.g. heat pumps: write
`models/heat.py` with this interface, append it to `MODELS`, add a `heat` block to `scenario_defaults` in
`config.json` (and to the scenarios that should have it). `scenario.json`
then lists it under `streams`, and `../lv-screening` adds a
`demand+pv+ev+heat` case, its peak and energy columns, the HV/MV sums and the
dashboard curves without code changes. (Checked on 2026-10-13 with a
throwaway constant model through generation, screening, aggregation and
dashboard.)

## Output (`output/<name>/<level>/`)

One folder per product, named by the Swiss network level (Netzebene / niveau
de réseau) where the series are injected; `generate --level` picks it, the
scenario configuration is the same for both:

| level | where | what |
|---|---|---|
| `nl7` (default) | LV connections | per-connection daily series, per-network yearly sums (one file per network) |
| `nl4` | HV/MV substations, 65/16 kV | the allocation summed per substation, expected series (one file for all) |

### `nl7`: LV connections

| file | content |
|---|---|
| `allocation.csv` | one row per connection: `network_id, node, plmax_kw, qlmax_kvar, nominal_demand_kw, pv_kwp, ev_count` |
| `networks.csv` | per network: connections (`n_nodes`), fuse-rated peak, nominal demand, PV kWp, EVs |
| `pv_day.csv` | the normalised PV day of the daily product |
| `daily/<network_id>.csv` | one row per step (`step`, `hour`), one column per connection and stream: `<node>:demand_kw`, `<node>:demand_kvar`, `<node>:pv_kw`, `<node>:ev_kw` (`<node>:<stream>_kw` / `_kvar` in general); all-zero columns omitted |
| `yearly/<network_id>.csv` | `time, demand_kw, demand_kvar, pv_kw, ev_kw` (one column per stream column) summed over the network, at `yearly.step_min` (8760 rows hourly) |
| `scenario.json` | `streams` (name -> `load` / `generation`, the contract read by the screening), `grid` (region and the population used), `demand_factor`, totals (regional and allocated; `to_region`, `region_share`, `pv_split`, `ev_split`), PV day, the representative day of each season (`pv_season_days`, read by the scenario browser), sizes, hashes of the configuration (its content, whatever the layout of `config.json`) and of `allocation.csv`, version, timing |

Consumers: `../lv-screening` (`python -m lvgrid screen --scenario <name>`)
reads `nl7/daily/`; MATLAB reads any of the files with `readtable`
(`VariableNamingRule='preserve'` keeps the `node:stream` headers). The
`yearly/` files feed energy balances and the subtransmission view.

### `nl4`: HV/MV substations

The same scenario at the 11 HV/MV substations (`scengen/substations.py`),
for load flows of the 65 kV grid. The `nl7` allocation is summed per
substation (`grid.networks.hvmv`, from `../data/mv/lv_to_hvmv.csv`); the
splits are proportional, so a substation gets exactly the sum of its
connections' shares. Each model's `expected` then gives the series a sum of
thousands of connections converges to:

- PV: exact (linear in kWp, one profile for every connection);
- demand: summed P_max × the expected household day (mean of
  `nl4.expectation_samples` draws per cluster, weighted by the cluster
  probabilities); Q exact, since P_max is proportional to the fuse rating;
- EV: EV count × the expected charging of one vehicle (mean of
  `nl4.expectation_samples` simulated sessions).

| file | content |
|---|---|
| `allocation.csv` | one row per substation: `hvmv, code, name, city, mva, n_networks, n_connections, plmax_kw, qlmax_kvar, nominal_demand_kw, pv_kwp, ev_count` |
| `daily.csv` | one row per substation and step: `hvmv, step, hour, demand_kw, demand_kvar, pv_kw, ev_kw, net_kw, net_kvar` (net = loads − generation, > 0 drawn from the 65 kV grid) |
| `yearly.csv` | the same over the year at `yearly.step_min`: `hvmv, time, ...` |
| `pv_day.csv` | as in `nl7` |
| `scenario.json` | as in `nl7`, plus `level`, `n_substations`, `expectation_samples` and `unmapped` (the networks without a substation, left out, and their totals) |

Against the `nl7` yearly files of sc1_2040 summed per substation (2026-11-14):
PV identical; demand energy within 0.7 % and hourly correlation 0.94-0.99;
EV energy within 0.3 %. The yearly peak is 5-12 % lower for demand and
3-6 % for EV: `nl4` is the expected day, while the drawn year's maximum
also carries the random fluctuation of 365 independent days. Not included,
as in `nl7`: LV and MV losses, MV-connected customers and generators.

Small print: EV sessions are cut at midnight (0.002 % of the EV energy with
the defaults; it grows with late arrivals and heavy-tailed energies); the
demand model has no calendar, so the yearly demand is 365 independent days
without seasonality; existing PV in
the grid data is not added to the scenario PV (the SFOE total is taken as
the total).

## Scenario browser (`dashboard`)

A local Dash app (`scengen/dashboard/`) on everything a scenario produced:
demand, PV, EV and any further stream listed in `scenario.json`. Net load =
loads − generation; below zero the network feeds back through its
transformer (reverse flow). Pick a scenario, and optionally a second one
under *compare with*. It shows the `nl7` level. A badge tells whether `output/<name>/nl7/` still matches
`scenarios/<name>/config.json` (hash in `scenario.json`) and the current
generator version, or has not been generated; the configuration is one click
away. It never starts a generation; reload the page after one.

- **Overview**: key figures (energy per stream, kWh per connection, PV
  full-load hours and its energy at the realistic capacity factor, kWh per
  vehicle, regional peak and largest reverse flow, networks above their
  transformer rating, networks with reverse flow); energy per season and over
  the year (each stream, total load, PV and PV at the realistic capacity
  factor); the regional day (representative, the representative day of each
  season, peak, reverse-flow or mean day; streams stacked, net load, and the
  compared scenario's net load); the hourly year
  with a range slider; energy per month; duration curves; the net-load
  heatmap (day × hour, red = reverse flow).
- **Networks**: every network on two selectable axes (default: largest
  reverse flow against peak net load, both in % of the transformer, with the
  100 % lines) and a sortable, filterable table (energy per stream, peak and
  lowest net load, transformer loading, reverse-flow hours; above 100 % in
  red). A point or a row opens the network.
- **Network**: fuses, transformer, PV, EVs, energy and peaks; a day of its
  streams against the transformer rating (the representative day at the
  daily step, or a season's, the peak, reverse-flow or mean day from the
  yearly file);
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
scengen/               grid, scenario, injections (in-memory `prepare`), output (file writer), substations (level nl4);
                       demand_check (the rule and sanity check of demand_factor); config (paths, LEVELS), clearsky
scengen/dashboard/     the scenario browser: constants, data, figures, app
scengen/models/        one module per stream: demand, pv, ev (+ common allocation helpers)
config.json            demand-model fit settings, the basis of demand_factor, nl4 settings, scenario defaults, SFOE table
scenario.ipynb         the notebook: grid, scenario, allocation, preview in memory, write, generate
demand_factor.ipynb    notebook: where demand_factor comes from (the rule on the peak, the sanity check on the energy, the smoothing of the demand model)
scenarios/<name>/      config.json per scenario (tracked)
output/<name>/<level>/ generated files, one folder per network level: nl7, nl4 (ignored)
tests/                 pytest smoke tests (test_scengen.py)
(the one-off exports of the inputs are in ../data/tools/, see ../data/README.md)
```
