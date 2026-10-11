# sanity_check: LV portfolio sanity check and scenario load flows

> **Superseded (2026-10-11):** stages 4–7 of this toolbox are re-implemented in Python in [`../../lv-screening/`](../../lv-screening/README.md), which reads the same `data_v2.mat` (exported once to CSV) and reproduces the one-shot classification. Stages 1–3 (reading the OIKEN Excel files and patching line/transformer parameters) are still only here.

This MATLAB toolbox screens the low-voltage (LV) networks of Sierre and Sion (1,116 networks, OIKEN data) in two steps:
1. **One-shot load flow:** a simple snapshot to catch data or model errors.
2. **Temporal load flow:** 24 h at 15 min, with stochastic household demand plus PV and EV allocated from the SFOE 2030/2040 scenarios. It shows which networks need reinforcement.

Results are written as Markdown pages to a static MkDocs website (`sanity-check-website/`).

This repo is the entry point of the data analysis. The companion repo `tech-selection` (storage/technology selection) shares part of the code in `util/` and `grid/`; both will later be merged into `lv-grid-core-util`.

---

## Quick start

**Requirements:**
- MATLAB (tested with R2025b) with the Statistics and Machine Learning Toolbox (needed for the GMM demand model).
- Python with `mkdocs`, only for the website.

1. Get the household training data `load_consumption_train_heapo.mat` (160 MB, not in git) and place it in `util/`. A copy is in `tech-selection/util/`.
2. Open `main.m` and edit **only** the `USER SETTINGS` block: choose the stages and the scenario.
3. Run `main.m` from the repo root. It adds `util/`, `grid/` and the data folders to the path and leaves out `test_files/`.
4. Build the website:
   ```
   cd sanity-check-website
   mkdocs serve
   ```

**Typical run for one scenario.** Stages 5–6 don't depend on the scenario, so you only rerun them when the data or config changes. For a second scenario, run only stage 7.
```matlab
settings.oneshot_loadflow    = true;   % stage 5
settings.oneshot_lf_analysis = true;   % stage 6
settings.temporal_loadflow   = true;   % stage 7
settings.scenario            = 'sc1_2040';   % sc1/sc2/sc3 x 2030/2040
settings.networks            = 'healthy';    % networks that passed the one-shot check
```

**Test on a few networks** instead of the full portfolio, which takes about 1–1.5 h per scenario:
```matlab
temporal_loadflow_main(data_v2, 'sc1_2040', 'healthy', ["LV_Grid_92436","LV_Grid_92432"])
```

At the start of stage 7, MATLAB asks whether to empty the result folders. **Continue** deletes the previous results of that scenario.

---

## Pipeline (`main.m`)

| Stage | What it does | Main function | Produces |
|---|---|---|---|
| 1 | Read the OIKEN Excel files | `read_data_sierre/sion` | `network_data/mat_data/*_dat.mat` (raw) |
| 2a/2b | Diagnose line, substation and transformer parameters | `line_parameter_analysis`, `transformer_parameter_analysis` | `output/transformer_fill_table.mat`, website pages |
| 3 | Patch missing line and transformer parameters | `patch_grid_data` | `data_v2.mat` (**processed data used by stages 4–7**) |
| 4 | DER (PV) penetration overview | `analyze_power_mix_raw_ALL_LV` | Website page |
| 5 | One-shot load flow on all networks | `LV_SanityCheck` | `output/all_LV_oneshot_result.mat` |
| 6 | Classify networks: converged / healthy / violation | `analyze_loadflow_results` | `output/one_shot_lf_network_classification.mat` |
| 7 | Temporal load flow for one SFOE scenario | `temporal_loadflow_main` → `run_temporal_network` | `output/scenario_<sc>/temporal_results/*.mat`, website pages |

Stages 1–3 only need rerunning when OIKEN delivers new data.

---

## How the load flows are set up

**Network model** (`combined_lv_sub_SFOE`, `get_grid_SFOE`):
- Each MV/LV substation plus its LV grid becomes one radial network.
- The MV side of the transformer is the slack (node 1, 1.0 pu).
- Transformer impedances are converted to the common base (Sb = 100 kVA, Vb = 230 V).
- Closed LV switches are merged into the busbar; feeders behind open switches are pruned.
- The model is single-phase equivalent: all powers are divided by 3.

