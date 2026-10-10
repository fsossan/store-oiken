# Overnight LiIon vs NaIon full-year eps sweep — 2026-09-30

**Status: stopped early per user request, 9/10 runs completed.** Findings below are drawn only from the 9 validated results; the 10th (`NaIon, eps=1e4`) never produced valid output and is not included.

## Setup

- Network: `LV_Grid_101`, scenario `sc1_2040`, `main.m` defaults (`rng(1234+101)` seeded once per network → demand/PV realization is **identical across all 9 runs**, so differences below are attributable only to technology/eps, not random variation).
- Horizon: `days=365`, `Ts_h=1` → `T=8760`.
- Demand + PV only (`ev_profile.enabled=false`), both block-averaged from native 15-min data (`allow_ts_downsample=true`), PV series `clearsky`.
- `curtailment_activate=false`, `min_loss=false`, `throughput_penalty=false`, `cha_dis_bin_activate=false` (relaxed linear penalty, `plain` form only — the `charge_referred` variant was reverted earlier this session).
- Each technology run in isolation (`technology_cfg.json` swapped to a single-tech file per leg), not a joint LiIon-vs-NaIon selection.
- `cha_dis_penalty_eps` swept at `{1e2, 5e2, 1e3, 5e3, 1e4}` per technology.

