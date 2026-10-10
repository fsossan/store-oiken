function blk_diag = repeat_block_diag(matrix, m)
% Make a block-diagonal matrix by repeating <matrix> m times (sparse).
% blkdiag of m dense copies returns a dense m*rows x m*cols matrix; kron
% with a sparse identity keeps it sparse, O(m) memory instead of O(m^2).
    blk_diag = kron(speye(m), sparse(matrix));