**One-shot (stage 5).** Every connection is loaded at the same moment:
- load = `demand_factor` × fuse rating = **6 %**, the DSO planning value;
- PV = `generation_factor` × installed PV = **0.7**.

It is a screening check for gross errors, not a realistic operating point.

**Temporal (stage 7).** One synthetic day per network, 96 × 15 min, built by `build_temporal_profiles`:
- **Base load:** stochastic household profiles from a GMM model trained on Swiss smart-meter data. The data is HEAPO, with heat pumps, PV and EV removed. The method is Grammatikos, Ali & Sossan, *A Stochastic Model for Generating Synthetic Daily Household Electricity Demand Profiles from Smart-Meter Data*, ACM SIGENERGY EIR, 2026.
  - Each node gets a random household cluster and a sampled day, scaled by 6 % of its fuse rating (Eq. 7 of the paper).
  - The model is fitted once per run and cached in `output/demand_model.mat`.
- **PV:** SFOE-allocated kWp per node × a clear-sky day profile (`pv_profiles_year.mat`).
- **EV:** SFOE-allocated number of EVs per node. Each EV charges at 11 kW for 4 h, arriving between 17:00 and 21:00 (normal distribution, mean 18:00, σ 0.6 h).
- **Seeds:** fixed per network, so each network gets the same base load in 2030 and 2040. The scenarios then differ only in PV and EV.
- **Violations:** voltage < 0.9 or > 1.1 pu, line loading > 100 %, transformer loading > 100 %.

All settings are in `util/general_config.json`: per-unit bases, demand and generation factors, the SFOE scenarios, and the `demand_profile`, `pv_profile` and `ev_profile` blocks.

---

## Reading the results: current assumptions and known limitations

- **EV load is an upper bound.** With the current settings about 98 % of EVs charge at full power at the same time (around 19:00), and each charges 44 kWh/day. That is much more than typical daily use (about 10 kWh). Evening undervoltage, overloads and transformer congestion are therefore driven mainly by EVs. The EV parameters are under review.
- **Base load is low.** Scaling to 6 % of the fuse rating gives a median of about 2,000 kWh/yr per household. Measured HEAPO households average about 3,000 kWh/yr.
  - The 6 % is a planning value for simultaneous load. Measured households reach about half of it, even on their highest day.
  - The demand model samples nodes independently, a limitation the paper itself states. So the coincident peak of many houses is somewhat below the measured one.
- **PV and EV totals in the temporal report are about 15 % too high.** The allocation copies each node's values onto parallel branches and the report sums every row. The load flow itself counts each node once. This is a reporting fix still to be made.
- **Data issues found, not yet fixed:**
  - 2 networks have no transformer in the substation data.
  - A few multi-transformer networks show unrealistic currents (near-zero impedance loops).
  - 34 networks have branches stored in the upstream direction.
  - The one-shot check removes most of these from the temporal analysis.

---

## Repository layout

```
main.m                    entry point (user settings at the top)
data_v2.mat               processed grid data (stage 3 output, used by stages 4-7)
util/                     analysis functions + general_config.json + profile data
grid/                     load flow solver (loadflow_FPIs_convergance)
network_data/             raw OIKEN Excel files and their .mat versions
output/                   results (.mat); output/scenario_*/ is not tracked by git
sanity-check-website/     MkDocs site; docs/ is generated by the pipeline
test_files/               archived / unused code (not tracked, not on the path)
```

## Data not in git

| File | Size | Where to get it |
|---|---|---|
| `util/load_consumption_train_heapo.mat` | 160 MB | `tech-selection/util/`, or rebuilt from the HEAPO dataset (Brudermueller et al., 2025) |
| `output/scenario_*/` | about 1,000 files per scenario | Regenerate with stage 7 |
| `output/demand_model.mat` | Small | Created automatically on the first stage 7 run |

## Branches

- `main`: the version before the sync with tech-selection (May 2026).
- `develop`: the current version. It has the new demand, PV and EV generators from tech-selection, the fitted-once demand model, the transformer-orientation fix and the code cleanup.
