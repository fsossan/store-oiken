# Case Study: Diagnosing and Fixing a Quadratic Memory Blowup in a MATLAB/CVX Optimization Pipeline

## The situation

A MATLAB research codebase solves a Mixed-Integer Linear Program (MILP) for
optimal battery siting/sizing on electrical distribution networks, using CVX
+ Gurobi. The model is built by *sequential linearization*: at each timestep
`t`, a nonlinear power-flow is linearized around an operating point, and the
per-timestep sensitivity matrices are stacked across the full time horizon
`T` before being handed to the solver.

At `T = 96` (one day, 15-minute resolution) everything worked. Scaling toward
a full year (`T = 35,040`) was the actual goal, but the pipeline ran out of
memory on a 64 GB workstation somewhere around `T ≈ 9,600` (100 days). Two
prior optimization passes had already been made — replacing a `cumsum`-based
constraint with a sequential recursion, and replacing one `pinv()` call with
a Kronecker-product shortcut — and both were real, correct fixes. But the
OOM persisted. That's the situation a fresh diagnosis had to start from: **the
easy wins were already taken, and the problem was still there.**

## The diagnostic method

The starting hypothesis, stated by the person requesting the fix, was: *"the
bottleneck is the modeling, not the problem size."* That framing matters —
it means the fix should be sought in *how data is represented*, not in the
physics or the optimization formulation. That turned out to be exactly
right, and it shaped the whole approach:

1. **Trace the real call graph, not the documented one.** Rather than
   guessing, the call chain was walked top-down through the actual entry
   point (`main.m → run_ess_selection_portfolio → solve_network_tech_selection
   → run_seq_lin_loop_ess → build_sensitivity_matrices_v2 → solve_ess_milp_v2`),
   reading every file that sits between "load data" and "hand a matrix to
   the solver." A written architecture doc (this repo has a very good one,
   `CLAUDE.md`) is a map, not the territory — it can drift from what the code
   actually does, especially in a fast-moving research codebase with
   multiple work-in-progress files (`_v2` suffixes, `.asv` autosaves,
   commented-out lines). Trust the code.

2. **Look for data-structure choices, not just algorithms.** The two prior
   fixes were both algorithmic (a smarter recursion, a smarter pseudo-inverse
   trick). The next layer to check wasn't "is the math efficient" but "what
   *type* of object is the math producing." In MATLAB specifically, this
   means asking of every matrix in the hot path: *is this sparse or dense,
   and does it stay that way through every operation applied to it?*

3. **Compute a back-of-envelope estimate and check it against the observed
   failure point.** Once a suspicious matrix-construction pattern was found,
   the very next step — before touching any code — was to estimate its size
   in bytes as a function of `T`, and see whether that estimate crossed the
   OOM threshold near `T ≈ 9,600`. One of the matrices came out to roughly
   **294 GB dense at that horizon**, on a 64 GB machine. That's the "smoking
   gun" moment in this kind of investigation: a *quantitative* match between
   a code pattern's theoretical memory cost and the empirically observed
   failure point is much stronger evidence than "this looks inefficient."

4. **Know the tool's promotion rules cold.** The actual bug wasn't a typo or
   an off-by-one — it was a MATLAB semantics gotcha, repeated in three
   different places:

   > **`blkdiag(A, B, C, ...)` returns a dense matrix unless *every* input is
   > already sparse.**

   None of the three call sites were sparse, so all three silently produced
   dense output — each one for a matrix that was *structurally*
   block-diagonal (only `T` blocks worth of real information), but stored as
   if every one of the `T²` block positions might be nonzero.

## The three bugs (plus one found during verification)

All three lived in the plumbing that turns "one network's per-timestep
sensitivity data" into "one big matrix CVX can multiply against the decision
variables." None of them touched the physics or the MILP formulation.

