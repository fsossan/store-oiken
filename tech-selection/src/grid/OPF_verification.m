
function [I_lf, V_lf, S_lf, lf_converged, lf_num_iter]=OPF_verification(Injections,grid,Injections_PV)
% OPF_VERIFICATION  Nonlinear (FPI) load-flow ground truth for verifying
%                    the linearized MILP solution.
%
%   [I_lf, V_lf, S_lf] = OPF_verification(Injections, grid)
%   [I_lf, V_lf, S_lf] = OPF_verification(Injections, grid, Injections_PV)
%   [I_lf, V_lf, S_lf, lf_converged, lf_num_iter] = OPF_verification(...)
%
%   Injections    : [T x Nd] complex, demand-node injection (baseline +
%                   BESS dispatch), same convention as sens.P0/Q0
%   Injections_PV : [T x Npv] real, OPTIONAL PV-curtailment adjustment
%                   (i.e. -P_curt; always <= 0, since curtailment only
%                   ever reduces injection at a PV node). Omit or pass []
%                   when curtailment is not active/not computed. Without
%                   it, PV curtailment is NOT reflected in this
%                   verification load flow, so the "ground truth" current/
%                   voltage would show the pre-curtailment scenario.
%   lf_converged  : [T x 1] logical, lf_num_iter : [T x 1] double -- per-
%                   timestep convergence of THIS (solved-dispatch)
%                   verification load flow; see loadflow_FPIs and
%                   summarize_lf_convergence. This is the convergence
%                   record that matters most for trusting a result, since
%                   it's the actual solved operating point, not just the
%                   base case.

T = size(Injections, 1);
nodes_with_demand = grid.nodal_nominal_power >0;
to_all_nodes_D = pinv(make_M(nodes_with_demand));
nodal_injections_D_pu=Injections;

apply_pv = nargin >= 3 && ~isempty(Injections_PV);
if apply_pv
    nodes_with_PV   = grid.nodal_PV_SFOE > 0;
    to_all_nodes_PV = pinv(make_M(nodes_with_PV));
end

% Running Load flow Verification

YLLi = inv(grid.Y(2:end, 2:end));   % constant across timesteps

for t=1:T
    injections_D = to_all_nodes_D* nodal_injections_D_pu(t, :).';
    injections = injections_D;
    if apply_pv
        injections = injections + to_all_nodes_PV * Injections_PV(t, :).';
    end

    [ V, I, S, conv_t, iter_t ] = loadflow_FPIs(grid.Y, 1, injections, 1, ...
        grid.voltageToBranchCurrent_pu, YLLi);

     Vm{t} = abs(V);
     Im{t} = abs(I);
     S_{t}= S;
     Cv{t} = conv_t;
     It{t} = iter_t;



end


I_lf=vertcat(Im{:});
V_lf = vertcat(Vm{:});
S_lf = vertcat(S_{:});
lf_converged = [Cv{:}].';
lf_num_iter  = [It{:}].';


end