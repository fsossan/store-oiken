function R = linear_reshape_test(N, T)
% Given with a NxT vector, say x, produces a matrix R such that y = Rx
% is y = reshape(x, N, T)'(:).
% R is a permutation matrix (one 1 per row/column) built directly as
% sparse, instead of via a dense zeros(T*N,T*N) + row-by-row loop, which
% cost O((T*N)^2) memory/time and was the dominant OOM source at long
% horizons (see docs/DEVELOPMENT_NOTES.md sensitivity-matrix scaling notes).
row_idx = (1:N*T)';
n_idx   = repelem((1:N)', T);
t_idx   = repmat((1:T)', N, 1);
col_idx = (t_idx - 1)*N + n_idx;
R = sparse(row_idx, col_idx, 1, N*T, N*T);
end