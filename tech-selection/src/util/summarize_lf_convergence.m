function summary = summarize_lf_convergence(lf_converged, lf_num_iter)
%SUMMARIZE_LF_CONVERGENCE  Roll up per-timestep loadflow_FPIs convergence
%                          tracking into one summary struct.
%
%   summary = summarize_lf_convergence(lf_converged, lf_num_iter)
%
%   lf_converged : [1 x T] logical    (loadflow_FPIs' `converged` output,
%                  one per timestep)
%   lf_num_iter  : [1 x T] double     (loadflow_FPIs' `num_iter` output;
%                  N_OF_ITER+1 sentinel where not converged)
%
%   summary : struct
%       .all_converged   scalar logical   true iff every timestep converged
%       .n_converged     scalar           count of converged timesteps
%       .n_total         scalar           T
%       .pct_converged   scalar           100 * n_converged / n_total
%       .failed_idx      [k x 1]          timestep indices that did NOT converge
%       .max_iter        scalar           worst-case iterations used
%       .mean_iter       scalar           average iterations used
%
%   Shared by linear_grid_model.m, re_linearization.m, and
%   run_seq_lin_loop_ess.m (via OPF_verification's convergence outputs) so
%   the same summary shape backs both the base operating point's and the
%   solved dispatch's convergence record -- see analyze_loadflow_convergence.

T = numel(lf_converged);
summary.all_converged = all(lf_converged);
summary.n_converged    = nnz(lf_converged);
summary.n_total         = T;
summary.pct_converged   = 100 * summary.n_converged / T;
summary.failed_idx      = find(~lf_converged(:));
summary.max_iter        = max(lf_num_iter);
summary.mean_iter       = mean(lf_num_iter);

end
