# Does "at most one technology per node" change tech selection?

**Result: no.** Dropping `sum(I(n,:)) <= 1` gave identical siting, technology choice, sizing and cost in all three objective variants. No node chose to host both technologies.

Script: `experiments/run_one_tech_per_node_study.m` (6 runs). Raw results: `output/one_tech_per_node_study/results.mat`.

## Question

`solve_ess_milp.m` forces each node to host at most one technology:

```matlab
for n = 1:Nd
    sum(I(n,:)) <= 1;   % at most one technology per node
end
```

Compare the current MILP (constraint on) with the same MILP without that line (constraint off). With it off, a node may host a LiIon unit and a NaIon unit at the same time.

## Setup

| Item | Value |
|---|---|
| Network / scenario | `LV_Grid_230`, `sc1_2040` |
| Horizon | 1 day, 15-min steps (T = 96) |
| Profiles | demand + PV (clearsky, scale 1) + EV, all enabled |
| Technologies | LiIon (C-rate 1.1, eta 0.90) and NaIon (C-rate 5, eta 0.85), both available |
| Costs (both techs) | cE 300 CHF/kWh, cS 100 CHF/kW, cI 2000 CHF per installed unit |
| Charge/discharge exclusivity | exact (binary), pinned in memory |
| Curtailment | off |
| Prices (live `sizing_cfg.json`) | energy 0.15 CHF/kWh, throughput loss 0.15 CHF/kWh |
| Gurobi MIPGap | 1e-6 (read from the run log; set in the CVX install directory) |
| Demand realization | one fixed sample (`rng(1234+230)`) |

Objective variants:
- `Finv`: capex only (E + S + I).
- `Finv_Sloss`: plus transformer/slack loss cost.
- `Finv_Sloss_Eloss`: plus battery round-trip loss cost.

The technology parameters are hardcoded in the script. `technology_cfg.json` is not read.

## Results

Total cost (kCHF):

| Objective | Constraint on | Constraint off | Difference |
|---|---|---|---|
| `Finv` | 25.338 | 25.338 | 0.000 |
| `Finv_Sloss` | 28.955 | 28.955 | 0.000 |
| `Finv_Sloss_Eloss` | 39.151 | 39.151 | 0.000 |

Gurobi's own best objectives agree to 6e-8 relative or better, which is below the MIPGap of 1e-6.

Sites and sizes. These are the same with the constraint on and off:

| Objective | Node | Tech | E (kWh) | S (kW) |
|---|---|---|---|---|
| `Finv` | 34 | NaIon | 3.227 | 15.32 |
| | 35 | LiIon | 44.283 | 10.536 |
| | 41 | LiIon | 7.725 | 1.822 |
| `Finv_Sloss` | 34 | NaIon | 3.567 | 16.291 |
| | 35 | LiIon | 26.647 | 6.139 |
| | 41 | LiIon | 27.038 | 6.272 |
| `Finv_Sloss_Eloss` | 34 | NaIon | 3.554 | 16.255 |
| | 35 | LiIon | 25.851 | 6.303 |
| | 41 | LiIon | 26.039 | 6.033 |

Cost breakdown, `Finv_Sloss_Eloss` (kCHF): E 16.633, S 2.859, I 6.000 (3 units x 2), slack loss 3.710, battery loss 9.949.

Other checks:
- All 6 runs solved. No charge/discharge exclusivity violation in any run.
- Linearization error is identical between on and off (voltage error about 7.4e-3 to 7.6e-3 pu).
- With the constraint on, the totals reproduce the earlier PV+EV study's "Both" rows (25.338 / 28.959 / 39.151 kCHF). The only gap is `Finv_Sloss`: 28.955 now vs 28.959 before (0.014%). This is consistent with the earlier run using a looser MIPGap. I did not check what tolerance the earlier run used.

## Interpretation

The constraint is not binding here. The solver had the freedom to put both technologies at one node and never did.

