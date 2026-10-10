# Why the exclusivity penalty λ can pick the wrong technology

Status: **confirmed and fixed, 2026-09-28.** The mechanism below was verified
on a real network and the charge-referred fix was implemented and tested
against the exact formulation — see "Confirmed" after the derivation, and
`experiments/test_charge_referred_penalty.m` / `util/solve_ess_milp.m`'s
`cha_dis_penalty_form` option.

Math is written as standard LaTeX (`$...$` inline, `$$...$$` block). GitHub,
VS Code's Markdown preview (with a KaTeX/MathJax extension), and most
Markdown viewers render this directly; a plain text editor will show the raw
`$` syntax instead.

## Notation

Same symbols as `docs/methodology.pdf` (Section II):

| Symbol | Meaning |
|---|---|
| $P^{\mathrm{ess},+}_{n,j,t}$, $P^{\mathrm{ess},-}_{n,j,t}$ | charging / discharging power, ESS $j$ at node $n$, time $t$ (Eq. 11) |
| $\eta^{\mathrm{cha}}_j$, $\eta^{\mathrm{dis}}_j$ | charging / discharging efficiency of technology $j$ (Eq. 12) |
| $E_{n,j}$ | installed energy capacity |
| $\mathrm{SOE}_{n,j,t}$ | state of energy (Eq. 12) |
| $\Delta t$ | sampling time (was $T_s$ in code comments; same quantity) |
| $\mu_{n,j,t}$, $\mathcal{J}^{\mathrm{MU}}$ | exact binary mutual-exclusivity mode and the set of technologies it applies to (Eq. 14) |

Symbols not in the PDF (they belong to the relaxed-formulation / cost-annualization
subsections of the paper, which aren't in the excerpt I read, but you already
use them, so I keep them):

| Symbol | Meaning |
|---|---|
| $\lambda$ | exclusivity-penalty weight |
| $c^{\mathrm{sp}}$ | spot price of ESS round-trip loss, CHF/kWh, real/un-annualized (`throughput_loss_price_CHF_per_kWh` in `sizing_cfg.json`) |
| $L$ | technology lifetime, years |
| $\Psi$ | annualization factor, $\Psi = \dfrac{8760\,L}{T\,\Delta t}$ — the ratio of one lifetime's real hours ($8760$ h/yr $\times\, L$) to the simulated horizon's real hours ($T\Delta t$) |

Two derived quantities used throughout this note:
$$
\rho_j = \eta^{\mathrm{cha}}_j \, \eta^{\mathrm{dis}}_j \qquad \text{(round-trip efficiency of technology } j\text{)}
$$
$$
c^{\mathrm{eff}} := c^{\mathrm{sp}} \Psi \qquad \text{(annualized specific loss price — this is what the earlier version of this note called } c^{\mathrm{eff}}\text{, now spelled out)}
$$

## The two cost terms, in this notation

Exclusivity penalty (relaxed formulation, replaces $\mu_{n,j,t}$):
$$
\mathcal{F}^{\mathrm{pen}} = \lambda \sum_{n,j,t} \left( P^{\mathrm{ess},+}_{n,j,t} + P^{\mathrm{ess},-}_{n,j,t} \right)
$$

Round-trip loss cost:
$$
\mathcal{F}^{\mathrm{eff}} = c^{\mathrm{sp}} \Psi \, \Delta t \sum_{n,j,t} \left[ P^{\mathrm{ess},+}_{n,j,t} \left(1-\eta^{\mathrm{cha}}_j\right) + P^{\mathrm{ess},-}_{n,j,t} \left(\frac{1}{\eta^{\mathrm{dis}}_j} - 1\right) \right]
= c^{\mathrm{eff}} \Delta t \sum_{n,j,t} \left[ \cdots \right]
$$
($\Delta t$ turns a power sum into energy; $\Psi$ scales that one simulated horizon's energy cost up to a full lifetime's — see Notation.)

Both are added to the objective at the same time; the objective never
contains one without the other unless `min_loss`/`throughput_penalty` are
turned off.

## Step 1 — the cyclic SOE constraint links discharge to charge

The problem uses a periodic boundary, $\mathrm{SOE}_{n,j,0} = \mathrm{SOE}_{n,j,T}$
(`solve_ess_milp.m:164`). Summing Eq. 12 over the whole horizon for one
$(n,j)$:
$$
\Delta t \sum_t \left( \eta^{\mathrm{cha}}_j P^{\mathrm{ess},+}_{n,j,t} - \frac{1}{\eta^{\mathrm{dis}}_j} P^{\mathrm{ess},-}_{n,j,t} \right) = \mathrm{SOE}_{n,j,T} - \mathrm{SOE}_{n,j,0} = 0
$$

