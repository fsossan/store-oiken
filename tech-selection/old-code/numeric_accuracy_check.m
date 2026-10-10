function numeric_accuracy_check(A)

tol = 1e-12;

nz = A(abs(A) > tol);

disp(['min(A)=', num2str(min(A(:)))]);
disp(['max(A)=', num2str(max(A(:)))]);

if isempty(nz)
    disp('All entries are numerically zero');
else
    disp(['min|nz|=', num2str(min(abs(nz)))]);
    disp(['max|A|=',  num2str(max(abs(A(:))))]);
    disp(['spread=',  num2str(max(abs(A(:))) / min(abs(nz)))]);
end

disp(['#tiny<', num2str(tol), ' = ', num2str(sum(abs(A(:)) < tol))]);
disp(['#nz=', num2str(nnz(abs(A) > tol))]);

end