**1. A permutation matrix stored as `zeros(N,N)` + a loop.**
A function (`linear_reshape_test.m`) needed to reorder a stacked vector from
"all nodes at each time" to "all times at each node." Mathematically this is
a pure permutation — one `1` per row, everything else `0` — but it was built
with `R = zeros(T*N, T*N)` followed by a loop writing one row at a time. That
is *both* O((T·N)²) memory *and* O((T·N)²) time, for an operation whose
actual information content is O(T·N). This was the single worst offender —
the one that produced the 294 GB estimate above.

*Fix*: build the permutation directly as a sparse matrix from index vectors,
with no loop:
```matlab
row_idx = (1:N*T)';
n_idx   = repelem((1:N)', T);
t_idx   = repmat((1:T)', N, 1);
col_idx = (t_idx - 1)*N + n_idx;
R = sparse(row_idx, col_idx, 1, N*T, N*T);
```
Same matrix, same numerical values — verified by direct comparison against
the old implementation on small test cases — just stored honestly.

**2. `blkdiag` of `T` dense copies of a small matrix.**
A helper (`repeat_block_diag.m`) repeated a small "expand demand-nodes to
all-nodes" matrix `T` times along the diagonal, via
`blkdiag(repmat({matrix}, T, 1){:})`. Dense input, dense output, `O(T²)`.

*Fix*: replace with `kron(speye(T), sparse(matrix))` — mathematically
identical block-diagonal structure, but sparse by construction. This is a
standard trick: `kron` with a sparse identity is the idiomatic way to
"repeat a block T times" in MATLAB without ever materializing the zero
off-diagonal blocks.

**3. `blkdiag` of `T` dense per-timestep sensitivity blocks.**
The main sensitivity-assembly function (`build_sensitivity_matrices_v2.m`)
takes eight different physical quantities (voltage sensitivity, current
sensitivity, slack-power sensitivity, etc.), each stored as a MATLAB cell
array with one dense matrix per timestep, and does
`blkdiag(cell_array{:})` to stack them into one big matrix per quantity.
Same disease as #2, just with real (not synthetic) per-timestep data, and
applied eight times over.