**Data integrity check performed**: every result's *actual* embedded config (`out.cfg.solver.cha_dis_penalty_eps`, `out.sizing.tech_names`) was read back from each `.mat` file and cross-checked against its filename tag — all 9 match exactly. This mattered because after the sweep was interrupted, the live `sizing_cfg.json`/`technology_cfg.json` on disk were found in a state inconsistent with the sweep script's own logic (reading `LiIon`+`eps=5e+3` when the script's last action should have left `NaIon`+`eps=1e4`), suggesting a separate, concurrent interactive MATLAB session may have also been editing these files overnight. The per-file embedded-config check rules this out as a contamination risk for the 9 saved results specifically — each `.mat` carries the config that was actually live in *that run's own process* at solve time, independent of whatever the shared JSON files said before or after.

A stale `101-NaIon-eps1e4_ERROR.mat` sits in the results folder — **ignore it**, it's a leftover from an unrelated earlier failure (timestamped *before* this sweep even started) that the driver script's fallback logic picked up when the real 10th run was killed mid-solve without producing any new output of its own.

## Results table

| Technology | eps | Status | Iters | v_err | E_nom (kWh) | S_conv (kVA) | Nodes | Cost total (CHF, excl. penalty) | Penalty (CHF) | Solve time |
|---|---|---|---|---|---|---|---|---|---|---|
| LiIon | 1e2 | Solved | 1 | 0.72% | 46.3 | 17.25 | 3 | 21,628 | 43,864 | 37.9 min |
| LiIon | 5e2 | Solved | 1 | 0.84% | 57.2 | 31.13 | 3 | 26,259 | 208,073 | 89.1 min |
| LiIon | 1e3 | Solved | 2 | 0.76% | 57.4 | 21.62 | 4 | 25,371 | 307,700 | 29.3 min |
| LiIon | 5e3 | Solved | 1 | 0.91% | **985.0** | 64.94 | 4 | **309,987** | 1,563,040 | 149.6 min |
| LiIon | 1e4 | Solved | 1 | 0.89% | **995.8** | 59.84 | 4 | **312,721** | 3,122,083 | 89.6 min |
| NaIon | 1e2 | Solved | 1 | 0.32% | 41.7 | 11.57 | 3 | 19,679 | 35,796 | 42.9 min |
| NaIon | 5e2 | Solved | 1 | 0.84% | 54.0 | 27.40 | 3 | 24,933 | 166,178 | 32.6 min |
| NaIon | 1e3 | Solved | 1 | 0.84% | 59.4 | 30.84 | 3 | 26,916 | 329,488 | 62.2 min |
| NaIon | 5e3 | Solved | 2 | 0.70% | 63.7 | 29.03 | 4 | 30,020 | 1,448,007 | 23.4 min |
| NaIon | 1e4 | **not completed** | — | — | — | — | — | — | — | killed mid-solve |

(`E_nom`/`S_conv` are network totals; `Cost total` = `E+S+I+L+Curt+BESSLoss`, matching `solve_ess_milp.m`'s definition — `Penalty` is deliberately excluded from that total per the code's own comment, "diagnostic only, NOT a real economic cost," but it **was** part of what the solver actually minimized.)

## Exclusivity (phantom charge/discharge) diagnostics

| Technology | eps | Clean? | Total phantom (kWh) | % of dispatch | Worst node max_rating_frac |
|---|---|---|---|---|---|
| LiIon | 1e2 | No | 5,478.1 | 14.26% | **97.0%** (node 62) |
| LiIon | 5e2 | No | 4,108.2 | 11.27% | 80.8% (node 62) |
| LiIon | 1e3 | No | 16.1 | 0.06% | 26.2% (node 62) |
| LiIon | 5e3 | **Yes** | 0.0 | 0.00% | 0.0% |
| LiIon | 1e4 | **Yes** | 0.0 | 0.00% | 0.0% |
| NaIon | 1e2 | No | 2,878.2 | 9.18% | 36.0% (node 62) |
| NaIon | 5e2 | No | 1,396.5 | 4.80% | 27.8% (node 62) |
| NaIon | 1e3 | No | 1,133.8 | 3.93% | 28.5% (node 62) |
| NaIon | 5e3 | **Yes** | ~0.0 | ~0.00% | 0.0% |

## Key findings

**1. Real-world solve time was far longer than expected, and highly variable.** Individual full-year (`T=8760`) MILP solves took **23 minutes to 2.5 hours** each (not the ~4 minutes the closest earlier precedent in CLAUDE.md — a `T≈9600` run under a different, simpler config — suggested). This is why the 10-run overnight batch only got through 9 in the time available. This is new, concrete timing data worth keeping for future full-year sweep planning; the old ~4 min figure should not be assumed to generalize to this config (`current_mag_cstr=true`, real C-rate technologies, full economics block active).

**2. At `eps ≥ 5e3`, the penalty term overwhelms the real objective and produces economically implausible results.** `Penalty` reaches 1.4–3.1 **million** CHF at `eps=5e3`/`1e4` — 5–10× the "real" cost total, and the LiIon sizing/cost at these eps values jumps **~17× in energy capacity** (46–57 kWh → 985–996 kWh) and **~12×in total cost** (21–26k → 310–313k CHF) compared to `eps≤1e3`, despite solving the exact same physical problem. This is exactly the failure mode CLAUDE.md already warns about for this penalty term ("must stay small relative to real cost signals... not merely a tie-breaker") — at this horizon, `eps≥5e3` clearly violates that. **The "clean" (zero-violation) dispatch at high eps should not be read as the economically correct answer** — it's the LP over-investing in storage specifically to starve the penalty term, not a genuine cost-optimal sizing decision.

**3. LiIon and NaIon respond very differently to rising eps — NaIon reaches clean dispatch far more cheaply.** NaIon's sizing/cost grows only modestly and smoothly across the whole sweep (42k→54k→59k→64k kWh, 19.7k→24.9k→26.9k→30.0k CHF) and reaches zero violation at `eps=5e3` at a cost of only 30,020 CHF. LiIon's sizing stays comparably modest through `eps=1e3` (~57 kWh, ~25-26k CHF) but then **explodes** at `eps=5e3` to 985 kWh / 310k CHF to reach the same "clean" state. This is mechanistically consistent with the core C-rate theme of this whole investigation: LiIon's low C-rate (1.1) means the *only* way for it to stop needing the phantom simultaneous-charge/discharge exploit is to massively oversize `E_nom` (since `B_plus`/`B_minus` are individually capped at `c_rate·E_nom`); NaIon's much higher C-rate (5) gives it enough headroom to satisfy the same power needs without either the exploit or a comparable size blow-up.

**4. LiIon showed *worse* exclusivity violations than NaIon at low eps here — the opposite of the earlier documented finding.** CLAUDE.md's existing note (from an earlier, native-15-min/`T=35,040` investigation) identifies NaIon's high C-rate as the technology prone to this exploit, with LiIon assumed safe. Here, at `eps=1e2` (`Ts_h=1`, `T=8760`), **LiIon's node 62 hit 97.0% of its own rating cap simultaneously charging and discharging** — far worse than NaIon's worst case at the same eps (36.0%). This is flagged as an open discrepancy, not yet explained — possibly resolution-dependent (hourly vs. 15-min) or an interaction with the much smaller `E_nom` LiIon installs at low eps leaving it less individual headroom relative to its dispatch needs. Worth a dedicated follow-up before generalizing either finding.

**5. Convergence was clean everywhere it completed.** All 9 runs hit `Solved` status with voltage linearization error well under the 1% threshold (0.32%–0.91%); 2 of 9 needed a second sequential-linearization iteration (`LiIon eps=1e3`, `NaIon eps=5e3`), the rest converged on iteration 1.

## Not yet done (stopped here per instruction)

- `NaIon, eps=1e4` never completed.
- No `analyze_tech_selection`/`analyze_losses`/`analyze_voltage_current` figures were generated or exported for any of the 9 results (the sweep only ran the solve + console-only exclusivity/convergence diagnostics; `export_open_figures`/tikz export was not part of this batch).
- No attempt yet to find a "good" intermediate eps between `1e3` (violations still present but cost sane) and `5e3` (clean but cost distorted) — the sweet spot, if one exists at this horizon, is still open.
- The LiIon-vs-NaIon exclusivity-severity reversal (finding 4) is unexplained.

## Follow-up: throughput-loss test at eps=5e3 (2026-09-30, later same day)

**Hypothesis tested (user's): once throughput (round-trip) losses are priced into the objective, LiIon should become the better technology, since it's more efficient (`η_ch·η_dis = 0.81`) than NaIon (`0.7225`).**

Two more runs, both `eps=5e3`, both otherwise identical to the sweep above, with `flags.throughput_penalty` flipped `true` (was `false` throughout the sweep):

| Technology | E_nom (kWh) | S_conv (kVA) | Investment (kCHF) | BESS throughput-loss cost (kCHF) | Real total (kCHF) | Total dispatch (kWh) |
|---|---|---|---|---|---|---|
| NaIon (no loss pricing, from sweep) | 63.7 | 29.03 | 30.02 | 0 (not priced) | 30.02 | 25,369 |
| NaIon (**with** loss pricing) | 63.56 | 28.57 | 29.93 | **9.18** | **39.10** | 25,324 |
| LiIon (no loss pricing, from sweep) | 985.0 | 64.94 | 309.99 | 0 (not priced) | 309.99 | 27,384 |
| LiIon (**with** loss pricing) | 984.98 | 64.94 | 309.99 | **6.47** | **316.46** | 27,384 |

**Verdict: the hypothesis does not hold — NaIon is still ~8× cheaper than LiIon even with losses priced in (39.1 kCHF vs 316.5 kCHF).**

The efficiency part of the hypothesis is directionally correct in isolation: LiIon's loss cost (6.47 kCHF) is lower than NaIon's (9.18 kCHF) despite similar total throughput (27.4k vs 25.3k kWh) — consistent with LiIon's real round-trip-efficiency advantage. But that effect is a ~2.7 kCHF difference, completely swamped by the pre-existing ~280 kCHF gap in `Investment` alone, and sizing (`E_nom`, `S_conv`) barely moved for either technology when the loss term was added — confirming the loss cost doesn't feed back into siting/sizing decisions here, it's just a bolt-on penalty on top of whatever dispatch was already chosen.

**Caveat this comparison inherits from finding 2 above**: LiIon's ~985 kWh sizing at `eps=5e3` is itself the already-documented penalty-distortion artifact (LiIon needs to massively overbuild `E_nom` to reach zero exclusivity violation at this eps — not a genuine economic requirement). So this specific test doesn't cleanly isolate "does throughput-loss pricing change the tech ranking" from "eps=5e3 is already known to distort LiIon's sizing." A cleaner test of the hypothesis would rerun both technologies with `throughput_penalty=true` at a **lower, non-distorting eps** (e.g. `1e3`, where LiIon's sizing was still reasonable, ~57 kWh) — not yet done.

## Housekeeping performed while stopping

- Killed the in-progress `NaIon eps=1e4` MATLAB process (PIDs 7204/34612) without touching your own separate interactive MATLAB sessions (identified and left alone: the VS Code MATLAB language-server processes, and what appear to be two personal interactive sessions opened 2026-09-29 evening).
- `util/sizing_cfg.json` and `util/technology_cfg.json` were already back at `LiIon`-only / `eps=5e+3` by the time I checked (matching the sweep's pre-run backup) — no repo config changes were needed or made.
- The stray `101-NaIon-eps1e4_ERROR.mat` was left in place but is not a real result (see above) — safe to delete.
