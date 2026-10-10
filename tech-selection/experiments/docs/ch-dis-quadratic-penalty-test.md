# Quadratic charge/discharge penalty: why it was tested and ruled out

This is a side investigation split out of [ch-dis-relaxation-scaling-study.md](ch-dis-relaxation-scaling-study.md) — the main document covers the charge/discharge exclusivity penalty fix, the full-year run, and the round-trip-loss-pricing fix that actually solved the residual violation. This file covers one lead that was tested along the way and didn't pan out, kept separate so it doesn't clutter the main narrative.

## Why a quadratic penalty looked promising

An older, single-node sizing script (battery arbitrage against real electricity prices) used an L2 (quadratic) penalty — `0.001 * norm(Bplus, 2) + 0.001 * norm(Bminus, 2)` — instead of the L1 (linear) penalty this pipeline uses. A quadratic penalty's marginal cost grows with the size of the violation; a linear penalty's marginal cost is flat regardless of size. That distinction mapped directly onto the residual full-year problem documented in the main doc: the linear penalty drove many small violations to exact zero easily, but had no extra leverage against a few large, concentrated ones — exactly the shape the NaIon full-year violation had. So testing a quadratic form directly was the natural next step.

## Small-scale calibration

`D=2`, sweeping `eps_quad`:

| eps_quad | objective (k CHF) | phantom % | max violation (kW) | clean? | solve time |
|---|---|---|---|---|---|
| 0 | 3.2296 | 41.71% | 8.09 | no | 6.94 s |
| 0.001 | 3.2296 | 21.42% | 0.0425 | no | 1.73 s |
| 0.01 | 3.2296 | 7.70% | 0.00995 | no | 0.66 s |
| 0.1 | 3.2296 | 0.99% | 0.00247 | no | 0.57 s |
| **1** | **3.2297** | **0.03%** | **0.000150** | **yes** | **0.64 s** |
| 10 | 3.2304 | 1.11% | 0.00127 | no | 1.07 s |
| 100 | 3.2370 | 0.79% | 0.00127 | no | 0.74 s |

`eps_quad=1` looked like the clear best point — genuinely clean, barely any objective movement. Worth noting: it doesn't reach *exact* zero the way the linear penalty did, and going past `eps_quad=1` doesn't improve things monotonically (10 is worse than 1, on both counts) — a sign the quadratic form doesn't behave quite as cleanly as the linear one did, even before scaling up.

## The full-year test

Same network, `eps_quad=1`:

- Solve time: **4,197 s (~70 minutes)**, against the linear penalty's 108 s — about **39x slower**
- Phantom throughput: 12.80% overall — no better than the linear penalty's 12.56%
- LiIon violations: 25,318 / 70,080 (the linear penalty left LiIon at exactly zero)
- NaIon violations: 34,808 / 70,080 (up from 388)

Worse on both counts. Not a small effect — a decisive negative result.

## Why it was so slow

Checked directly rather than assumed: CVX doesn't hand a solver a native quadratic objective. It always compiles `sum_square(x)` into an epigraph form — a cone constraint plus a linear variable — regardless of solver. That part was cheap here: CVX only produced 2 such constraints. But Gurobi's own presolve then broke those 2 constraints apart into **280,322 separate second-order cone constraints** — the log says so directly: *"Root relaxation presolved model has 280,322 second-order cone constraints."* Handling that many small cones in the barrier method, instead of one clean diagonal term in the objective, is what actually cost the time — not the quadratic penalty itself. The root relaxation alone took 1,060 s (vs. ~80 s for the linear LP's barrier solve), and the branch-and-bound needed 7 nodes instead of 1, because the quadratic term shifted the relaxation just enough that the small siting binaries weren't already integer-feasible at the root.

So the idea that a diagonal quadratic term should be cheap for a barrier method is still true — it just isn't what got solved here. A genuine native quadratic objective (no cone constraints at all) would be a different computation entirely, but getting CVX to produce one isn't possible through its normal atom library; it would mean building the sparse matrices by hand and calling Gurobi's native API directly, bypassing CVX for this term.

## A simplification that doesn't work

One simplification was raised and is worth recording why it doesn't work: replacing `sum_square(x)` (sum of squares) with `square(sum(x))` (square of the sum) would indeed avoid the disaggregation problem — a single scalar square only ever needs one small cone constraint, nothing for presolve to break apart. But it penalizes a different thing entirely. `sum_square` charges more for one large, concentrated violation than for many small ones — which is exactly the shape needed here. `square(sum(x))` only sees the total annual throughput; it can't distinguish a single large violation from ordinary dispatch spread across the whole year, so it wouldn't specifically discourage the NaIon problem at all. It also scales differently with horizon length — `sum(x)` grows roughly with `T`, so `square(sum(x))` grows roughly with `T²`, which would need dividing by `T²` (not `T`) to stay horizon-invariant. Cheaper, but the wrong tool.

## Where this stands

- The quadratic penalty, as implemented through CVX, is ruled out — 39x slower for no improvement, for a reason now fully understood (Gurobi's presolve, not the underlying math).
- Not yet tried: controlling Gurobi's presolve behavior directly (e.g. via `PreQLinearize`/`Presolve` parameters passed through CVX) to keep `sum_square`'s original 2-constraint form intact instead of letting presolve explode it. This would test whether the "cheap diagonal quadratic" theory holds once the model is actually given the chance to be diagonal. Decision on whether to pursue this is still open.
- Moot in practice either way: the main doc's round-trip-loss-pricing fix (`opts.throughput_penalty`) solved the residual violation this was meant to fix, without touching the penalty's shape at all. This quadratic path is no longer the leading candidate for anything, just a documented dead end.