Likely reason (reasoning from the inputs, not tested):
- LiIon and NaIon have the same cost per kWh and per kW. Splitting a node between them cannot reduce capex. Only eta and C-rate differ.
- A second unit at the same node costs another cI = 2 kCHF, about 8% of the `Finv` total.
- So one well-suited technology per node wins. NaIon goes where the C-rate binds (node 34), LiIon elsewhere.

## Caveats

- One network, one day, one demand sample.
- Exact charge/discharge exclusivity only. Your live JSON has it off; results with the relaxed form were not tested.
- The null result probably depends on cI being large relative to any saving, and on identical cE/cS across the two technologies. With a small cI or technologies with different per-kWh costs, the constraint could bind. That was not tested.

## Search for a two-technologies-at-one-node case

Script: `experiments/search_two_techs_same_node.m`. Same setup as above, `Finv_Sloss_Eloss`, constraint off. Preprocessing runs once, so each case is a single MILP. For a case that produced a two-technology node, the constraint-on solve was run too, to price the split.

| Search | Values | Node with two techs? |
|---|---|---|
| Installation cost cI (CHF) | 2000, 500, 100, 0 | No. At cI = 0 two extra small single-tech units appear (nodes 36, 38). |
| LiIon cost (CHF/kWh), NaIon stays 300 | 150, 75, 30, each at cI = 2000 and 0 | No. At 75 and below, node 34 switches from NaIon to LiIon, but never to a mix. |
| LiIon C-rate 0.2 (synthetic), LiIon 150 CHF/kWh | cI = 2000, 500, 100 | No. |
| Same, cI = 0 | | **Yes, node 38.** |

The one hit (LiIon C-rate 0.2, LiIon 150 CHF/kWh, cI = 0):

| Node | Tech | E (kWh) | S (kW) |
|---|---|---|---|
| 34 | NaIon | 3.238 | 15.546 |
| 35 | LiIon | 29.036 | 5.926 |
| 36 | NaIon | 0.317 | 0.761 |
| **38** | **LiIon** | 1.016 | 0.207 |
| **38** | **NaIon** | 0.085 | 0.296 |
| 41 | LiIon | 28.950 | 5.908 |

- Total: 26.353 kCHF with the constraint off vs 26.373 kCHF with it on. The split saves **0.020 kCHF (20 CHF, 0.08%)**.
- With the constraint on, node 38 gets LiIon only and the rest is unchanged.
- The saving is real, not solver noise: Gurobi reported gap 0.0000% at MIPGap 1e-6.
- At cI = 100 the split disappears. A second unit costs more than the 20 CHF it saves, so the break-even cI is about 20 CHF.

**Conclusion.** Two technologies at one node can be optimal, but only when installation is essentially free and one technology is power-limited. In this case (network, one day, one demand sample) the gain is negligible. With realistic parameters (cI = 2000 CHF, LiIon C-rate 1.1) the constraint never binds.

**Why (reasoning from the results, not tested separately).** A node needs two technologies only if its energy need and its power need both bind, and its power-to-energy ratio lies between the two C-rates. At nodes 35 and 41 the ratio is about 0.24 (energy-limited), at node 34 it is above 4 (power-limited), so one technology covers each. Node 38 is a tiny node where both limits bind at once.

**Caveats.**
- The LiIon C-rate of 0.2 is synthetic and unrealistic (real LiIon here is 1.1). It was chosen to make nodes 35 and 41 power-limited for LiIon.
- I expected a larger mixed saving at nodes 35 and 41 (my hand estimate was 500 to 800 CHF). The solver did not use it. My estimate ignored the extra round-trip loss cost of NaIon and its extra converter cost, so it was too optimistic.
- Not tried: other networks, other days, or a demand sample with more nodes in the intermediate power-to-energy range. Those would be the natural place to look for a larger effect.

## Code changes made for this study

- New flag `one_tech_per_node` (default `true`): `util/sizing_cfg.json` (flags), `util/solve_network_tech_selection.m` (copies it into `opts`), `util/solve_ess_milp.m` (a missing field counts as `true`, so old scripts are unaffected).
- Documented in `CLAUDE.md` under the optimization loop, step 2.
