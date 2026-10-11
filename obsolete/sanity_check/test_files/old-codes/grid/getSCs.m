function [dVmagdP, dVmagdQ, dVmagdVslackmag, dSslackstardP, dSslackstardQ, dSslackstardVslackmag, dImagdP, dImagdQ,dIdP,dIdQ ,dImagdVslackmag] = ...
    getSCs(YY, S0, V0, I0, N1N2Y, n_of_phases)
% YY: admittance matrix - with slack bus
% S: single phase loads in per unit
% E: voltage at the linearization/working point in per unit with slack bus

% Vabslin = V0 + dVmagdP * (real(S - S0)) + dVmagdQ * (imag(S - S0)) + dVmagdVslackmag * (Vslack - Vslack0)
% Sslacklin = S0 + dSslackstardP * (real(S - S0)) + dSsclackstardQ * (imag(S - S0))  + dSslackstardVslackmag * (Vslack - Vslack0)



N = (size(YY, 1)/n_of_phases) - 1;
bigN = N * n_of_phases;

if n_of_phases == 1
    L = size(N1N2Y, 1);
else
    L = numel(N1N2Y);
end


splitLinearComplexSystem = @(x) vertcat([real(x), -imag(x)], [imag(x), real(x)]); 
RealImagVectortoComplex = horzcat(eye(bigN), sqrt(-1)*eye(bigN));


Enew=V0((n_of_phases+1):end);
Snew=S0((n_of_phases+1):end);


YLL = YY(n_of_phases+1:end, n_of_phases+1:end);
Y0  = YY(1:n_of_phases, 1:n_of_phases);
Y0L = YY(1:n_of_phases, n_of_phases+1:end);
YL0 = YY(n_of_phases+1:end, 1:n_of_phases);



F=YY*V0;
Fn=F((n_of_phases+1):end);


% Eq. (6): I need to treat dE/dPl, which appears as complex conjugate
A0 = diag(Fn);
A1 = repmat(reshape(conj(Enew), bigN, 1), 1, bigN) .* YLL;
A = splitLinearComplexSystem(A0) .* horzcat(ones(bigN*2, bigN), -ones(bigN*2, bigN)) ...
    + splitLinearComplexSystem(A1);


% ---
% Sensitivity coefficients of voltages to nodal injections
% ---
% A is constant over every RHS below, so factorize it once and reuse. The
% old code called linsolve(A, e_k) once per unit vector (2*bigN solves,
% each re-factorizing A from scratch -> O(bigN^4)); solving A against the
% whole identity in one shot is O(bigN^3) and numerically identical.
dA = decomposition(A, 'lu');                    % same LU linsolve used internally
Ainv = dA \ eye(2*bigN);                       % [2bigN x 2bigN]
Ycplx = RealImagVectortoComplex * Ainv;        % [bigN x 2bigN] complex

dVdP = Ycplx(:, 1:bigN);                        % columns 1..bigN  = dV/dP
dVdQ = Ycplx(:, bigN+1:2*bigN);                 % columns bigN+1.. = dV/dQ

invAbsE = 1 ./ abs(Enew);
dVmagdP = invAbsE .* real(conj(Enew) .* dVdP); % per-column, broadcast over Enew
dVmagdQ = invAbsE .* real(conj(Enew) .* dVdQ);

% add slack-bus
dVdP = vertcat(zeros(n_of_phases, bigN), dVdP);
dVmagdP = vertcat(zeros(n_of_phases, bigN), dVmagdP);
dVdQ = vertcat(zeros(n_of_phases, bigN), dVdQ);
dVmagdQ = vertcat(zeros(n_of_phases, bigN), dVmagdQ);


% ---
% Sensitivity coefficients of voltages MAG to slack power
% ---
dVdVslackmag = zeros(bigN, n_of_phases);
dVmagdVslackmag = zeros(bigN, n_of_phases);

for p=1:n_of_phases
    H = nan(bigN, 1);
    for i=1:bigN
        H(i) = conj(Enew(i)) * YY(n_of_phases+i, p);
    end

    % LHS of Eq. 18
    RHS = -H.*exp(i*0);
    RHS = [real(RHS); imag(RHS)];
    %solve the linear system (reuse the factorization from above)
    y = RealImagVectortoComplex * (dA \ RHS);
    dVdVslackmag(:, p) = y;
    dVmagdVslackmag(:, p) = (abs(Enew)) .* real(y ./ Enew);
end
% add slack-bus
dVmagdVslackmag = vertcat(eye(n_of_phases), dVmagdVslackmag);
dVdVslackmag = vertcat(eye(n_of_phases), dVdVslackmag);




