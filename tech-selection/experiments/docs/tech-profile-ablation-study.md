# Technology-selection case study: LV_Grid_230, short horizon

## Why this started

The paper's Results section needs a case study showing *why* ESS gets sited and *which* technology (LiIon vs. NaIon vs. either) the MILP picks, isolated from the confound of which loads are actually driving the violations. The design: a 3x3 ablation on a single representative network, crossing

- **profile composition** (baseline demand always on) — `PV` (demand+PV), `EV` (demand+EV), `PVEV` (demand+PV+EV)
- **technology availability** — `LiIon`-only, `NaIon`-only, `Both`

on `LV_Grid_230` (N=41, Nd=13, Npv=13), short horizon (`D=1`, T=96, native 15-min day), using the paper's exact/binary formulation (`opts.cha_dis_bin_activate=true`, the live default). This network was chosen because it has documented EV/PV-driven violations and was independently confirmed to converge 100% under the load-flow (all three profile compositions) — so none of the 9 runs risk hitting the hard-stop convergence guard added to `linear_grid_model.m`/`re_linearization.m` this session.

The script is [`experiments/run_tech_profile_ablation.m`](../experiments/run_tech_profile_ablation.m). It changes nothing on disk in `sizing_cfg.json`/`technology_cfg.json` — every axis is overridden in-memory on a per-call copy of `ctx.cfg`, so it's safe to run alongside someone else's own `main.m`/live-config run. Reproduce with:

```matlab
T = run_tech_profile_ablation("LV_Grid_230", "sc1_2040", false, "clearsky");   % or "measured"
```

## Reproducibility (verified, not assumed)

Before trusting a 9-run comparison, it mattered whether the *same* demand realization was used across all 9 (otherwise an apparent PV/EV/tech effect could just be demand noise). Traced and confirmed directly:

- `solve_network_tech_selection.m` calls `rng(1234 + net_num)` once, before anything else runs for that network.
- `build_temporal_profiles.m` always generates demand **first**, before PV and EV.
- `preprocess_network.m` has zero rng-consuming calls in between.

So every one of the 9 runs reseeds to the identical `rng(1354)` state before drawing anything random, and demand is drawn before the PV/EV toggle can matter — the demand realization is guaranteed identical across all 9 runs, with no manual caching needed. (Separately, `generate_nodal_scenarios_4.m`'s own `seed` argument was found to be *not* a full seed — see the corrected notes in `CLAUDE.md` and `util/generate_load_profile.m`'s docstring — but that doesn't affect this study since the pipeline's actual call order sidesteps the issue.)

## Technology definitions

Cost coefficients are identical for both technologies (`cE=300 CHF/kWh`, `cS=100 CHF/kW`, `cI=2000 CHF`); only C-rate and round-trip efficiency differ:

| | c_rate | eta_ch | eta_dis | Emax (pu) | Smax (pu) |
|---|---|---|---|---|---|
| LiIon | 1.1 | 0.90 | 0.90 | 40 | 40 |
| NaIon | 5.0 | 0.85 | 0.85 | 40 | 40 |

**Note:** `NaIon` is present in the repo's git history (commit `0ef0899`) but is currently missing from the live working-tree `util/technology_cfg.json` (only `LiIon` remains, apparently removed as part of an in-progress experiment). This study does not depend on the live file — `run_tech_profile_ablation.m` hardcodes both technologies' parameters directly — but if `technology_cfg.json` is meant to have both long-term, it should be restored.

**Cost-term flags used**: whatever the live `sizing_cfg.json` says at run time (not overridden), so this matches whatever formulation the rest of the portfolio is being solved with. At the time of this study: `min_loss=false`, `throughput_penalty=false`, `curtailment_activate=false`, `cha_dis_bin_activate=true`. This means the two technologies' efficiency difference (0.90 vs. 0.85) currently has **no cost consequence** in the objective — only C-rate and capex drive technology choice here. If the paper's narrative wants efficiency to matter, `throughput_penalty=true` needs to be turned on for a follow-up run.

## Key finding: PV and EV barely overlap in time on this network's realization

Before even comparing costs, a direct check of the generated profiles (`experiments/` scratch check, not saved) explains a pattern that shows up throughout the results below:

| series | PV active steps (of 96) | EV active steps (of 96) | overlap |
|---|---|---|---|
| measured | 45 (steps 28–72, ~7:00–18:00) | 22 (steps 71–92, ~17:45–23:00) | 2 steps |
| clearsky | 50 (steps 26–75, ~6:30–18:45) | 22 (steps 71–92, ~17:45–23:00) | 5 steps |