Writing $\bar P^+_{n,j} = \sum_t P^{\mathrm{ess},+}_{n,j,t}$ and
$\bar P^-_{n,j} = \sum_t P^{\mathrm{ess},-}_{n,j,t}$:
$$
\bar P^-_{n,j} = \rho_j \, \bar P^+_{n,j}
$$

Over a full cycle, total discharge is fixed by total charge and the
technology's own round-trip efficiency — not a free choice.

## Step 2 — both costs, per $(n,j)$, as a multiple of $\bar P^+_{n,j}$

$$
\mathcal{F}^{\mathrm{pen}}_{n,j} = \lambda \left(\bar P^+_{n,j} + \bar P^-_{n,j}\right) = \lambda (1+\rho_j)\, \bar P^+_{n,j}
$$

$$
\mathcal{F}^{\mathrm{eff}}_{n,j} = c^{\mathrm{eff}} \Delta t \left[(1-\eta^{\mathrm{cha}}_j)\bar P^+_{n,j} + \left(\tfrac{1}{\eta^{\mathrm{dis}}_j}-1\right)\bar P^-_{n,j}\right] = c^{\mathrm{eff}} \Delta t (1-\rho_j)\, \bar P^+_{n,j}
$$

(the second equality uses $\bar P^-_{n,j}=\rho_j \bar P^+_{n,j}$ and
$(1-\eta^{\mathrm{cha}}_j) + (\tfrac{1}{\eta^{\mathrm{dis}}_j}-1)\eta^{\mathrm{cha}}_j\eta^{\mathrm{dis}}_j = 1-\rho_j$;
recall $c^{\mathrm{eff}} = c^{\mathrm{sp}}\Psi$).

Adding them:
$$
\mathcal{F}^{\mathrm{pen}}_{n,j} + \mathcal{F}^{\mathrm{eff}}_{n,j} = \Big[\, \big(\lambda + c^{\mathrm{eff}}\Delta t\big) + \big(\lambda - c^{\mathrm{eff}}\Delta t\big)\rho_j \,\Big]\, \bar P^+_{n,j}
$$

## Step 3 — the sign of the $\rho_j$ term flips

- $\lambda < c^{\mathrm{eff}}\Delta t$: cost falls as $\rho_j$ rises → efficient
  technology wins. Intended behaviour.
- $\lambda > c^{\mathrm{eff}}\Delta t$: cost **rises** as $\rho_j$ rises → the
  **lossy** technology wins.

Your stated assumption, $\lambda \gg c^{\mathrm{eff}}\Delta t$, is exactly the
regime where the sign flips. Expanding $c^{\mathrm{eff}}\Delta t = c^{\mathrm{sp}}\Psi\Delta t$
and $\Psi = \dfrac{8760L}{T\Delta t}$, the $\Delta t$ **cancels**:
$$
c^{\mathrm{eff}}\Delta t = c^{\mathrm{sp}} \cdot \frac{8760\,L}{T}
$$
and (in the code) $\lambda = \dfrac{\varepsilon\cdot\min(c^E,c^S)}{T}$ also
scales as $1/T$ (`cha_dis_penalty_eps` scaled by the cheapest tech cost,
divided by $T$). Both sides carry the same $1/T$, so it cancels too — **the
crossover doesn't depend on $T$ or $\Delta t$ at all, only on $L$**. Solving
$\lambda(\varepsilon^*) = c^{\mathrm{eff}}\Delta t$ for the threshold value of
`cha_dis_penalty_eps`:
$$
\varepsilon^* = \frac{c^{\mathrm{sp}} \cdot 8760\, L}{\min(c^E, c^S)}
$$

