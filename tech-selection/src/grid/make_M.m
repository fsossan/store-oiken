function M = make_M (x_sel, make_it_sparse)
    % Return a matrix M (possibly sparse) to perform the linear
    % transformation Mx = x_sel equivalent to x_sel = x(sel).
    if nargin == 0
        x_sel = randn(10, 1)>0.5;
        make_it_sparse = false;
    end
    
    if nargin == 1
        make_it_sparse = false;
    end
    
    if make_it_sparse
        M = sparse(zeros(sum(x_sel), numel(x_sel)));
    else
        M = zeros(sum(x_sel), numel(x_sel));
    end    
    % determine index of 1 elements in sel
    index_of_one_elements = 1:numel(x_sel);
    index_of_one_elements = index_of_one_elements(x_sel > 0);
    % rows and columns of 1 elements
    rows = (1:size(M,1))';
    columns = (index_of_one_elements)';
    % assign 1 elements
    idx = sub2ind(size(M), rows, columns);
    M(idx) = 1;
end