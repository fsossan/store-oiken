# tech-selection

Optimal siting, sizing and technology selection of battery energy storage
(Li-ion vs Na-ion) across a portfolio of low-voltage distribution networks in
the Sion/Sierre region (Valais, Switzerland), under the Swiss Federal Office of
Energy (SFOE) 2030/2040 energy-transition scenarios.

For each network one mixed-integer linear program chooses where to install
storage, how large to make each unit (energy and converter rating), which
technology to use, and its dispatch over the horizon, subject to linearised
voltage, line-current and transformer limits. The AC load flow enters through
sequential linearisation around a fixed-point load-flow operating point, and
every solution is re-verified with the nonlinear load flow.

## Requirements

- MATLAB R2022a or newer. Base MATLAB covers the grid construction, the
  injections, the portfolio report and the load flows.
- Statistics and Machine Learning Toolbox, only to **fit** the demand model
  (`fitgmdist`); sampling from the cached fit needs base MATLAB. (The legacy
  sampler kept for `experiments/test_load_profile_determinism.m` needs the
  toolbox and R2024a.)
- [CVX](http://cvxr.com/cvx/) with **Gurobi** as the registered solver.
  `src/util/solve_ess_milp.m` sets `cvx_solver gurobi`; without Gurobi, CVX
  falls back to SDPT3, which cannot handle the binary variables and fails
  opaquely.
- Gurobi parameters (MIPGap, tolerances) live in `config/sizing_cfg.json` under
  `solver.gurobi` and are passed through `cvx_solver_settings`. Stock CVX 2.2's
  Gurobi shim has an indexing bug that makes any custom setting fail with an
  empty `gurobi()` error; the one-line shim fix is in the Gurobi note of
  `docs/DEVELOPMENT_NOTES.md`. Alternatively set `solver.apply_gurobi_settings`
  to `false` to run with Gurobi's defaults (MIPGap 1e-4).
- Optional: `matlab2tikz` on the path for TikZ figure export in
  `experiments/tech-selection-result-analysis/`.
- Input data: see [data/README.md](data/README.md). One required file (163 MB)
  is not in git and has to be placed in `data/external/` first.

## Running

```matlab
cd /path/to/tech-selection      % or: run('/path/to/tech-selection/setup_paths.m')
main
```

`main.m` owns the run knobs:

| Knob | Meaning |
|---|---|
| `scenario`     | key of `config/general_config.json` → `scenarios` (e.g. `sc1_2030`, `sc1_2040`) |
| `network_id`   | one id, a string array of ids, or `"ALL"` for the violation-flagged portfolio |
| `horizon`      | `[]` = full day, or e.g. `1:32` for a short debug window |
| `enable_plots` | diagnostic figures (temporal profiles, tech selection, losses, voltages, ...) |
| `run_opts`     | `MAX_LIN_ITER`, `skip_solved`, 4-way multi-instance split, `run_dir` |

Simulated day count and time step live in `config/sizing_cfg.json` under
`horizon` (`days`, `Ts_h`); technology parameters in
`config/technology_cfg.json`; per-unit bases, demand factors and the SFOE
scenario table in `config/general_config.json`.

`setup_paths()` puts `src/` (and `experiments/`) on the MATLAB path, keeps
the archived code (now `../obsolete/tech-selection-old-code/`) off it, and returns the project folder layout. Every file the
pipeline reads or writes is resolved through `src/util/project_paths.m`, so
nothing depends on MATLAB's current directory.

## Repository layout

```
main.m, setup_paths.m   entry point and path setup
config/                 the three JSON configuration files
data/                   inputs (see data/README.md)
  raw/                    tracked, read-only: LV grid portfolio, yearly PV profile
  external/               not in git: demand training data (163 MB)
  derived/                tracked caches derived from raw data, incl. load_gmm/
                          (the fitted demand model; lets a clone run without the 163 MB file)
src/grid/               power-system primitives: grid construction, fixed-point
                        load flow, sensitivity coefficients, load-flow verification
src/util/               pipeline, profile generators, MILP formulation,
                        analysis and plotting functions
experiments/            study scripts and their write-ups; their outputs go to
                        results/experiments/
results/                everything the code writes; git-ignored, created on demand
docs/                   development notes and the load-simulator report
```

## Results

Each call to `run_ess_selection_portfolio` (what `main.m` runs) creates one
folder and writes only into it:

```
results/<yyyymmdd_HHMMSS>_<scenario>/
  config_snapshot.json       all configs, run options, MATLAB version, git commit
  allocation_<scenario>.mat  PV/EV allocation used for this run
  run_log.txt                one line per network (START / SOLVED / THRESH / SUBOPTIMAL / FAILED)
  solved/LV_Grid_<n>.mat     full result struct `out`, including out.cfg
  thresh/, subopt/, error/   networks that did not reach a solved state
  figures/                   temporal-profile PNGs (enable_plots)
  all_dispatch_logs.mat
```

Nothing is overwritten across runs. To resume an interrupted run, or to let
several multi-instance MATLAB sessions write into the same folder, set
`run_opts.run_dir` to that folder (and `skip_solved = true` to skip networks
already present in `solved/`).

Saved results are self-contained: the `analyze_*` functions in `src/util/`
take `(out, cfg)` with `cfg = out.cfg`, so a result can be re-analysed later
regardless of the current config files.

Outputs produced before the 2026-10-10 restructure were moved unchanged to
`../obsolete/tech-selection-legacy-output/` (the former `output/` tree) and
`results/experiments/` (the former `experiments/results/` and
`experiments/tech-selection-result-analysis/{results,figures}/`).

## Stage 1: injections and the portfolio report

A **profile** is a dimensionless shape over the day (the PV year in per unit
of kWp, the demand GMM's cluster means, the EV charging block). The
**injections** are those shapes multiplied by each node's magnitude: the power
at every node per time step that the load flow and the MILP consume.
`src/util/build_nodal_injections.m` builds them for one network and is
deterministic for a given grid, scenario and config (demand and EV draw from
their own seeded streams), so the report below and a MILP solve see identical
inputs.

The demand model is fitted once per parameter set and cached in
`data/derived/load_gmm/` (`load_gmm_model`); only the first run needs the
163 MB training file.

```matlab
tbl = run_portfolio_report('sc1_2030');                 % all 1116 networks
tbl = run_portfolio_report('sc1_2030', "PORTFOLIO");    % the violation-flagged portfolio
tbl = run_portfolio_report('sc1_2030', "LV_Grid_101");
```

writes `results/report/<timestamp>_<scenario>/portfolio_report.csv` with one
row per network: node, line and transformer counts, transformer kVA, fuse-rated
and realised peak demand, daily energy, PV kWp and peak, EV count and peak,
peak transformer import and export, and the calendar day each stream used
(see `summarize_network_injections` for the full column list), plus a
histogram sheet. No load flow is run at this stage.

## Pipeline

```
main.m
└─ load_ess_selection_context(scenario)        data + config + PV/EV allocation + portfolio list
   └─ run_ess_selection_portfolio(...)         run folder, per-network loop, try/catch, saving
      └─ solve_network_tech_selection(...)     one network, no file I/O
         ├─ preprocess_network                 get_grid_SFOE → linear_grid_model
         │    └─ build_temporal_profiles       demand (GMM sampler), PV (representative day), EV;
         │                                     per-timestep loadflow_FPIs + getSCs → sensitivities
         ├─ check_voltage_guard
         └─ run_seq_lin_loop_ess               build_sensitivity_matrices → solve_ess_milp (CVX/Gurobi)
                                               → OPF_verification (nonlinear load flow)
                                               → build_network_result (+ analyze_* figures)
```

## Conventions worth knowing

- **Per unit**: `Sb = 100 kVA`, `Vb = 230 V`, single-phase. A pu energy or
  power times 300 is three-phase kWh or kW. The `analyze_*` functions and the
  run log hard-code this factor.
- **Node indexing excludes the slack bus.** Every N-space array (voltages,
  sensitivities, `out.grid.vmag_lin`) is indexed 1..N for topology nodes
  2..N+1. `out.sizing.demand_node_id` already carries the +1.
- **Signs**: nodal injections are negative for load, positive for generation;
  `B_plus` is charging (a load), `B_minus` discharging.
- **`gm.lm.Imag0` is a complex phasor**, not a magnitude; wrap with `abs()`.
- **Time axis**: `T = days * 24/Ts_h`, day-contiguous. `Ts_h` must equal the
  native resolution of the input data (15 min).
- **Best iteration** of the sequential linearisation is the one with the
  smallest voltage linearisation error, not the lowest cost.

## Current status and handoff

See [docs/STATUS.md](docs/STATUS.md) for what was verified on which machine,
the first commands to run after a move, open decisions, and the agreed plans
for the load-flow screening stage and the dashboard.

## Known issues

- The slack bus is not internal node 1 for 15 of the 1116 networks; of the
  236-network portfolio only `LV_Grid_92713` is affected, and its results are
  physically wrong, not just mislabelled.
- The cyclic state-of-energy constraint spans the entire horizon, not each
  day, so for `days > 1` the battery may drift between days.
- The portfolio list in `data/derived/` exists only for `sc1_2040`; other
  scenarios fall back to it with a warning.
- The base-case and verification load flows run a fixed number of undamped
  fixed-point iterations; a non-converged timestep stops that network with an
  error instead of producing a result.

See [docs/DEVELOPMENT_NOTES.md](docs/DEVELOPMENT_NOTES.md) for the full
design notes (struct layouts, every past fix and why, open questions).