EV charging in this realization is predominantly an **evening/night** load (starts as PV is ending for the day), so PV generation and EV charging demand barely coincide. This is not a bug — it's a genuine feature of this demand+EV realization, and it's actually a useful point for the paper: it's precisely the kind of temporal mismatch that makes ESS valuable (only storage can time-shift daytime PV to cover the evening EV peak; PV alone structurally cannot).

## Results: `series="measured"`

| Profile | Tech | Status | Total cost (CHF) | Sites | LiIon / NaIon sites | E_tot (pu) | S_tot (pu) | Baseline Vmag viol. | Baseline Imag viol. |
|---|---|---|---|---|---|---|---|---|---|
| PV | LiIon | solved | 0 | 0 | — | 0 | 0 | 0% | 0% |
| PV | NaIon | solved | 0 | 0 | — | 0 | 0 | 0% | 0% |
| PV | Both | solved | 0 | 0 | — | 0 | 0 | 0% | 0% |
| EV | LiIon | solved | 28,447 | 3 | 3 / 0 | 0.219 | 0.092 | 4.88% | 0.41% |
| EV | NaIon | solved | 26,270 | 3 | 0 / 3 | 0.194 | 0.092 | 4.88% | 0.41% |
| EV | Both | solved | **25,351** | 3 | 2 / 1 | 0.184 | 0.092 | 4.88% | 0.41% |
| PVEV | LiIon | solved | 28,447 | 3 | 3 / 0 | 0.219 | 0.092 | 4.88% | 0.41% |
| PVEV | NaIon | solved | 26,406 | 3 | 0 / 3 | 0.195 | 0.095 | 4.88% | 0.41% |
| PVEV | Both | solved | **25,351** | 3 | 2 / 1 | 0.184 | 0.092 | 4.88% | 0.41% |

Raw results: `output/tech_profile_ablation_measured/` (per-combination `.mat`, `summary.csv`, `summary.mat`).

## Results: `series="clearsky"`

| Profile | Tech | Status | Total cost (CHF) | Sites | LiIon / NaIon sites | E_tot (pu) | S_tot (pu) | Baseline Vmag viol. | Baseline Imag viol. |
|---|---|---|---|---|---|---|---|---|---|
| PV | LiIon | solved | 3,607 | 1 | 1 / 0 | 0.0156 | 0.0069 | 0% | 0.41% |
| PV | NaIon | solved | 3,529 | 1 | 0 / 1 | 0.0147 | 0.0069 | 0% | 0.41% |
| PV | Both | solved | 3,529 | 1 | 0 / 1 | 0.0147 | 0.0069 | 0% | 0.41% |
| EV | LiIon | solved | 28,447 | 3 | 3 / 0 | 0.2187 | 0.0923 | 4.88% | 0.41% |
| EV | NaIon | solved | 26,270 | 3 | 0 / 3 | 0.1945 | 0.0923 | 4.88% | 0.41% |
| EV | Both | solved | **25,351** | 3 | 2 / 1 | 0.1843 | 0.0923 | 4.88% | 0.41% |
| PVEV | LiIon | solved | 28,434 | 3 | 3 / 0 | 0.2185 | 0.0923 | 4.88% | 0.81% |
| PVEV | NaIon | solved | 26,256 | 3 | 0 / 3 | 0.1943 | 0.0923 | 4.88% | 0.81% |
| PVEV | Both | solved | **25,338** | 3 | 2 / 1 | 0.1841 | 0.0923 | 4.88% | 0.81% |

Raw results: `output/tech_profile_ablation_clearsky/` (per-combination `.mat`, `summary.csv`, `summary.mat`). Measured-series results were preserved under `output/tech_profile_ablation_measured/` for comparison rather than overwritten.

## Interpretation

**PV's effect on this network depends heavily on which series is used — and clearsky reveals a real, second violation mode that measured completely hid.** Under `measured`, demand+PV with no EV never triggers `check_voltage_guard` — cost is exactly 0. Under `clearsky` (higher peak, wider generation window — see the overlap table above), the same PV-only scenario **does** site 1 ESS unit (~3.5-3.6k CHF) and shows a nonzero baseline current violation (0.41%) that was completely absent under `measured` (0%). This is a PV self-export overcurrent/over-voltage issue — the opposite failure mode from the EV-driven undervoltage seen elsewhere in this study — and it only shows up because `measured`'s representative day happened to have weaker generation. **This is the main reason the series choice matters for this paper**: `measured` alone would have led to the false conclusion that PV never causes problems on this network, when in fact it's a matter of how strong a solar day gets simulated.