% ---
% Sensitivity coefficients of the line cur magnitude wrt to nodal
% injections. Eqs (15) - (17)
% ---
dIdP = nan(L*n_of_phases, bigN);
dIdQ = nan(L*n_of_phases, bigN);
dImagdP = nan(L*n_of_phases, bigN);
dImagdQ = nan(L*n_of_phases, bigN);
dImagdVslackmag = nan(L*n_of_phases, 3);


if n_of_phases == 1
    for l=1:L
        node_from = N1N2Y(l, 1);
        node_to = N1N2Y(l, 2);
        % Eq. (15)
        dIdP(l,:) = inv(N1N2Y(l,3)) * (dVdP(node_from, :) - dVdP(node_to, :));
        dIdQ(l,:) = inv(N1N2Y(l,3)) * (dVdQ(node_from, :) - dVdQ(node_to, :));
        % Eq. (16)
        dImagdP(l, :) = (1/abs(I0(l))) * real( conj(I0(l)) * dIdP(l,:) );
        dImagdQ(l, :) = (1/abs(I0(l))) * real( conj(I0(l)) * dIdQ(l,:) );
        
        % SCs against slack voltage
        dIdVslackmag = inv(N1N2Y(l,3)) * (dVdVslackmag(node_from:node_from+n_of_phases-1, :) - dVdVslackmag(node_to:node_to+n_of_phases-1, :));
        dImagdVslackmag(l, :) = (1/abs(I0(l))) * real( diag(conj(I0(l))) * dIdVslackmag );
    end
else
    for l=1:L
        node_from = (N1N2Y{l}.fromto(1) - 1) * n_of_phases + 1;
        node_to = (N1N2Y{l}.fromto(2) - 1) * n_of_phases + 1;
        % Eq. (15)
        dIdP = inv(N1N2Y{l}.lineimpedance) * (dVdP(node_from:node_from+n_of_phases-1, :) - dVdP(node_to:node_to+n_of_phases-1, :));
        dIdQ = inv(N1N2Y{l}.lineimpedance) * (dVdQ(node_from:node_from+n_of_phases-1, :) - dVdQ(node_to:node_to+n_of_phases-1, :));
        % Eq. (16)
        three_l = (l - 1) * n_of_phases + 1;
        three_l = three_l:three_l+n_of_phases-1;
        dImagdP(three_l, :) = inv(diag(abs(I0(three_l)))) * real( diag(conj(I0(three_l))) * dIdP );
        dImagdQ(three_l, :) = inv(diag(abs(I0(three_l)))) * real( diag(conj(I0(three_l))) * dIdQ );
        
        % SCs against slack voltage
        dIdVslackmag = inv(N1N2Y{l}.lineimpedance) * (dVdVslackmag(node_from:node_from+n_of_phases-1, :) - dVdVslackmag(node_to:node_to+n_of_phases-1, :));
        dImagdVslackmag(three_l, :) = inv(diag(abs(I0(three_l)))) * real( diag(conj(I0(three_l))) * dIdVslackmag );
    end
end

% ---
% Sensitivity coefficients of the line cur magnitude to voltage magnitude
% These are not specified in the paper but can be derived starting from
% dVdVslackmag similarly to what done with dVdP
% ---



% for l=1:L
%     if n_of_phases > 1
%         line_impedance = N1N2Y{l}.lineimpedance;
%     else
%         line_impedance = N1N2Y(l,3);
%     end
%     
%     three_l = (l - 1) * n_of_phases + 1;
%     three_l = three_l:(three_l + n_of_phases - 1);
%     
%     dIdVslackmag = inv(line_impedance) * (dVdVslackmag(node_from:node_from+n_of_phases-1, :) - dVdVslackmag(node_to:node_to+n_of_phases-1, :));
%     dImagdVslackmag(three_l, :) = inv(diag(abs(I0(three_l)))) * real( diag(conj(I0(three_l))) * dIdVslackmag );
% end


% ---
% SCs of the power injections at the GCP
% ---
dSslackstardVslackmag = 0;
dSslackstardP = 0;
dSslackstardQ = 0;

if n_of_phases == 1    
    dSslackstardP =   V0(1) * conj([Y0, Y0L] * dVdP); %YY(1,1) + E * YY(1, :);
    dSslackstardQ =  -V0(1) * conj([Y0, Y0L] * dVdQ);
    
    % approximated (as we dont
    dSslackstardVslackmag = 0;%Y0 * conj(V0(1));%+ Y0 * V0(1);
else
    
    dSslackstardP = diag(V0(1:n_of_phases)) * conj([Y0, Y0L] * dVdP); %YY(1,1) + E * YY(1, :);
    dSslackstardQ = diag(V0(1:n_of_phases)) * conj([Y0, Y0L] * dVdQ);
    
    
    % approximated
    dSslackstardVslackmag = 0;%Y0 * conj(V0(1));%+ Y0 * V0(1);
end