With the live `sizing_cfg.json` real-unit prices ($c^{\mathrm{sp}}=0.15$
CHF/kWh, $c^E=300$ CHF/kWh, $c^S=100$ CHF/kW, $L=15$ years):
$$
\varepsilon^* = \frac{0.15 \times 8760 \times 15}{100} \approx 197
$$
The live default `cha_dis_penalty_eps` is `1e+2` (below the line); anything
pushed higher to more fully suppress phantom throughput crosses it. (No pu
scaling appears anywhere here — the code internally multiplies both $c^{\mathrm{sp}}$
and $c^E$/$c^S$ by the same $bp\!\cdot\!ph=300$ factor before this comparison,
so it cancels out of the ratio; the real-unit prices above give the same
$\varepsilon^*$ as the code's internal pu values would.)

## Where your original derivation has a gap

$\mathcal{F}^{\mathrm{pen}} \ne \lambda\,\mathcal{F}^{\mathrm{eff}}$. They
weight the two directions differently: $\mathcal{F}^{\mathrm{eff}}$ uses
$(1-\eta^{\mathrm{cha}}_j)$ and $(\tfrac{1}{\eta^{\mathrm{dis}}_j}-1)$;
$\mathcal{F}^{\mathrm{pen}}$ uses $1$ and $1$. The objective adds the two
terms, it does not replace one with a scaled copy of the other — and their
$\rho_j$-dependence (Step 2) has opposite sign. Scaling $\mathcal{F}^{\mathrm{eff}}$
by $\lambda$ (as in your derivation) shows that $\lambda\,\mathcal{F}^{\mathrm{eff}}$
alone would correctly reward efficiency for any $\lambda>0$ — true, but that
object is not what's in the solver. $\mathcal{F}^{\mathrm{pen}}$ is a
separate, added term with its own, opposite-signed effect once $\bar P^-_{n,j}$
is tied to $\bar P^+_{n,j}$ by the SOE cycle.

## Why only PV-only nodes, and why not single-technology runs

- **PV-only violation**: the grid constraint fixes how much power must be
  absorbed, so $\bar P^+_{n,j}$ is set by the violation and is roughly the
  same across technologies. The cost is the Step 3 bracket times
  $\bar P^+_{n,j}$, so a large $\lambda$ directly rewards the lossy
  technology.
- **EV-only violation**: the need fixes discharge, $\bar P^-_{n,j}=D$, so
  $\bar P^+_{n,j}=D/\rho_j$. Substituting gives a cost
  $D\big[\lambda(1+1/\rho_j) + c^{\mathrm{eff}}\Delta t(1/\rho_j - 1)\big]$, which
  falls as $\rho_j$ rises for *any* $\lambda$ — the efficient technology
  always wins here, whatever $\lambda$ is.
- **Single-technology runs**: there is no ranking between technologies to
  distort. $\lambda$ only pushes dispatch toward exclusivity, which is what
  it's meant to do.

## Worked numbers (illustrative, not from a real node)

$c^{\mathrm{eff}}\Delta t=1$, LiIon $\rho=0.81$, NaIon $\rho=0.7225$,
$\bar P^+=100$ (a fixed PV-absorption need):

| $\lambda$ | LiIon cost | NaIon cost | Winner |
|---|---|---|---|
| 0.5 | 109.5 | 113.9 | LiIon (correct) |
| 3 | 562 | 544.5 | **NaIon (wrong)** |

## Does dropping the cyclic constraint help?

No, not as a real fix. Without it, Step 1 doesn't hold and
$\mathcal{F}^{\mathrm{pen}}+\mathcal{F}^{\mathrm{eff}}$ becomes
$$
\big[\lambda + c^{\mathrm{eff}}\Delta t(1-\eta^{\mathrm{cha}}_j)\big]\bar P^+_{n,j} + \big[\lambda + c^{\mathrm{eff}}\Delta t(\tfrac{1}{\eta^{\mathrm{dis}}_j}-1)\big]\bar P^-_{n,j},
$$
both brackets shrink as efficiency rises, for any $\lambda$ — so for a fixed
$\bar P^+,\bar P^-$ the ranking can't flip. But:
- At $D=1$ the battery would end the day full/empty and couldn't repeat the
  next day — the cyclic constraint exists for a reason.
- At long horizon the SOE box bounds bring the same coupling back:
  $\mathrm{SOE}_T-\mathrm{SOE}_0$ can be at most one battery's $E_{n,j}$, which
  is a vanishing fraction of a year's throughput, so $\bar P^-_{n,j}\approx
  \rho_j\bar P^+_{n,j}$ holds anyway.

## A remedy consistent with this derivation

Penalize charge referred to the same base as the round-trip cost, instead of
raw $P^{\mathrm{ess},+}+P^{\mathrm{ess},-}$:
$$
\mathcal{F}^{\mathrm{pen}}_{\mathrm{charge\text{-}referred}} = \lambda \sum_{n,j,t} \left( P^{\mathrm{ess},+}_{n,j,t} + \frac{P^{\mathrm{ess},-}_{n,j,t}}{\eta^{\mathrm{cha}}_j \eta^{\mathrm{dis}}_j} \right)
$$
Under Step 1, $\bar P^-_{n,j}/\rho_j = \bar P^+_{n,j}$ for every technology,
so this term becomes $2\lambda\,\bar P^+_{n,j}$ regardless of $\rho_j$ — no
ranking effect, for any $\lambda$. It still grows with simultaneous
charge+discharge, so it still discourages the phantom-throughput behaviour it
was added for. (A plain $\lambda\sum P^{\mathrm{ess},+}_{n,j,t}$ penalty has
the same no-ranking-effect property, and is simpler, but weights the two
directions less symmetrically than $\mathcal{F}^{\mathrm{eff}}$ does.)

Not tested yet — see next steps.

## Where this lives in the code

- $\mathcal{F}^{\mathrm{pen}}$: `costPenalty`, `solve_ess_milp.m:336-341`.
- $\mathcal{F}^{\mathrm{eff}}$: `costBESSLoss`, `solve_ess_milp.m:315-319`, gated
  by `opts.throughput_penalty`.
- $c^{\mathrm{sp}}$: `throughput_loss_price_CHF_per_kWh`, `sizing_cfg.json`
  `economics` block (pu-scaled into `cfg.economics.cThroughputLoss` by
  `load_ess_selection_config.m`, same `bp*ph=300` treatment as `cL`/`cCurt`).
- $\Psi$: not a named variable in code — it's the `* 365 * 15 / days_simulated`
  multiplier applied inline in `costBESSLoss`'s (and `costL`'s/`costCurt`'s)
  formula. $L=15$ is currently hardcoded rather than read per-technology.
- Cyclic SOE: `solve_ess_milp.m:164`.
- Config: `cha_dis_penalty_eps`, `util/sizing_cfg.json` `solver` block.
- This is a **different** known issue from the one already documented in
  CLAUDE.md's "Charge/discharge exclusivity penalty" note (the C-rate
  joint-bound exploit that survives at full-year scale regardless of
  `eps`) — both live in the same relaxed formulation but are separate
  mechanisms. Don't conflate the two when this is picked back up.