*Fix*: convert each cell's contents to sparse (`cellfun(@sparse, cell_array,
'UniformOutput', false)`) before the `blkdiag` call. Worth noting explicitly:
**the individual per-timestep blocks are not themselves sparse** — a
voltage-sensitivity matrix genuinely has every node responding (weakly) to
every other node's injection, so it's numerically dense within one
timestep. The saving isn't "fewer nonzeros per block" — it's "the `T-1`
structurally-zero off-diagonal block *positions* per block-row are never
allocated at all."

**4. The one that survived the first round of fixes: sparse comparison
against a positive threshold.**
After the first three fixes were implemented, unit-verified on small cases,
and pushed through the real pipeline, it failed again — but at a *different*
line, with a *different* huge array size (`140,160 × 70,080`, 82.3 GB). A
few lines after the newly-sparse sensitivity matrices were built, an
existing numerical clean-up step ran:
```matlab
sens.dImagdP(abs(sens.dImagdP) < tol) = 0;   % tol = 1e-8
```
This looks harmless, and was harmless when `dImagdP` was already dense. But
once `dImagdP` became sparse, this line re-densified it: **`abs(X) < tol`,
for a positive `tol`, is `true` for every implicit zero as well as every
explicit stored value below threshold.** MATLAB has to materialize a full
logical mask the same size as the "conceptual" dense matrix to answer that
comparison — undoing the entire fix, one line later, invisibly.

*Fix*: `spfun`, which applies a function only to a sparse matrix's
*explicitly stored* nonzero entries, leaving implicit zeros alone:
```matlab
clean_sp = @(X) spfun(@(v) v .* (abs(v) >= tol), X);
sens.dImagdP = clean_sp(sens.dImagdP);
```
Verified against the original threshold semantics on a small case before
being trusted on the real matrices.

## Verification strategy — why the bug order matters

The fix was validated in three escalating stages, deliberately, not as an
afterthought:

1. **Pure numerical equivalence, no solver involved.** Small hand-checkable
   cases (`N`, `T` in the single digits) comparing the new sparse
   implementations against the old dense ones with `isequal(full(new),
   old)`. This isolates "is the math the same" from "does the rest of the
   system still work," and runs in milliseconds — cheap enough to do before
   touching anything expensive.

2. **The real end-to-end pipeline, at the previously-working scale.** Running
   the actual entry point (`main.m`) is what caught bug #4 — a unit test on
   `linear_reshape_test` and `repeat_block_diag` in isolation would never
   have exercised the `spfun` line, because that line lives downstream, in a
   different function, operating on the *output* of the fixed functions.
   This is the general lesson: **passing unit tests for the pieces you
   changed doesn't prove the system you changed still works — only running
   the system does.**

3. **The real pipeline, at the target (previously-failing) scale.** Once (1)
   and (2) passed, the actual regression target — the horizon that used to
   OOM — was run for real. It solved: a converged MILP, a sensible physical
   result (specific battery technologies sited with specific capacities),
   in a few minutes total.

## Reusable lessons

- **When memory scales worse than the problem should, suspect the storage
  representation before the algorithm.** Two genuinely correct algorithmic
  fixes had already been made in this codebase and the OOM was still there,
  because the remaining bottleneck was never about *how many* floating-point
  operations were being done — it was about a data structure that was
  quadratic in size for no algorithmic reason.

- **In MATLAB (and this generalizes to most numerical languages with a
  sparse/dense duality — SciPy, Julia, Eigen), know your library's type
  promotion rules explicitly, don't assume.** `blkdiag` densifies unless
  every input is sparse. Comparisons against a positive threshold densify a
  sparse matrix. `kron` preserves sparsity if either operand is sparse.
  These rules are documented but easy to violate silently, because the code
  still *runs* — it just runs enormously more expensively, and only fails
  once the problem size crosses a threshold, which is exactly the pattern
  this bug produced ("works for a day, dies somewhere past 100 days").

- **A quantitative back-of-envelope estimate is worth more than an intuition
  that something "looks slow."** Computing `(T·N)² × 8 bytes` and getting a
  number in the hundreds of gigabytes, matching the observed failure
  horizon almost exactly, turned "this looks like it could be the issue"
  into "this is almost certainly the issue" — before writing a single line
  of fix code.

- **Fix the smallest, most localized thing that addresses the root cause.**
  All three original fixes were confined to three small, shared utility
  functions (`linear_reshape_test.m`, `repeat_block_diag.m`,
  `build_sensitivity_matrices_v2.m`). Because they're shared utilities,
  fixing them once automatically fixed every call site — no changes were
  needed in the higher-level pipeline code (`preprocess_network.m`,
  `solve_ess_milp_v2.m`) at all, because sparse matrices flow through
  ordinary matrix multiplication and CVX affine expressions transparently.
  Minimizing blast radius also minimizes the surface area for new bugs.

- **The fourth bug is the reminder to actually finish verification.** It
  would have been easy to declare victory after the three planned fixes
  passed their unit tests. The fourth bug only surfaced because the
  verification plan explicitly included "run the real system," not just
  "test the changed functions in isolation."

## Where this leaves the project

Validated: the pipeline now solves at `T = 9,600` (100 days), the exact
horizon that used to fail, in a few minutes. Not yet validated: the full
`T = 35,040` (one year) target. Known remaining candidates if that turns out
to still be a problem, in rough priority order: a wall-clock (not memory)
inefficiency in the per-timestep sensitivity computation itself (redundant
matrix factorizations inside `getSCs.m`); CVX's own model-construction
overhead at very large variable counts, which is separate from both the
memory fix and Gurobi's solve time; and a modeling question about whether
the storage state-of-energy constraint should cycle daily rather than once
per horizon, which becomes actively relevant once the horizon spans many
months.