**EV charging is the dominant driver of siting on this network under both series**, and by a wide margin (25-28k CHF vs. ~3.5k CHF for PV alone) — consistent with EV's larger baseline voltage violation (4.88%) against PV's smaller current violation (0.41%). PV's incremental effect on top of EV is small but, under `clearsky`, now measurably real and consistently beneficial: `PVEV` costs are lower than the matching `EV`-only cost for all three technology variants (28,447→28,434 for LiIon, 26,270→26,256 for NaIon, 25,351→25,338 for Both) — small (~0.05%), but no longer exactly zero as under `measured`'s narrower overlap window. Baseline current violations roughly double when PV is added on top of EV under `PVEV`/clearsky (0.41%→0.81%), reflecting that stronger PV output during the 5-timestep overlap with EV charging adds its own current stress on top of EV's.

**NaIon beats LiIon-only on this network**, and by a real margin (26,270 vs. 28,447 CHF, ~7.7% cheaper) — its higher C-rate (5 vs. 1.1) lets it deliver the same power with less installed energy capacity (`E_tot` 0.194 vs. 0.219 pu) for the identical converter rating (`S_tot` 0.092 pu both), and since energy capacity is priced 3x more heavily than power rating here (`cE=300` vs `cS=100` CHF/kWh-or-kW), that C-rate advantage translates directly into lower total capex — even though NaIon's round-trip efficiency (0.85) is worse than LiIon's (0.90); recall efficiency isn't priced under the current `throughput_penalty=false` default, so this comparison is purely a capex/C-rate story, not an efficiency one.

**Letting the solver choose freely (`Both`) beats either single technology** — 25,351 CHF, cheapest of all nine solved cases, by mixing 2 LiIon + 1 NaIon sites rather than forcing a uniform choice. This is the clearest evidence in this study that per-node technology heterogeneity has real value: the MILP's Big-M siting/technology-linking (`sum(I(n,:))<=1` per node, `util/solve_ess_milp.m`) is doing genuine comparative work here, not just picking whichever technology happens to be cheaper everywhere.

## Caveats for the paper text

- **PV series choice materially changes the conclusion for PV-only scenarios**: `measured` shows zero PV-driven violations/siting; `clearsky` shows a real (if small) self-export violation and ~3.5k CHF of siting. Since `measured` uses a single representative day (`D=1`, `season="all"`) whose solar strength isn't guaranteed strong, `clearsky` is the safer choice for a paper claim about "PV can also cause violations" — recommend leading with `clearsky` and citing `measured` only as a robustness/sensitivity note, not the other way around.
- **Single-network case study**, not a portfolio claim — frame accordingly (`LV_Grid_230` was chosen for tractability + documented EV/PV violations, not because it's necessarily representative of the whole Sion/Sierre portfolio).
- **Efficiency doesn't currently affect technology choice** in this run (`throughput_penalty=false`) — if the paper's narrative leans on round-trip efficiency as a differentiator, a follow-up run with `throughput_penalty=true` is needed; this study's NaIon advantage is a pure C-rate/capex story.
- **No ramp-rate (`J^RR`) or reactive-only-technology (`J^Q`) constraints are implemented** in `solve_ess_milp.m` at all (see the earlier methodology-vs-code check this session) — fine since neither LiIon nor NaIon here is meant to exercise those clauses, but worth an explicit note in the paper rather than silent omission if citing eqs. (18)/(19) as implemented.
- **SOE headroom bounds (`α`, `β` in eqs. 15a/15b of the paper) are not implemented** — `solve_ess_milp.m` allows `SOE` to range over the full `[0, E_nom]`, not `[α·E_nom, (1-α)·E_nom]`.
- **PV allocation semantics**: `nodal_PV_SFOE` (used here) represents SFOE's scenario-cadre PV target for 2040, read as *cumulative* installed capacity (not incremental) — see the discussion in the project chat log / this session's investigation of `allocate_PV_EV_SFOE.m`. The network's already-installed PV (DSO fuse-rating-based, `Pg_kW_` x0.7) is not part of this model at all (computed once for a vestigial classification load-flow inside `get_grid_SFOE.m`, then discarded).
- **Demand realization is one GMM draw**, not a validated "typical" day — `generate_nodal_scenarios_4.m` is documented as a WIP placeholder for the eventual real load-profile source (see `CLAUDE.md`).
