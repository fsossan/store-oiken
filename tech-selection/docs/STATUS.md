# Status and handoff, 2026-10-10

Read this first when picking the project up on another machine. It records what
changed on 2026-10-10, what was verified where, what to run next, and the plans
that were agreed but not built. The detailed design notes are in
`docs/DEVELOPMENT_NOTES.md`; the user-facing overview is `README.md`.

## 0. Update 2026-10-11: stage 1 and the screening moved to Python

The plans of sections 6 and 7 were implemented in Python instead, in
`../lv-screening/` (see its README): data sanity check (one-shot load flow),
scenario injections (demand GMM, PV representative day, EV), daily load-flow
screening with three nested cases, HTML dashboard with topology maps, node
coordinates recovered from the DSO database backup, and a clear-sky PV
utility. `run_portfolio_report` / `build_nodal_injections` here remain the
inputs of the MILP; the Python screening is the place to derive the per-
scenario violation list (`violation_ids_<scenario>.mat` is still generated
nowhere in MATLAB). Computation of the MILP stays in MATLAB.

## 1. State of the repository

**Nothing from 2026-10-10 is committed.** All changes are in the working tree
(the folder moves are staged as renames via `git mv`). Before moving machines
through git:

```bash
git add -A
git commit -m "Restructure folders, fix review findings, add stage-1 injections + portfolio report"
```

Copying the folder instead of using git also works; `results/` (10 GB of
old outputs) and `data/external/` (163 MB) are git-ignored and must be copied
by hand if needed.

What changed today, in order:

1. **Folder restructure.** `src/{grid,util}` for code, `config/` for the three
   JSON files, `data/{raw,external,derived}` for inputs, `results/` for every
   output (git-ignored). `setup_paths.m` + `src/util/project_paths.m` replace
   `addpath(genpath(pwd))`; nothing depends on the current directory any more.
   Old outputs moved unchanged to `results/legacy_output/` and
   `results/experiments/`. The former `CLAUDE.md` became
   `docs/DEVELOPMENT_NOTES.md`. Four unused `LV_data` files were deleted.
   Line endings normalised to LF with a `.gitattributes`.
2. **Run folders.** `run_ess_selection_portfolio` now writes to
   `results/<timestamp>_<scenario>/` with a config snapshot; nothing is ever
   overwritten. `run_opts.run_dir` resumes a folder.
3. **Nine review fixes** (details in the git diff and the function headers):
   curtailment cost in the relaxed objective; Gurobi settings re-enabled behind
   `solver.apply_gurobi_settings`; PV/EV-subset assertion in
   `preprocess_network`; charge/discharge loss formulas in `analyze_losses`;
   required C-rate definition in `explain_tech_selection`; scatter labels in
   `analyze_tech_selection`; unit factor centralised in `kw_per_pu_of`
   (`cfg.units.kW_per_pu`, `out.meta.kW_per_pu`); dead config keys removed;
   shadowed names in `getSCs` / `loadflow_FPIs`.
4. **Stage 1: injections and portfolio report.**
   - `fit_load_gmm` / `load_gmm_model`: demand GMM fitted once per parameter
     set, cached in `data/derived/load_gmm/` as plain arrays.
   - `sample_load_gmm`: base-MATLAB sampler on seeded substreams; day d of
     node i is the same for any horizon length.
   - `build_nodal_injections` (ex `build_temporal_profiles`, kept as wrapper):
     adds `.magnitudes`, `.calendar` (incl. the PV date used), `.seeds`.
   - `summarize_network_injections` + `run_portfolio_report`: one row per
     network, CSV/MAT/JSON/PNG in `results/report/<timestamp>_<scenario>/`.
   - `config.visualization.plot_topology` switches the per-network topology
     figure off (the report sets it to false).

**Demand realisations differ from all results produced before 2026-10-10**, by
design: one cached fit instead of a per-solve refit, and seeded draws. The old
numbers are reproducible only from `results/legacy_output/`.

## 2. Verified where

| Item | Mac (R2025b, no Stats toolbox, no Gurobi) | Windows (Stats toolbox + Gurobi) |
|---|---|---|
| setup_paths, context loading, allocation, violation-list fallback | passed | to do |
| get_grid_SFOE, build_nodal_injections (demand off), PV + EV | passed on 101/230/92713 | to do with demand on |
| run_portfolio_report, CSV/PNG, slack flag on 92713 | passed | to do with demand on |
| preprocess_network: load flow + sensitivities + subset assert | passed on LV_Grid_101 | to do |
| run folder, log, error capture | passed (solver missing -> `error/`) | to do |
| sample_load_gmm properties (deterministic, nested, rng untouched) | passed on a synthetic model | - |
| **fit_load_gmm** | cannot (no toolbox) | **to do, once** |
| **MILP solve, Gurobi settings call** | cannot (no Gurobi) | **to do** |

## 3. First commands on the other laptop

```matlab
cd <repo>
setup_paths;
tbl = run_portfolio_report('sc1_2030', "LV_Grid_101");   % fits + caches the GMM (~1 min), then 1 row
tbl = run_portfolio_report('sc1_2030', "PORTFOLIO");     % 236 networks, a few minutes
main                                                      % MILP on LV_Grid_101
```

- If the first solve fails with an empty `gurobi()` error, the CVX Gurobi shim
  needs the one-line fix described in the Gurobi note of
  `docs/DEVELOPMENT_NOTES.md`, or set `solver.apply_gurobi_settings` to false.