## Confirmed (2026-09-28)

Ran `experiments/test_charge_referred_penalty.m` on `LV_Grid_230` (PV-only:
demand+PV, EV disabled; both LiIon/NaIon; `throughput_penalty` on): exact
binary formulation (ground truth) vs. relaxed `plain` vs. relaxed
`charge_referred`, at `cha_dis_penalty_eps` = 50 (below $\varepsilon^*\approx197$),
500 and 2000 (above):

| Run | eps | Node 35 tech | Total (kCHF) | Matches exact? |
|---|---|---|---|---|
| exact (binary) | — | LiIon | 4.4165 | — (ground truth) |
| plain | 50 | LiIon | 4.4165 | yes |
| charge_referred | 50 | LiIon | 4.4165 | yes |
| plain | 500 | **NaIon** | 4.7116 | **no** |
| charge_referred | 500 | LiIon | 4.4165 | yes |
| plain | 2000 | **NaIon** | 4.7116 | **no** |
| charge_referred | 2000 | LiIon | 4.4165 | yes |

Exactly the predicted pattern: `plain` matches the exact formulation below the
crossover and diverges above it (at both 500 and 2000); `charge_referred`
matches the exact formulation at every eps tested, including well above the
crossover. Both derivation and fix are empirically confirmed on a real
network, not just algebra.

Implemented as `cfg.solver.cha_dis_penalty_form` (`util/sizing_cfg.json`,
`"plain"` | `"charge_referred"`, default `"plain"` — opt in explicitly), read
in `solve_ess_milp.m`'s `costPenalty` block. Default unchanged, so this is
backward compatible; not yet made the default for real runs.

## Next steps (remaining)

1. ~~Confirm the mechanism on a real PV-only network~~ — done above.
2. ~~Implement the charge-referred penalty as an option~~ — done above,
   `cha_dis_penalty_form`.
3. Test `charge_referred` at long horizon (this note's derivation shows the
   fix is horizon-independent, same as the bug, but not yet run at scale).
4. Decide whether to make `charge_referred` the default (currently opt-in) —
   would need re-validating any existing results/paper numbers that used
   `plain` at an eps near or above $\varepsilon^*$.
5. Update the paper text with this derivation and the confirmed fix.