- After the fit, commit `data/derived/load_gmm/*.mat` (a few MB): any machine
  with it can generate demand without the 163 MB training file or the toolbox.
- Sanity check on the report: `demand_peak_over_trafo` across the portfolio is
  the first direct test of the 6 % demand factor. On LV_Grid_101 the eight EVs
  alone, with no base demand, already push six nodes below 0.87 pu and one
  line to 2.45x its rating in the evening.

## 4. Decisions taken

- Computation stays in MATLAB; Python only for visualisation / a dashboard.
- Terminology: a *profile* is a dimensionless shape; *injections* are the
  per-node power series the load flow consumes.
- `experiments/` is tracked again (code + write-ups only; outputs live under
  `results/experiments/`). Add `experiments/` back to `.gitignore` if you want
  it local-only. `experiments/archive/` stays ignored.
- The portfolio list (`data/derived/violation_ids_sc1_2040.mat`) has no
  generator in the repo; `load_ess_selection_context` falls back to it with a
  warning for other scenarios. Stage 2 will regenerate it per scenario.

## 5. Open items for the owner

- Provenance of the grid data (operator, date, usage restrictions) and the
  source of `load_consumption_train_heapo.mat`: both blank in `data/README.md`.
- Whether `old-code/` (10k lines, archived) and `docs/load_simulator_final.pdf`
  should be in the shared repo.
- Modelling caveats not fixed: cyclic SOE constraint spans the whole horizon
  when `days > 1`; slack bus is not internal node 1 for `LV_Grid_92713` (results
  wrong); the base and verification load flows run a fixed 20 undamped
  iterations; demand is 6 % of fuse rating with constant power factor and does
  not depend on the scenario (no demand growth, no heat pumps).
- The OFEN scenario rows only feed PV capacity and EV count into the model;
  wind, heat pumps, total demand and installed capacity are unused.

## 6. Stage 2 plan: load-flow screening (agreed, not built)

- `screen_network(grid, inj, cfg)`: per-timestep load flow only (no
  sensitivities), damped solver, keep V [N x T], |I| [L x T], slack S, and
  convergence per step.
- Three cases per network: demand only, demand + PV, demand + PV + EV, to
  attribute each violation to its driver.
- Metrics per network and case: convergence share, min/max voltage with node,
  steps under/over, worst line loading with line id, transformer peak loading,
  violation hours, severity (sum of excess over the limit).
- Outputs: `results/screening/<scenario>/screening.csv`, per-network detail
  `.mat`, and `violation_ids_<scenario>.mat` from a stated rule (converged,
  single transformer, any violation), promoted into `data/derived/`.
- QA in the same pass: slack index, unreachable nodes, zero-impedance lines,
  ampacity vs `Section_mm2_` / `Cu_Al` (columns in the grid file nobody reads),
  transformer rating vs summed PLmax.
- `parfor` over networks; minutes for the full portfolio once the GMM is cached.
- Reuse: `get_grid_SFOE`, `build_nodal_injections`,
  `loadflow_FPIs_convergance`, `report_violations`, `plot_gm_temporal_profiles`.

## 7. Dashboard plan (agreed, not built)

- `tools/report_dashboard.py`: pandas + Plotly, takes a report folder (later
  also a screening folder), writes one self-contained HTML next to the CSV. No
  server; the repo's `.venv` is the place for the two dependencies.
- Contents: sortable/filterable network table; the histograms as interactive
  plots; scatter of PV kWp vs demand peak with transformer rating as marker
  size; later colour by violation type from stage 2.
- Comparison mode: two report folders (e.g. sc1_2030 vs sc1_2040) side by side
  or as per-network deltas.
- Build it after the first real report (with demand) exists, so the plots are
  tuned on real numbers; the three-row smoke-test CSV in `results/report/` has
  demand switched off.

## 8. Later improvements discussed

- EV: energy-based sessions (daily km -> kWh, charge until delivered), weekday/
  weekend arrival mix, charger power mix, day-to-day variation for `days > 1`.
- PV: bring the pvlib step into the repo (`tools/`), PVGIS TMY at a stated
  Sion coordinate and orientation (the grid data has no coordinates), writing
  the same `pv_profiles_year.mat`.
- Calendar coupling: pick the PV day first, then sample demand with the same
  season/weekday mask and EV with the same weekday flag.
- Demand calibration: replace the flat 6 % of fuse rating with an
  after-diversity maximum demand curve, and report the result.

## 9. Files touched today (for orientation)

New: `setup_paths.m`, `README.md`, `data/README.md`, `docs/DEVELOPMENT_NOTES.md`,
`docs/STATUS.md`, `.gitattributes`, `src/util/{project_paths, resolve_data_file,
kw_per_pu_of, fit_load_gmm, sample_load_gmm, load_gmm_model,
build_nodal_injections, summarize_network_injections, run_portfolio_report}.m`.

Rewritten: `main.m`, `src/util/{load_ess_selection_context,
run_ess_selection_portfolio, generate_load_profile, build_temporal_profiles}.m`.

Patched: `src/util/{allocate_PV_EV_SFOE, solve_network_tech_selection,
load_pv_profile, solve_ess_milp, analyze_losses, explain_tech_selection,
analyze_tech_selection, analyze_curtailment,
analyze_charge_discharge_exclusivity, run_seq_lin_loop_ess,
build_network_result, load_ess_selection_config, preprocess_network,
combined_lv_sub_SFOE}.m`, `src/grid/{getSCs, loadflow_FPIs, linear_grid_model,
get_grid_SFOE}.m`, both config files, all `experiments/*.m` (path setup only).
